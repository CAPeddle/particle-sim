# ExecPlan: Phase 7 — Spawn Patterns (Initial Conditions)

**Date:** 2026-03-12  
**Status:** Not Started  
**Prerequisite:** [Phase 2 — TOML Config](2026-03-12-phase-2-toml-config-system.md) (`initial_condition` key) and [Phase 4 — SPH Model](2026-03-12-phase-4-sph-smoothing-kernel-density.md) (`FluidSPHModel` struct exists to receive the init kernel output) — all Progress checkboxes in both plans must be ticked before starting this plan.

---

## Purpose / Big Picture

Currently, particles are spawned in a random circle (existing `initParticlesKernel`). SPH physics is most interesting and testable with specific initial conditions — a dam break, a falling column, or a uniform grid. This plan adds selectable init kernels driven by the `initial_condition` config key.

**Terms:**
- **Dam break** — Dense block of particles on one side of the domain, empty on the other. Classic SPH test case; tests pressure propagation and free surface.
- **Falling column** — Particles arranged in a vertical column above the centre; gravity pulls them down and they splash. Tests boundary collision and splashing.
- **Grid spawn** — Uniform grid of particles with configurable spacing. Used for stable initial conditions and verifying density = rest density.
- **`InitCondition`** — Enum class with `RandomCircle`, `Grid`, `DamBreak`, `FallingColumn` variants.

---

## Progress

- [ ] `Prerequisites verified` — [Phase 2](2026-03-12-phase-2-toml-config-system.md) and [Phase 4](2026-03-12-phase-4-sph-smoothing-kernel-density.md) show all checkboxes ticked; `src/config/ConfigReader.hpp` and `src/models/FluidSPHModel.cuh` exist
- [ ] `RED tests added`
- [ ] `GREEN implementation completed`
- [ ] `REFACTOR + validation completed`
- [ ] `Code review — zero ERRORs`

---

## Decision Log

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Each init condition is a separate `__global__` kernel (not a branching monolith) | Kernel code is simpler; selection is done on CPU before launch. |
| 2 | `InitCondition` read from `config.toml [model.sph] initial_condition` string | Config-driven; also overrideable via ImGui "Reset" dropdown. |

---

## Context and Orientation

**What this plan adds:**
- `src/models/FluidInitKernels.cuh/.cu` — `gridInitKernel`, `damBreakInitKernel`, `fallingColumnInitKernel`.
- `src/models/InitCondition.hpp` — `InitCondition` enum + string→enum parser.
- Updated `FluidSPHModel::init()` — selects init kernel from config.
- Updated `main.cpp` Reset button — dropdown to select init condition.
- `tests/gpu/models/FluidInitTest.cu` — validates particle counts and position bounds for each condition.

---

## Concrete Steps

### Step 0 — Verify prerequisites

Open [Phase 2](2026-03-12-phase-2-toml-config-system.md) and [Phase 4](2026-03-12-phase-4-sph-smoothing-kernel-density.md) and confirm all checkboxes are ticked in both.

Verify the key artifacts exist:

```bash
ls src/config/ConfigReader.hpp src/models/FluidSPHModel.cuh
```

Confirm all tests pass:

```bash
cmake --build build --target particle_sim_tests && cd build && ctest --output-on-failure
```

If either check fails, do not proceed — resolve the blocking phase first.

### Step 1 — `src/models/InitCondition.hpp`

```cpp
#pragma once
#include <string_view>
#include <expected>
#include "config/ConfigError.hpp"

namespace psim::models {

enum class InitCondition { RandomCircle, Grid, DamBreak, FallingColumn };

[[nodiscard]] std::expected<InitCondition, psim::config::ConfigError>
parseInitCondition(std::string_view name);

} // namespace psim::models
```

### Step 2 — RED tests

- `parseInitCondition("grid")` → `InitCondition::Grid`.
- `parseInitCondition("dam_break")` → `InitCondition::DamBreak`.
- `parseInitCondition("unknown")` → `ConfigError`.
- Grid init: all particles within domain bounds; spacing between adjacent particles ≈ expected spacing.
- Dam break: left half of domain is dense; right half is empty.

### Step 3 — Kernels in `src/models/FluidInitKernels.cu`

```cuda
__global__ void gridInitKernel(float* posX, float* posY, float* velX, float* velY,
    uint32_t count, float2 domainMin, float2 domainSize, float spacing);

__global__ void damBreakInitKernel(float* posX, float* posY, float* velX, float* velY,
    uint32_t count, float2 domainMin, float2 domainSize);

__global__ void fallingColumnInitKernel(float* posX, float* posY, float* velX, float* velY,
    uint32_t count, float2 domainMin, float2 domainSize);
```

### Step 4 — Wire into FluidSPHModel and ImGui Reset

`FluidSPHModel::init()` calls the selected kernel.  
Reset button in `main.cpp` gains a `ImGui::Combo` for init condition, calls `model.destroy()` then `model.init(count)` with updated condition.

---

## Validation and Acceptance

| # | Check | Observable Evidence |
|---|-------|---------------------|
| 1 | Tests pass | `ctest -R FluidInit` — PASSED |
| 2 | Visual: dam break | Particles start left; splash rightward when unpaused |
| 3 | Visual: grid | Particles in uniform grid; stable under low gravity |
| 4 | Config controls spawn | Changing `initial_condition` in `config.toml` + restart changes spawn pattern |

---

## Artifacts and Notes

- `src/models/InitCondition.hpp`
- `src/models/FluidInitKernels.cuh`
- `src/models/FluidInitKernels.cu`
- `tests/gpu/models/FluidInitTest.cu`

---

## Interfaces and Dependencies

**Depends on:** Phase 2 (TOML config), Phase 4 (FluidSPHModel exists).  
**Required by:** Phase 4 testing benefits greatly from controlled init conditions.
