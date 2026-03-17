# ExecPlan: Phase 6b — GpuScalarFieldInput + Rendering Decoupling (W-18)

**Date:** 2026-03-16
**Status:** Not Started
**Parent plan:** [Phase 6a — Post-Review Remediation](2026-03-16-phase-6a-review-remediation.md)
**Spike:** [docs/spikes/arch-gpu-scalar-field-visualization-spike.md](../../docs/spikes/arch-gpu-scalar-field-visualization-spike.md)
**Prerequisite:** Phase 6a must be ✅ Complete (all Progress checkboxes ticked, 83/83 tests passing).

---

## Purpose / Big Picture

Phase 6a deferred one item: **W-18** — `updateDensityHeatmap` takes a `FluidSPHModel&` directly,
coupling the renderer to the model's internal field layout. This plan closes W-18 by introducing a
thin `GpuScalarFieldInput` view struct that carries only what the scatter kernel needs: device
pointers, particle count, domain bounds, and a normalisation range.

Beyond the coupling fix, this plan introduces the **Option C normalisation strategy** (decided
in the spike): callers supply `minValue`/`maxValue` with `overrideRange = true` for direct
control, or set `overrideRange = false` to have the renderer auto-compute the range from the
scalar data each frame via a GPU min/max reduction.

After this plan completes:
- `updateDensityHeatmap` no longer references `FluidSPHModel` in any header. Any simulation
  model can drive the heatmap overlay by constructing a `GpuScalarFieldInput`.
- The `DensityHeatmap` struct is the last piece of rendering infrastructure that needs to
  exist before Stage 2 (`GpuScalarField` multi-overlay, Phase 7+) can be built on top.
- W-18 is closed in `plan.md`.

**Observable from outside:** The density heatmap renders identically to before. No visual
change. The change is entirely at the API call-site in `main.cpp`, which now builds a
`GpuScalarFieldInput` instead of passing the model struct.

**Terms:**
- **W-18** — Deferred warning from Phase 6a review: `updateDensityHeatmap` directly accesses
  `FluidSPHModel` fields; tracked in `plan.md`.
- **`GpuScalarFieldInput`** — New non-owning POD view struct in `psim::rendering` that
  carries device pointers + metadata needed by the scatter kernel. Lives in
  `src/rendering/GpuScalarFieldInput.cuh`.
- **Scatter kernel** — `scatterDensityKernel` in `DensityHeatmap.cu`; accumulates per-particle
  scalar values into a `resolution × resolution` texel grid.
- **Option C normalisation** — `overrideRange` flag in `GpuScalarFieldInput`. When `true`:
  uses caller-supplied `minValue`/`maxValue`. When `false`: auto-computes min/max via a device
  reduction pass before the scatter kernel.
- **Min/max reduction** — A two-pass CUDA kernel that finds the minimum and maximum values
  in a `float[N]` array. Output is a 2-element device buffer copied to host before scatter.
- **`overrideRange`** — Boolean field in `GpuScalarFieldInput`. `true` = caller owns the
  normalisation range; `false` = renderer measures it from the data each frame.
- **SoA** — Struct-of-Arrays: separate arrays for each field (`posX[]`, `posY[]`, `density[]`)
  rather than one array of structs. Required for GPU memory coalescing.
- **CUDA-GL interop lifecycle** — `register → map → surface write → unmap` sequence used to
  write device-computed values directly into an OpenGL texture without a CPU copy.
- **`CudaBuffer<T>`** — Project RAII wrapper around `cudaMalloc`/`cudaFree` that makes CUDA
  device memory ownership explicit and exception-safe.
- **Stage 2** — The planned `GpuScalarField` generalisation (Phase 7+, tracked in `plan.md`)
  that renames `DensityHeatmap` → `GpuScalarField` and introduces
  `std::vector<GpuScalarField>` for simultaneous multi-field overlays. This plan is its
  prerequisite.

---

## Progress

- [ ] `Prerequisites verified` — 83/83 tests passing, clang-format clean, baseline confirmed
- [ ] `RED tests added` — failing tests committed, no implementation yet
- [ ] `GREEN implementation completed` — all RED tests now pass
- [ ] `REFACTOR + validation completed` — clang-format, clang-tidy, ASan/UBSan clean
- [ ] `Code review — zero ERRORs` — code-reviewer + expert-cpp agent sign-off
- [ ] `plan.md updated` — W-18 closed, spike follow-up actions ticked

---

## Surprises & Discoveries

*(Fill in as work proceeds.)*

---

## Decision Log

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | `GpuScalarFieldInput` lives in `src/rendering/GpuScalarFieldInput.cuh` (not `.hpp`) | `float2` is a CUDA vector type from `<vector_types.h>`; placing it in a `.hpp` would create a hidden CUDA toolkit dependency for any C++-only TU that includes the header. `.cuh` is the established project convention for CUDA-type-bearing headers. |
| 2 | Option C normalisation: `overrideRange` flag | Supports both interactive use (`overrideRange = true`, ImGui slider controls the range) and exploratory use (`overrideRange = false`, auto-range from data). Avoids two different struct types. See spike §Finding 2. |
| 3 | Min/max reduction via a separate kernel, not `thrust` | No Thrust dependency in this project; a simple parallel reduction kernel is sufficient for this use case and keeps the dependency surface minimal. |
| 4 | Effective min/max cached in `DensityHeatmap` as `computedMin`/`computedMax` | `updateDensityHeatmap` writes the resolved range (either from override or from reduction); `renderDensityHeatmap` reads it for uniform upload. Avoids passing extra parameters through the render call. |
| 5 | `heatmap.frag` gains `u_minValue` uniform; `u_maxDensity` becomes `u_maxValue` | Enables the full [minValue, maxValue] → [0, 1] normalisation in the fragment shader. Existing `u_maxDensity` is renamed to `u_maxValue` for consistency with the new `GpuScalarFieldInput` field names. |
| 6 | Fail-Fast null-pointer check before kernel launch | When `particleCount > 0` and any device pointer is null, `updateDensityHeatmap` calls `std::abort()` immediately rather than deferring to a kernel fault. Consistent with project Fail-Fast policy; makes the precondition death-testable. |
| 7 | Existing `maxDensity` field on `DensityHeatmap` retained as a named constant for the call site | Keeps backward-compatible ImGui slider behaviour: `heatmap.maxDensity` is what the user adjusts; `main.cpp` passes it as `GpuScalarFieldInput.maxValue` with `overrideRange = true`. Field is renamed to `defaultMaxValue` to avoid confusion with `computedMax`. |
| 8 | `resolution > 4096` guard added to `initDensityHeatmap` | At `resolution = 65536`, `uint32_t * uint32_t` wraps to exactly 0, producing a zero-sized kernel launch that re-uses stale accumulator data silently. The guard eliminates the risk. 4096 × 4096 = 16M texels, which already exceeds any plausible debug overlay use case. |

