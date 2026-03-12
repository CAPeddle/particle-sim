#include "config/ConfigReader.hpp"

#include "config/ParameterLoader.hpp"
#include "core/Parameter.hpp"

#include <gtest/gtest.h>
#include <string>
#include <string_view>

#ifndef FIXTURE_DIR
#error "FIXTURE_DIR must be defined via CMake compile definition"
#endif

namespace psim::config
{

namespace
{

constexpr std::string_view VALID_CONFIG = FIXTURE_DIR "/valid_config.toml";
constexpr std::string_view MISSING_KEY = FIXTURE_DIR "/missing_key.toml";
constexpr std::string_view BAD_TYPE = FIXTURE_DIR "/bad_type.toml";
constexpr std::string_view NONEXISTENT = FIXTURE_DIR "/does_not_exist.toml";

// Named constants for test parameter values.
// Prevents magic-number warnings while documenting intent.
constexpr float SPEED_DEFAULT_FALLBACK = 2.5F;   ///< Fallback when key is absent.
constexpr float SPEED_SENTINEL_FALLBACK = 99.0F; ///< Sentinel that differs from any real config value.
constexpr float PARAM_MAX_VALUE = 10.0F;         ///< Upper bound for speed parameters in tests.
constexpr float PARAM_STEP_VALUE = 0.1F;         ///< Step increment for speed parameters in tests.
constexpr float SPEED_INITIAL_VALUE = 7.0F;      ///< Initial value chosen to be distinct from default.

} // namespace

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

struct ConfigReaderTest : public ::testing::Test
{
    ConfigReader reader; // NOLINT(readability-redundant-member-init) — explicit default for clarity
};

// ---------------------------------------------------------------------------
// isLoaded()
// ---------------------------------------------------------------------------

TEST_F(ConfigReaderTest, IsLoaded_BeforeLoad_ReturnsFalse)
{
    // Arrange / Act / Assert
    EXPECT_FALSE(reader.isLoaded());
}

TEST_F(ConfigReaderTest, IsLoaded_AfterSuccessfulLoad_ReturnsTrue)
{
    // Arrange
    auto result = reader.load(VALID_CONFIG);

    // Assert
    ASSERT_TRUE(result.has_value());
    EXPECT_TRUE(reader.isLoaded());
}

// ---------------------------------------------------------------------------
// load()
// ---------------------------------------------------------------------------

TEST_F(ConfigReaderTest, Load_ValidFile_ReturnsSuccess)
{
    // Act
    auto result = reader.load(VALID_CONFIG);

    // Assert
    EXPECT_TRUE(result.has_value());
}

TEST_F(ConfigReaderTest, Load_NonExistentFile_ReturnsConfigError)
{
    // Act
    auto result = reader.load(NONEXISTENT);

    // Assert
    ASSERT_FALSE(result.has_value());
    EXPECT_FALSE(result.error().message.empty());
}

// ---------------------------------------------------------------------------
// get<T>() — success cases
// ---------------------------------------------------------------------------

TEST_F(ConfigReaderTest, Get_Float_ValidKeyAndType_ReturnsCorrectValue)
{
    // Arrange
    ASSERT_TRUE(reader.load(VALID_CONFIG).has_value());

    // Act
    auto result = reader.get<float>("framework", "simulation_speed");

    // Assert
    ASSERT_TRUE(result.has_value());
    EXPECT_FLOAT_EQ(*result, 1.5F);
}

TEST_F(ConfigReaderTest, Get_Bool_ValidKeyAndType_ReturnsCorrectValue)
{
    // Arrange
    ASSERT_TRUE(reader.load(VALID_CONFIG).has_value());

    // Act
    auto result = reader.get<bool>("framework", "vsync");

    // Assert
    ASSERT_TRUE(result.has_value());
    EXPECT_TRUE(*result);
}

TEST_F(ConfigReaderTest, Get_Int_ValidKeyAndType_ReturnsCorrectValue)
{
    // Arrange
    ASSERT_TRUE(reader.load(VALID_CONFIG).has_value());

    // Act
    auto result = reader.get<int>("framework.window", "width");

    // Assert
    ASSERT_TRUE(result.has_value());
    EXPECT_EQ(*result, 1280);
}

TEST_F(ConfigReaderTest, Get_String_ValidKeyAndType_ReturnsCorrectValue)
{
    // Arrange
    ASSERT_TRUE(reader.load(VALID_CONFIG).has_value());

    // Act
    auto result = reader.get<std::string>("framework.window", "title");

    // Assert
    ASSERT_TRUE(result.has_value());
    EXPECT_EQ(*result, "Test Window");
}

// ---------------------------------------------------------------------------
// get<T>() — error cases
// ---------------------------------------------------------------------------

TEST_F(ConfigReaderTest, Get_Float_MissingKey_ReturnsConfigError)
{
    // Arrange
    ASSERT_TRUE(reader.load(MISSING_KEY).has_value());

    // Act
    auto result = reader.get<float>("framework", "simulation_speed");

    // Assert
    ASSERT_FALSE(result.has_value());
    EXPECT_FALSE(result.error().message.empty());
}

TEST_F(ConfigReaderTest, Get_Float_WrongType_ReturnsConfigError)
{
    // Arrange
    ASSERT_TRUE(reader.load(BAD_TYPE).has_value());

    // Act
    auto result = reader.get<float>("framework", "simulation_speed");

    // Assert
    ASSERT_FALSE(result.has_value());
    EXPECT_FALSE(result.error().message.empty());
}

// ---------------------------------------------------------------------------
// getOrDefault<T>()
// ---------------------------------------------------------------------------

TEST_F(ConfigReaderTest, GetOrDefault_MissingKey_ReturnsProvidedDefault)
{
    // Arrange
    ASSERT_TRUE(reader.load(MISSING_KEY).has_value());

    // Act
    auto const result = reader.getOrDefault<float>("framework", "simulation_speed", SPEED_DEFAULT_FALLBACK);

    // Assert
    EXPECT_FLOAT_EQ(result, SPEED_DEFAULT_FALLBACK);
}

TEST_F(ConfigReaderTest, GetOrDefault_ExistingKey_ReturnsConfigValue)
{
    // Arrange
    ASSERT_TRUE(reader.load(VALID_CONFIG).has_value());

    // Act
    auto const result = reader.getOrDefault<float>("framework", "simulation_speed", SPEED_SENTINEL_FALLBACK);

    // Assert
    EXPECT_FLOAT_EQ(result, 1.5F);
}

// ---------------------------------------------------------------------------
// ParameterLoader — ConfigReader → Parameter<T> bridge
// ---------------------------------------------------------------------------

TEST_F(ConfigReaderTest, LoadParameter_ValidConfig_FillsParameterValue)
{
    // Arrange
    ASSERT_TRUE(reader.load(VALID_CONFIG).has_value());

    psim::core::Parameter<float> param{
        .value = 0.0F,
        .minValue = 0.0F,
        .maxValue = PARAM_MAX_VALUE,
        .step = PARAM_STEP_VALUE,
        .name = "speed",
        .description = "Simulation speed",
    };

    // Act
    auto result = loadParameter(reader, "framework", "simulation_speed", param);

    // Assert
    ASSERT_TRUE(result.has_value());
    EXPECT_FLOAT_EQ(param.value, 1.5F);
}

TEST_F(ConfigReaderTest, LoadParameter_MissingKey_ReturnsErrorAndLeavesParamUnchanged)
{
    // Arrange
    ASSERT_TRUE(reader.load(MISSING_KEY).has_value());

    psim::core::Parameter<float> param{
        .value = SPEED_INITIAL_VALUE,
        .minValue = 0.0F,
        .maxValue = PARAM_MAX_VALUE,
        .step = PARAM_STEP_VALUE,
        .name = "speed",
        .description = "Simulation speed",
    };

    // Act
    auto result = loadParameter(reader, "framework", "simulation_speed", param);

    // Assert
    ASSERT_FALSE(result.has_value());
    EXPECT_FLOAT_EQ(param.value, SPEED_INITIAL_VALUE); // unchanged
}

} // namespace psim::config
