#include <gtest/gtest.h>

// Verifies that the GoogleTest harness is correctly wired into CMake.
// This test has no domain logic — it exists only to confirm the test
// infrastructure itself compiles and runs.
TEST(SmokeTest, HarnessCompiles)
{
    EXPECT_EQ(1, 1);
}
