# ExecPlan: Phase 3 — UniformGridIndex GPU Implementation

**Date:** 2026-03-12  
**Status:** Not Started  
**Prerequisite:** [Phase 0 — GoogleTest Integration](2026-03-12-phase-0-googletest-integration.md) — all four Progress checkboxes must be ticked. [Phase 1](2026-03-12-phase-1-simulation-model-interface.md) and [Phase 2](2026-03-12-phase-2-toml-config-system.md) are desirable (for `CudaBuffer` alignment with `Parameter<T>` types) but not strictly blocking.

---

## Purpose / Big Picture

`ISpatialIndex` (already defined in `src/spatial/ISpatialIndex.hpp`) has no implementation. `UniformGridIndex` is the GPU-accelerated uniform-grid implementation using counting sort construction (count → prefix sum → scatter), as documented in ADR-001. It is required by the SPH density calculation in Phase 4.

**Algorithm summary (counting sort spatial hash):**
1. **Hash** each particle position to a cell index: `cell = floor(x / cellSize) + gridWidth * floor(y / cellSize)`.
2. **Count** particles per cell (atomic add into a `cellCounts` array).
3. **Prefix sum** (exclusive scan) on `cellCounts` to get `cellStarts` — the starting offset in the sorted array for each cell.
4. **Scatter** particle indices into a sorted `sortedIndices` array at their cell's offset.
5. **Query**: for a query point, enumerate the 3×3 neighbourhood of cells; iterate `sortedIndices[cellStarts[c]..cellStarts[c]+cellCounts[c]]` for each cell `c`; emit indices within `radius`.

**Terms:**
- **Uniform grid** — Spatial index where the domain is divided into equal-size cells. Particles are assigned to one cell; queries inspect a fixed neighbourhood of cells.
- **Counting sort** — Non-comparison sort that builds position arrays via three passes: count, prefix sum, scatter. O(N) construction, no per-particle atomic contention.
- **Cell size** — The side length of each grid cell. Should be ≥ query radius. Larger cells reduce false-negative misses; smaller cells improve query locality.
- **Struct-of-Arrays (SoA)** — Memory layout where each field of a particle is a separate contiguous array. Required for GPU memory coalescing.
- **`CUDA_CHECK`** — Macro wrapping all CUDA API calls to abort on error. Defined in `src/core/CudaUtils.hpp`.

---

## Progress

- [ ] `Prerequisites verified` — [Phase 0](2026-03-12-phase-0-googletest-integration.md) shows all four checkboxes ticked; `ctest` runs and passes
- [ ] `RED tests added` — CPU-side contract tests and GPU validation harness committed; build fails  
- [ ] `GREEN implementation completed` — `UniformGridIndex.cu/.cuh` written; tests pass  
- [ ] `REFACTOR + validation completed` — clang-format clean; CUDA kernel profiling baseline recorded  
- [ ] `Code review — zero ERRORs`

---

## Surprises & Discoveries

_Empty — fill during execution._

---

## Decision Log

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Cell size = query radius | Guarantees at most 3×3 cell neighbourhood covers all neighbours within radius. |
| 2 | Domain bounds passed to `rebuild()` (not computed from positions) | Explicit bounds are safe for dynamic domains; auto-computed bounds require extra device-to-host sync. |
| 3 | Use `thrust::exclusive_scan` for prefix sum | Avoids hand-writing a parallel scan; thrust is part of CUDA toolkit. |
| 4 | `maxNeighbours` is a fixed compile-time constant (default 64) | Fixed-size avoids dynamic allocation in kernel; `QueryResult::truncated` flags if exceeded. |
| 5 | `CUDA_CHECK` defined in `src/core/CudaUtils.hpp`, not inline in `.cu` | Shared across all CUDA files; single definition location. |

---

## Outcomes & Retrospective

_Empty — fill at completion._

---

## Context and Orientation

**Current state:**  
- `src/spatial/ISpatialIndex.hpp` — fully defined interface. Not modified here.  
- No `UniformGridIndex` exists.  
- No `src/core/CudaUtils.hpp` exists.

