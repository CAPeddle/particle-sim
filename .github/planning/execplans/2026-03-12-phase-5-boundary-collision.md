# ExecPlan: Phase 5 — Boundary Collision with Damping

**Date:** 2026-03-12  
**Status:** Complete  
**Prerequisite:** [Phase 2 — TOML Config](2026-03-12-phase-2-toml-config-system.md) (reads `damping`, `boundary_mode`) and [Phase 0 — GoogleTest](2026-03-12-phase-0-googletest-integration.md) — all Progress checkboxes in both plans must be ticked before starting this plan.

---

## Purpose / Big Picture

The existing CUDA update kernel uses modulo wrap-around boundaries (particles teleport to the opposite edge). For SPH fluid simulation, this is physically wrong — fluids should bounce off walls with energy loss. This plan replaces the current boundary with a configurable mode: `reflect` (default for SPH) or `wrap` (keep for other demos).

**Terms:**
- **Reflect boundary** — When a particle exceeds the domain boundary, its velocity component perpendicular to the wall is negated and scaled by a damping factor `d ∈ (0, 1]`. Position is clamped to the boundary.
- **Wrap boundary** — Particle position is wrapped via modulo to the opposite edge (current behaviour).
- **Damping** — Scalar `d` multiplied into the velocity component on bounce. `d = 1.0` is elastic (no energy loss), `d = 0.5` absorbs half the kinetic energy.
- **`BoundaryMode`** — Enum class with `Reflect` and `Wrap` variants, passed as kernel argument.

---

## Progress

- [x] `Prerequisites verified` — [Phase 2](2026-03-12-phase-2-toml-config-system.md) shows all checkboxes ticked; `src/config/ConfigReader.hpp` and `config.toml` exist — 2026-03-15
- [x] `RED tests added` — `tests/unit/core/BoundaryUtilsTest.cpp` (12 CPU tests) and `tests/gpu/core/BoundaryTest.cu` (9 GPU tests) committed — 2026-03-15
- [x] `GREEN implementation completed` — `SimConstants.hpp`, `BoundaryUtils.cuh`, `ParticleSystem` wired; 74/74 tests pass — 2026-03-15
- [x] `REFACTOR + validation completed` — build clean, zero new warnings, 74/74 tests pass — 2026-03-15
- [x] `Code review — zero ERRORs` — 2026-03-15

---

## Surprises & Discoveries

**S-1: Release build disables `assert()` preconditions, breaking `UniformGridIndex` death tests.**

The three `Constructor_*_Aborts` death tests in `UniformGridIndexTest` rely on `assert()` firing when invalid constructor arguments are supplied. CMake's Release configuration sets `-DNDEBUG`, which compiles out `assert()`. After this plan ran `cmake -B build -DCMAKE_BUILD_TYPE=Release`, those tests started failing. Reverting to `Debug` mode restored all 74 tests to passing.

This is a pre-existing structural issue (not introduced by Phase 5). The `UniformGridIndex` precondition checks should be replaced with explicit `std::abort()` or `CudaUtils.hpp`-style Fail-Fast checks that remain active in Release builds. Tracked as a cleanup item.

**S-2: `applyBoundary` declared `__host__ __device__` enables dual test coverage.**

Q4 requested both CPU and GPU test coverage. Making `applyBoundary` `__host__ __device__ __forceinline__` allowed 12 direct host-side tests in `BoundaryUtilsTest.cpp` and 9 GPU-dispatched tests in `BoundaryTest.cu`, sharing identical arithmetic expectations. The CPU tests run instantly; the GPU tests confirm the device path produces bit-identical results.

---

## Decision Log

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | `BoundaryMode` as an enum class, not a compile-time template parameter | Allows runtime switching via ImGui / config without recompilation. |
| 2 | Fix fluid-sim's position-clamping bug on left/top walls | Original code didn't clamp position on left/top walls — particles could escape. Fixed here. |
| 3 | `damping` default 0.8 (not 0.999) for reflect mode | 0.999 is appropriate for velocity drag per frame; 0.8 is better for a single bounce event. |

---

## Outcomes & Retrospective