---

## Outcomes & Retrospective

*(Complete after plan closes.)*

**What was achieved:**

**What remains (if anything):**

**Patterns to promote:**

**Reusable findings:**

**New anti-patterns:**

---

## Context and Orientation

### Current state (baseline from Phase 6a)

`updateDensityHeatmap` in `src/rendering/DensityHeatmap.cu` directly accesses six
`FluidSPHModel` fields:

```cpp
void updateDensityHeatmap(DensityHeatmap& heatmap, const psim::models::FluidSPHModel& model)
{
    // model.posX.get(), model.posY.get(), model.density.get()
    // model.params.domainMin, model.params.domainMax, model.params.particleCount
}
```

This couples `DensityHeatmap.cuh` to `FluidSPHModel.cuh` via a forward declaration, and
prevents any non-SPH simulation model from using the heatmap overlay. The shader normalises
the density value using a single `u_maxDensity` uniform; values below zero are clipped to
blue silently.

### Files touched by this plan

| File | Change |
|------|--------|
| `src/rendering/GpuScalarFieldInput.cuh` | **New** — `GpuScalarFieldInput` struct |
| `src/rendering/DensityHeatmap.cuh` | Remove `FluidSPHModel` forward declaration; change `updateDensityHeatmap` signature; add `computedMin`/`computedMax`/`rangeBuffer` fields; rename `maxDensity` → `defaultMaxValue`; add `uniformMinValueLoc`; update Doxygen |
| `src/rendering/DensityHeatmap.cu` | Rename `density` → `scalarValues` in `scatterDensityKernel`; add `minMaxReductionKernel`; implement `overrideRange` branch; add `resolution > 4096` guard; add D→H range readback; update `renderDensityHeatmap` to upload `u_minValue` and `u_maxValue` |
| `shaders/heatmap.frag` | Add `u_minValue`; rename `u_maxDensity` → `u_maxValue`; update normalisation formula |
| `src/main.cpp` | Update `updateDensityHeatmap` call to construct and pass `GpuScalarFieldInput`; update `heatmap.maxDensity` reference to `heatmap.defaultMaxValue` |
| `tests/unit/rendering/DensityHeatmapTest.cpp` | Update call sites; add 5 new test cases |
| `plan.md` | Close W-18 TODO; tick spike follow-up actions |

### Key invariant

`GpuScalarFieldInput` carries non-owning raw device pointers. It must not outlive the
`FluidSPHModel` (or any other model) that owns the underlying `CudaBuffer<float>` allocations.
This is a documented `@note` on the struct, not enforced at runtime.

---

## Plan of Work

Four implementation steps following mandatory TDD order:

1. **RED** — Write all new tests first; commit the failing state.
2. **GREEN** — Create `GpuScalarFieldInput.cuh`; update `DensityHeatmap.cuh/.cu` and
   `heatmap.frag`; update `main.cpp` call site.
3. **REFACTOR** — clang-format, clang-tidy, ASan/UBSan.
4. **CODE REVIEW** — dual agent review; zero ERRORs required.

All implementation is within `psim::rendering`. No changes to `psim::models`,
`psim::spatial`, or `psim::core`.

---

## Concrete Steps

### Step 0 — Verify prerequisites

Confirm Phase 6a baseline is clean.

```bash
cd /home/cpeddle/projects/personal/particle-sim
cmake --build build --target particle_sim particle_sim_tests particle_sim_gpu_tests 2>&1 | tail -3
```

Expected: `[100%] Built target particle_sim_gpu_tests` (or equivalent), zero errors.

```bash
cd build && ctest --output-on-failure 2>&1 | tail -4
```

Expected: `100% tests passed, 0 tests failed out of 83`

```bash
cd ..
clang-format --dry-run --Werror \
  src/rendering/DensityHeatmap.cuh \
  src/rendering/DensityHeatmap.cu \
  src/main.cpp \
  tests/unit/rendering/DensityHeatmapTest.cpp 2>&1 && echo "format clean"
```

Expected: `format clean`

If any check fails, resolve the Phase 6a baseline before continuing.

---

### Step 1 — RED tests

**Agent:** `testing`
**Files:** `tests/unit/rendering/DensityHeatmapTest.cpp`
**Depends on:** Step 0

Write all five new test cases and update the existing `updateDensityHeatmap` call sites
**before touching any implementation**. The signature change in Step 2 will make two of the
new tests fail to compile — that is the RED state.

#### 1a — New standalone struct test (no GL fixture needed)

Add outside the `DensityHeatmapTest` fixture (uses `TEST`, not `TEST_F`):

