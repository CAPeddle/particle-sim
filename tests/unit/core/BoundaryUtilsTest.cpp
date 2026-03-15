// BoundaryUtilsTest.cpp
//
// CPU-side unit tests for psim::core::applyBoundary().
//
// Because applyBoundary() is declared __host__ __device__, the function is
// callable directly from host code — no CUDA kernel wrapper required.
//
// Test naming: MethodName_Scenario_ExpectedBehaviour

#include "core/BoundaryUtils.cuh"

#include <gtest/gtest.h>

using psim::core::BoundaryMode;
using psim::core::applyBoundary;

// ---------------------------------------------------------------------------
// Test fixture
// ---------------------------------------------------------------------------

struct BoundaryUtilsTest : public ::testing::Test
{
protected:
    // Standard square domain [-1, 1] x [-1, 1] used by the particle system.
    static constexpr float MIN = -1.0F;
    static constexpr float MAX = 1.0F;
    static constexpr float DAMPING = 0.8F;
    static constexpr float ELASTIC = 1.0F;
    static constexpr float TOLERANCE = 1e-5F;
};

// ---------------------------------------------------------------------------
// Reflect — right wall
// ---------------------------------------------------------------------------

TEST_F(BoundaryUtilsTest, ApplyBoundary_ReflectRightWall_ClampsPosAndNegatesVx)
{
    // Arrange
    float x = 1.1F, y = 0.0F, vx = 2.0F, vy = 0.0F;

    // Act
    applyBoundary(x, y, vx, vy, MIN, MAX, MIN, MAX, BoundaryMode::Reflect, DAMPING);

    // Assert — position clamped, velocity negated and damped
    EXPECT_NEAR(x, 1.0F, TOLERANCE);
    EXPECT_NEAR(vx, -1.6F, TOLERANCE);  // 2.0 * -0.8
    EXPECT_NEAR(y, 0.0F, TOLERANCE);    // y unchanged
    EXPECT_NEAR(vy, 0.0F, TOLERANCE);   // vy unchanged
}

// ---------------------------------------------------------------------------
// Reflect — left wall
// ---------------------------------------------------------------------------

TEST_F(BoundaryUtilsTest, ApplyBoundary_ReflectLeftWall_ClampsPosAndNegatesVx)
{
    // Arrange
    float x = -1.1F, y = 0.0F, vx = -3.0F, vy = 0.0F;

    // Act
    applyBoundary(x, y, vx, vy, MIN, MAX, MIN, MAX, BoundaryMode::Reflect, DAMPING);

    // Assert
    EXPECT_NEAR(x, -1.0F, TOLERANCE);
    EXPECT_NEAR(vx, 2.4F, TOLERANCE);   // -3.0 * -0.8 = 2.4
    EXPECT_NEAR(y, 0.0F, TOLERANCE);
    EXPECT_NEAR(vy, 0.0F, TOLERANCE);
}

// ---------------------------------------------------------------------------
// Reflect — top wall
// ---------------------------------------------------------------------------

TEST_F(BoundaryUtilsTest, ApplyBoundary_ReflectTopWall_ClampsPosAndNegatesVy)
{
    // Arrange
    float x = 0.0F, y = 1.2F, vx = 0.0F, vy = 5.0F;

    // Act
    applyBoundary(x, y, vx, vy, MIN, MAX, MIN, MAX, BoundaryMode::Reflect, DAMPING);

    // Assert
    EXPECT_NEAR(y, 1.0F, TOLERANCE);
    EXPECT_NEAR(vy, -4.0F, TOLERANCE);  // 5.0 * -0.8
    EXPECT_NEAR(x, 0.0F, TOLERANCE);
    EXPECT_NEAR(vx, 0.0F, TOLERANCE);
}

// ---------------------------------------------------------------------------
// Reflect — bottom wall
// ---------------------------------------------------------------------------

TEST_F(BoundaryUtilsTest, ApplyBoundary_ReflectBottomWall_ClampsPosAndNegatesVy)
{
    // Arrange
    float x = 0.0F, y = -1.3F, vx = 0.0F, vy = -2.5F;

    // Act
    applyBoundary(x, y, vx, vy, MIN, MAX, MIN, MAX, BoundaryMode::Reflect, DAMPING);

    // Assert
    EXPECT_NEAR(y, -1.0F, TOLERANCE);
    EXPECT_NEAR(vy, 2.0F, TOLERANCE);   // -2.5 * -0.8 = 2.0
    EXPECT_NEAR(x, 0.0F, TOLERANCE);
    EXPECT_NEAR(vx, 0.0F, TOLERANCE);
}

// ---------------------------------------------------------------------------
// Reflect — zero velocity at wall stays clamped
// ---------------------------------------------------------------------------

TEST_F(BoundaryUtilsTest, ApplyBoundary_ReflectZeroVelocity_ClampsPositionVelocityStaysZero)
{
    // Arrange — particle exactly at boundary with zero velocity
    float x = 1.5F, y = 0.0F, vx = 0.0F, vy = 0.0F;

    // Act
    applyBoundary(x, y, vx, vy, MIN, MAX, MIN, MAX, BoundaryMode::Reflect, DAMPING);

    // Assert — position clamped, velocity remains zero (0.0 * -damping = 0.0)
    EXPECT_NEAR(x, 1.0F, TOLERANCE);
    EXPECT_NEAR(vx, 0.0F, TOLERANCE);
}

