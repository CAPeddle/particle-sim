---
applyTo: "**/*.cpp,**/*.h,**/*.hpp,**/*.cc,**/*.hxx,**/*.cxx,**/*.cu,**/*.cuh"
---

# C++ and CUDA File Rules — particle-sim

These instructions apply to all C++ and CUDA source and header files. They are a focused, always-on subset of the full standards in `.github/copilot-instructions.md`.

---

## Language

- Target **C++23** for CPU code — portable features only; no compiler-specific extensions.
- Target **CUDA 20** for GPU code — `__device__` lambdas, cooperative groups where needed.
- Use concepts, ranges, `std::span`, `std::expected`, `constexpr` algorithms where appropriate.
- No exceptions — use `std::expected<T, E>` or `std::error_code` for all error propagation.

---

## Naming

| Element | Style | Example |
|---------|-------|---------|
| Files | PascalCase | `ParticleSystem.cu`, `ISpatialIndex.hpp` |
| Classes / Structs / Enums / Concepts | PascalCase | `ParticleSystem`, `QueryResult` |
| Interfaces | `IInterfaceName` | `ISpatialIndex`, `ISimulationModel` |
| Functions / Methods | camelCase | `rebuild()`, `queryAll()` |
| Variables / Parameters | camelCase | `particleCount`, `maxNeighbours` |
| Private members | camelCase (no prefix) | `cellSize`, `positions` |
| Constants | `UPPER_SNAKE_CASE` | `MAX_PARTICLES` |
| CUDA kernels | camelCase + `Kernel` suffix | `updatePositionsKernel` |
| Namespace | `psim::` or sub-namespace | `psim::spatial`, `psim::rendering` |

---

## Header Layout

- All headers in `src/` (no separate `include/` directory for this project)
- Use `#pragma once` (already established in codebase)
- CUDA headers: `.cuh` extension
- CUDA sources: `.cu` extension

---

## Required Patterns

### No Raw Memory Management (CPU)
```cpp
// WRONG
auto* p = new Resource(config);
delete p;

// CORRECT
auto p = std::make_unique<Resource>(config);
```

### CUDA Memory with RAII
```cpp
// Always wrap CUDA calls with error checking
CUDA_CHECK(cudaMalloc(&devicePtr, size));
// Use RAII wrapper for automatic cleanup
```

### Rule of Five
Any class with a custom destructor must explicitly declare all five special members.

### Fail-Fast
Validate all preconditions at function entry. Return `std::unexpected(ErrorCode::InvalidArgument)` rather than proceeding with invalid input.

### `[[nodiscard]]`
All functions returning `std::expected<T, E>`, error codes, resource handles, or computed values must be `[[nodiscard]]`.

---

## CUDA-Specific Rules

### Error Checking
Wrap all CUDA API calls:
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

### Memory Layout
Use Struct-of-Arrays for GPU memory coalescing:
```cpp
// CORRECT — coalesced access
struct ParticlePositionsView {
    const float* x;  // All x values contiguous
    const float* y;  // All y values contiguous
    std::size_t count;
};
```

### Kernel Decorators
Always specify `__global__`, `__device__`, or `__host__`:
```cpp
__global__ void updatePositionsKernel(float* positions, int count);
__device__ float computeDistance(float x1, float y1, float x2, float y2);
__host__ __device__ float clamp(float val, float lo, float hi);
```

---

## Internal Linkage — Anonymous Namespaces

Free functions used only within a single `.cpp` file **must** be in `namespace {}`.

```cpp
// CORRECT
namespace { void internalHelper(const Config& cfg) { ... } }
```

---

## Container and View Vocabulary

| Scenario | Correct type |
|----------|-------------|
| Read-only sequence parameter | `std::span<const T>` |
| Mutable sequence parameter (no resize) | `std::span<T>` |
| Parameter needing push/erase/resize | `std::vector<T>&` |
| Stored collection | `std::vector<T>` |
| Nullable value | `std::optional<T>` |
| Fallible return | `std::expected<T, E>` |
| GPU memory view | Custom `*View` structs |

---

## Documentation

All public declarations require Doxygen comments:

```cpp
/// @brief One-sentence description.
/// @param paramName Description.
/// @return Description of return value and error cases.
/// @details Any additional context, invariants, thread-safety.
```

---

## Formatting and Linting

- Format before every commit: `clang-format -i --style=file:.clang-format <file>`
- Lint `.cpp`/`.hpp` before every commit: `clang-tidy -p build/ <file>` — zero findings required
- Note: `.cu`/`.cuh` files are formatted but not linted (limited clang-tidy support)
- The `agentStop` hook enforces both automatically
