#include "spatial/UniformGridIndex.cuh"

#include <cuda_runtime.h>
#include <gtest/gtest.h>
#include <vector>

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

namespace
{

/// Uploads a host vector of floats to a freshly allocated device buffer.
/// Caller is responsible for cudaFree on the returned pointer.
float* uploadFloats(const std::vector<float>& host)
{
    float* dev = nullptr;
    cudaMalloc(&dev, host.size() * sizeof(float));
    cudaMemcpy(dev, host.data(), host.size() * sizeof(float), cudaMemcpyHostToDevice);
    return dev;
}

/// Allocates a zeroed device int buffer of `size` ints. Caller owns it.
int* allocDeviceInts(std::size_t size)
{
    int* dev = nullptr;
    cudaMalloc(&dev, size * sizeof(int));
    cudaMemset(dev, 0, size * sizeof(int));
    return dev;
}

} // namespace

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

struct UniformGridIndexGpuTest : public ::testing::Test
{
protected:
    void TearDown() override
    {
        // Confirm no pending CUDA errors after each test
        EXPECT_EQ(cudaGetLastError(), cudaSuccess);
    }
};

// ---------------------------------------------------------------------------
// Test 1: 4 particles in corners of a 2x2 grid — all 4 within radius 2.0
// ---------------------------------------------------------------------------

TEST_F(UniformGridIndexGpuTest, FourParticles_AllNeighbours_RadiusTwoPointZero)
{
    // Arrange: 4 particles at (0.5,0.5), (1.5,0.5), (0.5,1.5), (1.5,1.5)
    // Domain: [0,2)x[0,2), cellSize=1.0, radius=2.0 => all are neighbours
    const std::vector<float> hx = {0.5F, 1.5F, 0.5F, 1.5F};
    const std::vector<float> hy = {0.5F, 0.5F, 1.5F, 1.5F};
    const std::size_t N = hx.size();

    float* dx = uploadFloats(hx);
    float* dy = uploadFloats(hy);

    psim::spatial::UniformGridIndex index{1.0F, make_float2(0.0F, 0.0F), make_float2(2.0F, 2.0F)};

    psim::spatial::ParticlePositionsView positions{dx, dy, N};
    index.rebuild(positions);

    constexpr std::size_t MAX_NBRS = 8U;
    int* dIndices = allocDeviceInts(N * MAX_NBRS);
    int* dCounts = allocDeviceInts(N);

    psim::spatial::NeighbourOutputView output{dIndices, dCounts, MAX_NBRS};
    psim::spatial::QueryParams params{2.0F};

    // Act
    auto result = index.queryNeighbours(output, params);

    // Assert — operation succeeds
    ASSERT_TRUE(result.has_value());
    EXPECT_FALSE(result->truncated);

    // Download counts
    std::vector<int> hCounts(N);
    cudaMemcpy(hCounts.data(), dCounts, N * sizeof(int), cudaMemcpyDeviceToHost);

    // Each particle should have 3 neighbours (all others within radius 2.0)
    for (std::size_t i = 0; i < N; ++i)
    {
        EXPECT_EQ(hCounts[i], 3) << "Particle " << i;
    }

    cudaFree(dx);
    cudaFree(dy);
    cudaFree(dIndices);
    cudaFree(dCounts);
}

// ---------------------------------------------------------------------------
// Test 2: Line of 10 particles, spacing 1.0, radius 1.5 — only adjacent
// ---------------------------------------------------------------------------

