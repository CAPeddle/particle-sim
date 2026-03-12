#include "core/Parameter.hpp"

#include <gtest/gtest.h>
#include <string>
#include <type_traits>
#include <variant>

namespace psim::core
{

// ---------------------------------------------------------------------------
// Parameter<float>
// ---------------------------------------------------------------------------

TEST(ParameterTest, FloatParameter_StoresAllFields_Correctly)
{
    // Arrange / Act
    Parameter<float> const param{
        .value = 1.5F,
        .minValue = 0.0F,
        .maxValue = 10.0F,
        .step = 0.1F,
        .name = "radius",
        .description = "Smoothing radius",
    };

    // Assert
    EXPECT_FLOAT_EQ(param.value, 1.5F);
    EXPECT_FLOAT_EQ(param.minValue, 0.0F);
    EXPECT_FLOAT_EQ(param.maxValue, 10.0F);
    EXPECT_FLOAT_EQ(param.step, 0.1F);
    EXPECT_EQ(param.name, "radius");
    EXPECT_EQ(param.description, "Smoothing radius");
}

// ---------------------------------------------------------------------------
// Parameter<int>
// ---------------------------------------------------------------------------

TEST(ParameterTest, IntParameter_StoresAllFields_Correctly)
{
    // Arrange / Act
    Parameter<int> const param{
        .value = 42,
        .minValue = 0,
        .maxValue = 100,
        .step = 1,
        .name = "count",
        .description = "Particle count",
    };

    // Assert
    EXPECT_EQ(param.value, 42);
    EXPECT_EQ(param.minValue, 0);
    EXPECT_EQ(param.maxValue, 100);
    EXPECT_EQ(param.step, 1);
    EXPECT_EQ(param.name, "count");
    EXPECT_EQ(param.description, "Particle count");
}

// ---------------------------------------------------------------------------
// Parameter<bool>
// ---------------------------------------------------------------------------

TEST(ParameterTest, BoolParameter_StoresValueAndName_Correctly)
{
    // Arrange / Act
    Parameter<bool> const param{
        .value = true,
        .minValue = false,
        .maxValue = true,
        .step = false,
        .name = "gravity",
        .description = "Enable gravity",
    };

    // Assert
    EXPECT_TRUE(param.value);
    EXPECT_EQ(param.name, "gravity");
    EXPECT_EQ(param.description, "Enable gravity");
}

// ---------------------------------------------------------------------------
// ParameterValue concept — compile-time constraints
// ---------------------------------------------------------------------------

// Verified via static_assert: only float, int, bool, std::string satisfy ParameterValue.
static_assert(ParameterValue<float>, "float must satisfy ParameterValue");
static_assert(ParameterValue<int>, "int must satisfy ParameterValue");
static_assert(ParameterValue<bool>, "bool must satisfy ParameterValue");
static_assert(ParameterValue<std::string>, "std::string must satisfy ParameterValue");
static_assert(!ParameterValue<double>, "double must NOT satisfy ParameterValue");
static_assert(!ParameterValue<unsigned int>, "unsigned int must NOT satisfy ParameterValue");

// ---------------------------------------------------------------------------
// ParameterEntry variant
// ---------------------------------------------------------------------------

TEST(ParameterEntryTest, HoldsFloatParameter_VisitReturnsCorrectValue)
{
    // Arrange
    ParameterEntry const entry = Parameter<float>{
        .value = 3.14F,
        .minValue = 0.0F,
        .maxValue = 6.28F,
        .step = 0.01F,
        .name = "pi",
        .description = "Approximation of pi",
    };

    // Act / Assert
    std::visit(
        [](auto const& param)
        {
            using T = std::decay_t<decltype(param)>;
            if constexpr (std::is_same_v<T, Parameter<float>>)
            {
                EXPECT_FLOAT_EQ(param.value, 3.14F);
                EXPECT_EQ(param.name, "pi");
            }
            else
            {
                FAIL() << "Expected Parameter<float>, got another type";
            }
        },
        entry);
}

TEST(ParameterEntryTest, HoldsIntParameter_VisitReturnsCorrectValue)
{
    // Arrange
    ParameterEntry const entry = Parameter<int>{
        .value = 7,
        .minValue = 1,
        .maxValue = 100,
        .step = 1,
        .name = "iterations",
        .description = "Solver iterations",
    };

    // Act / Assert
    std::visit(
        [](auto const& param)
        {
            using T = std::decay_t<decltype(param)>;
            if constexpr (std::is_same_v<T, Parameter<int>>)
            {
                EXPECT_EQ(param.value, 7);
                EXPECT_EQ(param.name, "iterations");
            }
            else
            {
                FAIL() << "Expected Parameter<int>, got another type";
            }
        },
        entry);
}

TEST(ParameterEntryTest, HoldsBoolParameter_VisitReturnsCorrectValue)
{
    // Arrange
    ParameterEntry const entry = Parameter<bool>{
        .value = false,
        .minValue = false,
        .maxValue = true,
        .step = false,
        .name = "paused",
        .description = "Pause simulation",
    };

    // Act / Assert
    std::visit(
        [](auto const& param)
        {
            using T = std::decay_t<decltype(param)>;
            if constexpr (std::is_same_v<T, Parameter<bool>>)
            {
                EXPECT_FALSE(param.value);
                EXPECT_EQ(param.name, "paused");
            }
            else
            {
                FAIL() << "Expected Parameter<bool>, got another type";
            }
        },
        entry);
}

} // namespace psim::core