```cpp
/// GpuScalarFieldInput must default-construct with all pointers null,
/// particleCount zero, and overrideRange false.
TEST(GpuScalarFieldInputTest, DefaultConstruct_AllFieldsAtDefaultValues)
{
    // Arrange / Act
    psim::rendering::GpuScalarFieldInput input{};

    // Assert
    EXPECT_EQ(input.posX,         nullptr);
    EXPECT_EQ(input.posY,         nullptr);
    EXPECT_EQ(input.scalarValues, nullptr);
    EXPECT_EQ(input.particleCount, 0U);
    EXPECT_EQ(input.domainMin.x,  0.0F);
    EXPECT_EQ(input.domainMin.y,  0.0F);
    EXPECT_EQ(input.domainMax.x,  0.0F);
    EXPECT_EQ(input.domainMax.y,  0.0F);
    EXPECT_EQ(input.minValue,     0.0F);
    EXPECT_EQ(input.maxValue,     1.0F);
    EXPECT_FALSE(input.overrideRange);
}
```

This test will fail to **compile** once `GpuScalarFieldInput.cuh` does not yet exist. That
is the expected RED state with `#include "rendering/GpuScalarFieldInput.cuh"` added at the
top.

#### 1b — Zero particle count is a no-op

Add as `TEST_F(DensityHeatmapTest, ...)`:

```cpp
TEST_F(DensityHeatmapTest, UpdateDensityHeatmap_ZeroParticleCount_IsNoOp)
{
    // Arrange
    DensityHeatmap heatmap;
    auto result = psim::rendering::initDensityHeatmap(
        heatmap, TEST_HEATMAP_RESOLUTION, SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");
    ASSERT_TRUE(result.has_value());

    psim::rendering::GpuScalarFieldInput input{};
    input.particleCount  = 0U;
    input.domainMin      = {0.0F, 0.0F};
    input.domainMax      = {1.0F, 1.0F};
    input.overrideRange  = true;
    input.minValue       = 0.0F;
    input.maxValue       = 100.0F;
    heatmap.enabled      = true;

    // Act — must not crash, CUDA must report no errors
    EXPECT_NO_FATAL_FAILURE(psim::rendering::updateDensityHeatmap(heatmap, input));

    // Assert
    EXPECT_EQ(cudaGetLastError(), cudaSuccess);

    psim::rendering::destroyDensityHeatmap(heatmap);
}
```

This test **fails to compile** until the new `updateDensityHeatmap(DensityHeatmap&, const GpuScalarFieldInput&)` signature exists. That is the RED state.

#### 1c — Null pointer with non-zero count aborts (death test)

```cpp
TEST_F(DensityHeatmapTest, UpdateDensityHeatmap_NullPositionPtr_WithNonZeroCount_Aborts)
{
    // Arrange
    DensityHeatmap heatmap;
    auto result = psim::rendering::initDensityHeatmap(
        heatmap, TEST_HEATMAP_RESOLUTION, SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");
    ASSERT_TRUE(result.has_value());

    psim::rendering::GpuScalarFieldInput input{};
    input.posX          = nullptr;  // intentionally null
    input.posY          = nullptr;
    input.scalarValues  = nullptr;
    input.particleCount = 10U;      // non-zero with null pointers -> Fail-Fast
    input.domainMin     = {0.0F, 0.0F};
    input.domainMax     = {1.0F, 1.0F};
    input.overrideRange = true;
    input.minValue      = 0.0F;
    input.maxValue      = 100.0F;
    heatmap.enabled     = true;

    // Act + Assert — Fail-Fast policy: abort on null pointer with non-zero count
    EXPECT_DEATH(psim::rendering::updateDensityHeatmap(heatmap, input), "");

    // Note: destroyDensityHeatmap is intentionally not called; the process
    // forked by EXPECT_DEATH is what aborts, not this process.
    psim::rendering::destroyDensityHeatmap(heatmap);
}
```

This test **fails to compile** until the new signature exists.

#### 1d — `overrideRange = true` uses provided min/max

```cpp
TEST_F(DensityHeatmapTest, UpdateDensityHeatmap_OverrideRangeTrue_UsesProvidedMinMax)
{
    // Arrange
    DensityHeatmap heatmap;
    auto result = psim::rendering::initDensityHeatmap(
        heatmap, TEST_HEATMAP_RESOLUTION, SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");
    ASSERT_TRUE(result.has_value());

    // Allocate a trivial 1-particle scalar field on device
    psim::core::CudaBuffer<float> posX, posY, scalars;
    posX.allocate(1);   posY.allocate(1);   scalars.allocate(1);
    float hPosX = 0.5F, hPosY = 0.5F, hScalar = 42.0F;
    CUDA_CHECK(cudaMemcpy(posX.get(), &hPosX, sizeof(float), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(posY.get(), &hPosY, sizeof(float), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(scalars.get(), &hScalar, sizeof(float), cudaMemcpyHostToDevice));

    psim::rendering::GpuScalarFieldInput input{};
    input.posX          = posX.get();
    input.posY          = posY.get();
    input.scalarValues  = scalars.get();
    input.particleCount = 1U;
    input.domainMin     = {0.0F, 0.0F};
    input.domainMax     = {1.0F, 1.0F};
    input.overrideRange = true;
    input.minValue      = 10.0F;
    input.maxValue      = 50.0F;
    heatmap.enabled     = true;

    // Act
    EXPECT_NO_FATAL_FAILURE(psim::rendering::updateDensityHeatmap(heatmap, input));

    // Assert — computedMin/computedMax must reflect the provided override, not 42.0
    EXPECT_FLOAT_EQ(heatmap.computedMin, 10.0F);
    EXPECT_FLOAT_EQ(heatmap.computedMax, 50.0F);
    EXPECT_EQ(cudaGetLastError(), cudaSuccess);

    psim::rendering::destroyDensityHeatmap(heatmap);
}
```

This test **fails to compile** until the new signature and `computedMin`/`computedMax` fields exist.

#### 1e — `overrideRange = false` auto-computes range from device data

