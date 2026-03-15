// BoundaryTest.cu
//
// GPU-side tests for psim::core::applyBoundary().
//
// Because applyBoundary() is __host__ __device__, it is tested both on the
// CPU (BoundaryUtilsTest.cpp) and here on the GPU via thin __global__ wrapper
// kernels, validating that the device-side path produces identical results.
//
// Pattern follows SphKernelsTest.cu: each test case invokes a single-thread
// kernel, copies the result to the host, and asserts with GTest.
//
// Test naming: MethodName_Scenario_ExpectedBehaviour

#include "core/BoundaryUtils.cuh"
#include "core/CudaUtils.hpp"

#include <cuda_runtime.h>
#include <gtest/gtest.h>

using psim::core::BoundaryMode;
using psim::core::applyBoundary;

// ---------------------------------------------------------------------------
// Device wrapper kernel
// ---------------------------------------------------------------------------

namespace
{

/// @brief POD holding a particle state snapshot for device/host transfer.
struct ParticleState
{
    float x;
    float y;
    float vx;
    float vy;
};

/// @brief Wrapper kernel: applies applyBoundary() on the GPU and stores the result.
///
/// @param state       Input particle state (device pointer).
/// @param result      Output particle state after boundary (device pointer).
/// @param minX        Domain left.
/// @param maxX        Domain right.
/// @param minY        Domain bottom.
/// @param maxY        Domain top.
/// @param mode        BoundaryMode to apply.
/// @param damping     Damping coefficient.
__global__ void applyBoundaryDevice(const ParticleState* state,
                                    ParticleState*       result,
                                    float                minX,
                                    float                maxX,
                                    float                minY,
                                    float                maxY,
                                    BoundaryMode         mode,
                                    float                damping)
{
    float x  = state->x;
    float y  = state->y;
    float vx = state->vx;
    float vy = state->vy;

    applyBoundary(x, y, vx, vy, minX, maxX, minY, maxY, mode, damping);

    result->x  = x;
    result->y  = y;
    result->vx = vx;
    result->vy = vy;
}

/// @brief Runs the applyBoundary device function via a single-thread kernel.
///
/// @return Host-side particle state after boundary application.
ParticleState runOnGpu(ParticleState input,
                       float         minX,
                       float         maxX,
                       float         minY,
                       float         maxY,
                       BoundaryMode  mode,
                       float         damping)
{
    ParticleState* dInput  = nullptr;
    ParticleState* dResult = nullptr;
    CUDA_CHECK(cudaMalloc(&dInput, sizeof(ParticleState)));
    CUDA_CHECK(cudaMalloc(&dResult, sizeof(ParticleState)));

    CUDA_CHECK(cudaMemcpy(dInput, &input, sizeof(ParticleState), cudaMemcpyHostToDevice));

    applyBoundaryDevice<<<1, 1>>>(dInput, dResult, minX, maxX, minY, maxY, mode, damping);

    CUDA_CHECK(cudaDeviceSynchronize());

    ParticleState hResult{};
    CUDA_CHECK(cudaMemcpy(&hResult, dResult, sizeof(ParticleState), cudaMemcpyDeviceToHost));

    CUDA_CHECK(cudaFree(dInput));
    CUDA_CHECK(cudaFree(dResult));

    return hResult;
}

} // namespace

// ---------------------------------------------------------------------------
// Test fixture
// ---------------------------------------------------------------------------

struct BoundaryTest : public ::testing::Test
{
protected:
    static constexpr float MIN     = -1.0F;
    static constexpr float MAX     = 1.0F;
    static constexpr float DAMPING = 0.8F;
    static constexpr float ELASTIC = 1.0F;
    static constexpr float TOL     = 1e-5F;

    void TearDown() override { EXPECT_EQ(cudaGetLastError(), cudaSuccess); }
};

// ---------------------------------------------------------------------------
// GPU Reflect tests
// ---------------------------------------------------------------------------

TEST_F(BoundaryTest, ApplyBoundary_GpuReflectRightWall_ClampsPosAndNegatesVx)
{
    // Arrange
    ParticleState const input{1.1F, 0.0F, 2.0F, 0.0F};

    // Act
    ParticleState const result = runOnGpu(input, MIN, MAX, MIN, MAX, BoundaryMode::Reflect, DAMPING);

    // Assert
    EXPECT_NEAR(result.x,  1.0F,  TOL);
    EXPECT_NEAR(result.vx, -1.6F, TOL);  // 2.0 * -0.8
    EXPECT_NEAR(result.y,  0.0F,  TOL);
    EXPECT_NEAR(result.vy, 0.0F,  TOL);
}

