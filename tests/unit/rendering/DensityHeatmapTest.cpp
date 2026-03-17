// DensityHeatmapTest.cpp
//
// Lifecycle unit tests for DensityHeatmap (init / destroy).
//
// Rendering is not testable headlessly, so tests guard with GTEST_SKIP when a
// GL / CUDA context cannot be established (CI / WSL headless environments).
// When a display and CUDA device are present, tests exercise the full texture
// creation and teardown path.
//
// TDD: these tests are written before the implementation (RED phase). They
// will fail to link until DensityHeatmap.cu is wired into the build.

// clang-format off
// GLAD must be included before GLFW and any other GL headers.
#include <glad/gl.h>
// clang-format on

#include "rendering/DensityHeatmap.cuh"

#include "core/CudaUtils.hpp"
#include "rendering/GpuScalarFieldInput.cuh"

#include <GLFW/glfw3.h>
#include <array>
#include <cstdint>
#include <cuda_runtime_api.h>
#include <driver_types.h>
#include <gtest/gtest.h>

using psim::rendering::DensityHeatmap;
using psim::rendering::destroyDensityHeatmap;
using psim::rendering::initDensityHeatmap;

/// Resolution used for all lifecycle tests (small to keep init fast).
static constexpr int TEST_HEATMAP_RESOLUTION = 64;

/// OpenGL context version required for CUDA-GL interop.
static constexpr int OPENGL_MAJOR = 4;
static constexpr int OPENGL_MINOR = 6;

TEST(GpuScalarFieldInputTest, DefaultConstruct_AllFieldsAtDefaultValues)
{
    // Arrange / Act
    const psim::rendering::GpuScalarFieldInput input{};

    // Assert
    EXPECT_EQ(input.posX, nullptr);
    EXPECT_EQ(input.posY, nullptr);
    EXPECT_EQ(input.scalarValues, nullptr);
    EXPECT_EQ(input.particleCount, 0U);
    EXPECT_EQ(input.domainMin.x, 0.0F);
    EXPECT_EQ(input.domainMin.y, 0.0F);
    EXPECT_EQ(input.domainMax.x, 0.0F);
    EXPECT_EQ(input.domainMax.y, 0.0F);
    EXPECT_EQ(input.minValue, 0.0F);
    EXPECT_EQ(input.maxValue, 1.0F);
    EXPECT_FALSE(input.overrideRange);
}

// ---------------------------------------------------------------------------
// Test fixture — creates a 1×1 invisible GL window for context
// ---------------------------------------------------------------------------

struct DensityHeatmapTest : public ::testing::Test
{
protected:
    // NOLINTBEGIN(cppcoreguidelines-non-private-member-variables-in-classes,misc-non-private-member-variables-in-classes)
    GLFWwindow* window{nullptr};
    // NOLINTEND(cppcoreguidelines-non-private-member-variables-in-classes,misc-non-private-member-variables-in-classes)

