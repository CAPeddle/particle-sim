# ExecPlan: Phase 1 — ISimulationModel + Parameter\<T\>

**Date:** 2026-03-12  
**Status:** Completed  
**Prerequisite:** [Phase 0 — GoogleTest Integration](2026-03-12-phase-0-googletest-integration.md) — all four Progress checkboxes must be ticked before starting this plan.

---

## Purpose / Big Picture

Particle-sim is a _framework_, not a single simulation. The `ISimulationModel` interface is the extension point that allows different simulations (SPH fluid, Game of Life, etc.) to be registered and run without modifying framework code.

`Parameter<T>` is the metadata-bearing runtime parameter type that models declare. The framework uses this metadata to auto-generate ImGui controls and (later) to serialize/deserialize from TOML config.

Neither exists yet. All later phases depend on them being in place before adding model-specific logic.

**Terms:**
- **ISimulationModel** — Abstract C++ interface (`psim::core` namespace) that each simulation model must implement. Defines lifecycle (init/update/destroy) and parameter declaration.
- **Parameter\<T\>** — Template struct that wraps a value of type `T` with metadata: display name, min, max, step, description. Used by ImGui layer to render controls generically.
- **Strategy Pattern** — Design pattern where a family of algorithms (simulation models) are encapsulated behind a common interface and made interchangeable.
- **TDD** — Test-Driven Development: failing test committed before implementation.

---

## Progress

- [x] `Prerequisites verified` — Phase 0 shows all four checkboxes ticked; `ctest` 1/1 PASSED — 2026-03-12
- [x] `RED tests added` — test files committed; build fails because classes don't exist yet — 2026-03-12
- [x] `GREEN implementation completed` — headers written; tests pass — 2026-03-12
- [x] `REFACTOR + validation completed` — clang-format + clang-tidy clean — 2026-03-12
- [x] `Code review — zero ERRORs` — 2026-03-12

---

## Surprises & Discoveries

_Empty — fill during execution._

---

## Decision Log

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | `ISimulationModel` in `src/core/` | Core framework interface; not model-specific. |
| 2 | `Parameter<T>` as a plain struct template (not class hierarchy) | Simple data holder; no virtual dispatch needed. ImGui layer inspects it directly. |
| 3 | `Parameter<T>` constrains `T` with a concept `ParameterValue` | Limits instantiations to `float`, `int`, `bool` — the only types ImGui can render as sliders/checkboxes. Catches errors at compile time. |
| 4 | `ISimulationModel::parameters()` returns `std::span<ParameterEntry>` | Non-owning view; model owns the storage. Framework gets read access without allocation. |
| 5 | `ParameterEntry` is a type-erased wrapper using `std::variant` | Avoids virtual dispatch per parameter while still supporting heterogeneous collections. |

---

## Outcomes & Retrospective

_Empty — fill at completion._

---

## Context and Orientation

**Current state after Phase 0:**
- GoogleTest is integrated; `ctest` works.
- `src/spatial/ISpatialIndex.hpp` exists (separate from this plan — not modified here).
- No `src/core/` directory exists.

**What this plan adds:**
- `src/core/Parameter.hpp` — `ParameterValue` concept + `Parameter<T>` struct + `ParameterEntry` variant
- `src/core/ISimulationModel.hpp` — abstract model interface
- `tests/unit/core/ParameterTest.cpp` — unit tests for `Parameter<T>`
- `tests/unit/core/ISimulationModelTest.cpp` — interface contract tests via a test double

**Files modified:**
- `tests/CMakeLists.txt` — add new test source files

---

## Plan of Work

1. Write RED tests for `Parameter<T>` and `ISimulationModel`.
2. Implement `Parameter.hpp`.
3. Implement `ISimulationModel.hpp`.
4. Run tests; confirm GREEN.
5. clang-format + clang-tidy. Confirm clean.

---

## Concrete Steps

### Step 0 — Verify prerequisites

Open [Phase 0](2026-03-12-phase-0-googletest-integration.md) and confirm all four Progress checkboxes are ticked.

Then run from the workspace root:

```bash
cd /home/cpeddle/projects/personal/particle-sim
cmake --build build --target particle_sim_tests
cd build && ctest --output-on-failure
```

Expected: `100% tests passed`. If this fails, do not proceed — fix Phase 0 first.

### Step 1 — RED: Write tests (before any implementation)

**`tests/unit/core/ParameterTest.cpp`**

Tests cover:
- `Parameter<float>` stores value, min, max, step, name correctly.
- `Parameter<int>` static_asserts that non-`ParameterValue` types are rejected (negative test via SFINAE, not runtime).
- `ParameterEntry` holds a `Parameter<float>` or `Parameter<int>` and `std::visit` can retrieve the value.

**`tests/unit/core/ISimulationModelTest.cpp`**

Tests cover (via a `TestModel` derived class):
- `init()` is called and succeeds.
- `update(dt)` is called with correct delta time.
- `parameters()` returns the declared parameters with correct metadata.
- Model can be destroyed cleanly.

These tests **must be committed before any `.hpp` file in `src/core/` is created.**

### Step 2 — Implement `src/core/Parameter.hpp`

