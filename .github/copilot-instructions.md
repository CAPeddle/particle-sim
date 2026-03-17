# copilot-instructions.md

## Purpose

This document instructs GitHub Copilot (and any code generator) how to produce code for **particle-sim**.
These rules define particle-sim's architecture, coding style, and quality expectations to ensure the codebase remains maintainable, portable, and production-ready.

> **High-level summary**
>
> * **Language:** C++23 + CUDA 20
> * **Build:** CMake 3.28 + Ninja
> * **Packages:** FetchContent (GLFW, GLAD, ImGui)
> * **GPU:** CUDA 13.2, CUDA-OpenGL interop
> * **Formatting:** clang-format (LLVM-based), see `.clang-format`
> * **Linting:** clang-tidy — strict, all warnings as errors, see `.clang-tidy`
> * **Testing:** GoogleTest + GoogleMock (TDD / Triple-A) — to be integrated
> * **Sanitizers:** ASan / UBSan (TSan for CPU code)
> * **Targets:** Linux (WSL primary), Windows native
> * **Quality:** SOLID / KISS / Fail-Fast / RAII patterns

---

## Priority Guidelines

1. **Platform & Tooling**
   * Must build with CMake 3.28+ + Ninja.
   * Primary development: WSL Linux with CUDA 13.2.
   * Windows native builds supported via MSVC 2022+.
   * Target GPU: NVIDIA RTX 4050 Laptop (SM 89 / Ada Lovelace).

2. **Language Standards**
   * Use modern, portable **C++23** features for CPU code (concepts, ranges, `std::span`, `constexpr` algorithms).
   * Use **CUDA 20** features for GPU kernels (`__device__` lambdas, cooperative groups where needed).
   * Avoid compiler-specific extensions except CUDA-specific `__host__`, `__device__`, `__global__`.

3. **Formatting & Linting**
   * Always format using clang-format (`--style=file:.clang-format`).
   * Code must be clang-tidy clean — zero warnings, zero errors. All checks are hard errors.
   * Never suppress a check without an inline `// NOLINT(check-name)` comment explaining the reason.
   * Note: CUDA `.cu` files have limited clang-tidy support; focus on `.cpp` / `.hpp` files.

4. **Architecture & Layout**
   * Follow the canonical directory structure defined below.
   * Strategy Pattern: Models implement `ISimulationModel` interface.
   * Struct-of-Arrays for GPU memory coalescing.
   * Double buffering (ping-pong) for synchronous updates.

5. **API Surface**
   * Keep public API minimal and documented.
   * Prefer deep modules (wide interface, narrow public surface).

6. **Testing**
   * Follow **Red → Green → Refactor** TDD cycle.
   * Write tests before implementation where practical.
   * GPU tests use separate validation harnesses.

7. **Safety / Memory**
   * Validate preconditions (Fail-Fast).
   * Use `std::unique_ptr`, `std::shared_ptr`, `std::span`, `std::optional`, `std::expected`.
   * Avoid hidden allocations and unnecessary dynamic memory.
   * Never call `new` / `delete` directly for CPU memory.
   * CUDA memory: Use RAII wrappers for `cudaMalloc` / `cudaFree`.

8. **Error Handling**
   * No exceptions. Use `std::expected<T, E>` or `std::error_code` for all error propagation.
   * Check all CUDA calls for errors; use a macro wrapper.

9. **Documentation**
   * Use Doxygen-style `/// @brief` comments for all public APIs.

---

## Technology Stack

| Area | Tooling / Policy |
|------|-----------------|
| **Language** | C++23 (CPU), CUDA 20 (GPU) |
| **Platform** | Linux/WSL (primary), Windows |
| **GPU** | NVIDIA CUDA 13.2, RTX 4050 (SM 89) |
| **Build System** | CMake ≥ 3.28 + Ninja |
| **Package Manager** | FetchContent |
| **Graphics** | OpenGL 4.6 (via GLAD), CUDA-GL interop |
| **Windowing** | GLFW 3.4 |
| **UI** | Dear ImGui 1.91.6 |
| **Testing** | GoogleTest / GoogleMock (to be integrated) |
| **Formatting** | clang-format (LLVM-based) |
| **Linting** | clang-tidy (strict — all checks, all errors) |
| **Sanitizers** | ASan / UBSan (CPU code) |