```cpp
TEST_F(DensityHeatmapTest, UpdateDensityHeatmap_OverrideRangeFalse_AutoComputesRange)
{
    // Arrange
    DensityHeatmap heatmap;
    auto result = psim::rendering::initDensityHeatmap(
        heatmap, TEST_HEATMAP_RESOLUTION, SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");
    ASSERT_TRUE(result.has_value());

    // Three particles with scalar values 5, 15, 10 → auto min = 5, max = 15
    constexpr uint32_t N = 3U;
    psim::core::CudaBuffer<float> posX, posY, scalars;
    posX.allocate(N);   posY.allocate(N);   scalars.allocate(N);
    const float hPosX[N]    = {0.2F, 0.5F, 0.8F};
    const float hPosY[N]    = {0.5F, 0.5F, 0.5F};
    const float hScalars[N] = {5.0F, 15.0F, 10.0F};
    CUDA_CHECK(cudaMemcpy(posX.get(),    hPosX,    N * sizeof(float), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(posY.get(),    hPosY,    N * sizeof(float), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(scalars.get(), hScalars, N * sizeof(float), cudaMemcpyHostToDevice));

    psim::rendering::GpuScalarFieldInput input{};
    input.posX          = posX.get();
    input.posY          = posY.get();
    input.scalarValues  = scalars.get();
    input.particleCount = N;
    input.domainMin     = {0.0F, 0.0F};
    input.domainMax     = {1.0F, 1.0F};
    input.overrideRange = false;   // request auto-compute
    heatmap.enabled     = true;

    // Act
    EXPECT_NO_FATAL_FAILURE(psim::rendering::updateDensityHeatmap(heatmap, input));

    // Assert — computed range must match actual min/max of device data
    EXPECT_FLOAT_EQ(heatmap.computedMin,  5.0F);
    EXPECT_FLOAT_EQ(heatmap.computedMax, 15.0F);
    EXPECT_EQ(cudaGetLastError(), cudaSuccess);

    psim::rendering::destroyDensityHeatmap(heatmap);
}
```

This test **fails to compile** until the new signature, fields, and auto-compute path exist.

#### 1f — Update existing call sites

In the existing `Update_WhenDisabled_DoesNotCrash` and any other test that calls
`updateDensityHeatmap(heatmap, model)`, update the call to use a `GpuScalarFieldInput`.
These will also fail to compile until the signature changes — that is fine and expected
as part of the RED state.

#### Verify RED state

```bash
cmake --build build --target particle_sim_gpu_tests 2>&1 | grep "error:" | head -15
```

Expected: compilation errors on `GpuScalarFieldInput` undefined type and on the
`updateDensityHeatmap` call sites with the old `FluidSPHModel` argument. The struct
default-construction test (`GpuScalarFieldInputTest`) requires `GpuScalarFieldInput.cuh`
to not yet exist.

Commit the failing tests:

```bash
git add tests/unit/rendering/DensityHeatmapTest.cpp
git commit -m "test(rendering): RED — GpuScalarFieldInput and overrideRange normalisation tests"
```

---

### Step 2 — GREEN implementation

**Agent:** `developer`
**Depends on:** Step 1

#### 2a — Create `src/rendering/GpuScalarFieldInput.cuh`

New file. Full content:

```cpp
#pragma once

#include <cstdint>
#include <cuda_runtime.h> // float2

namespace psim::rendering
{

/// @brief Non-owning view of device-side scalar field data for GPU heatmap accumulation.
///
/// Passed to `updateDensityHeatmap` each frame in place of a concrete model type.
/// Decouples the rendering pipeline from `FluidSPHModel` internals — any simulation
/// model can drive the heatmap by constructing this struct from its device buffers.
///
/// **Normalisation:**
/// - `overrideRange == true`:  normalise using `[minValue, maxValue]` as supplied.
/// - `overrideRange == false`: auto-compute min/max from `scalarValues` via device
///   reduction (adds one `cudaMemcpy` device→host per frame).
///
/// @note All device pointers must be non-null when `particleCount > 0`.
/// @note `particleCount == 0` is valid; the scatter pass is a no-op.
/// @note This struct is non-owning. It must not outlive the allocations that back
///       `posX`, `posY`, and `scalarValues`.
/// @note When `overrideRange == true` and `maxValue == minValue`, the implementation
///       adds a small epsilon to `maxValue` to avoid division by zero.
struct GpuScalarFieldInput
{
    // NOLINTBEGIN(misc-non-private-member-variables-in-classes)
    const float* posX{nullptr};         ///< Device x-position array [particleCount].
    const float* posY{nullptr};         ///< Device y-position array [particleCount].
    const float* scalarValues{nullptr}; ///< Device per-particle scalar [particleCount].
    uint32_t     particleCount{0};      ///< Number of particles.
    float2       domainMin{};           ///< Domain lower-left corner (world units).
    float2       domainMax{};           ///< Domain upper-right corner (world units).
    float        minValue{0.0F};        ///< Lower normalisation bound (overrideRange == true).
    float        maxValue{1.0F};        ///< Upper normalisation bound (overrideRange == true).
    bool         overrideRange{false};  ///< true = use minValue/maxValue; false = auto-compute.
    // NOLINTEND(misc-non-private-member-variables-in-classes)
};

} // namespace psim::rendering
```

#### 2b — Update `src/rendering/DensityHeatmap.cuh`

Apply the following changes:

1. Remove the `psim::models::FluidSPHModel` forward declaration (lines 16–19).
2. Add `#include "rendering/GpuScalarFieldInput.cuh"`.
3. Add three new fields to `DensityHeatmap` after `alpha`:

```cpp
float defaultMaxValue{DEFAULT_MAX_DENSITY}; ///< User-facing max reference (replaces maxDensity; used by ImGui slider and passed as maxValue when overrideRange == true).
float computedMin{0.0F};                    ///< Effective lower bound written by updateDensityHeatmap; read by renderDensityHeatmap.
float computedMax{DEFAULT_MAX_DENSITY};     ///< Effective upper bound written by updateDensityHeatmap; read by renderDensityHeatmap.
psim::core::CudaBuffer<float> rangeBuffer;  ///< 2-element device buffer: [0] = min, [1] = max. Used by auto-compute reduction.
int uniformMinValueLoc{-1};                 ///< Cached location of u_minValue uniform.
```

