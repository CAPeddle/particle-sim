# particle-sim — Living Plan

_Last updated: 2026-03-20_

## Phase Status

| Phase | ExecPlan | Status |
|-------|----------|--------|
| Phase 0 — GoogleTest Integration | `.github/planning/execplans/2026-03-12-phase-0-googletest-integration.md` | ✅ Complete |
| Phase 1 — ISimulationModel Interface | `.github/planning/execplans/2026-03-12-phase-1-simulation-model-interface.md` | ✅ Complete |
| Phase 2 — TOML Config System | `.github/planning/execplans/2026-03-12-phase-2-toml-config-system.md` | ✅ Complete |
| Phase 3 — UniformGridIndex GPU | `.github/planning/execplans/2026-03-12-phase-3-uniform-grid-index.md` | ✅ Complete |
| Phase 4 — SPH Smoothing Kernel + Density | `.github/planning/execplans/2026-03-12-phase-4-sph-smoothing-kernel-density.md` | ✅ Complete |
| Phase 5 — Boundary Collision with Damping | `.github/planning/execplans/2026-03-12-phase-5-boundary-collision.md` | ✅ Complete |
| Phase 6 — Density Heatmap Visualisation | `.github/planning/execplans/2026-03-12-phase-6-density-heatmap.md` | ✅ Complete |
| Phase 6a — Post-Review Remediation | `.github/planning/execplans/2026-03-16-phase-6a-review-remediation.md` | ✅ Complete |
| Phase 6b — GpuScalarFieldInput + W-18 Close | `.github/planning/execplans/2026-03-16-phase-6b-gpu-scalar-field-input.md` | ✅ Complete |
| **Migrate to Windows Native** | `.github/planning/execplans/2026-03-17-migrate-to-windows-native.md` | 🟡 Docs + review pending |

---

## Environment Notes

- **Windows native (primary)** (from 2026-03-17): RTX 4050 Laptop, SM 8.9, driver 595.79, CUDA 13.2
- **WSL2: not supported** — `glfwCreateWindow` always fails (no NVIDIA EGL ICD). CUDA compute works but GL interop does not.
- **CUDA Toolkit: 13.2** confirmed on Windows native.

---

## Open TODOs

### Deferred: ImGui boundary controls (Phase 5)

> **TODO (Phase 5 Step 4, deferred):** Add an ImGui dropdown to select `BoundaryMode` at runtime
> and a slider for `boundaryDamping`, wired to `ParticleSystem::boundaryMode` and
> `ParticleSystem::boundaryDamping`. Deferred from Phase 5 to keep scope focused on
> kernel + test correctness. To be implemented when the rendering loop is properly connected
> to the SPH model.
>
> Track as: `feat(ui): add BoundaryMode dropdown and boundaryDamping slider in ImGui`

### `assert()` preconditions require Debug build

> **TODO (core hardening):** The `UniformGridIndex` constructor uses `assert()` for Fail-Fast
> precondition checks. These are compiled out in Release builds (`-DNDEBUG`), causing
> `Constructor_*_Aborts` death tests to fail. Replace with explicit `if (...) std::abort()`
> guards (or a project-wide `PSIM_ASSERT` macro) that remain active regardless of build type.
>
> Track as: `fix(spatial): replace assert() preconditions with always-on Fail-Fast checks in UniformGridIndex`

### Profiling Phase — `QueryResult::maxCountObserved`

> **TODO (Profiling Phase):** `QueryResult::maxCountObserved` is currently returned as `0` (placeholder).
> Computing the true maximum requires either an atomic-max into device memory or a
> post-query device-to-host reduction pass — both add a sync cost.
> Defer to a dedicated profiling step: measure whether the cost warrants it vs.
> sizing `maxPerParticle` conservatively and relying on `truncated`.
>
> Track as: `perf(spatial): implement maxCountObserved via device reduction in UniformGridIndex`

### `cudaDeviceSynchronize` coupling in `launchComputeDensityKernel`

> **TODO (Phase 6+ / performance pass):** `detail::launchComputeDensityKernel` in `FluidSPHModel.cu`
> ends with `CUDA_CHECK(cudaDeviceSynchronize())`, which forces a full CPU–GPU sync after every
> density pass. This caps frame rate once the rendering loop is active. Replace with a CUDA
> stream-based approach that pipelines density computation with rendering when profiling shows
> it is a bottleneck.
>
> Track as: `perf(models): pipeline computeDensityKernel with CUDA streams, remove global sync`