---

## Directory Structure

```
particle-sim/
├── CLAUDE.md              # AI context and project vision
├── CMakeLists.txt         # Root build configuration
├── docs/
│   └── adr/               # Architecture Decision Records
├── src/
│   ├── main.cpp           # Application entry point
│   ├── core/              # Framework core (Application, ISimulationModel, Parameter)
│   ├── models/            # Simulation model implementations
│   │   ├── GameOfLifeCUDA.cu/.cuh
│   │   └── FluidSPHCUDA.cu/.cuh
│   ├── spatial/           # Spatial indexing (ISpatialIndex, UniformGridIndex)
│   ├── rendering/         # OpenGL rendering, CUDA-GL interop
│   └── ui/                # ImGui layer
├── shaders/
│   ├── particle.vert
│   └── particle.frag
└── tests/                 # Unit and integration tests
```

* **Filenames:** `PascalCase`. Example: `ParticleSystem.cu`, `ISpatialIndex.hpp`.
* **CUDA files:** `.cu` for sources, `.cuh` for headers.
* **Headers:** `#pragma once` (already established in codebase).

---

## Naming Conventions

| Element | Style | Example |
|---------|-------|---------|
| **Namespaces** | `psim::Subsystem` | `psim::spatial`, `psim::rendering` |
| **Classes / Structs / Enums / Concepts** | PascalCase | `ParticleSystem`, `QueryResult` |
| **Interfaces** | `IInterfaceName` | `ISpatialIndex`, `ISimulationModel` |
| **Functions / Methods** | camelCase | `rebuild()`, `queryAll()` |
| **Variables / Parameters** | camelCase | `particleCount`, `maxNeighbours` |
| **Private members** | camelCase (no prefix) | `cellSize`, `positions` |
| **Constants** | `UPPER_SNAKE_CASE` or `inline constexpr` | `MAX_PARTICLES` |
| **CMake targets** | snake_case | `particle_sim` |
| **CUDA kernels** | camelCase with `Kernel` suffix | `updatePositionsKernel` |

---

## Docstrings

All public APIs must use Doxygen-style comments:

```cpp
/// @brief Rebuilds the spatial index for a new particle configuration.
///
/// @param positions Device memory view of particle positions (non-owning).
///
/// @details
/// - Must be called before any query operations.
/// - Invalidates any prior query results.
/// - O(N) construction using counting sort.
///
/// @pre positions.x, positions.y are valid device pointers.
/// @pre positions.count > 0.
///
/// @note Thread-safety: Not thread-safe. Do not call concurrently with queries.
virtual void rebuild(ParticlePositionsView positions) = 0;
```

Include `@brief`, `@param`, `@tparam`, `@return`, `@pre`, `@post`, `@note`, and `@details` where applicable. Document invariants, ownership, and thread-safety.

---

## Coding Practices

* **SOLID / KISS** — small, focused classes with a single responsibility.
* **Fail-Fast** — validate preconditions at function entry; assert in debug, return error in release.
* **Pure Functions** — prefer stateless helpers.
* **Encapsulation** — minimal public surface; avoid `friend`.
* **Memory & Ownership** — use smart pointers and `std::span`. Never call `new` / `delete`.
* **Rule of Five** — any class with a custom destructor must explicitly declare all five special members.
  * Use `= default` for compiler-generated implementations.
  * Use `= delete` to disable copying/moving when not needed.
  * Prefer RAII and smart pointers to avoid needing custom special members at all.
