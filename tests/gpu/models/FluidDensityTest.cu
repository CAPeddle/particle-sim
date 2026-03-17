// FluidDensityTest.cu
//
// GPU integration tests for the SPH density computation pipeline.
// Validates that computeDensity produces correct density values for known
// particle arrangements with analytically verifiable results.
//
// Test naming: MethodName_Scenario_ExpectedBehaviour

#include "core/CudaUtils.hpp"
#include "models/FluidSPHModel.cuh"
#include "spatial/UniformGridIndex.cuh"

#include <cmath>
#include <cuda_runtime.h>
#include <gtest/gtest.h>
#include <vector>

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

namespace
{

/// Copies a host vector to a pre-allocated device buffer of the same size.
void uploadToDevice(float* devPtr, const std::vector<float>& host)
{
    CUDA_CHECK(cudaMemcpy(devPtr, host.data(), host.size() * sizeof(float), cudaMemcpyHostToDevice));
}

/// Downloads a device float buffer to a host vector.
std::vector<float> downloadFromDevice(const float* devPtr, std::size_t count)
{
    std::vector<float> host(count);
    CUDA_CHECK(cudaMemcpy(host.data(), devPtr, count * sizeof(float), cudaMemcpyDeviceToHost));
    return host;
}

/// Compute the expected smoothingKernel value (host-side mirror for validation).
float hostSmoothingKernel(float distance, float radius)
{
    if (distance >= radius)
    {
        return 0.0F;
    }
    float q = (radius - distance) / radius;
    return q * q * q;
}

} // namespace

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

struct FluidDensityTest : public ::testing::Test
{
protected:
    void TearDown() override { EXPECT_EQ(cudaGetLastError(), cudaSuccess); }
};

// ---------------------------------------------------------------------------
// Test 1: Single particle — density equals self-contribution only
// ---------------------------------------------------------------------------

/// A single isolated particle has no neighbours. Its density equals
/// mass * W(0, h) from the explicit self-contribution in computeDensityKernel.
TEST_F(FluidDensityTest, ComputeDensity_SingleParticle_EqualsSelfContribution)
{
    // Arrange
    constexpr float H = 1.0F;
    constexpr float MASS = 1.0F;
    constexpr float EXPECTED_DENSITY = MASS * 1.0F; // W(0,1) = 1.0

    psim::models::FluidSPHParams params;
    params.particleCount = 1U;
    params.influenceRadius = H;
    params.mass = MASS;
    params.domainMin = {0.0F, 0.0F};
    params.domainMax = {2.0F, 2.0F};
    params.maxNeighbours = 16U;

    psim::models::FluidSPHModel model;
    psim::models::initFluidModel(model, params);

    const std::vector<float> hx = {0.5F};
    const std::vector<float> hy = {0.5F};
    uploadToDevice(model.posX.get(), hx);
    uploadToDevice(model.posY.get(), hy);

    psim::spatial::UniformGridIndex index{1.0F, make_float2(0.0F, 0.0F), make_float2(2.0F, 2.0F)};

    psim::spatial::ParticlePositionsView positions{model.posX.get(), model.posY.get(), 1U};
    index.rebuild(positions);

    // Act
    psim::models::computeDensity(model, index);

    // Assert
    auto density = downloadFromDevice(model.density.get(), 1);
    ASSERT_EQ(density.size(), 1U);
    EXPECT_FLOAT_EQ(density[0], EXPECTED_DENSITY);
}

// ---------------------------------------------------------------------------
// Test 2: Two particles at known separation — density matches analytic result
// ---------------------------------------------------------------------------

/// Two particles separated by 0.5 world units (h = 1.0). Each has one neighbour.
/// Expected density per particle = mass * (W(0,h) + W(0.5, h))
///                               = 1.0 * (1.0 + 0.125) = 1.125.
TEST_F(FluidDensityTest, ComputeDensity_TwoParticlesKnownDistance_MatchesAnalytic)
{
    // Arrange
    constexpr float H = 1.0F;
    constexpr float DIST = 0.5F;
    constexpr float MASS = 1.0F;
    const float EXPECTED = MASS * (hostSmoothingKernel(0.0F, H) + hostSmoothingKernel(DIST, H));

    psim::models::FluidSPHParams params;
    params.particleCount = 2U;
    params.influenceRadius = H;
    params.mass = MASS;
    params.domainMin = {0.0F, 0.0F};
    params.domainMax = {2.0F, 2.0F};
    params.maxNeighbours = 16U;

    psim::models::FluidSPHModel model;
    psim::models::initFluidModel(model, params);

    // Particles at (0.5, 0.5) and (1.0, 0.5) — separation = 0.5
    const std::vector<float> hx = {0.5F, 1.0F};
    const std::vector<float> hy = {0.5F, 0.5F};
    uploadToDevice(model.posX.get(), hx);
    uploadToDevice(model.posY.get(), hy);

    psim::spatial::UniformGridIndex index{1.0F, make_float2(0.0F, 0.0F), make_float2(2.0F, 2.0F)};

    psim::spatial::ParticlePositionsView positions{model.posX.get(), model.posY.get(), 2U};
    index.rebuild(positions);

    // Act
    psim::models::computeDensity(model, index);

    // Assert — both particles should have equal density by symmetry
    auto density = downloadFromDevice(model.density.get(), 2);
    ASSERT_EQ(density.size(), 2U);
    EXPECT_FLOAT_EQ(density[0], EXPECTED);
    EXPECT_FLOAT_EQ(density[1], EXPECTED);
}