// ---------------------------------------------------------------------------
// Reflect — elastic bounce (damping = 1.0) preserves speed
// ---------------------------------------------------------------------------

TEST_F(BoundaryUtilsTest, ApplyBoundary_ReflectElasticBounce_SpeedPreserved)
{
    // Arrange
    float x = 1.1F, y = 0.0F, vx = 3.0F, vy = 0.0F;

    // Act
    applyBoundary(x, y, vx, vy, MIN, MAX, MIN, MAX, BoundaryMode::Reflect, ELASTIC);

    // Assert — magnitude unchanged, direction negated
    EXPECT_NEAR(x, 1.0F, TOLERANCE);
    EXPECT_NEAR(vx, -3.0F, TOLERANCE);
}

// ---------------------------------------------------------------------------
// Inside domain — no effect (both modes)
// ---------------------------------------------------------------------------

TEST_F(BoundaryUtilsTest, ApplyBoundary_InsideDomainReflect_NoChange)
{
    // Arrange
    float x = 0.5F, y = -0.3F, vx = 1.0F, vy = -2.0F;
    float const origX = x, origY = y, origVx = vx, origVy = vy;

    // Act
    applyBoundary(x, y, vx, vy, MIN, MAX, MIN, MAX, BoundaryMode::Reflect, DAMPING);

    // Assert
    EXPECT_NEAR(x, origX, TOLERANCE);
    EXPECT_NEAR(y, origY, TOLERANCE);
    EXPECT_NEAR(vx, origVx, TOLERANCE);
    EXPECT_NEAR(vy, origVy, TOLERANCE);
}

TEST_F(BoundaryUtilsTest, ApplyBoundary_InsideDomainWrap_NoChange)
{
    // Arrange
    float x = 0.5F, y = -0.3F, vx = 1.0F, vy = -2.0F;
    float const origX = x, origY = y, origVx = vx, origVy = vy;

    // Act
    applyBoundary(x, y, vx, vy, MIN, MAX, MIN, MAX, BoundaryMode::Wrap, DAMPING);

    // Assert
    EXPECT_NEAR(x, origX, TOLERANCE);
    EXPECT_NEAR(y, origY, TOLERANCE);
    EXPECT_NEAR(vx, origVx, TOLERANCE);
    EXPECT_NEAR(vy, origVy, TOLERANCE);
}

// ---------------------------------------------------------------------------
// Wrap — right edge
// ---------------------------------------------------------------------------

TEST_F(BoundaryUtilsTest, ApplyBoundary_WrapRightEdge_WrapsToLeft)
{
    // Arrange — x = 1.1, domain [-1, 1], width = 2.0 => x becomes 1.1 - 2.0 = -0.9
    float x = 1.1F, y = 0.0F, vx = 1.0F, vy = 0.0F;

    // Act
    applyBoundary(x, y, vx, vy, MIN, MAX, MIN, MAX, BoundaryMode::Wrap, DAMPING);

    // Assert — position wraps, velocity unchanged
    EXPECT_NEAR(x, -0.9F, TOLERANCE);
    EXPECT_NEAR(vx, 1.0F, TOLERANCE);
}

// ---------------------------------------------------------------------------
// Wrap — left edge
// ---------------------------------------------------------------------------

TEST_F(BoundaryUtilsTest, ApplyBoundary_WrapLeftEdge_WrapsToRight)
{
    // Arrange — x = -1.4, domain [-1, 1] => x becomes -1.4 + 2.0 = 0.6
    float x = -1.4F, y = 0.0F, vx = -1.0F, vy = 0.0F;

    // Act
    applyBoundary(x, y, vx, vy, MIN, MAX, MIN, MAX, BoundaryMode::Wrap, DAMPING);

    // Assert
    EXPECT_NEAR(x, 0.6F, TOLERANCE);
    EXPECT_NEAR(vx, -1.0F, TOLERANCE);
}

// ---------------------------------------------------------------------------
// Wrap — top edge
// ---------------------------------------------------------------------------

TEST_F(BoundaryUtilsTest, ApplyBoundary_WrapTopEdge_WrapsToBottom)
{
    // Arrange — y = 1.3, domain [-1, 1] => y becomes 1.3 - 2.0 = -0.7
    float x = 0.0F, y = 1.3F, vx = 0.0F, vy = 2.0F;

    // Act
    applyBoundary(x, y, vx, vy, MIN, MAX, MIN, MAX, BoundaryMode::Wrap, DAMPING);

    // Assert
    EXPECT_NEAR(y, -0.7F, TOLERANCE);
    EXPECT_NEAR(vy, 2.0F, TOLERANCE);
}

// ---------------------------------------------------------------------------
// Wrap — bottom edge
// ---------------------------------------------------------------------------

TEST_F(BoundaryUtilsTest, ApplyBoundary_WrapBottomEdge_WrapsToTop)
{
    // Arrange — y = -1.5, domain [-1, 1] => y becomes -1.5 + 2.0 = 0.5
    float x = 0.0F, y = -1.5F, vx = 0.0F, vy = -1.0F;

    // Act
    applyBoundary(x, y, vx, vy, MIN, MAX, MIN, MAX, BoundaryMode::Wrap, DAMPING);

    // Assert
    EXPECT_NEAR(y, 0.5F, TOLERANCE);
    EXPECT_NEAR(vy, -1.0F, TOLERANCE);
}
