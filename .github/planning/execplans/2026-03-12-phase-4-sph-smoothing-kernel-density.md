# ExecPlan: Phase 4 — SPH Smoothing Kernel + Density Calculation

**Date:** 2026-03-12  
**Status:** Not Started  
**Prerequisite:** [Phase 3 — UniformGridIndex](2026-03-12-phase-3-uniform-grid-index.md) and [Phase 2 — TOML Config](2026-03-12-phase-2-toml-config-system.md) — all Progress checkboxes in both plans must be ticked before starting this plan.

---

## Purpose / Big Picture

This phase implements the first real SPH physics: the smoothing kernel function and the density calculation kernel. Together they produce a `density` array on device memory that is the foundation for all pressure and viscosity forces.

**SPH** (Smoothed Particle Hydrodynamics) approximates field quantities (density, pressure) by summing contributions from neighbouring particles weighted by a smoothing kernel W(r, h), where r = distance and h = influence radius.

**Terms:**
- **Smoothing kernel** — `W(r, h) = max(0, (h - r) / h)^3` — cubic falloff. Zero outside radius `h`, maximum at `r = 0`.
- **Kernel gradient** — Analytic derivative: `∇W = -3 * ((h - r) / h)^2 * (1/h)` for `r < h`, else 0. Used for pressure forces.
- **Density** — At particle `i`: `ρ_i = Σ_j m_j * W(|x_i - x_j|, h)` summed over all neighbours `j`.
- **`FluidSPHModel`** — new struct/class in `src/models/` that will hold particle data and call these kernels (shell created in this phase, populated in later phases).

---

## Progress

- [ ] `Prerequisites verified` — [Phase 3](2026-03-12-phase-3-uniform-grid-index.md) and [Phase 2](2026-03-12-phase-2-toml-config-system.md) show all checkboxes ticked; `src/spatial/UniformGridIndex.cuh` and `src/config/ConfigReader.hpp` exist
- [ ] `RED tests added`
- [ ] `GREEN implementation completed`
- [ ] `REFACTOR + validation completed`
- [ ] `Code review — zero ERRORs`

---

## Surprises & Discoveries

_Empty — fill during execution._

---

