// SphKernelsTest.cu
//
// Unit tests for the smoothing kernel device functions in SphKernels.cuh.
// Because the functions are __device__, they are exercised via thin
// __global__ wrapper kernels that write a single float result to
// device memory, which is then copied to host for assertion.
//
// Test naming: MethodName_Scenario_ExpectedBehaviour

#include "core/CudaUtils.hpp"
#include "models/SphKernels.cuh"

#include <cuda_runtime.h>
#include <gtest/gtest.h>

// ---------------------------------------------------------------------------
// Device wrappers
// ---------------------------------------------------------------------------

namespace
{

/// Evaluates smoothingKernel(distance, radius) on the GPU and returns the result.
__global__ void evalSmoothingKernelDevice(float distance, float radius, float* result)
{
    *result = psim::models::smoothingKernel(distance, radius);
}

/// Evaluates smoothingKernelGradient(distance, radius) on the GPU and returns the result.
__global__ void evalSmoothingKernelGradientDevice(float distance, float radius, float* result)
{
    *result = psim::models::smoothingKernelGradient(distance, radius);
}

float evalSmoothing(float distance, float radius)
{
    float* dResult = nullptr;
    CUDA_CHECK(cudaMalloc(&dResult, sizeof(float)));
    evalSmoothingKernelDevice<<<1, 1>>>(distance, radius, dResult);
    CUDA_CHECK(cudaDeviceSynchronize());
    float hResult = 0.0F;
    CUDA_CHECK(cudaMemcpy(&hResult, dResult, sizeof(float), cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaFree(dResult));
    return hResult;
}

float evalGradient(float distance, float radius)
{
    float* dResult = nullptr;
    CUDA_CHECK(cudaMalloc(&dResult, sizeof(float)));
    evalSmoothingKernelGradientDevice<<<1, 1>>>(distance, radius, dResult);
    CUDA_CHECK(cudaDeviceSynchronize());
    float hResult = 0.0F;
    CUDA_CHECK(cudaMemcpy(&hResult, dResult, sizeof(float), cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaFree(dResult));
    return hResult;
}

} // namespace

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

struct SphKernelsTest : public ::testing::Test
{
protected:
    void TearDown() override { EXPECT_EQ(cudaGetLastError(), cudaSuccess); }
};

// ---------------------------------------------------------------------------
// smoothingKernel — value tests
// ---------------------------------------------------------------------------

/// W(0, 1) must equal 1.0: maximum weight at zero distance.
TEST_F(SphKernelsTest, SmoothingKernel_AtOrigin_ReturnsOne)
{
    // Arrange / Act
    float result = evalSmoothing(0.0F, 1.0F);

    // Assert
    EXPECT_FLOAT_EQ(result, 1.0F);
}

/// W(1, 1) must equal 0.0: kernel is exactly zero at the influence boundary.
TEST_F(SphKernelsTest, SmoothingKernel_AtBoundary_ReturnsZero)
{
    // Arrange / Act
    float result = evalSmoothing(1.0F, 1.0F);

    // Assert
    EXPECT_FLOAT_EQ(result, 0.0F);
}

/// W(1.5, 1) must equal 0.0: kernel is zero beyond the influence radius.
TEST_F(SphKernelsTest, SmoothingKernel_BeyondRadius_ReturnsZero)
{
    // Arrange / Act
    float result = evalSmoothing(1.5F, 1.0F);

    // Assert
    EXPECT_FLOAT_EQ(result, 0.0F);
}

/// W(0.5, 1): q = (1-0.5)/1 = 0.5; W = 0.5^3 = 0.125.
TEST_F(SphKernelsTest, SmoothingKernel_HalfRadius_ReturnsCubicValue)
{
    // Arrange
    constexpr float EXPECTED = 0.125F; // (0.5)^3

    // Act
    float result = evalSmoothing(0.5F, 1.0F);

    // Assert
    EXPECT_FLOAT_EQ(result, EXPECTED);
}

/// W must be in [0, 1] for any distance in [0, h].
TEST_F(SphKernelsTest, SmoothingKernel_InsideRadius_IsNonNegative)
{
    // Arrange / Act / Assert
    EXPECT_GE(evalSmoothing(0.0F, 1.0F), 0.0F);
    EXPECT_GE(evalSmoothing(0.25F, 1.0F), 0.0F);
    EXPECT_GE(evalSmoothing(0.75F, 1.0F), 0.0F);
    EXPECT_GE(evalSmoothing(0.99F, 1.0F), 0.0F);
}

// ---------------------------------------------------------------------------
// smoothingKernelGradient — value tests
// ---------------------------------------------------------------------------

/// dW/dr(0.5, 1): q = 0.5; gradient = -3 * 0.25 / 1 = -0.75.
TEST_F(SphKernelsTest, KernelGradient_HalfRadius_MatchesAnalytic)
{
    // Arrange
    constexpr float EXPECTED = -0.75F; // -3 * (0.5)^2 / 1

    // Act
    float result = evalGradient(0.5F, 1.0F);

    // Assert
    EXPECT_FLOAT_EQ(result, EXPECTED);
}

/// dW/dr at the boundary must be 0.
TEST_F(SphKernelsTest, KernelGradient_AtBoundary_ReturnsZero)
{
    // Arrange / Act
    float result = evalGradient(1.0F, 1.0F);

    // Assert
    EXPECT_FLOAT_EQ(result, 0.0F);
}

/// dW/dr beyond the radius must be 0.
TEST_F(SphKernelsTest, KernelGradient_BeyondRadius_ReturnsZero)
{
    // Arrange / Act
    float result = evalGradient(2.0F, 1.0F);

    // Assert
    EXPECT_FLOAT_EQ(result, 0.0F);
}

/// Gradient must be <= 0 everywhere inside the support (kernel is monotonically decreasing).
TEST_F(SphKernelsTest, KernelGradient_InsideRadius_IsNonPositive)
{
    EXPECT_LE(evalGradient(0.0F, 1.0F), 0.0F);
    EXPECT_LE(evalGradient(0.1F, 1.0F), 0.0F);
    EXPECT_LE(evalGradient(0.5F, 1.0F), 0.0F);
    EXPECT_LE(evalGradient(0.9F, 1.0F), 0.0F);
}
