# ExecPlan: Phase 0 — GoogleTest Integration

**Date:** 2026-03-12  
**Status:** In Progress  
**Scope:** Add GoogleTest + GoogleMock to CMake; create test runner target; write first smoke test to verify the harness works.

---

## Purpose / Big Picture

All subsequent phases (TOML config, ISimulationModel, UniformGridIndex, SPH) follow TDD. That requires a working test harness _before any implementation code is written_. This plan stands up that harness as a standalone deliverable so every later phase can begin with RED tests immediately.

**Terms:**
- **TDD** — Test-Driven Development: write a failing test (RED) before the implementation code exists, make it pass (GREEN), then refactor.
- **GoogleTest (GTest)** — Google's C++ unit-testing framework (`gtest`).
- **GoogleMock (GMock)** — Mocking add-on bundled with GoogleTest (`gmock`).
- **FetchContent** — CMake module that downloads external dependencies at configure time.
- **CTest** — CMake's built-in test runner, invoked with `ctest`.

---

## Progress

- [x] `RED tests added` — `tests/unit/SmokeTest.cpp` committed 2026-03-12
- [x] `GREEN implementation completed` — `ctest` reports 1/1 PASSED 2026-03-12
- [x] `REFACTOR + validation completed` — clang-format OK, clang-tidy 0 findings 2026-03-12
- [x] `Code review — zero ERRORs` — 2026-03-12

---

## Surprises & Discoveries

_Empty — fill during execution._

---

## Decision Log

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Use `FetchContent` for GoogleTest, tag `v1.15.2` | Consistent with project's FetchContent-only policy; v1.15.2 is the latest stable as of 2026-03-12. |
| 2 | Separate `particle_sim_tests` executable | Keeps test binary isolated from the main executable; CTest can discover it automatically. |
| 3 | `gtest_discover_tests()` for CTest auto-discovery | Avoids manually naming every test in CMakeLists; picks up new tests automatically. |

---

## Outcomes & Retrospective

**Completed 2026-03-12.**

- GoogleTest v1.15.2 successfully integrated via FetchContent.
- `gtest_discover_tests()` auto-discovers tests — no manual CTest registration needed.
- `INSTALL_GTEST OFF` prevents GoogleTest from polluting the install target.
- Pattern to promote: add `target_compile_options` with `-Wall -Wextra -Wpedantic -Wshadow -Wconversion` on the test target separately from the main target, so warning flags are consistent.

---

## Context and Orientation

**Current state:**
- `CMakeLists.txt` has no GoogleTest reference, no `tests/` target.
- `tests/` directory does not exist.
- The project builds and runs (`./build/particle_sim` renders particles).

**What this plan adds:**
- GoogleTest v1.15.2 via FetchContent.
- `tests/` directory with a `CMakeLists.txt` that builds `particle_sim_tests`.
- `add_subdirectory(tests)` wired into the root `CMakeLists.txt`.
- `enable_testing()` + `gtest_discover_tests()` so `ctest` works.
- One smoke test: `SmokeTest_AlwaysPasses` to verify the harness itself.

**Files touched:**
- `CMakeLists.txt` (root) — add FetchContent block + `enable_testing()` + `add_subdirectory(tests)`
- `tests/CMakeLists.txt` — new file, builds the test executable
- `tests/unit/SmokeTest.cpp` — new file, one trivial `TEST()` to confirm linking works

---

## Plan of Work

1. Add GoogleTest FetchContent block to root `CMakeLists.txt`.
2. Add `enable_testing()` and `add_subdirectory(tests)` to root `CMakeLists.txt`.
3. Create `tests/CMakeLists.txt` that builds `particle_sim_tests` linked against `gtest_main` and `gmock`.
4. Create `tests/unit/SmokeTest.cpp` with a trivial `EXPECT_EQ(1, 1)` test.
5. Configure + build. Confirm `ctest` reports 1/1 PASSED.
6. clang-format the new `.cpp` file. Confirm clang-tidy clean.

---

## Concrete Steps

### Step 1 — Add GoogleTest FetchContent and test wiring to root CMakeLists.txt

In `CMakeLists.txt`, after the ImGui block and before the main executable block, add:

```cmake
# ============================================================================
# GoogleTest
# ============================================================================
FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        v1.15.2
    GIT_SHALLOW    TRUE
)
# Suppress GoogleTest's own install rules
set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

enable_testing()
add_subdirectory(tests)
```

### Step 2 — Create tests/CMakeLists.txt

```cmake
add_executable(particle_sim_tests
    unit/SmokeTest.cpp
)

target_link_libraries(particle_sim_tests PRIVATE
    gtest_main
    gmock
)

target_compile_options(particle_sim_tests PRIVATE
    $<$<COMPILE_LANGUAGE:CXX>:-Wall -Wextra -Wpedantic -Wshadow -Wconversion>
)

include(GoogleTest)
gtest_discover_tests(particle_sim_tests)
```

### Step 3 — Create tests/unit/SmokeTest.cpp

```cpp
#include <gtest/gtest.h>

// Verifies that the GoogleTest harness is correctly wired into CMake.
// This test has no domain logic — it exists only to confirm the test
// infrastructure itself compiles and runs.
TEST(SmokeTest, HarnessCompiles)
{
    EXPECT_EQ(1, 1);
}
```

### Step 4 — Configure, build, and run tests

```bash
# Working directory: /home/cpeddle/projects/personal/particle-sim
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
cd build && ctest --output-on-failure
```

Expected output:
```
Test project /home/cpeddle/projects/personal/particle-sim/build
    Start 1: SmokeTest.HarnessCompiles
1/1 Test #1: SmokeTest.HarnessCompiles ........   Passed    0.00 sec

100% tests passed, 0 tests failed out of 1
```

### Step 5 — clang-format

```bash
clang-format -i --style=file:.clang-format tests/unit/SmokeTest.cpp
```

---

## Validation and Acceptance

| # | Check | Observable Evidence |
|---|-------|---------------------|
| 1 | Build succeeds | `cmake --build build` exits 0, no errors |
| 2 | Tests pass | `ctest --output-on-failure` reports `100% tests passed, 0 tests failed out of 1` |
| 3 | clang-format clean | `clang-format --dry-run --Werror tests/unit/SmokeTest.cpp` exits 0 |
| 4 | clang-tidy clean | `clang-tidy -p build tests/unit/SmokeTest.cpp` exits 0, zero findings |

---

## Idempotence and Recovery

- Re-running `cmake -B build` is safe — FetchContent caches the downloaded source.
- If GoogleTest download fails (network), set `GIT_SHALLOW FALSE` and retry.
- The test executable is separate from `particle_sim` — removing `tests/` does not affect the main build.

---

## Artifacts and Notes

- GoogleTest source: `build/_deps/googletest-src/`
- Test binary: `build/tests/particle_sim_tests`
- CTest config: `build/CTestTestfile.cmake`

---

## Interfaces and Dependencies

**Depends on:** Nothing (pure CMake + download).  
**Required by:** All subsequent phases (Phases 1–8) — every TDD cycle needs this.  
**No changes to:** `src/`, `shaders/`, existing `CMakeLists.txt` targets other than additions.