// ---------------------------------------------------------------------------
// Test 3: Particles outside each other's radius — each has only self-contribution
// ---------------------------------------------------------------------------

/// Two particles separated by more than h (influence radius). Neither is the
/// other's neighbour. Each density equals mass * W(0, h) = 1.0.
TEST_F(FluidDensityTest, ComputeDensity_TwoParticlesBeyondRadius_NoCrossContribution)
{
    // Arrange
    constexpr float H = 1.0F;
    constexpr float MASS = 1.0F;
    constexpr float EXPECTED = MASS * 1.0F; // W(0, 1) only

    psim::models::FluidSPHParams params;
    params.particleCount = 2U;
    params.influenceRadius = H;
    params.mass = MASS;
    params.domainMin = {0.0F, 0.0F};
    params.domainMax = {4.0F, 4.0F};
    params.maxNeighbours = 16U;

    psim::models::FluidSPHModel model;
    psim::models::initFluidModel(model, params);

    // Particles at (0.5, 0.5) and (3.5, 0.5) — separation >> h
    const std::vector<float> hx = {0.5F, 3.5F};
    const std::vector<float> hy = {0.5F, 0.5F};
    uploadToDevice(model.posX.get(), hx);
    uploadToDevice(model.posY.get(), hy);

    psim::spatial::UniformGridIndex index{1.0F, make_float2(0.0F, 0.0F), make_float2(4.0F, 4.0F)};

    psim::spatial::ParticlePositionsView positions{model.posX.get(), model.posY.get(), 2U};
    index.rebuild(positions);

    // Act
    psim::models::computeDensity(model, index);

    // Assert
    auto density = downloadFromDevice(model.density.get(), 2);
    ASSERT_EQ(density.size(), 2U);
    EXPECT_FLOAT_EQ(density[0], EXPECTED);
    EXPECT_FLOAT_EQ(density[1], EXPECTED);
}

// ---------------------------------------------------------------------------
// Test 4: All density values are finite (no NaN / Inf)
// ---------------------------------------------------------------------------

/// Four particles in a 2×2 arrangement. No density value should be NaN or Inf.
TEST_F(FluidDensityTest, ComputeDensity_FourParticles_AllDensitiesFinite)
{
    // Arrange
    psim::models::FluidSPHParams params;
    params.particleCount = 4U;
    params.influenceRadius = 2.0F;
    params.mass = 1.0F;
    params.domainMin = {0.0F, 0.0F};
    params.domainMax = {2.0F, 2.0F};
    params.maxNeighbours = 8U;

    psim::models::FluidSPHModel model;
    psim::models::initFluidModel(model, params);

    const std::vector<float> hx = {0.5F, 1.5F, 0.5F, 1.5F};
    const std::vector<float> hy = {0.5F, 0.5F, 1.5F, 1.5F};
    uploadToDevice(model.posX.get(), hx);
    uploadToDevice(model.posY.get(), hy);

    psim::spatial::UniformGridIndex index{1.0F, make_float2(0.0F, 0.0F), make_float2(2.0F, 2.0F)};

    psim::spatial::ParticlePositionsView positions{model.posX.get(), model.posY.get(), 4U};
    index.rebuild(positions);

    // Act
    psim::models::computeDensity(model, index);

    // Assert
    auto density = downloadFromDevice(model.density.get(), 4);
    ASSERT_EQ(density.size(), 4U);
    for (std::size_t i = 0U; i < density.size(); ++i)
    {
        EXPECT_TRUE(std::isfinite(density[i])) << "Density[" << i << "] is not finite: " << density[i];
        EXPECT_GT(density[i], 0.0F) << "Density[" << i << "] is not positive";
    }
}