TEST_F(UniformGridIndexGpuTest, TenParticlesLine_AdjacentNeighboursOnly)
{
    // Arrange: particles at x=0.5,1.5,...,9.5, all y=0.5
    // radius=1.5 => neighbours only within 1 cell
    const std::size_t N = 10;
    std::vector<float> hx(N);
    std::vector<float> hy(N, 0.5F);
    for (std::size_t i = 0; i < N; ++i)
    {
        hx[i] = static_cast<float>(i) + 0.5F;
    }

    float* dx = uploadFloats(hx);
    float* dy = uploadFloats(hy);

    psim::spatial::UniformGridIndex index{1.0F, make_float2(0.0F, 0.0F), make_float2(10.0F, 10.0F)};

    psim::spatial::ParticlePositionsView positions{dx, dy, N};
    index.rebuild(positions);

    constexpr std::size_t MAX_NBRS = 16U;
    int* dIndices = allocDeviceInts(N * MAX_NBRS);
    int* dCounts = allocDeviceInts(N);

    psim::spatial::NeighbourOutputView output{dIndices, dCounts, MAX_NBRS};
    psim::spatial::QueryParams params{1.5F};

    // Act
    auto result = index.queryNeighbours(output, params);

    // Assert
    ASSERT_TRUE(result.has_value());
    EXPECT_FALSE(result->truncated);

    std::vector<int> hCounts(N);
    cudaMemcpy(hCounts.data(), dCounts, N * sizeof(int), cudaMemcpyDeviceToHost);

    // Endpoints have 1 neighbour, interior particles have 2
    EXPECT_EQ(hCounts[0], 1) << "First particle (left endpoint)";
    EXPECT_EQ(hCounts[N - 1], 1) << "Last particle (right endpoint)";
    for (std::size_t i = 1; i < N - 1; ++i)
    {
        EXPECT_EQ(hCounts[i], 2) << "Interior particle " << i;
    }

    cudaFree(dx);
    cudaFree(dy);
    cudaFree(dIndices);
    cudaFree(dCounts);
}

// ---------------------------------------------------------------------------
// Test 3: truncated == false for small particle count (N <= maxPerParticle)
// ---------------------------------------------------------------------------

TEST_F(UniformGridIndexGpuTest, SmallCount_TruncatedIsFalse)
{
    // Arrange: 4 co-located particles, maxPerParticle=64 => never truncated
    const std::vector<float> hx = {5.0F, 5.0F, 5.0F, 5.0F};
    const std::vector<float> hy = {5.0F, 5.0F, 5.0F, 5.0F};
    const std::size_t N = hx.size();

    float* dx = uploadFloats(hx);
    float* dy = uploadFloats(hy);

    psim::spatial::UniformGridIndex index{1.0F, make_float2(0.0F, 0.0F), make_float2(10.0F, 10.0F)};

    psim::spatial::ParticlePositionsView positions{dx, dy, N};
    index.rebuild(positions);

    constexpr std::size_t MAX_NBRS = 64U;
    int* dIndices = allocDeviceInts(N * MAX_NBRS);
    int* dCounts = allocDeviceInts(N);

    psim::spatial::NeighbourOutputView output{dIndices, dCounts, MAX_NBRS};
    psim::spatial::QueryParams params{1.5F};

    // Act
    auto result = index.queryNeighbours(output, params);

    // Assert
    ASSERT_TRUE(result.has_value());
    EXPECT_FALSE(result->truncated);

    cudaFree(dx);
    cudaFree(dy);
    cudaFree(dIndices);
    cudaFree(dCounts);
}

// ---------------------------------------------------------------------------
// Test 4: queryFromPoints — out-of-domain query points return 0 neighbours
// ---------------------------------------------------------------------------