**What this plan adds:**
- `src/core/CudaUtils.hpp` — `CUDA_CHECK` macro, `CudaBuffer<T>` RAII wrapper.
- `src/spatial/UniformGridIndex.cuh` — class declaration.
- `src/spatial/UniformGridIndex.cu` — `rebuild()` + `queryNeighbours()` + `queryFromPoints()` implementations.
- `tests/unit/spatial/UniformGridIndexTest.cpp` — CPU-side interface contract tests.
- `tests/gpu/spatial/UniformGridIndexGpuTest.cu` — GPU integration tests (small particle counts, verifiable by CPU).
- `CMakeLists.txt` updates: add test sources, add `src/spatial/UniformGridIndex.cu` to `particle_sim`.

---

## Plan of Work

1. Create `src/core/CudaUtils.hpp` (CUDA_CHECK + CudaBuffer RAII).
2. Write RED tests — CPU interface tests + GPU validation harness.
3. Implement `UniformGridIndex.cuh/.cu`.
4. Add to CMakeLists.txt.
5. Build; run tests.
6. clang-format all new files.

---

## Concrete Steps

### Step 0 — Verify prerequisites

Open [Phase 0](2026-03-12-phase-0-googletest-integration.md) and confirm all four Progress checkboxes are ticked.

Then run:

```bash
cmake --build build --target particle_sim_tests && cd build && ctest --output-on-failure
```

Expected: `100% tests passed`. If this fails, resolve Phase 0 first.

Optionally verify Phase 1 + 2 completion (not blocking, but reduces merge conflicts later):

```bash
ls src/core/Parameter.hpp src/core/ISimulationModel.hpp src/config/ConfigReader.hpp 2>/dev/null && echo 'Phases 1+2 present' || echo 'Phases 1+2 not yet done — proceeding without them'
```

### Step 1 — `src/core/CudaUtils.hpp`

```cpp
#pragma once

#include <cuda_runtime.h>
#include <cstddef>
#include <cstdio>
#include <cstdlib>

/// @brief Wraps a CUDA API call; prints error and aborts on failure.
#define CUDA_CHECK(call)                                                   \
    do {                                                                   \
        cudaError_t err__ = (call);                                        \
        if (err__ != cudaSuccess) {                                        \
            std::fprintf(stderr, "CUDA error at %s:%d: %s\n",             \
                         __FILE__, __LINE__, cudaGetErrorString(err__));   \
            std::abort();                                                  \
        }                                                                  \
    } while (0)

namespace psim::core {

/// @brief RAII wrapper for a CUDA device memory allocation.
///
/// @tparam T Element type. T must be trivially destructible.
template <typename T>
class CudaBuffer
{
public:
    CudaBuffer() = default;

    explicit CudaBuffer(std::size_t count) { allocate(count); }

    ~CudaBuffer() { free(); }

    CudaBuffer(const CudaBuffer&)            = delete;
    CudaBuffer& operator=(const CudaBuffer&) = delete;

    CudaBuffer(CudaBuffer&& other) noexcept
        : ptr_{other.ptr_}, count_{other.count_}
    {
        other.ptr_   = nullptr;
        other.count_ = 0;
    }

    CudaBuffer& operator=(CudaBuffer&& other) noexcept
    {
        if (this != &other) {
            free();
            ptr_         = other.ptr_;
            count_       = other.count_;
            other.ptr_   = nullptr;
            other.count_ = 0;
        }
        return *this;
    }

    void allocate(std::size_t count)
    {
        free();
        CUDA_CHECK(cudaMalloc(&ptr_, count * sizeof(T)));
        count_ = count;
    }

    void free() noexcept
    {
        if (ptr_) {
            cudaFree(ptr_);
            ptr_   = nullptr;
            count_ = 0;
        }
    }

    [[nodiscard]] T*          get()   const noexcept { return ptr_; }
    [[nodiscard]] std::size_t count() const noexcept { return count_; }
    [[nodiscard]] bool        empty() const noexcept { return count_ == 0; }

private:
    T*          ptr_   = nullptr;
    std::size_t count_ = 0;
};

} // namespace psim::core
```