**Delivered:**
- `src/core/SimConstants.hpp` — canonical home for `BoundaryMode`, `MAX_NEIGHBOURS`, `MAX_PARTICLES`.
- `src/core/BoundaryUtils.cuh` — `__host__ __device__` `applyBoundary()`, fixing the fluid-sim left/top wall clamping bug.
- `src/models/FluidSPHModel.cuh` — `DEFAULT_MAX_NEIGHBOURS` now aliases `psim::core::MAX_NEIGHBOURS` (Q3 alignment).
- `src/rendering/ParticleSystem.cuh` — `boundaryMode` and `boundaryDamping` fields added.
- `src/rendering/ParticleSystem.cu` — inline wrap removed from `updateParticlesKernel`; separate `applyBoundaryKernel` added (Q2).
- `config.toml` — `boundary_damping = 0.8` added under `[model.sph]` as a separate key from `damping` (Q1).
- 21 new tests (12 CPU, 9 GPU). Total: 74/74 passing.

**Deferred:**
- ImGui dropdown for `BoundaryMode` and damping slider (Q5) — tracked in `plan.md`.

---

## Context and Orientation

**Current state:** `src/rendering/ParticleSystem.cu` has an `updatePositionsKernel` that applies wrap-around in a swirl demo. No boundary collision or damping.

**What this plan adds:**
- `BoundaryMode` enum in `src/core/SimConstants.hpp` (new file, also holds `MAX_NEIGHBOURS`, etc.).
- CUDA boundary helper functions in a new `src/core/BoundaryUtils.cuh`.
- Modified `updatePositionsKernel` (or new `applyBoundaryKernel`) in `ParticleSystem.cu`.
- `config.toml` `boundary_mode` and `boundary_damping` keys already in Phase 2's schema.
- `tests/gpu/core/BoundaryTest.cu` — GPU tests for reflect and wrap.

---

## Concrete Steps

### Step 0 — Verify prerequisites

Open [Phase 2](2026-03-12-phase-2-toml-config-system.md) and confirm all checkboxes are ticked.

Verify the key artifacts exist:

```bash
ls src/config/ConfigReader.hpp config.toml
```

Confirm all tests pass:

```bash
cmake --build build --target particle_sim_tests && cd build && ctest --output-on-failure
```

If either check fails, do not proceed — resolve Phase 2 first.

### Step 1 — `src/core/BoundaryUtils.cuh`

```cuda
#pragma once

enum class BoundaryMode : int { Wrap = 0, Reflect = 1 };

__device__ __forceinline__ void applyBoundary(
    float& x, float& y, float& vx, float& vy,
    float minX, float maxX, float minY, float maxY,
    BoundaryMode mode, float damping)
{
    if (mode == BoundaryMode::Reflect) {
        if (x > maxX) { vx *= -damping; x = maxX; }
        if (x < minX) { vx *= -damping; x = minX; }
        if (y > maxY) { vy *= -damping; y = maxY; }
        if (y < minY) { vy *= -damping; y = minY; }
    } else {
        float w = maxX - minX;
        float h = maxY - minY;
        if (x > maxX) x -= w;
        if (x < minX) x += w;
        if (y > maxY) y -= h;
        if (y < minY) y += h;
    }
}
```

### Step 2 — RED tests

- Reflect: particle at `x = 1.1`, bounds `[-1, 1]`, `vx = 2`, `damping = 0.8` → `x = 1.0`, `vx = -1.6`.
- Reflect: left wall — particle at `x = -1.1` → `x = -1.0`, `vx` negated and damped.
- Wrap: particle at `x = 1.1`, bounds `[-1, 1]` → `x = -0.9`.
- Zero velocity: particle at boundary with zero velocity stays at boundary.

### Step 3 — Update `ParticleSystem.cu`

Add `BoundaryMode boundaryMode` and `float boundaryDamping` to the kernel call. Read from config via `ParticleSystem` struct (new fields).

### Step 4 — ImGui control

In `main.cpp`, add a dropdown for `BoundaryMode` and a slider for `boundaryDamping` using `Parameter<float>` from Phase 1.

---

## Validation and Acceptance

| # | Check | Observable Evidence |
|---|-------|---------------------|
| 1 | Tests pass | `ctest -R Boundary` — PASSED |
| 2 | Particles bounce off walls visually | Run `./build/particle_sim`, particles reflect off all four edges |
| 3 | Damping = 1.0 is elastic | Particles don't lose speed on bounce (Visual + test) |
| 4 | Wrap mode still works | Selectable in ImGui; particles teleport as before |

---

## Artifacts and Notes

- `src/core/BoundaryUtils.cuh`
- `src/core/SimConstants.hpp`
- Modified `src/rendering/ParticleSystem.cu`
- `tests/gpu/core/BoundaryTest.cu`

---

## Interfaces and Dependencies

**Depends on:** Phase 2 (config reads `boundary_mode`, `boundary_damping`).  
**Required by:** Phase 4 (SPH model needs correct boundaries) — can run in any order after Phase 2.