### Non-virtual `queryNeighboursDirect` on `UniformGridIndex` (long-term vtable fix)

> **TODO (spatial cleanup):** The qualified-id workaround in `FluidSPHModelOps.cpp` bypasses
> the vtable to avoid the nvcc/g++ mismatch (see ADR-001 Known Limitations). The preferred
> fix is to add a non-virtual `queryNeighboursDirect` method to `UniformGridIndex` that returns
> a plain POD result and carries no `#ifndef __CUDACC__` guard. This eliminates the qualified-id
> dependency and is safer for any future consumers.
>
> Track as: `refactor(spatial): add queryNeighboursDirect to UniformGridIndex to replace vtable workaround`

### ~~Deferred: `DensityHeatmapInput` view struct~~ — **Closed by Phase 6b**

> Closed by [Phase 6b ExecPlan](.github/planning/execplans/2026-03-16-phase-6b-gpu-scalar-field-input.md).
> `GpuScalarFieldInput` introduced in `src/rendering/GpuScalarFieldInput.cuh` and
> `updateDensityHeatmap` now consumes that view type instead of `FluidSPHModel`.

### Deferred: `GpuScalarField` — Generic GPU Field Visualisation System (Phase 7+ — CONFIRMED)

> **TODO (Rendering generalisation — Option B confirmed):** `DensityHeatmap` hard-codes the
> density field and owns its CUDA-GL interop pipeline. A generic `GpuScalarField` type is
> confirmed for Phase 7+ to support simultaneous overlays (e.g., density + pressure
> side-by-side comparison).
>
> **Design decisions (from spike 2026-03-16):**
> - `GpuScalarField` owns one pipeline instance (texture + CUDA resource + VAO/VBO + accumBuffer).
> - Active fields stored as `std::vector<GpuScalarField>` in `Application` / rendering layer.
> - Public API: `renderScalarField(const GpuScalarFieldInput&)` — input struct carries
>   `posX`, `posY`, `scalarValues`, `particleCount`, `domainMin`, `domainMax`, plus
>   `overrideRange` flag with `minValue`/`maxValue` (Option C normalisation).
> - When `overrideRange == false`: auto-compute min/max via device reduction (one D→H sync).
> - `u_colourMap` uniform deferred — add only when a signed scalar field is introduced.
> - Non-copyable, non-movable (`= delete`); Rule of Five via RAII. ADR required before implementation.
>
> **Trigger:** addition of `pressure[]` or any second per-particle scalar buffer in `FluidSPHModel`.
>
> **Spike:** `docs/spikes/arch-gpu-scalar-field-visualization-spike.md` (✅ Complete — Option B confirmed; Stage 2 design finalised)
>
> Track as: `feat(rendering): introduce GpuScalarField generic GPU field visualisation system`

### Deferred: Signed scalar field support (`u_colourMap` diverging colour map)

> **TODO (Rendering — signed fields):** The current `heatmap.frag` hard-codes a sequential
> blue→red ramp that silently clips negative values to blue, making them visually
> indistinguishable from zero. Signed fields (vorticity curl-z, divergence magnitude) require
> a diverging colour map (blue ↔ red through white/black centre).
>
> **Deferred until:** a signed scalar field buffer is added to `FluidSPHModel` (vorticity,
> divergence). At that point, add `uniform int u_colourMap` to `heatmap.frag`
> (0 = sequential, 1 = diverging) and a corresponding `colourMap` field in `GpuScalarFieldInput`.
> Do not add speculatively — no signed field exists today.
>
> Track as: `feat(rendering): add u_colourMap diverging colour ramp for signed scalar fields`

### Backlog (from fluid-sim predecessor)

See `docs/fluid-sim-migration.md` for the prioritised migration backlog (7 features).
Primary candidates: SPH smoothing kernel, density/gradient calculation, boundary collision.

---

## Design Decisions Made in Phase 3

| # | Decision |
|---|----------|
| 1 | `ISpatialIndex` query methods return `std::expected<QueryResult, SpatialIndexError>` — Fail-Fast modernisation |
| 2 | Separate `particle_sim_gpu_tests` executable so GPU/CPU tests are independently runnable |
| 3 | `queryFromPoints()` fully implemented (not stubbed) |
| 4 | `maxCountObserved` returns `0` until a profiling phase adds a device reduction (see TODO above) |