## Decision Log

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Smoothing kernel as `__device__ __forceinline__` free function in `SphKernels.cuh` | Shared across density, pressure, viscosity kernels; inlining avoids function call overhead in hot path. |
| 2 | Kernel gradient implemented analytically | Finite differences (fluid-sim's approach) require 2× density evaluations and introduce step-size sensitivity. |
| 3 | Normalisation constant included | Fluid-sim omitted it; without normalisation, density values are relative. Adding it now avoids a later correction to gas_constant tuning. |
| 4 | Density array is device-only `CudaBuffer<float>` | Only used as input to pressure kernel; no need to copy to host every frame. |

---

## Outcomes & Retrospective

_Empty — fill at completion._

---

## Context and Orientation

**Current state after Phase 3:**
- `UniformGridIndex` can rebuild and query a spatial index.
- `config.toml` provides `influence_radius`, `particle_count`, etc.
- `ParticleSystem` (existing) has positions as `float4` (xy = position, zw = color).

**What this plan adds:**
- `src/models/SphKernels.cuh` — `smoothingKernel()` + `smoothingKernelGradient()` device functions.
- `src/models/FluidSPHModel.cuh/.cu` — model struct with SoA position/velocity/density arrays + `computeDensityKernel`.
- `tests/gpu/models/SphKernelsTest.cu` — validates kernel values and gradient at known distances.
- `tests/gpu/models/FluidDensityTest.cu` — validates density against analytic result for a known particle arrangement.

---

## Concrete Steps

### Step 0 — Verify prerequisites

Open [Phase 3](2026-03-12-phase-3-uniform-grid-index.md) and [Phase 2](2026-03-12-phase-2-toml-config-system.md) and confirm all checkboxes are ticked in both.

Verify the key artifacts exist:

```bash
ls src/spatial/UniformGridIndex.cuh src/config/ConfigReader.hpp
```

Confirm all tests pass:

```bash
cmake --build build --target particle_sim_tests && cd build && ctest --output-on-failure
```

If either check fails, do not proceed — resolve the blocking phase first.

### Step 1 — `src/models/SphKernels.cuh`

```cuda
#pragma once

/// @brief Cubic smoothing kernel W(r, h) = max(0, (h - r) / h)^3
///
/// @param distance  Distance between particles (r). Must be >= 0.
/// @param radius    Influence radius (h). Must be > 0.
/// @return Kernel weight in [0, 1]. Zero for distance >= radius.
__device__ __forceinline__ float smoothingKernel(float distance, float radius)
{
    if (distance >= radius) return 0.0F;
    float q = (radius - distance) / radius;
    return q * q * q;
}

/// @brief Analytic gradient magnitude of the smoothing kernel: dW/dr
///
/// @return Negative value (kernel decreases with distance). Zero for distance >= radius.
__device__ __forceinline__ float smoothingKernelGradient(float distance, float radius)
{
    if (distance >= radius) return 0.0F;
    float q = (radius - distance) / radius;
    return -3.0F * q * q / radius;
}
```

### Step 2 — RED tests for kernels

- `smoothingKernel(0, 1)` == 1.0f (at origin).
- `smoothingKernel(1, 1)` == 0.0f (at boundary).
- `smoothingKernel(1.5, 1)` == 0.0f (outside).
- `smoothingKernelGradient(0.5, 1)` matches `(-3 * 0.5^2 / 1)` == -0.75f.
- Density of 1 particle alone == `mass * smoothingKernel(0, h)`.

### Step 3 — `src/models/FluidSPHModel.cuh`

Declares `FluidSPHParams` (POD struct mirroring TOML `[model.sph]` values), SoA arrays for position/velocity/density, and:
- `void initFluidModel(FluidSPHModel&, const FluidSPHParams&)` — allocates SoA buffers.
- `void computeDensity(FluidSPHModel&, const UniformGridIndex&)` — launches `computeDensityKernel`.
- `void destroyFluidModel(FluidSPHModel&)` — frees CudaBuffers.

### Step 4 — `src/models/FluidSPHModel.cu`

Implements `computeDensityKernel`:

```cuda
__global__ void computeDensityKernel(
    const float* posX, const float* posY,
    const int*   neighbourIndices, const int* neighbourCounts,
    int          maxNeighbours,
    float        influenceRadius, float mass,
    float*       outDensity, uint32_t count)
{
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= count) return;

    float px = posX[idx];
    float py = posY[idx];
    float density = 0.0F;

    int nCount = neighbourCounts[idx];
    for (int n = 0; n < nCount; ++n) {
        int   j  = neighbourIndices[idx * maxNeighbours + n];
        float dx = posX[j] - px;
        float dy = posY[j] - py;
        float d  = sqrtf(dx * dx + dy * dy);
        density += mass * smoothingKernel(d, influenceRadius);
    }

    outDensity[idx] = density;
}
```

### Step 5 — CMakeLists.txt

Add `src/models/FluidSPHModel.cu` to `particle_sim` sources. Add test `.cu` files to `particle_sim_tests`.

### Step 6 — Build and test

```bash
cmake --build build
cd build && ctest --output-on-failure -R Sph
```

---

## Validation and Acceptance

| # | Check | Observable Evidence |
|---|-------|---------------------|
| 1 | Kernel unit tests pass | `ctest -R SphKernels` — PASSED |
| 2 | Density test passes | `ctest -R FluidDensity` — PASSED |
| 3 | No NaN/Inf in density output | Test asserts `std::isfinite` on all density values |
| 4 | Build clean | Zero warnings |

---

## Artifacts and Notes

- `src/models/SphKernels.cuh`
- `src/models/FluidSPHModel.cuh`
- `src/models/FluidSPHModel.cu`
- `tests/gpu/models/SphKernelsTest.cu`
- `tests/gpu/models/FluidDensityTest.cu`

---

## Interfaces and Dependencies

**Depends on:** Phase 3 (UniformGridIndex), Phase 2 (TOML config for `FluidSPHParams`).  
**Required by:** Phase 6 (density heatmap uses the density array), future pressure/viscosity force phases.