TEST_F(BoundaryTest, ApplyBoundary_GpuReflectLeftWall_ClampsPosAndNegatesVx)
{
    // Arrange
    ParticleState const input{-1.1F, 0.0F, -3.0F, 0.0F};

    // Act
    ParticleState const result = runOnGpu(input, MIN, MAX, MIN, MAX, BoundaryMode::Reflect, DAMPING);

    // Assert
    EXPECT_NEAR(result.x,  -1.0F, TOL);
    EXPECT_NEAR(result.vx,  2.4F, TOL);  // -3.0 * -0.8
}

TEST_F(BoundaryTest, ApplyBoundary_GpuReflectTopWall_ClampsPosAndNegatesVy)
{
    // Arrange
    ParticleState const input{0.0F, 1.2F, 0.0F, 5.0F};

    // Act
    ParticleState const result = runOnGpu(input, MIN, MAX, MIN, MAX, BoundaryMode::Reflect, DAMPING);

    // Assert
    EXPECT_NEAR(result.y,  1.0F,  TOL);
    EXPECT_NEAR(result.vy, -4.0F, TOL);  // 5.0 * -0.8
}

TEST_F(BoundaryTest, ApplyBoundary_GpuReflectBottomWall_ClampsPosAndNegatesVy)
{
    // Arrange
    ParticleState const input{0.0F, -1.3F, 0.0F, -2.5F};

    // Act
    ParticleState const result = runOnGpu(input, MIN, MAX, MIN, MAX, BoundaryMode::Reflect, DAMPING);

    // Assert
    EXPECT_NEAR(result.y,  -1.0F, TOL);
    EXPECT_NEAR(result.vy,  2.0F, TOL);  // -2.5 * -0.8
}

TEST_F(BoundaryTest, ApplyBoundary_GpuReflectElasticBounce_SpeedPreserved)
{
    // Arrange
    ParticleState const input{1.1F, 0.0F, 3.0F, 0.0F};

    // Act
    ParticleState const result = runOnGpu(input, MIN, MAX, MIN, MAX, BoundaryMode::Reflect, ELASTIC);

    // Assert
    EXPECT_NEAR(result.x,  1.0F,  TOL);
    EXPECT_NEAR(result.vx, -3.0F, TOL);
}

// ---------------------------------------------------------------------------
// GPU Wrap tests
// ---------------------------------------------------------------------------

TEST_F(BoundaryTest, ApplyBoundary_GpuWrapRightEdge_WrapsToLeft)
{
    // Arrange
    ParticleState const input{1.1F, 0.0F, 1.0F, 0.0F};

    // Act
    ParticleState const result = runOnGpu(input, MIN, MAX, MIN, MAX, BoundaryMode::Wrap, DAMPING);

    // Assert
    EXPECT_NEAR(result.x,  -0.9F, TOL);
    EXPECT_NEAR(result.vx,  1.0F, TOL);  // velocity unchanged
}

TEST_F(BoundaryTest, ApplyBoundary_GpuWrapLeftEdge_WrapsToRight)
{
    // Arrange
    ParticleState const input{-1.4F, 0.0F, -1.0F, 0.0F};

    // Act
    ParticleState const result = runOnGpu(input, MIN, MAX, MIN, MAX, BoundaryMode::Wrap, DAMPING);

    // Assert
    EXPECT_NEAR(result.x,   0.6F, TOL);
    EXPECT_NEAR(result.vx, -1.0F, TOL);
}

TEST_F(BoundaryTest, ApplyBoundary_GpuInsideDomainReflect_NoChange)
{
    // Arrange
    ParticleState const input{0.5F, -0.3F, 1.0F, -2.0F};

    // Act
    ParticleState const result = runOnGpu(input, MIN, MAX, MIN, MAX, BoundaryMode::Reflect, DAMPING);

    // Assert — inside domain: nothing changes
    EXPECT_NEAR(result.x,  0.5F,  TOL);
    EXPECT_NEAR(result.y,  -0.3F, TOL);
    EXPECT_NEAR(result.vx, 1.0F,  TOL);
    EXPECT_NEAR(result.vy, -2.0F, TOL);
}

TEST_F(BoundaryTest, ApplyBoundary_GpuInsideDomainWrap_NoChange)
{
    // Arrange
    ParticleState const input{0.5F, -0.3F, 1.0F, -2.0F};

    // Act
    ParticleState const result = runOnGpu(input, MIN, MAX, MIN, MAX, BoundaryMode::Wrap, DAMPING);

    // Assert
    EXPECT_NEAR(result.x,  0.5F,  TOL);
    EXPECT_NEAR(result.y,  -0.3F, TOL);
    EXPECT_NEAR(result.vx, 1.0F,  TOL);
    EXPECT_NEAR(result.vy, -2.0F, TOL);
}