* **Concurrency** — isolate shared state; prefer message-passing.
* **Error Handling** — no exceptions. Use `std::expected<T, E>` or `std::error_code`.
* **Performance** — avoid hidden allocations; expose profiling hooks.
* **Deep Modules** — prefer wide, deep interfaces.

### CUDA-Specific Practices

* **Memory Coalescing** — use Struct-of-Arrays layout so warp threads access contiguous memory.
* **Warp Divergence** — use fixed maximum neighbour counts with padding; process similar-count particles together.
* **Atomic Contention** — prefer counting sort (count → prefix sum → scatter) over per-particle atomics.
* **Synchronisation** — use separate kernel launches as implicit barriers for multi-pass algorithms.
* **Error Checking** — wrap all CUDA calls with error-checking macro:
  ```cpp
  #define CUDA_CHECK(call) \
      do { \
          cudaError_t err = call; \
          if (err != cudaSuccess) { \
              std::fprintf(stderr, "CUDA error at %s:%d: %s\n", \
                  __FILE__, __LINE__, cudaGetErrorString(err)); \
              std::abort(); \
          } \
      } while(0)
  ```

### Container and View Vocabulary

| Scenario | Preferred type |
|----------|---------------|
| Parameter — read-only sequence access | `std::span<const T>` |
| Parameter — element mutation, no resize | `std::span<T>` |
| Parameter — push/erase/resize | `std::vector<T>&` |
| Data member / stored collection | `std::vector<T>` |
| Return — transfer ownership | `std::vector<T>` |
| Return — non-owning view (lifetime externally guaranteed only) | `std::span<T>` |
| GPU memory view | Custom `*View` structs (e.g., `ParticlePositionsView`) |

---

## Testing

Tests use the **Triple-A (Arrange / Act / Assert)** pattern.

* **Framework:** GoogleTest + GoogleMock (to be integrated).
* **Naming:** `MethodName_Scenario_ExpectedBehaviour`.
* **Location:** `tests/unit/<subsystem>/`, `tests/integration/`.
* **TDD rule:** Tests are written **before** implementation. The RED phase must be committed.

```cpp
#include <gtest/gtest.h>

struct UniformGridIndexTest : public ::testing::Test
{
    // Common setup
};

TEST_F(UniformGridIndexTest, Rebuild_ValidPositions_BuildsWithoutError)
{
    // Arrange
    UniformGridIndex index{cellSize, domainBounds};
    auto positions = createTestPositions(100);

    // Act
    index.rebuild(positions);

    // Assert
    EXPECT_FALSE(index.empty());
}
```

---

## Build & CI

### CMake

* Use `target_*` commands; never global includes.
* Mandatory warning flags:
  ```cmake
  # C/C++ (not CUDA)
  -Wall -Wextra -Wpedantic -Wshadow -Wconversion
  ```
* CUDA flags:
  ```cmake
  --expt-relaxed-constexpr -allow-unsupported-compiler
  ```
* Enable sanitizers for CPU code:
  ```cmake
  -fsanitize=address,undefined -fno-omit-frame-pointer
  ```

### Build Instructions

**Prerequisites:** CMake 3.28+, Ninja, CUDA Toolkit 13.2, GCC 13+ or Clang 18+ (Linux), MSVC 2022+ (Windows).

**Step 1 — Configure:**
```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
```

**Step 2 — Build:**
```bash
cmake --build build
```

**Step 3 — Run:**
```bash
./build/particle_sim
```

### Adding New Source Files

When creating a new `.cpp`, `.cu`, `.hpp`, or `.cuh` file:
* Add to `target_sources(particle_sim ...)` in `CMakeLists.txt`.
* Follow the directory structure conventions.

---

## Formatting and Linting

* **Formatting:** `clang-format -i --style=file:.clang-format <file>`. See `.clang-format`.
* **Linting:** `clang-tidy -p build/ <file>`. See `.clang-tidy`. All checks are hard errors.
* **Pre-commit gates:** Both tools run before commit. See `.github/hooks/quality-gate.json`.

---

## Contribution Flow