4. Rename `maxDensity` → `defaultMaxValue` (the field is now a user preference passed as
   `GpuScalarFieldInput.maxValue`, not the effective rendering range).

5. Update `uniformMaxDensityLoc` → `uniformMaxValueLoc` for consistency with the renamed
   shader uniform.

6. Update `destroyDensityHeatmap` `@post` to note `computedMin`/`computedMax` are reset.

7. Change `updateDensityHeatmap` declaration:

```cpp
/// @brief Scatters per-particle scalar values into the heatmap texture and resolves
/// the normalisation range.
///
/// Three CUDA kernel passes: clear → [optional min/max reduction] → scatter → surface write.
/// Writes `heatmap.computedMin` / `heatmap.computedMax` for use by `renderDensityHeatmap`.
///
/// @param heatmap  Initialised heatmap. No-op if `enabled == false`.
/// @param input    Non-owning view of device-side particle data and normalisation hints.
///
/// @pre initDensityHeatmap has been called on `heatmap`.
/// @pre input.particleCount == 0 OR (input.posX, input.posY, input.scalarValues are all non-null).
/// @pre input.domainMax.x > input.domainMin.x and input.domainMax.y > input.domainMin.y.
/// @note input.particleCount == 0 is valid; the scatter pass is launched with zero blocks (no-op).
void updateDensityHeatmap(DensityHeatmap& heatmap, const GpuScalarFieldInput& input);
```

8. Add `@pre resolution <= 4096` to `initDensityHeatmap` Doxygen.

#### 2c — Update `src/rendering/DensityHeatmap.cu`

**2c-i — Remove `FluidSPHModel` include:**
```cpp
// Remove this line:
#include "models/FluidSPHModel.cuh"
// Add in its place:
#include "rendering/GpuScalarFieldInput.cuh"
```

**2c-ii — Add `minMaxReductionKernel`** (after `clearAccumKernel`, before `scatterDensityKernel`):

```cpp
/// @brief Parallel reduction to find min and max over a float array.
///
/// Uses a two-pass block reduction. For N particles across a 1D grid of blocks,
/// each block reduces its tile to a single min and a single max using shared memory,
/// then atomically updates the global output.
///
/// @param values  Device float array [count].
/// @param count   Number of elements.
/// @param outMin  Device float[1] — output minimum (must be pre-initialised to +FLT_MAX).
/// @param outMax  Device float[1] — output maximum (must be pre-initialised to -FLT_MAX).
__global__ void minMaxReductionKernel(const float* values,
                                      uint32_t count,
                                      float* outMin,
                                      float* outMax)
{
    extern __shared__ float sdata[];   // first half: min, second half: max
    float* sMin = sdata;
    float* sMax = sdata + blockDim.x;

    uint32_t tid = threadIdx.x;
    uint32_t idx = blockIdx.x * blockDim.x + tid;

    float localMin = (idx < count) ? values[idx] : 0.0F;  // FLT_MAX for real init below
    float localMax = localMin;

    if (idx < count)
    {
        localMin = values[idx];
        localMax = values[idx];
    }
    else
    {
        // Out-of-range threads contribute neutral values (require <cfloat>)
        localMin =  3.402823466E+38F;  // FLT_MAX
        localMax = -3.402823466E+38F;  // -FLT_MAX
    }

    sMin[tid] = localMin;
    sMax[tid] = localMax;
    __syncthreads();

    // Block-level parallel reduction (stride halving)
    for (uint32_t stride = blockDim.x / 2U; stride > 0U; stride >>= 1U)
    {
        if (tid < stride)
        {
            sMin[tid] = sMin[tid] < sMin[tid + stride] ? sMin[tid] : sMin[tid + stride];
            sMax[tid] = sMax[tid] > sMax[tid + stride] ? sMax[tid] : sMax[tid + stride];
        }
        __syncthreads();
    }

    // Thread 0 of each block writes block result to global memory
    if (tid == 0U)
    {
        atomicMin(reinterpret_cast<int*>(outMin),
                  __float_as_int(sMin[0])); // NOLINT(cppcoreguidelines-pro-type-reinterpret-cast)
        atomicMax(reinterpret_cast<int*>(outMax),
                  __float_as_int(sMax[0])); // NOLINT(cppcoreguidelines-pro-type-reinterpret-cast)
    }
}
```

> **Note for the implementing developer:** `atomicMin`/`atomicMax` operate on integers. The
> bit-pattern of a positive IEEE 754 float is ordered identically to its integer
> reinterpretation, so `__float_as_int` + `atomicMin`/`atomicMax` is a valid and standard
> technique for non-negative float ranges. For general (possibly negative) floats, a
> 64-bit compound atomic or a separate two-stage reduction is safer. If particle scalar
> values can be negative (they will be for vorticity in Stage 2), replace this with a
> standard two-pass host-side reduction or a Thrust call. Track as a TODO in the
> Discoveries section if float min/max reduction for negative values is needed.

**2c-iii — Rename `density` → `scalarValues`** in `scatterDensityKernel` parameter list
and all internal usages. Internal to the `.cu` TU only — no ABI change.

**2c-iv — Update `initDensityHeatmap`:**

Add after the `resolution <= 0` guard:

```cpp
if (resolution > 4096)
{
    return std::unexpected(std::make_error_code(std::errc::invalid_argument));
}
```

Allocate the range buffer in Step 4 (after the accumulation buffers):

```cpp
heatmap.rangeBuffer.allocate(2); // [0] = min, [1] = max
```

Cache the new uniform locations after linking:

```cpp
heatmap.uniformMinValueLoc = glGetUniformLocation(heatmap.shaderProgram, "u_minValue");
heatmap.uniformMaxValueLoc = glGetUniformLocation(heatmap.shaderProgram, "u_maxValue");  // renamed from uniformMaxDensityLoc
```