### Step 2 — RED tests (committed before .cu implementation exists)

**`tests/unit/spatial/UniformGridIndexTest.cpp`** — CPU-side tests:
- Constructor with valid cell size and domain bounds succeeds.
- `rebuild()` does not crash on minimal input (1 particle).
- `queryNeighbours()` before `rebuild()` — define and test the precondition behaviour.

**`tests/gpu/spatial/UniformGridIndexGpuTest.cu`** — GPU correctness tests:
- 4 particles in a 2×2 grid, cell size = 1.0, radius = 1.5 → each particle should find the other 3.
- 10 particles in a line, radius = 1.5 → only adjacent particles are neighbours.
- `QueryResult::truncated == false` for small particle counts.

### Step 3 — `src/spatial/UniformGridIndex.cuh`

Declares `UniformGridIndex : public ISpatialIndex` with:
- Constructor `UniformGridIndex(float cellSize, float2 domainMin, float2 domainMax)`.
- Override of `rebuild()`, `queryNeighbours()`, `queryFromPoints()`.
- Private members: `CudaBuffer<int>` for cellCounts, cellStarts, sortedIndices; cached particle count.

### Step 4 — `src/spatial/UniformGridIndex.cu`

Implements three CUDA kernels:
- `hashParticlesKernel` — assigns each particle to a cell index and increments `cellCounts` atomically.
- `scatterParticlesKernel` — uses `cellStarts` to scatter particle indices into `sortedIndices`.
- `queryNeighboursKernel` — for each particle, iterates 3×3 cell neighbourhood and writes neighbours within radius.

Uses `thrust::exclusive_scan` for the prefix sum step between hash and scatter.

### Step 5 — CMakeLists.txt updates

Add `src/spatial/UniformGridIndex.cu` to `particle_sim` sources.  
Add `src/core/CudaUtils.hpp` — header-only, no source entry needed.  
Add GPU test sources to `particle_sim_tests` (CUDA test files are `.cu` — need `CUDA` language on the test target).

```cmake
# In tests/CMakeLists.txt — enable CUDA for test target
set_target_properties(particle_sim_tests PROPERTIES
    CUDA_SEPARABLE_COMPILATION ON
)
```

### Step 6 — Build and test

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
cd build && ctest --output-on-failure -R UniformGridIndex
```

---

## Validation and Acceptance

| # | Check | Observable Evidence |
|---|-------|---------------------|
| 1 | CPU contract tests pass | `ctest -R UniformGridIndexTest` — PASSED |
| 2 | GPU correctness tests pass | `ctest -R UniformGridIndexGpuTest` — PASSED |
| 3 | No truncation for small counts | `QueryResult::truncated == false` for ≤64 neighbours |
| 4 | clang-format clean on `.cuh` + test `.cpp` | `clang-format --dry-run --Werror` exits 0 |
| 5 | Main app builds | `cmake --build build -- particle_sim` exits 0 |

---

## Idempotence and Recovery

- CUDA kernels are deterministic for fixed particle positions — re-running tests is safe.
- If thrust scan causes link issues, replace with a custom scan kernel (documented in `Surprises & Discoveries`).
- `CudaBuffer::free()` is `noexcept` — safe to call repeatedly (guarded by null check).

---

## Artifacts and Notes

- `src/core/CudaUtils.hpp`
- `src/spatial/UniformGridIndex.cuh`
- `src/spatial/UniformGridIndex.cu`
- `tests/unit/spatial/UniformGridIndexTest.cpp`
- `tests/gpu/spatial/UniformGridIndexGpuTest.cu`

---

## Interfaces and Dependencies

**Depends on:** Phase 0 (GoogleTest), `ISpatialIndex.hpp` (already exists).  
**Required by:** Phase 4 (SPH density calculation queries `UniformGridIndex`).  
**ADR reference:** `docs/adr/0001-spatial-indexing-strategy.md` — documents why uniform grid over kd-tree.