TEST_F(UniformGridIndexGpuTest, QueryFromPoints_OutOfDomain_ZeroNeighbours)
{
    // Arrange: index built with 2 particles inside domain
    // Query from a point far outside the domain
    const std::vector<float> hx = {5.0F, 5.1F};
    const std::vector<float> hy = {5.0F, 5.0F};
    const std::vector<float> qx = {100.0F};
    const std::vector<float> qy = {100.0F};
    const std::size_t N = hx.size();
    const std::size_t NQuery = qx.size();

    float* dx = uploadFloats(hx);
    float* dy = uploadFloats(hy);
    float* dqx = uploadFloats(qx);
    float* dqy = uploadFloats(qy);

    psim::spatial::UniformGridIndex index{1.0F, make_float2(0.0F, 0.0F), make_float2(10.0F, 10.0F)};

    psim::spatial::ParticlePositionsView positions{dx, dy, N};
    index.rebuild(positions);

    constexpr std::size_t MAX_NBRS = 16U;
    int* dIndices = allocDeviceInts(NQuery * MAX_NBRS);
    int* dCounts = allocDeviceInts(NQuery);

    psim::spatial::ParticlePositionsView queryPts{dqx, dqy, NQuery};
    psim::spatial::NeighbourOutputView output{dIndices, dCounts, MAX_NBRS};
    psim::spatial::QueryParams params{1.5F};

    // Act
    auto result = index.queryFromPoints(queryPts, output, params);

    // Assert
    ASSERT_TRUE(result.has_value());

    std::vector<int> hCounts(NQuery);
    cudaMemcpy(hCounts.data(), dCounts, NQuery * sizeof(int), cudaMemcpyDeviceToHost);
    EXPECT_EQ(hCounts[0], 0);

    cudaFree(dx);
    cudaFree(dy);
    cudaFree(dqx);
    cudaFree(dqy);
    cudaFree(dIndices);
    cudaFree(dCounts);
}

// ---------------------------------------------------------------------------
// Test 5: Single particle — 0 neighbours
// ---------------------------------------------------------------------------

TEST_F(UniformGridIndexGpuTest, SingleParticle_ZeroNeighbours)
{
    // Arrange
    const std::vector<float> hx = {5.0F};
    const std::vector<float> hy = {5.0F};

    float* dx = uploadFloats(hx);
    float* dy = uploadFloats(hy);

    psim::spatial::UniformGridIndex index{1.0F, make_float2(0.0F, 0.0F), make_float2(10.0F, 10.0F)};

    psim::spatial::ParticlePositionsView positions{dx, dy, 1U};
    index.rebuild(positions);

    constexpr std::size_t MAX_NBRS = 16U;
    int* dIndices = allocDeviceInts(1U * MAX_NBRS);
    int* dCounts = allocDeviceInts(1U);

    psim::spatial::NeighbourOutputView output{dIndices, dCounts, MAX_NBRS};
    psim::spatial::QueryParams params{1.5F};

    // Act
    auto result = index.queryNeighbours(output, params);

    // Assert
    ASSERT_TRUE(result.has_value());
    EXPECT_FALSE(result->truncated);

    int hCount = 0;
    cudaMemcpy(&hCount, dCounts, sizeof(int), cudaMemcpyDeviceToHost);
    EXPECT_EQ(hCount, 0);

    cudaFree(dx);
    cudaFree(dy);
    cudaFree(dIndices);
    cudaFree(dCounts);
}
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// CUDA initialiser environment — forces CUDA context creation before
// GoogleTest executes any test body.
//
// In CUDA 13.2, lazy context init was tightened: the first cudaMalloc inside
// a constructor (e.g. UniformGridIndex built in a test body) aborts if no
// CUDA context has been established yet.  SetUp() calls cudaSetDevice(0)
// before the first test, ensuring eager context creation.
// ---------------------------------------------------------------------------

namespace
{

/// @brief GoogleTest environment that initialises the CUDA device on setup.
class CudaDeviceEnvironment : public ::testing::Environment
{
public:
    /// @brief Calls cudaSetDevice(0) to eagerly create a CUDA context.
    void SetUp() override
    {
        cudaError_t err = cudaSetDevice(0);
        ASSERT_EQ(err, cudaSuccess) << "CUDA device init failed: " << cudaGetErrorString(err);
    }
};

// NOLINTNEXTLINE(cppcoreguidelines-avoid-non-const-global-variables)
::testing::Environment* const kCudaEnv = ::testing::AddGlobalTestEnvironment(new CudaDeviceEnvironment{});

} // namespace