**2c-v — Rewrite `updateDensityHeatmap`** body (replace `const FluidSPHModel& model`
parameter with `const GpuScalarFieldInput& input`):

```cpp
void updateDensityHeatmap(DensityHeatmap& heatmap, const GpuScalarFieldInput& input)
{
    if (!heatmap.enabled || heatmap.textureId == 0U)
    {
        return;
    }

    // Fail-Fast: null pointers with non-zero count are a programming error
    if (input.particleCount > 0U &&
        (input.posX == nullptr || input.posY == nullptr || input.scalarValues == nullptr))
    {
        std::fprintf(stderr,
                     "updateDensityHeatmap: null device pointer with particleCount = %u\n",
                     input.particleCount);
        std::abort();
    }

    const uint32_t uRes = static_cast<uint32_t>(heatmap.resolution);
    const uint32_t totalTexels = uRes * uRes; // safe: resolution <= 4096, so max = 16M (fits uint32_t)

    constexpr uint32_t BLOCK_1D = 256U;

    // --- Resolve normalisation range ---
    if (input.overrideRange)
    {
        heatmap.computedMin = input.minValue;
        heatmap.computedMax = (input.maxValue == input.minValue)
                                ? input.minValue + 1.0F  // guard against zero range
                                : input.maxValue;
    }
    else if (input.particleCount > 0U)
    {
        // Auto-compute: initialise range buffer to neutral values, then reduce
        constexpr float FLT_MAX_VAL =  3.402823466E+38F;
        constexpr float FLT_MIN_VAL = -3.402823466E+38F;
        float initVals[2] = {FLT_MAX_VAL, FLT_MIN_VAL};
        CUDA_CHECK(cudaMemcpy(heatmap.rangeBuffer.get(), initVals, 2 * sizeof(float),
                              cudaMemcpyHostToDevice));

        const uint32_t gridReduce = (input.particleCount + BLOCK_1D - 1U) / BLOCK_1D;
        const uint32_t sharedMem = 2U * BLOCK_1D * static_cast<uint32_t>(sizeof(float));
        minMaxReductionKernel<<<gridReduce, BLOCK_1D, sharedMem>>>(
            input.scalarValues, input.particleCount,
            heatmap.rangeBuffer.get(),       // outMin
            heatmap.rangeBuffer.get() + 1);  // outMax
        CUDA_CHECK(cudaGetLastError());

        float hostRange[2] = {0.0F, 1.0F};
        CUDA_CHECK(cudaMemcpy(hostRange, heatmap.rangeBuffer.get(), 2 * sizeof(float),
                              cudaMemcpyDeviceToHost));
        heatmap.computedMin = hostRange[0];
        heatmap.computedMax = (hostRange[1] == hostRange[0])
                                ? hostRange[0] + 1.0F
                                : hostRange[1];
    }
    else
    {
        // Zero particles, overrideRange == false: use defaults
        heatmap.computedMin = 0.0F;
        heatmap.computedMax = 1.0F;
    }

    // --- Pass 1: clear accumulator ---
    CUDA_CHECK(cudaMemset(heatmap.discardCountBuf.get(), 0, sizeof(uint32_t)));
    clearAccumKernel<<<(totalTexels + BLOCK_1D - 1U) / BLOCK_1D, BLOCK_1D>>>(
        heatmap.accumBuffer.get(), heatmap.countBuffer.get(), totalTexels);
    CUDA_CHECK(cudaGetLastError());

    // --- Pass 2: scatter scalar values into texel grid ---
    if (input.particleCount > 0U)
    {
        const uint32_t gridParticles = (input.particleCount + BLOCK_1D - 1U) / BLOCK_1D;
        scatterDensityKernel<<<gridParticles, BLOCK_1D>>>(
            input.posX, input.posY, input.scalarValues,
            heatmap.accumBuffer.get(), heatmap.countBuffer.get(),
            input.domainMin, input.domainMax,
            static_cast<int>(uRes), input.particleCount,
            heatmap.discardCountBuf.get());
        CUDA_CHECK(cudaGetLastError());
    }

    // --- Pass 3: map CUDA resource, write texture ---
    CUDA_CHECK(cudaGraphicsMapResources(1, &heatmap.cudaTexResource, nullptr));

    cudaArray_t texArray = nullptr;
    CUDA_CHECK(cudaGraphicsSubResourceGetMappedArray(&texArray, heatmap.cudaTexResource, 0, 0));

    cudaResourceDesc resDesc{};
    resDesc.resType = cudaResourceTypeArray;
    resDesc.res.array.array = texArray;

    cudaSurfaceObject_t surfObj = 0;
    CUDA_CHECK(cudaCreateSurfaceObject(&surfObj, &resDesc));

    const auto uRes16 = static_cast<unsigned int>((static_cast<int>(uRes) + 15) / 16);
    dim3 block2d(16, 16);
    dim3 grid2d(uRes16, uRes16);
    writeTextureKernel<<<grid2d, block2d>>>(
        heatmap.accumBuffer.get(), heatmap.countBuffer.get(), surfObj, uRes);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());

    uint32_t hostDiscards = 0U;
    CUDA_CHECK(cudaMemcpy(&hostDiscards, heatmap.discardCountBuf.get(),
                          sizeof(uint32_t), cudaMemcpyDeviceToHost));
    if (hostDiscards > 0U)
    {
        std::fprintf(stderr,
                     "DensityHeatmap: %u/%u particle(s) out of domain and discarded\n",
                     hostDiscards, input.particleCount);
    }

    CUDA_CHECK(cudaDestroySurfaceObject(surfObj));
    CUDA_CHECK(cudaGraphicsUnmapResources(1, &heatmap.cudaTexResource, nullptr));
}
```

**2c-vi — Update `renderDensityHeatmap`** to upload the new uniforms:

```cpp
glUniform1f(heatmap.uniformMinValueLoc, heatmap.computedMin);
glUniform1f(heatmap.uniformMaxValueLoc, heatmap.computedMax);
// Remove the old line: glUniform1f(heatmap.uniformMaxDensityLoc, heatmap.maxDensity);
```

**2c-vii — Update `destroyDensityHeatmap`:** add `heatmap.rangeBuffer.free()` alongside
the existing accumulation buffer frees. Reset `uniformMinValueLoc = -1` and
`uniformMaxValueLoc = -1`.

#### 2d — Update `shaders/heatmap.frag`

```glsl
#version 460 core

uniform sampler2D u_densityTex;
uniform float     u_minValue;
uniform float     u_maxValue;
uniform float     u_alpha;

in  vec2 v_uv;
out vec4 fragColor;

void main()
{
    float raw  = texture(u_densityTex, v_uv).r;
    float d    = (raw - u_minValue) / max(u_maxValue - u_minValue, 1e-5);
    vec3  c    = mix(vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), clamp(d, 0.0, 1.0));
    fragColor  = vec4(c, u_alpha);
}
```

#### 2e — Update `src/main.cpp`

Replace the `updateDensityHeatmap(heatmap, model)` call with:

```cpp
psim::rendering::GpuScalarFieldInput scalarInput{};
scalarInput.posX          = model.posX.get();
scalarInput.posY          = model.posY.get();
scalarInput.scalarValues  = model.density.get();
scalarInput.particleCount = model.params.particleCount;
scalarInput.domainMin     = model.params.domainMin;
scalarInput.domainMax     = model.params.domainMax;
scalarInput.overrideRange = true;
scalarInput.minValue      = 0.0F;
scalarInput.maxValue      = heatmap.defaultMaxValue;

psim::rendering::updateDensityHeatmap(heatmap, scalarInput);
```

Also update any reference to `heatmap.maxDensity` → `heatmap.defaultMaxValue`
(e.g., ImGui slider target).

#### 2f — Build and verify GREEN

```bash
cmake --build build --target particle_sim particle_sim_tests particle_sim_gpu_tests 2>&1 | tail -5
```

Expected: zero errors.

```bash
cd build && ctest --output-on-failure 2>&1 | tail -5
```

Expected: all tests pass. The five new tests pass. The 83 existing tests still pass
(or skip cleanly in headless). Total ≥ 88 tests.

---

### Step 3 — Refactor and validate

**Agent:** `developer`
**Depends on:** Step 2

#### 3a — clang-format

```bash
cd /home/cpeddle/projects/personal/particle-sim
clang-format -i --style=file:.clang-format \
  src/rendering/GpuScalarFieldInput.cuh \
  src/rendering/DensityHeatmap.cuh \
  src/rendering/DensityHeatmap.cu \
  src/main.cpp \
  tests/unit/rendering/DensityHeatmapTest.cpp
```

Verify:

```bash
clang-format --dry-run --Werror \
  src/rendering/GpuScalarFieldInput.cuh \
  src/rendering/DensityHeatmap.cuh \
  src/rendering/DensityHeatmap.cu \
  src/main.cpp \
  tests/unit/rendering/DensityHeatmapTest.cpp 2>&1 && echo "format clean"
```

Expected: `format clean`

#### 3b — clang-tidy