* **Branches:** `main` (stable), `dev` (active), `feature/<short-description>`
* **Commits:** Follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)

### Commit Message Standard

```
<type>(<scope>): <short description>

[optional body]

Refs: PS-XXXX
```

**Allowed types:** `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, `chore`, `revert`

**Scopes:** `core`, `spatial`, `rendering`, `models`, `ui`, `build`, `docs`

### PR Requirements

* clang-format clean
* clang-tidy clean (zero warnings for `.cpp` / `.hpp`)
* Build succeeds without errors
* All tests pass

---

## AI Tool Usage Guidelines

*Based on Jason Turner, "Best Practices for AI Tool Use", CppCon 2025, and the github/awesome-copilot best practices review.*

### Known AI Weaknesses in C++

Language models default to pre-C++11 patterns. Be alert for:
* Raw `new`/`delete` — replace with `std::make_unique` / `std::make_shared`
* Raw owning pointers (`T*`, `T[]`) — use smart pointers
* Manual resource management — use RAII
* Exception-based error handling — use `std::expected`
* Pre-C++11 type casts (`(T)x`) — use `static_cast`, `reinterpret_cast`
* Hallucinated API calls — verify all functions exist in real headers before accepting

### CUDA-Specific AI Pitfalls

* **Wrong compute capability** — always specify SM 89 for this project
* **Missing error checks** — all CUDA calls must be wrapped with `CUDA_CHECK`
* **Incorrect memory layout** — verify Struct-of-Arrays, not Array-of-Structs
* **Missing `__device__` / `__host__` specifiers** — verify function decorators
* **Sync issues** — ensure proper `__syncthreads()` or kernel boundaries

### Prompt Discipline

When giving an AI a C++ task, always specify:
1. C++ standard: `C++23` (CPU), `CUDA 20` (GPU)
2. Forbidden patterns: `no new/delete, no raw owning pointers, no exceptions`
3. Error handling: `use std::expected<T, E>`
4. Naming convention: `psim:: namespace, PascalCase classes, camelCase functions`
5. Sanitizer: `must compile and run clean under ASan + UBSan`
6. GPU target: `SM 89 (RTX 4050 Laptop)`

### Output Review Checklist

Before accepting any AI-produced C++ code, verify:
- [ ] No raw `new`/`delete`
- [ ] No raw owning pointers
- [ ] No exceptions (`throw`, `try`, `catch`)
- [ ] No pre-C++11 idioms (C-style casts, C I/O functions in non-legacy code)
- [ ] Names match project conventions (`psim::`, PascalCase, camelCase)
- [ ] No hallucinated APIs — all calls exist in actual headers
- [ ] CUDA kernels have proper `__global__`, `__device__`, `__host__` decorators
- [ ] CUDA calls wrapped with error checking
- [ ] Code compiles without warnings at the project's warning level
- [ ] clang-tidy reports zero findings (for non-CUDA files)

### Use Agents, Not Just Chat

Prefer agent/coding-agent mode over single-shot chat. Agents can:
* Verify their own output iteratively
* Run build and test tools
* Re-try after failures

Single-shot chat cannot verify correctness — treat its output as a starting draft requiring full review.

### Available Skills

Skills provide step-by-step workflows for common tasks. Reference them when relevant.

| Skill | Trigger phrase | Purpose |
|-------|---------------|---------|
| [build-and-test](./../skills/build-and-test/SKILL.md) | "build the project", "run tests" | CMake + Ninja build steps, test execution |
| [conventional-commit](./../skills/conventional-commit/SKILL.md) | "commit", "write a commit message" | Conventional Commits 1.0.0 workflow with particle-sim scopes |
| [create-architectural-decision-record](./../skills/create-architectural-decision-record/SKILL.md) | "create an ADR", "record this decision" | ADR document to `docs/adr/` with full template |
| [create-technical-spike](./../skills/create-technical-spike/SKILL.md) | "create a spike", "research this" | Time-boxed research doc to `docs/spikes/` |