```cpp
#pragma once

#include <concepts>
#include <string_view>
#include <variant>

namespace psim::core {

/// @brief Concept restricting Parameter<T> to types renderable by ImGui.
template <typename T>
concept ParameterValue = std::same_as<T, float> || std::same_as<T, int> || std::same_as<T, bool>;

/// @brief Runtime parameter with metadata for UI rendering and serialization.
///
/// @tparam T Value type — must satisfy ParameterValue.
///
/// @note Instances are owned by the model that declares them.
///       The framework holds non-owning views (std::span<ParameterEntry>).
template <ParameterValue T>
struct Parameter
{
    T            value;        ///< Current value
    T            minValue;     ///< Minimum (used for slider range)
    T            maxValue;     ///< Maximum (used for slider range)
    T            step;         ///< Step size (used for drag controls)
    std::string_view name;     ///< Display name shown in ImGui
    std::string_view description; ///< Tooltip text
};

/// @brief Type-erased container for any Parameter<T>.
///
/// Allows heterogeneous collections of parameters without virtual dispatch.
using ParameterEntry = std::variant<Parameter<float>, Parameter<int>, Parameter<bool>>;

} // namespace psim::core
```

### Step 3 — Implement `src/core/ISimulationModel.hpp`

```cpp
#pragma once

#include "core/Parameter.hpp"

#include <span>
#include <cstdint>

namespace psim::core {

/// @brief Abstract interface for simulation models.
///
/// Each simulation model (SPH fluid, Game of Life, etc.) implements this
/// interface. The framework calls init() once, update() each frame, and
/// destroy() on shutdown.
///
/// @details
/// Models declare their runtime parameters via parameters(). The framework
/// uses this to auto-generate ImGui controls and serialize to TOML config.
///
/// Thread Safety: Not thread-safe. All methods must be called from the
/// render/simulation thread.
class ISimulationModel
{
public:
    virtual ~ISimulationModel() = default;

    ISimulationModel(const ISimulationModel&)            = delete;
    ISimulationModel& operator=(const ISimulationModel&) = delete;
    ISimulationModel(ISimulationModel&&)                 = default;
    ISimulationModel& operator=(ISimulationModel&&)      = default;

    /// @brief Initialize the model (allocate GPU memory, set up initial state).
    ///
    /// @param particleCount Number of particles to allocate.
    /// @return true on success, false on failure.
    ///
    /// @pre particleCount > 0
    /// @post Model is ready for update() calls.
    [[nodiscard]] virtual bool init(std::uint32_t particleCount) = 0;

    /// @brief Advance the simulation by one time step.
    ///
    /// @param dt Delta time in seconds. Must be > 0.
    ///
    /// @pre init() returned true.
    virtual void update(float dt) = 0;

    /// @brief Release all resources (GPU memory, OpenGL buffers).
    ///
    /// @post Model is in an uninitialized state. init() may be called again.
    virtual void destroy() = 0;

    /// @brief Returns a non-owning view of this model's runtime parameters.
    ///
    /// @return Span over parameter entries. Valid for the lifetime of this model.
    ///
    /// @note The returned span is invalidated if the model is destroyed.
    [[nodiscard]] virtual std::span<ParameterEntry> parameters() = 0;

    /// @brief Returns the display name of this model (e.g. "SPH Fluid").
    [[nodiscard]] virtual std::string_view name() const = 0;

protected:
    ISimulationModel() = default;
};

} // namespace psim::core
```

### Step 4 — Wire new sources into tests/CMakeLists.txt

Add `unit/core/ParameterTest.cpp` and `unit/core/ISimulationModelTest.cpp` to `particle_sim_tests` sources.

Also add `src/` to test include directories (tests include `core/Parameter.hpp`):

```cmake
target_include_directories(particle_sim_tests PRIVATE
    ${CMAKE_SOURCE_DIR}/src
)
```

### Step 5 — Build and test

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
cd build && ctest --output-on-failure
```

All tests must pass. Zero build warnings under `-Wall -Wextra -Wpedantic`.

### Step 6 — Format and lint

```bash
clang-format -i --style=file:.clang-format \
    src/core/Parameter.hpp \
    src/core/ISimulationModel.hpp \
    tests/unit/core/ParameterTest.cpp \
    tests/unit/core/ISimulationModelTest.cpp

clang-tidy -p build \
    src/core/Parameter.hpp \
    src/core/ISimulationModel.hpp \
    tests/unit/core/ParameterTest.cpp \
    tests/unit/core/ISimulationModelTest.cpp
```

---

## Validation and Acceptance

| # | Check | Observable Evidence |
|---|-------|---------------------|
| 1 | Tests pass | `ctest --output-on-failure` reports all tests PASSED |
| 2 | No build warnings | `cmake --build build` output contains no `warning:` lines |
| 3 | clang-format clean | `clang-format --dry-run --Werror` exits 0 for all new files |
| 4 | clang-tidy clean | `clang-tidy` exits 0 with zero findings for `.cpp`/`.hpp` files |

---

## Idempotence and Recovery

- Headers are pure declarations (no CUDA, no link-time dependencies). Re-running `cmake --build` is always safe.
- If the `ParameterValue` concept causes clang-tidy complaints, annotate with `// NOLINT` + reason.

---

## Artifacts and Notes

- `src/core/Parameter.hpp`
- `src/core/ISimulationModel.hpp`
- `tests/unit/core/ParameterTest.cpp`
- `tests/unit/core/ISimulationModelTest.cpp`

---

## Interfaces and Dependencies

**Depends on:** Phase 0 (GoogleTest).  
**Required by:** Phase 2 (TOML config, wires into `Parameter<T>`), Phase 3 (UniformGridIndex tests use `ISimulationModel`-aligned types), Phase 4 (SPH model implements `ISimulationModel`).
