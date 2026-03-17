#include "spatial/UniformGridIndex.cuh"

#include <gtest/gtest.h>

// ---------------------------------------------------------------------------
// Test fixture
// ---------------------------------------------------------------------------

/// @brief CPU-side contract tests for UniformGridIndex.
///
/// These tests verify the public API contract without actually running any CUDA
/// kernels. They check construction, state inspection, and precondition enforcement.
///
/// GPU correctness is covered in tests/gpu/spatial/UniformGridIndexGpuTest.cu.
struct UniformGridIndexTest : public ::testing::Test
{
protected:
    // Domain: 10x10, cell size 1.0 => 10x10 = 100 cells.
    static constexpr float CELL_SIZE = 1.0F;
    static constexpr float2 DOMAIN_MIN{0.0F, 0.0F};
    static constexpr float2 DOMAIN_MAX{10.0F, 10.0F};
};

// ---------------------------------------------------------------------------
// Construction tests
// ---------------------------------------------------------------------------

TEST_F(UniformGridIndexTest, Constructor_ValidParams_CreatesEmptyIndex)
{
    // Arrange / Act
    psim::spatial::UniformGridIndex index{CELL_SIZE, DOMAIN_MIN, DOMAIN_MAX};

    // Assert
    EXPECT_TRUE(index.empty());
    EXPECT_EQ(index.particleCount(), 0U);
}

TEST_F(UniformGridIndexTest, Constructor_ZeroCellSize_Aborts)
{
    // Fail-Fast: cell size of 0 is invalid
    EXPECT_DEATH((psim::spatial::UniformGridIndex{0.0F, DOMAIN_MIN, DOMAIN_MAX}), ".*");
}

TEST_F(UniformGridIndexTest, Constructor_NegativeCellSize_Aborts)
{
    EXPECT_DEATH((psim::spatial::UniformGridIndex{-1.0F, DOMAIN_MIN, DOMAIN_MAX}), ".*");
}

TEST_F(UniformGridIndexTest, Constructor_InvertedDomain_Aborts)
{
    // domainMin.x > domainMax.x is invalid
    EXPECT_DEATH((psim::spatial::UniformGridIndex{CELL_SIZE, DOMAIN_MAX, DOMAIN_MIN}), ".*");
}

// ---------------------------------------------------------------------------
// queryNeighbours — precondition: not yet built
// ---------------------------------------------------------------------------

TEST_F(UniformGridIndexTest, QueryNeighbours_BeforeRebuild_ReturnsNotBuiltError)
{
    // Arrange
    psim::spatial::UniformGridIndex index{CELL_SIZE, DOMAIN_MIN, DOMAIN_MAX};

    // Dummy output (null pointers are fine — should fail before touching them)
    psim::spatial::NeighbourOutputView output{nullptr, nullptr, 64U};
    psim::spatial::QueryParams params{1.5F};

    // Act
    auto result = index.queryNeighbours(output, params);

    // Assert
    ASSERT_FALSE(result.has_value());
    EXPECT_EQ(result.error(), psim::spatial::SpatialIndexError::NotBuilt);
}

// ---------------------------------------------------------------------------
// queryFromPoints — precondition: not yet built
// ---------------------------------------------------------------------------

TEST_F(UniformGridIndexTest, QueryFromPoints_BeforeRebuild_ReturnsNotBuiltError)
{
    // Arrange
    psim::spatial::UniformGridIndex index{CELL_SIZE, DOMAIN_MIN, DOMAIN_MAX};

    psim::spatial::ParticlePositionsView pts{nullptr, nullptr, 1U};
    psim::spatial::NeighbourOutputView output{nullptr, nullptr, 64U};
    psim::spatial::QueryParams params{1.5F};

    // Act
    auto result = index.queryFromPoints(pts, output, params);

    // Assert
    ASSERT_FALSE(result.has_value());
    EXPECT_EQ(result.error(), psim::spatial::SpatialIndexError::NotBuilt);
}

// ---------------------------------------------------------------------------
// queryNeighbours — null output buffer
// ---------------------------------------------------------------------------

TEST_F(UniformGridIndexTest, QueryNeighbours_NullOutputBuffer_ReturnsInvalidBuffer)
{
    // Arrange — build with a minimal real particle so the index IS built
    psim::spatial::UniformGridIndex index{CELL_SIZE, DOMAIN_MIN, DOMAIN_MAX};

    // Allocate 1 particle on device
    float* dx = nullptr;
    float* dy = nullptr;
    cudaMalloc(&dx, sizeof(float));
    cudaMalloc(&dy, sizeof(float));
    float hx = 5.0F;
    float hy = 5.0F;
    cudaMemcpy(dx, &hx, sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(dy, &hy, sizeof(float), cudaMemcpyHostToDevice);

    psim::spatial::ParticlePositionsView positions{dx, dy, 1U};
    index.rebuild(positions);

    // Null indices pointer => invalid buffer
    psim::spatial::NeighbourOutputView badOutput{nullptr, nullptr, 64U};
    psim::spatial::QueryParams params{1.5F};

    // Act
    auto result = index.queryNeighbours(badOutput, params);

    cudaFree(dx);
    cudaFree(dy);

    // Assert
    ASSERT_FALSE(result.has_value());
    EXPECT_EQ(result.error(), psim::spatial::SpatialIndexError::InvalidBuffer);
}