Run tidy via the including `.cpp` TU (clang-tidy cannot parse `.cu`/`.cuh` files directly
due to CUDA compiler flags — see Phase 6a Surprise #3):

```bash
clang-tidy -p build/ tests/unit/rendering/DensityHeatmapTest.cpp \
  --header-filter="src/rendering/.*" 2>&1 | grep -v "^$"
```

Expected: zero findings. If findings appear, fix them (do not suppress without an inline
`// NOLINT(check-name) — reason` comment).

#### 3c — Full test suite

```bash
cd build && ctest --output-on-failure 2>&1 | tail -5
```

Expected: 100% pass.

#### 3d — ASan + UBSan build (CPU code)

The reduction branch and the null-pointer Fail-Fast check involve CPU code paths that ASan
and UBSan can exercise. Run a sanitizer build:

```bash
cd /home/cpeddle/projects/personal/particle-sim
cmake -B build_asan -G Ninja -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" \
  -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined" 2>&1 | tail -3

cmake --build build_asan --target particle_sim_tests 2>&1 | tail -3

cd build_asan && ctest --output-on-failure -L "" --exclude-regex "gpu" 2>&1 | tail -5
```

Expected: zero ASan/UBSan errors on the CPU test suite. GPU tests are excluded from the
sanitizer build (CUDA requires a non-sanitized runtime).

**Clean up the sanitizer build directory after validation:**

```bash
cd /home/cpeddle/projects/personal/particle-sim && rm -rf build_asan
```

---

### Step 4 — Code review

**Agent:** `code-reviewer` + `expert-cpp`
**Depends on:** Step 3

Invoke both agents to review the diff of this plan. Requirements per
`copilot-instructions.md`:

**Mandatory checks:**
- [ ] No raw `new`/`delete`
- [ ] No exceptions (`throw`, `try`, `catch`)
- [ ] No pre-C++11 idioms or C-style casts
- [ ] Names: `psim::rendering`, PascalCase structs, camelCase methods
- [ ] All CUDA API calls wrapped with `CUDA_CHECK`
- [ ] `GpuScalarFieldInput` Doxygen complete: `@brief`, `@note` (ownership), preconditions
- [ ] `minMaxReductionKernel` Doxygen present
- [ ] `updateDensityHeatmap` Doxygen updated for new signature and `overrideRange` semantics
- [ ] `initDensityHeatmap` Doxygen has `@pre resolution <= 4096`
- [ ] `[[nodiscard]]` retained on `initDensityHeatmap` return
- [ ] `destroyDensityHeatmap` resets all new fields (`computedMin`, `computedMax`,
      `uniformMinValueLoc`, `uniformMaxValueLoc`, `rangeBuffer`)
- [ ] `rangeBuffer` freed in `destroyDensityHeatmap`
- [ ] `rangeBuffer` allocated in `initDensityHeatmap` (Step 4)
- [ ] Shader `u_maxDensity` fully removed; `u_minValue` + `u_maxValue` used consistently
- [ ] `uniformMaxDensityLoc` → `uniformMaxValueLoc` rename applied everywhere
- [ ] `DensityHeatmap` destructor assert still references `textureId == 0` (unchanged)

The review must return zero ERRORs before the plan is marked complete.

---

### Step 5 — Update plan.md

**Agent:** `developer`
**Depends on:** Step 4

In `plan.md`:

1. Close W-18: replace the `DensityHeatmapInput` deferred TODO block with:
   ```markdown
   ### ~~Deferred: `DensityHeatmapInput` view struct~~ — **Closed by Phase 6b**
   > Closed by [Phase 6b ExecPlan](.github/planning/execplans/2026-03-16-phase-6b-gpu-scalar-field-input.md).
   > `GpuScalarFieldInput` introduced in `src/rendering/GpuScalarFieldInput.cuh`.
   ```

2. Tick the spike follow-up actions for W-18 and `@pre`/`@note` Doxygen items.

3. Add Phase 6b to the Phase Status table:
   ```markdown
   | Phase 6b — GpuScalarFieldInput + W-18 Close | `.github/planning/execplans/2026-03-16-phase-6b-gpu-scalar-field-input.md` | ✅ Complete |
   ```

---

## Validation and Acceptance

All of the following must be true before this plan is marked ✅ Complete:

| Check | Command / Observable |
|-------|---------------------|
| Build succeeds, zero errors | `cmake --build build` exits 0 |
| All tests pass | `ctest --test-dir build --output-on-failure` exits 0; ≥ 88 tests pass |
| Five new tests present and passing | `ctest -R "GpuScalarFieldInput\|OverrideRange\|ZeroParticleCount\|NullPosition"` reports 5 passed |
| clang-format clean | `clang-format --dry-run --Werror <changed files>` exits 0 |
| clang-tidy clean | `clang-tidy -p build/ tests/unit/rendering/DensityHeatmapTest.cpp --header-filter="src/rendering/.*"` exits 0 |
| ASan/UBSan clean (CPU tests) | Sanitizer build CPU test suite exits 0 (see Step 3d) |
| `FluidSPHModel` forward declaration removed from `DensityHeatmap.cuh` | `grep -n "FluidSPHModel" src/rendering/DensityHeatmap.cuh` returns no matches |
| `u_maxDensity` removed from shader | `grep "u_maxDensity" shaders/heatmap.frag` returns no matches |
| W-18 closed in `plan.md` | `grep "W-18" plan.md` shows only the "Closed by Phase 6b" note |
| Code review: zero ERRORs | Dual agent review report shows 0 ERRORs |

---

## Idempotence and Recovery

**Build steps are idempotent.** Re-running `cmake --build build` with no source changes
produces the same output.

**Test runs are idempotent.** Tests that require GL/CUDA skip cleanly in headless
environments; they do not leave side effects.

**Recovery:**

| Failure | Recovery |
|---------|----------|
| GREEN build fails | Run `cmake --build build 2>&1 \| grep "error:"` to isolate; fix without modifying RED test assertions |
| `minMaxReductionKernel` returns wrong values | Verify shared memory size (must be `2 * blockDim.x * sizeof(float)`); check `__float_as_int` precondition (positive floats only — see Decision Log #3) |
| clang-tidy finding in new kernel code | `.cu` files are not linted by clang-tidy; findings are from `.cpp`/`.hpp` TUs only. Fix in the including TU or add `// NOLINT(check-name) — reason` |
| Death test flakes (EXPECT_DEATH timing) | Run with `--gtest_repeat=3`; if consistently failing, check `std::abort()` is reached before any CUDA call |
| ASan/UBSan build fails to configure | Ensure GCC 13+ is the active compiler: `which g++ && g++ --version` |

---

## Artifacts and Notes

- **Branch:** `feature/6b-gpu-scalar-field-input`
- **Spike (decision source):** `docs/spikes/arch-gpu-scalar-field-visualization-spike.md`
- **No scratch files** — this plan uses no temporary files outside the source tree.
- **Commit order:** 1 RED commit (Step 1) → 1 GREEN commit (Step 2 + shader) → 1 refactor
  commit (Step 3) → 1 plan.md commit (Step 5). Use Conventional Commits:
  - `test(rendering): RED — GpuScalarFieldInput and overrideRange tests`
  - `feat(rendering): GpuScalarFieldInput view struct, overrideRange normalisation, W-18 close`
  - `refactor(rendering): clang-format and tidy pass for Phase 6b`
  - `docs(plan): close W-18, add Phase 6b to phase table`

---

## Interfaces and Dependencies

| Component | Type | Impact |
|-----------|------|--------|
| `src/rendering/GpuScalarFieldInput.cuh` | New header | Non-owning POD view struct in `psim::rendering` |
| `src/rendering/DensityHeatmap.cuh` | Modified header | Signature change; new fields; forward declaration removed |
| `src/rendering/DensityHeatmap.cu` | Modified implementation | New kernel; new reduction path; scatter kernel rename |
| `shaders/heatmap.frag` | Modified shader | New `u_minValue` uniform; renamed `u_maxValue` |
| `src/main.cpp` | Modified call site | Constructs `GpuScalarFieldInput`; no logic change |
| `tests/unit/rendering/DensityHeatmapTest.cpp` | Modified tests | 5 new tests; updated call sites |
| `plan.md` | Documentation | W-18 closed; Phase 6b added to table |
| `psim::models::FluidSPHModel` | **No longer referenced** from `DensityHeatmap.cuh` | Coupling removed |
| `psim::spatial::*` | Not touched | No dependency |
| Stage 2 (`GpuScalarField`, Phase 7+) | Future | `GpuScalarFieldInput` is its input contract; this plan is Stage 2's prerequisite |
