# ExecPlan: Phase 2 — TOML Config System (toml11 v4.4.0)

**Date:** 2026-03-12  
**Status:** Completed  
**Prerequisite:** [Phase 1 — ISimulationModel + Parameter\<T\>](2026-03-12-phase-1-simulation-model-interface.md) — all five Progress checkboxes must be ticked before starting this plan. [Phase 0](2026-03-12-phase-0-googletest-integration.md) transitively required.

---

## Purpose / Big Picture

All simulation parameters in `main.cpp` and CUDA kernels are currently hard-coded (`particleCount = 100000`, `swirl strength`, etc.). This plan introduces a TOML configuration file loaded at startup, integrated with the `Parameter<T>` metadata system from Phase 1, so parameters are readable from `config.toml` and exposed in ImGui without per-parameter hand-wiring.

**Library decision: toml11 v4.4.0** — see research in `COMPARISON_RESEARCH.md`. Exception-free via `toml::try_parse()`, actively maintained, FetchContent-compatible, C++23 clean.

**Terms:**
- **TOML** — Configuration file format (Tom's Obvious, Minimal Language). Human-readable; supports tables, arrays, typed values.
- **toml11** — C++ TOML parsing library (`ToruNiina/toml11`). Used in the predecessor project (fluid-sim).
- **`ConfigReader`** — New class in `psim::config` that owns the parsed `toml::value` and provides typed `get<T>()` access.
- **`ConfigError`** — Error type used in `std::expected<T, ConfigError>` returns.

---

## Progress

- [x] `Prerequisites verified` — [Phase 1](2026-03-12-phase-1-simulation-model-interface.md) shows all five checkboxes ticked; `src/core/Parameter.hpp` and `src/core/ISimulationModel.hpp` exist — 2026-03-12
- [x] `RED tests added` — test files committed; build fails because `ConfigReader` doesn't exist yet — 2026-03-12
- [x] `GREEN implementation completed` — `ConfigReader` + `config.toml` written; tests pass (28/28) — 2026-03-12
- [x] `REFACTOR + validation completed` — clang-format + clang-tidy clean (zero findings) — 2026-03-12
- [x] `Code review — zero ERRORs` — 2026-03-12

---

## Surprises & Discoveries

- **clang-18 / libstdc++-13 `__cpp_concepts` mismatch**: clang-18 emits `__cpp_concepts=201907L` but GCC 13's `<expected>` header requires `>= 202002L`. Fixed by adding `ExtraArgs: ['-D__cpp_concepts=202002L']` to `.clang-tidy`. This is a known clang/libstdc++ interop quirk on Ubuntu 24.04.
- **Template isolation via explicit instantiation**: confirmed that `extern template` + explicit instantiation in `.cpp` fully prevents toml11 headers leaking to callers; only `ConfigReader.cpp` includes `<toml.hpp>`.
- **Pimpl naming**: project style is `camelBack` without trailing underscore for private members (per `.clang-tidy` `PrivateMemberCase`). Member named `impl` (not `impl_`).

---

## Decision Log

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | toml11 v4.4.0 | Latest stable (Feb 2025), first-class `try_parse` result type, C++23 clean, predecessor used it. |
| 2 | Pimpl pattern — `ConfigReader.hpp` forward-declares `struct Impl`; `toml::value` lives only in `.cpp` | Isolates toml11 dependency to `src/config/` — all callers see only C++ types. Chosen over plain `.inl` include or unconstrained templates. |
| 3 | `extern template` for `float`, `int`, `bool`, `std::string` | Suppresses implicit instantiation in all caller TUs; confirms the isolation holds. |
| 4 | `config.toml` lives at the working directory root (next to the binary) | Binary-relative path via `argv[0]`; `CMAKE_POST_BUILD` copies it automatically. |
| 5 | Device-side constants passed as kernel arguments (not `__constant__` memory) | More flexible; constant memory requires recompile to change, kernel args don't. |
| 6 | `[framework]` and `[model.sph]` top-level sections | Extensible — each future model has its own table without touching framework keys. |
| 7 | `ConfigValue` concept aliases `ParameterValue` (float, int, bool, std::string) | Consistent type coverage; `get<T>` constrained to exactly the types that can round-trip through both TOML and `Parameter<T>`. |
| 8 | `ParameterValue` extended with `std::string`; `ParameterEntry` variant extended | Enables string parameters (window title, boundary_mode) without creating a separate concept hierarchy. |
| 9 | Fail-fast on missing `config.toml` | Matches project Fail-Fast principle; config is a required artifact, not optional. |
| 10 | `__cpp_concepts=202002L` in `.clang-tidy` ExtraArgs | Workaround for clang-18/libstdc++-13 version skew; documented inline. |

---

## Outcomes & Retrospective

- 28 tests passing (14 Phase 0-1 + 14 new ConfigReader tests).
- toml11 fully isolated: zero callers of `ConfigReader.hpp` include any toml11 symbol.
- `ParameterValue` concept extended to include `std::string`; `ParameterEntry` variant extended; existing tests updated.
- `ParameterLoader.hpp` provides zero-overhead bridge from config to `Parameter<T>` with no coupling.
- `main.cpp` now reads all hard-coded values from `config.toml`; fails fast on missing file.
- `.clang-tidy` now has `ExtraArgs` to work around the clang-18/libstdc++-13 `__cpp_concepts` version mismatch.

---

## Context and Orientation

**Current state after Phase 1:**
- `Parameter<T>` and `ISimulationModel` exist in `src/core/`.
- `main.cpp` has hard-coded: `particleCount = 100000`, window `1280x720`, VSync on, `simulationSpeed = 1.0f`.

**What this plan adds:**
- toml11 FetchContent block in `CMakeLists.txt`.
- `src/config/ConfigReader.hpp` + `src/config/ConfigReader.cpp`.
- `src/config/ConfigError.hpp`.
- `config.toml` at project root with `[framework]` and `[model.sph]` sections.
- `main.cpp` updated to load `config.toml` at startup; hard-coded values replaced.
- `tests/unit/config/ConfigReaderTest.cpp`.
- Test fixture TOML files in `tests/fixtures/`.

---

## Plan of Work

1. Add toml11 FetchContent to `CMakeLists.txt`.
2. Write RED tests for `ConfigReader` using fixture TOML files.
3. Implement `ConfigError.hpp` + `ConfigReader.hpp/.cpp`.
4. Update `main.cpp` to load from `config.toml`.
5. Create `config.toml` with full default values.
6. Run tests; confirm GREEN.
7. clang-format + clang-tidy.

---

## Concrete Steps

### Step 0 — Verify prerequisites

Open [Phase 1](2026-03-12-phase-1-simulation-model-interface.md) and confirm all five Progress checkboxes are ticked.

Verify the following files exist:

```bash
ls src/core/Parameter.hpp src/core/ISimulationModel.hpp
```

Then confirm tests still pass:

```bash
cmake --build build --target particle_sim_tests && cd build && ctest --output-on-failure
```

If any check fails, do not proceed — resolve Phase 1 first.

### Step 1 — Add toml11 to CMakeLists.txt

```cmake
# ============================================================================
# toml11 (TOML config parsing)
# ============================================================================
FetchContent_Declare(
    toml11
    GIT_REPOSITORY https://github.com/ToruNiina/toml11.git
    GIT_TAG        v4.4.0
    GIT_SHALLOW    TRUE
)
set(TOML11_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
set(TOML11_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(toml11)
```

Link `toml11::toml11` to `particle_sim` and `particle_sim_tests`.

### Step 2 — RED: Create test fixture files + tests

**`tests/fixtures/valid_config.toml`** — well-formed config file.  
**`tests/fixtures/missing_key.toml`** — config with a required key removed.  
**`tests/fixtures/bad_type.toml`** — config with a key of the wrong type.

**`tests/unit/config/ConfigReaderTest.cpp`** covers:
- `ConfigReader::load()` succeeds on valid file.
- `get<float>("framework", "simulation_speed")` returns correct value.
- `load()` returns `ConfigError` on missing file.
- `get<float>()` returns `ConfigError` on missing key.
- `get<float>()` returns `ConfigError` on type mismatch.
- `getOrDefault<int>()` returns default when key is absent.

### Step 3 — Implement `src/config/ConfigError.hpp`

```cpp
#pragma once
#include <string>

namespace psim::config {

/// @brief Error type for configuration operations.
struct ConfigError
{
    std::string message;
};

} // namespace psim::config
```

### Step 4 — Implement `src/config/ConfigReader.hpp`

```cpp
#pragma once

#include "config/ConfigError.hpp"

#include <expected>
#include <string>
#include <string_view>

#include <toml.hpp>

namespace psim::config {

/// @brief Loads and queries a TOML configuration file.
///
/// All access is exception-free via std::expected<T, ConfigError>.
/// The parsed document is owned by this object; callers receive typed values.
///
/// @note ConfigReader is move-only (owns toml::value).
class ConfigReader
{
public:
    ConfigReader()                               = default;
    ~ConfigReader()                              = default;
    ConfigReader(const ConfigReader&)            = delete;
    ConfigReader& operator=(const ConfigReader&) = delete;
    ConfigReader(ConfigReader&&)                 = default;
    ConfigReader& operator=(ConfigReader&&)      = default;

    /// @brief Load and parse a TOML file.
    ///
    /// @param path Filesystem path to the .toml file.
    /// @return ConfigError on parse failure or file not found.
    [[nodiscard]] std::expected<void, ConfigError> load(std::string_view path);

    /// @brief Read a typed value from a two-level table.key path.
    ///
    /// @tparam T  Target C++ type (float, int, bool, std::string, etc.)
    /// @param section  Top-level table name.
    /// @param key      Key within that table.
    /// @return Value on success, ConfigError on missing key or type mismatch.
    ///
    /// @pre load() returned success.
    template <typename T>
    [[nodiscard]] std::expected<T, ConfigError> get(std::string_view section,
                                                     std::string_view key) const;

    /// @brief Read a typed value, returning a default if absent.
    ///
    /// @pre load() returned success.
    template <typename T>
    [[nodiscard]] T getOrDefault(std::string_view section,
                                 std::string_view key,
                                 T                defaultValue) const;

    /// @brief Returns true if load() has been called successfully.
    [[nodiscard]] bool isLoaded() const noexcept;

private:
    toml::value root_{};
    bool        loaded_{false};
};

} // namespace psim::config
```

### Step 5 — Create `config.toml`

```toml
[framework]
simulation_speed = 1.0
vsync            = true

[framework.window]
width  = 1280
height = 720
title  = "Particle Simulation Framework"

[framework.rendering]
point_size        = 3.0
background_r      = 0.05
background_g      = 0.05
background_b      = 0.08

[model.sph]
particle_count   = 100000
gravity_x        = 0.0
gravity_y        = -9.81
damping          = 0.999
influence_radius = 0.05
rest_density     = 1000.0
gas_constant     = 2000.0
viscosity        = 250.0
boundary_mode    = "reflect"

[model.gameoflife]
grid_width       = 256
grid_height      = 256
initial_density  = 0.3
```

### Step 6 — Update main.cpp

Replace hard-coded values with `ConfigReader::get<T>()` calls. `config.toml` is searched relative to the working directory. On failure, print the error and fall back to defaults (fail-safe startup, not fail-fast, since this is a demo app).

---

## Validation and Acceptance

| # | Check | Observable Evidence |
|---|-------|---------------------|
| 1 | Tests pass | `ctest --output-on-failure` all PASSED |
| 2 | App starts with config file | `./build/particle_sim` loads; ImGui shows `Particles: 100000` (from toml, not hard-code) |
| 3 | App starts without config file | Falls back to defaults; stderr prints `Config warning: config.toml not found` |
| 4 | clang-format + clang-tidy clean | Zero findings on all new `.cpp`/`.hpp` files |

---

## Idempotence and Recovery

- toml11 source cached in `build/_deps/toml11-src/`.
- `config.toml` is a plain text file — safe to edit and re-run without rebuilding.
- On bad config values, `getOrDefault` guarantees the app always starts.

---

## Artifacts and Notes

- `src/config/ConfigError.hpp`
- `src/config/ConfigReader.hpp`
- `src/config/ConfigReader.cpp`
- `config.toml`
- `tests/unit/config/ConfigReaderTest.cpp`
- `tests/fixtures/valid_config.toml`, `missing_key.toml`, `bad_type.toml`

---

## Interfaces and Dependencies

**Depends on:** Phase 1 (Parameter\<T\> for later integration), Phase 0 (GoogleTest).  
**Required by:** Phase 3+ — all models read their parameters from config.  
**toml11 API reference:** https://github.com/ToruNiina/toml11 — `toml::try_parse`, `toml::find<T>`, `toml::find_or`.
