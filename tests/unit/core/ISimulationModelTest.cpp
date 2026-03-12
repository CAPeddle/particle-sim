#include "core/ISimulationModel.hpp"

#include "core/Parameter.hpp"

#include <array>
#include <cstdint>
#include <gtest/gtest.h>
#include <span>
#include <string_view>
#include <tuple>
#include <variant>

namespace psim::core
{

namespace
{

// ---------------------------------------------------------------------------
// Test constants — avoids cppcoreguidelines-avoid-magic-numbers.
// ---------------------------------------------------------------------------

constexpr std::uint32_t TEST_PARTICLE_COUNT{256U};
constexpr float TEST_DELTA_TIME{0.016F};

constexpr float ALPHA_VALUE{0.5F};
constexpr float ALPHA_MIN{0.0F};
constexpr float ALPHA_MAX{1.0F};
constexpr float ALPHA_STEP{0.01F};
constexpr int COUNT_VALUE{10};
constexpr int COUNT_MIN{1};
constexpr int COUNT_MAX{100};
constexpr int COUNT_STEP{1};

// Default parameter storage for TestModel instances.
// Defined at namespace scope so TestModel has no private members, satisfying
// cppcoreguidelines-non-private-member-variables-in-classes.
std::array<ParameterEntry, 2> makeDefaultParams()
{
    return {
        Parameter<float>{
            .value = ALPHA_VALUE,
            .minValue = ALPHA_MIN,
            .maxValue = ALPHA_MAX,
            .step = ALPHA_STEP,
            .name = "alpha",
            .description = "Alpha parameter",
        },
        Parameter<int>{
            .value = COUNT_VALUE,
            .minValue = COUNT_MIN,
            .maxValue = COUNT_MAX,
            .step = COUNT_STEP,
            .name = "count",
            .description = "Count parameter",
        },
    };
}

// ---------------------------------------------------------------------------
// TestModel — minimal concrete ISimulationModel for interface contract tests.
// Public observation fields are intentional — test doubles expose state
// directly for assertion without accessor boilerplate.
// NOLINTBEGIN(misc-non-private-member-variables-in-classes,cppcoreguidelines-non-private-member-variables-in-classes)
// ---------------------------------------------------------------------------
struct TestModel final : public ISimulationModel
{
    bool initCalled{false};
    bool updateCalled{false};
    bool destroyCalled{false};
    float lastDeltaTime{0.0F};
    std::uint32_t lastParticleCount{0U};
    bool initShouldSucceed{true};

    std::array<ParameterEntry, 2> params{makeDefaultParams()};
    // NOLINTEND(misc-non-private-member-variables-in-classes,cppcoreguidelines-non-private-member-variables-in-classes)

    TestModel() = default;

    [[nodiscard]] bool init(std::uint32_t particleCount) override
    {
        initCalled = true;
        lastParticleCount = particleCount;
        return initShouldSucceed;
    }

    void update(float deltaTime) override
    {
        updateCalled = true;
        lastDeltaTime = deltaTime;
    }

    void destroy() override { destroyCalled = true; }

    [[nodiscard]] std::span<const ParameterEntry> parameters() const override
    {
        return std::span<const ParameterEntry>{params};
    }

    [[nodiscard]] std::string_view name() const override { return "TestModel"; }
};

// ---------------------------------------------------------------------------
// Visitor for Parameters_FirstEntry test — extracted to satisfy
// readability-function-cognitive-complexity.
// ---------------------------------------------------------------------------
struct FirstParamVisitor
{
    void operator()(Parameter<float> const& param) const
    {
        EXPECT_EQ(param.name, "alpha");
        EXPECT_FLOAT_EQ(param.minValue, ALPHA_MIN);
        EXPECT_FLOAT_EQ(param.maxValue, ALPHA_MAX);
    }

    template <typename T>
    void operator()(T const& /*param*/) const
    {
        FAIL() << "Expected Parameter<float> at index 0";
    }
};

} // anonymous namespace

// ---------------------------------------------------------------------------
// Interface contract tests
// ---------------------------------------------------------------------------

struct ISimulationModelTest : public ::testing::Test
{
    TestModel model; // NOLINT(readability-redundant-member-init)
};

TEST_F(ISimulationModelTest, Init_ValidParticleCount_ReturnsTrue)
{
    // Arrange — model is in default state

    // Act
    bool const result = model.init(TEST_PARTICLE_COUNT);

    // Assert
    EXPECT_TRUE(result);
    EXPECT_TRUE(model.initCalled);
    EXPECT_EQ(model.lastParticleCount, TEST_PARTICLE_COUNT);
}

TEST_F(ISimulationModelTest, Init_Failure_ReturnsFalse)
{
    // Arrange
    model.initShouldSucceed = false;

    // Act
    bool const result = model.init(TEST_PARTICLE_COUNT);

    // Assert
    EXPECT_FALSE(result);
}

TEST_F(ISimulationModelTest, Update_AfterInit_ReceivesCorrectDeltaTime)
{
    // Arrange
    std::ignore = model.init(TEST_PARTICLE_COUNT);

    // Act
    model.update(TEST_DELTA_TIME);

    // Assert
    EXPECT_TRUE(model.updateCalled);
    EXPECT_FLOAT_EQ(model.lastDeltaTime, TEST_DELTA_TIME);
}

TEST_F(ISimulationModelTest, Destroy_AfterInit_IsCalled)
{
    // Arrange
    std::ignore = model.init(TEST_PARTICLE_COUNT);

    // Act
    model.destroy();

    // Assert
    EXPECT_TRUE(model.destroyCalled);
}

TEST_F(ISimulationModelTest, Parameters_ReturnsNonEmptySpan)
{
    // Arrange / Act
    std::span<const ParameterEntry> const params = model.parameters();

    // Assert
    EXPECT_FALSE(params.empty());
    EXPECT_EQ(params.size(), 2U);
}

TEST_F(ISimulationModelTest, Parameters_FirstEntry_IsFloatParameterWithCorrectMetadata)
{
    // Arrange / Act
    std::span<const ParameterEntry> const params = model.parameters();

    // Assert
    ASSERT_GE(params.size(), 1U);
    std::visit(FirstParamVisitor{}, params[0]);
}

TEST_F(ISimulationModelTest, Name_ReturnsModelDisplayName)
{
    // Arrange / Act
    std::string_view const modelName = model.name();

    // Assert
    EXPECT_EQ(modelName, "TestModel");
}

} // namespace psim::core