    void SetUp() override
    {
        if (glfwInit() == GLFW_FALSE)
        {
            GTEST_SKIP() << "GLFW init failed — headless environment, skipping GL tests";
        }

        glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, OPENGL_MAJOR);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, OPENGL_MINOR);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

        window = glfwCreateWindow(1, 1, "DensityHeatmapTest", nullptr, nullptr);
        if (window == nullptr)
        {
            glfwTerminate();
            GTEST_SKIP() << "GL context creation failed — headless environment, skipping GL tests";
        }

        glfwMakeContextCurrent(window);

        if (gladLoadGL(glfwGetProcAddress) == 0)
        {
            glfwDestroyWindow(window);
            window = nullptr;
            glfwTerminate();
            GTEST_SKIP() << "GLAD load failed — skipping GL tests";
        }

        int deviceCount = 0;
        if (cudaGetDeviceCount(&deviceCount) != cudaSuccess || deviceCount == 0)
        {
            GTEST_SKIP() << "No CUDA device available";
        }
    }

    void TearDown() override
    {
        if (window != nullptr)
        {
            glfwDestroyWindow(window);
            window = nullptr;
            glfwTerminate();
        }
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Initialising a default-constructed heatmap must produce a non-zero GL texture ID.
TEST_F(DensityHeatmapTest, Init_ValidResolution_CreatesNonZeroTextureId)
{
    // Arrange
    DensityHeatmap heatmap;

    // Act
    auto result = psim::rendering::initDensityHeatmap(
        heatmap, TEST_HEATMAP_RESOLUTION, SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");
    ASSERT_TRUE(result.has_value()) << result.error().message();

    // Assert
    EXPECT_NE(heatmap.textureId, 0U);
    EXPECT_NE(heatmap.shaderProgram, 0U);
    EXPECT_NE(heatmap.quadVao, 0U);
    EXPECT_NE(heatmap.quadVbo, 0U);
    EXPECT_NE(heatmap.accumBuffer.get(), nullptr);
    EXPECT_NE(heatmap.countBuffer.get(), nullptr);
    EXPECT_NE(heatmap.discardCountBuf.get(), nullptr);

    destroyDensityHeatmap(heatmap);
}

/// After destroy, textureId must be reset to 0.
TEST_F(DensityHeatmapTest, Destroy_AfterInit_SetsTextureIdToZero)
{
    // Arrange
    DensityHeatmap heatmap;
    auto initResult = psim::rendering::initDensityHeatmap(
        heatmap, TEST_HEATMAP_RESOLUTION, SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");
    ASSERT_TRUE(initResult.has_value()) << initResult.error().message();

    // Act
    destroyDensityHeatmap(heatmap);

    // Assert
    EXPECT_EQ(heatmap.textureId, 0U);
    EXPECT_EQ(heatmap.shaderProgram, 0U);
    EXPECT_EQ(heatmap.quadVao, 0U);
    EXPECT_EQ(heatmap.quadVbo, 0U);
    EXPECT_EQ(heatmap.cudaTexResource, nullptr);
    EXPECT_EQ(heatmap.uniformDensityTexLoc, -1);
    EXPECT_EQ(heatmap.uniformMaxValueLoc, -1);
    EXPECT_EQ(heatmap.uniformAlphaLoc, -1);
}

/// Calling destroy twice must not crash or corrupt state.
TEST_F(DensityHeatmapTest, Destroy_CalledTwice_IsIdempotent)
{
    // Arrange
    DensityHeatmap heatmap;
    auto initResult = psim::rendering::initDensityHeatmap(
        heatmap, TEST_HEATMAP_RESOLUTION, SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");
    ASSERT_TRUE(initResult.has_value()) << initResult.error().message();
    destroyDensityHeatmap(heatmap);

    // Act + Assert — second destroy must not abort or segfault
    EXPECT_NO_FATAL_FAILURE(destroyDensityHeatmap(heatmap));
    EXPECT_EQ(heatmap.textureId, 0U);
}

/// `initDensityHeatmap` must return a success value when given valid arguments.
/// RED: fails to compile until initDensityHeatmap returns std::expected.
TEST_F(DensityHeatmapTest, Init_ReturnsSuccess_WhenValidArgs)
{
    // Arrange
    DensityHeatmap heatmap;

    // Act
    auto result =
        initDensityHeatmap(heatmap, TEST_HEATMAP_RESOLUTION, SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");

    // Assert
    EXPECT_TRUE(result.has_value());

    destroyDensityHeatmap(heatmap);
}

/// `initDensityHeatmap` must return an error when given invalid shader paths.
/// RED: fails to compile until initDensityHeatmap returns std::expected.
TEST_F(DensityHeatmapTest, Init_ReturnsError_WhenShaderPathInvalid)
{
    // Arrange
    DensityHeatmap heatmap;

    // Act
    auto result = initDensityHeatmap(heatmap, TEST_HEATMAP_RESOLUTION, "nonexistent.vert", "nonexistent.frag");

    // Assert
    EXPECT_FALSE(result.has_value());
    EXPECT_EQ(heatmap.textureId, 0U);
    EXPECT_EQ(heatmap.shaderProgram, 0U); // CR-4: shader program must not leak on load failure
}

/// `initDensityHeatmap` must return an error when resolution <= 0.
/// RED: fails to compile until initDensityHeatmap returns std::expected.
TEST_F(DensityHeatmapTest, Init_NegativeResolution_ReturnsError)
{
    // Arrange
    DensityHeatmap heatmap;

    // Act
    auto result = initDensityHeatmap(heatmap, -1, SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");

    // Assert
    EXPECT_FALSE(result.has_value());
}

/// `updateDensityHeatmap` must not crash when the heatmap is disabled.
TEST_F(DensityHeatmapTest, Update_WhenDisabled_DoesNotCrash)
{
    // Arrange
    DensityHeatmap heatmap;
    auto initResult = psim::rendering::initDensityHeatmap(
        heatmap, TEST_HEATMAP_RESOLUTION, SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");
    ASSERT_TRUE(initResult.has_value()) << initResult.error().message();
    heatmap.enabled = false;

    const psim::rendering::GpuScalarFieldInput input{};

    // Act + Assert — must not crash
    EXPECT_NO_FATAL_FAILURE(updateDensityHeatmap(heatmap, input));

    destroyDensityHeatmap(heatmap);
}

TEST_F(DensityHeatmapTest, UpdateDensityHeatmap_ZeroParticleCount_IsNoOp)
{
    // Arrange
    DensityHeatmap heatmap;
    auto result = psim::rendering::initDensityHeatmap(
        heatmap, TEST_HEATMAP_RESOLUTION, SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");
    ASSERT_TRUE(result.has_value());

    constexpr float TEST_MAX_VALUE = 100.0F;

    psim::rendering::GpuScalarFieldInput input{};
    input.particleCount = 0U;
    input.domainMin = {0.0F, 0.0F};
    input.domainMax = {1.0F, 1.0F};
    input.overrideRange = true;
    input.minValue = 0.0F;
    input.maxValue = TEST_MAX_VALUE;
    heatmap.enabled = true;

    // Act
    EXPECT_NO_FATAL_FAILURE(psim::rendering::updateDensityHeatmap(heatmap, input));

    // Assert
    EXPECT_EQ(cudaGetLastError(), cudaSuccess);

    psim::rendering::destroyDensityHeatmap(heatmap);
}

TEST_F(DensityHeatmapTest, UpdateDensityHeatmap_NullPositionPtr_WithNonZeroCount_Aborts)
{
    // Arrange
    DensityHeatmap heatmap;
    auto result = psim::rendering::initDensityHeatmap(
        heatmap, TEST_HEATMAP_RESOLUTION, SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");
    ASSERT_TRUE(result.has_value());

    constexpr uint32_t NON_ZERO_PARTICLE_COUNT = 10U;
    constexpr float TEST_MAX_VALUE = 100.0F;

    psim::rendering::GpuScalarFieldInput input{};
    input.posX = nullptr;
    input.posY = nullptr;
    input.scalarValues = nullptr;
    input.particleCount = NON_ZERO_PARTICLE_COUNT;
    input.domainMin = {0.0F, 0.0F};
    input.domainMax = {1.0F, 1.0F};
    input.overrideRange = true;
    input.minValue = 0.0F;
    input.maxValue = TEST_MAX_VALUE;
    heatmap.enabled = true;

    // Act + Assert
    EXPECT_DEATH(psim::rendering::updateDensityHeatmap(heatmap, input), "");

    psim::rendering::destroyDensityHeatmap(heatmap);
}

TEST_F(DensityHeatmapTest,
       UpdateDensityHeatmap_OverrideRangeTrue_UsesProvidedMinMax) // NOLINT(readability-function-cognitive-complexity)
{
    // Arrange
    DensityHeatmap heatmap;
    auto result = psim::rendering::initDensityHeatmap(
        heatmap, TEST_HEATMAP_RESOLUTION, SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");
    ASSERT_TRUE(result.has_value());

    constexpr float EXPECTED_MIN_VALUE = 10.0F;
    constexpr float EXPECTED_MAX_VALUE = 50.0F;

    psim::core::CudaBuffer<float> posX;
    psim::core::CudaBuffer<float> posY;
    psim::core::CudaBuffer<float> scalars;
    posX.allocate(1U);
    posY.allocate(1U);
    scalars.allocate(1U);
    const float hPosX = 0.5F;
    const float hPosY = 0.5F;
    const float hScalar = 42.0F;
    ASSERT_EQ(cudaMemcpy(posX.get(), &hPosX, sizeof(float), cudaMemcpyHostToDevice), cudaSuccess);
    ASSERT_EQ(cudaMemcpy(posY.get(), &hPosY, sizeof(float), cudaMemcpyHostToDevice), cudaSuccess);
    ASSERT_EQ(cudaMemcpy(scalars.get(), &hScalar, sizeof(float), cudaMemcpyHostToDevice), cudaSuccess);

    psim::rendering::GpuScalarFieldInput input{};
    input.posX = posX.get();
    input.posY = posY.get();
    input.scalarValues = scalars.get();
    input.particleCount = 1U;
    input.domainMin = {0.0F, 0.0F};
    input.domainMax = {1.0F, 1.0F};
    input.overrideRange = true;
    input.minValue = EXPECTED_MIN_VALUE;
    input.maxValue = EXPECTED_MAX_VALUE;
    heatmap.enabled = true;

    // Act
    EXPECT_NO_FATAL_FAILURE(psim::rendering::updateDensityHeatmap(heatmap, input));

    // Assert
    EXPECT_FLOAT_EQ(heatmap.computedMin, EXPECTED_MIN_VALUE);
    EXPECT_FLOAT_EQ(heatmap.computedMax, EXPECTED_MAX_VALUE);
    EXPECT_EQ(cudaGetLastError(), cudaSuccess);

    psim::rendering::destroyDensityHeatmap(heatmap);
}

TEST_F(DensityHeatmapTest,
       UpdateDensityHeatmap_OverrideRangeFalse_AutoComputesRange) // NOLINT(readability-function-cognitive-complexity)
{
    // Arrange
    DensityHeatmap heatmap;
    auto result = psim::rendering::initDensityHeatmap(
        heatmap, TEST_HEATMAP_RESOLUTION, SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");
    ASSERT_TRUE(result.has_value());

    constexpr uint32_t PARTICLE_COUNT = 3U;
    psim::core::CudaBuffer<float> posX;
    psim::core::CudaBuffer<float> posY;
    psim::core::CudaBuffer<float> scalars;
    posX.allocate(PARTICLE_COUNT);
    posY.allocate(PARTICLE_COUNT);
    scalars.allocate(PARTICLE_COUNT);
    const std::array<float, PARTICLE_COUNT> hPosX{{0.2F, 0.5F, 0.8F}};
    const std::array<float, PARTICLE_COUNT> hPosY{{0.5F, 0.5F, 0.5F}};
    const std::array<float, PARTICLE_COUNT> hScalars{{5.0F, 15.0F, 10.0F}};
    ASSERT_EQ(cudaMemcpy(posX.get(), hPosX.data(), PARTICLE_COUNT * sizeof(float), cudaMemcpyHostToDevice),
              cudaSuccess);
    ASSERT_EQ(cudaMemcpy(posY.get(), hPosY.data(), PARTICLE_COUNT * sizeof(float), cudaMemcpyHostToDevice),
              cudaSuccess);
    ASSERT_EQ(cudaMemcpy(scalars.get(), hScalars.data(), PARTICLE_COUNT * sizeof(float), cudaMemcpyHostToDevice),
              cudaSuccess);

    psim::rendering::GpuScalarFieldInput input{};
    input.posX = posX.get();
    input.posY = posY.get();
    input.scalarValues = scalars.get();
    input.particleCount = PARTICLE_COUNT;
    input.domainMin = {0.0F, 0.0F};
    input.domainMax = {1.0F, 1.0F};
    input.overrideRange = false;
    heatmap.enabled = true;

    // Act
    EXPECT_NO_FATAL_FAILURE(psim::rendering::updateDensityHeatmap(heatmap, input));

    // Assert
    EXPECT_FLOAT_EQ(heatmap.computedMin, 5.0F);
    EXPECT_FLOAT_EQ(heatmap.computedMax, 15.0F);
    EXPECT_EQ(cudaGetLastError(), cudaSuccess);

    psim::rendering::destroyDensityHeatmap(heatmap);
}

/// `renderDensityHeatmap` must not crash when the heatmap is enabled.
TEST_F(DensityHeatmapTest, Render_WhenEnabled_DoesNotCrash)
{
    // Arrange
    DensityHeatmap heatmap;
    auto initResult = psim::rendering::initDensityHeatmap(
        heatmap, TEST_HEATMAP_RESOLUTION, SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");
    ASSERT_TRUE(initResult.has_value()) << initResult.error().message();
    heatmap.enabled = true;

    // Act + Assert — must not crash
    EXPECT_NO_FATAL_FAILURE(renderDensityHeatmap(heatmap));

    destroyDensityHeatmap(heatmap);
}

/// Calling `destroyDensityHeatmap` on a default-constructed heatmap must be a no-op.
TEST_F(DensityHeatmapTest, Destroy_WithoutInit_IsNoOp)
{
    // Arrange
    DensityHeatmap heatmap;

    // Act + Assert — must not crash
    EXPECT_NO_FATAL_FAILURE(destroyDensityHeatmap(heatmap));
    EXPECT_EQ(heatmap.textureId, 0U);
}
