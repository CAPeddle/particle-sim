---
title: "GPU Scalar Field Visualization — Generic Abstraction"
category: "arch"
status: "✅ Complete"
priority: "Medium"
timebox: "3 hours"
created: 2026-03-16
updated: 2026-03-16
owner: "Copilot"
tags: ["technical-spike", "arch", "rendering", "cuda-gl-interop"]
---

# GPU Scalar Field Visualization — Generic Abstraction

## Summary

**Spike Objective:** Determine whether `DensityHeatmap` should be generalized into a reusable
`GpuScalarField` type that can visualize any per-particle scalar field (density, pressure,
vorticity, divergence magnitude) without duplicating the CUDA-GL interop pipeline.

**Why This Matters:** `DensityHeatmap` currently hard-codes the density field and couples
`updateDensityHeatmap` directly to `FluidSPHModel` (W-18, tracked in `plan.md`). Every new
scalar field visualization (pressure, vorticity, velocity magnitude) would require duplicating
the accumulation kernel, surface mapping, and fragment shader unless a common abstraction is
introduced. Getting this right before adding the next field eliminates future duplication and
maps cleanly onto the existing `psim::rendering` subsystem design.

**Timebox:** 3 hours

**Decision Deadline:** Before any Phase 7+ work that introduces a second rendered scalar field.

---

## Research Questions

**Primary Question:** Should the CUDA-GL interop pipeline (accumulate → surface write → GL
texture → fullscreen quad) be abstracted as a generic `GpuScalarField` that any simulation
model can populate, or should each field remain a purpose-built overlay?

**Secondary Questions:**

- What is the minimum view struct needed to decouple the scatter kernel from model internals?
  (Relates directly to the already-deferred `DensityHeatmapInput` item in `plan.md`.)
- Can the accumulation + write-to-surface kernels be reused verbatim for pressure, vorticity
  etc., or does each field require a semantically different scatter pass?
- Should `GpuScalarField` own the GL texture + CUDA resource, or should those stay in a
  separate lifecycle object (analogous to the current `DensityHeatmap` struct)?
- Does the fragment shader need to vary per field (e.g., signed divergence needs a diverging
  colour map, not the blue→red heatmap), and how does that affect the abstraction boundary?
- Is there value in a CPU-side `ScalarFieldDescriptor` (name, range, colour map enum) for
  ImGui integration (field selector, per-field max-value override)?

---

## Investigation Plan

### Research Tasks

- [x] Audit the current `DensityHeatmap` pipeline: identify which parts are field-specific
      vs. which are generic (accumulation buffer layout, kernel signatures, GL texture setup,
      shader uniforms, VAO/VBO).
- [x] Draft a `GpuScalarFieldInput` view struct (analogous to `ParticlePositionsView`) that
      carries enough information for the scatter kernel without referencing `FluidSPHModel`.
      Check whether this is simply `DensityHeatmapInput` with a more general name.
- [x] Assess whether the scatter kernel body is field-agnostic (it accumulates `float[N]` into
      a `resolution²` grid — it is, intrinsically). Confirm by inspecting `scatterDensityKernel`.
- [x] Evaluate two designs:
  - **Option A — Thin view struct only (`GpuScalarFieldInput`):** `updateDensityHeatmap`
    accepts a view struct instead of `FluidSPHModel&`. No new type; solves W-18; low risk.
  - **Option B — Full `GpuScalarField` abstraction:** Owns the texture, CUDA resource,
    accumulation buffers, and VAO/VBO. `renderScalarField(field)` is the public API.
    Generalizes the renderer; higher refactor cost; enables multi-field panels.
  - Determine which option the codebase is actually ready for (Phase 6a just landed; no
    second field exists yet).
- [x] Check whether multiple simultaneous scalar field overlays are a target use case
      (e.g., pressure field vs. density field side by side). If yes, Option B is warranted;
      if no, Option A is sufficient.
- [x] Review `heatmap.frag` to determine whether a single shader with a `uniform int u_colourMap`
      parameter would cover all planned fields, or whether diverging colour maps (signed fields)
      need a separate shader variant.
- [x] Confirm that the CUDA-GL interop lifecycle (register → map → write → unmap) is identical
      for all scalar fields. It should be, since all produce a `GL_R32F` texture.

**Secondary question disposition — `ScalarFieldDescriptor` / ImGui integration:**
A CPU-side `ScalarFieldDescriptor` (name, range, colour map enum) for ImGui field-selector
and per-field max-value override has no immediate value: only one scalar field exists, there
is no multi-field panel, and `DensityHeatmap.maxDensity` already provides the per-field range
mechanism via ImGui. Formally deferred to Stage 2 scope. No follow-up action required for Stage 1.

### Success Criteria

**This spike is complete when:**

- [x] A clear recommendation (Option A or B, or a staged approach) is documented with rationale.
- [x] The `GpuScalarFieldInput` (or `DensityHeatmapInput`) view struct fields are specified.
- [x] It is confirmed whether the accumulation kernel can be made field-agnostic with zero
      change to its body.
- [x] The fragment shader strategy (single shader with colour map uniform, or per-field shaders)
      is decided.
- [x] The rendering-decoupling TODO in `plan.md` (W-18) is superseded or clarified by this
      spike's recommendation.

---

## Technical Context

**Current pipeline (as of Phase 6a):**

```
FluidSPHModel { posX, posY, density, params }
    ↓  (passed directly to updateDensityHeatmap)
scatterDensityKernel  ← accumulates float[N] into resolution² grid
    ↓
writeTextureKernel    ← writes averages to cudaSurfaceObject_t
    ↓
GL_TEXTURE_2D (GL_R32F)
    ↓
heatmap.frag          ← u_densityTex, u_maxDensity, u_alpha → blue→red colour map
    ↓
fullscreen quad VAO
```

**Fields that would benefit from the same pipeline:**

| Field | Source array | Signed? | Suggested colour map |
|-------|-------------|---------|---------------------|
| Density | `density[]` | No | Blue → Red |
| Pressure | `pressure[]` | No | Blue → Red |
| Velocity magnitude | `sqrt(vx²+vy²)` | No | Blue → Red |
| Vorticity (curl z) | computed | **Yes** | Diverging (Blue ↔ Red) |
| Divergence | computed | **Yes** | Diverging (Blue ↔ Red) |

**Related Components:** `src/rendering/DensityHeatmap.cuh/.cu`, `shaders/heatmap.frag`,
`src/models/FluidSPHModel.cuh`, `src/core/CudaUtils.hpp`

**Dependencies:**
- Resolves and supersedes the `DensityHeatmapInput` W-18 deferred item in `plan.md`
- Should be completed before any Phase 7+ feature that introduces a second rendered field
- `initSphDemoParticles` bridge in `FluidSPHModel` is tagged `@deprecated` pending Phase 7;
  the spawn system and this spike are independent

**Constraints:**
- C++23 (CPU), CUDA 20 (GPU) — no exceptions, `std::expected<T, E>` for fallible ops
- CUDA-GL interop lifecycle must remain RAII-managed
- `GpuScalarField` (if introduced) must satisfy Rule of Five with non-copyable, non-movable policy
- FetchContent-compatible — no new system dependencies for a pure abstraction refactor
- SM 89 (RTX 4050 Laptop) target
- The abstraction must not break the existing `DensityHeatmap` tests (83 passing)

---

## Research Findings

### Investigation Results

#### 1 — `DensityHeatmap` pipeline audit (field-specific vs. generic)

| Component | Field-specific? | Notes |
|-----------|----------------|-------|
| `clearAccumKernel` | **No** | Zeroes `float[]` + `int[]` — completely generic |
| `scatterDensityKernel` | **Only by param name** | Parameter is named `density` but the logic accumulates any `float[N]` into a texel grid; rename to `scalarValues` and it's field-agnostic |
| `writeTextureKernel` | **No** | Averages `accum/count` → `GL_R32F` surface — completely generic |
| CUDA-GL interop lifecycle | **No** | `register → map → surface → unmap` is identical for every `GL_R32F` texture |
| `GL_R32F` texture + CUDA resource | **No** | Single-channel float is the correct internal format for all planned fields |
| `shaderProgram` (`heatmap.frag`) | **Partially** | Hard-codes sequential (blue→red) colour map; cannot represent signed (diverging) fields without modification |
| VAO/VBO fullscreen quad | **No** | Fullscreen UV-mapped quad is reusable as-is |
| Uniform locations cache | **Partially** | Caches `u_densityTex` + `u_maxDensity` + `u_alpha`; a `u_colourMap` uniform would need to be added for diverging fields |

**Conclusion:** The three CUDA kernels are field-agnostic in body. The only coupling is the `density` parameter name in `scatterDensityKernel` and the sequential-only fragment shader.

#### 2 — `GpuScalarFieldInput` minimum view struct

The following six fields are the complete dependency surface of `updateDensityHeatmap` on `FluidSPHModel`:

```cpp
namespace psim::rendering
{
/// @brief Non-owning view of device-side scalar field data for heatmap accumulation.
///
/// @note All device pointers must be valid and non-null when `particleCount > 0`.
/// @note `particleCount == 0` is valid; the scatter pass is a no-op in that case.
/// @note Normalisation range (`maxDensity` or equivalent) is owned by `DensityHeatmap`,
///       not by this struct. Values above the configured max saturate silently.
struct GpuScalarFieldInput
{
    const float* posX{nullptr};         ///< Device x-position array [particleCount].
    const float* posY{nullptr};         ///< Device y-position array [particleCount].
    const float* scalarValues{nullptr}; ///< Device per-particle scalar [particleCount].
    uint32_t     particleCount{0};      ///< Number of particles.
    float2       domainMin{};           ///< Domain lower-left corner.
    float2       domainMax{};           ///< Domain upper-right corner.
};
} // namespace psim::rendering
```

**Header extension decision (Expert C++ Review finding — resolved):**
`float2` is a CUDA vector type declared in `<vector_types.h>`. Placing it in a `.hpp` file
creates a hidden CUDA toolkit dependency for any C++-only translation unit that includes the
header. The project convention is unambiguous: `.cuh` for CUDA-type-bearing headers.
**Resolution: the file must be `src/rendering/GpuScalarFieldInput.cuh`, not `.hpp`.**
This is consistent with `DensityHeatmap.cuh` and all other CUDA-type-bearing headers in
`src/rendering/`.

This is effectively `DensityHeatmapInput` under a more general name. Using the general name
now costs nothing and avoids a rename when Stage 2 arrives.

**Precondition (must be documented):** `posX`, `posY`, `scalarValues` must be valid non-null
device pointers when `particleCount > 0`. `particleCount == 0` is valid — the scatter kernel
launch uses zero blocks (CUDA-defined no-op) and the clear pass still zeroes the accumulator.

#### 3 — `scatterDensityKernel` field-agnosticism confirmed

Inspection of the kernel body (`DensityHeatmap.cu` lines ~155–195) confirms:
- Only `posX[idx]`, `posY[idx]`, and `density[idx]` are read per thread.
- No density-specific formula, smoothing, or weighting is applied.
- Renaming the `density` parameter to `scalarValues` produces an identical kernel usable for
  any per-particle float array (pressure, velocity magnitude, vorticity magnitude, etc.).

#### 4 — Option A vs Option B assessment

**Option A — Thin view struct only (`GpuScalarFieldInput`):**
- `updateDensityHeatmap(DensityHeatmap&, const GpuScalarFieldInput&)` replaces
  `updateDensityHeatmap(DensityHeatmap&, const FluidSPHModel&)`.
- `DensityHeatmap` struct is unchanged; it still owns its texture, CUDA resource, VAO/VBO.
- Zero behaviour change. Resolves W-18. Risk: minimal (pure signature change + call-site update).
- Limitation: does not enable multi-field instances out of the box (caller creates multiple
  `DensityHeatmap` objects, one per field — which already works with the existing struct).

**Option B — Full `GpuScalarField` abstraction:**
- A single type owns all rendering resources and presents `renderScalarField(const GpuScalarFieldInput&)`.
- Enables a uniform API across all fields; a `std::vector<GpuScalarField>` enables multi-panel layouts.
- Requires renaming `DensityHeatmap` → `GpuScalarField` across 1 .cu, 1 .cuh, 1 test file,
  and `main.cpp` / `Application` call sites. Higher refactor surface with no second field yet.

**Verdict (updated 2026-03-16 — user decision):** Option B is confirmed for Stage 2.
The user confirmed that comparing density and pressure overlays simultaneously is a concrete
requirement. `std::vector<GpuScalarField>` is the correct Stage 2 API. Stage 1 (Option A)
still ships first as the lowest-risk path to W-18 closure and establishes `GpuScalarFieldInput`
as the shared input contract for Stage 2.

#### 5 — Multiple simultaneous overlays

**User decision (2026-03-16):** Multiple simultaneous overlays are a confirmed requirement —
comparing density and pressure side-by-side is an explicit target. Option B (`GpuScalarField`
owned abstraction with `std::vector<GpuScalarField>`) is therefore **confirmed for Stage 2**.

With Option A, calling the update function twice per frame with two separate `DensityHeatmap`
instances is already mechanically possible (each instance owns independent buffers and a GL
texture) but the API is awkward and requires the caller to manage two heterogeneous structs.
Option B provides the clean `std::vector` API that supports N overlays uniformly.

#### 6 — Fragment shader strategy

`heatmap.frag` currently uses a hard-coded sequential blue→red ramp:

```glsl
vec3 c = mix(vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), clamp(d, 0.0, 1.0));
```

- For unsigned fields (density, pressure, velocity magnitude) this is correct and sufficient.
- For signed fields (vorticity curl-z, divergence) values below zero are clamped to blue and
  are visually indistinguishable from zero — a **silent data-loss rendering bug**.

Two options:
- **Shader variant:** `heatmap_diverging.frag` — separate file, no uniform branching in shader.
- **`u_colourMap` uniform (int):** `0 = sequential, 1 = diverging`; branch in shader.
  Preferred because it avoids managing two shader programs for a single quad pipeline.

For Stage 1 (Option A), the shader change is deferred — no signed field exists yet.
For Stage 2, the `u_colourMap` approach is recommended: add one `uniform int u_colourMap`,
replace the hard-coded `mix` with a conditional ramp. Existing tests are unaffected because
they skip rendering in headless environments.

#### 7 — Edge cases found during audit

| Edge case | Location | Severity | Notes |
|-----------|----------|----------|-------|
| **`uint32_t` overflow in `totalTexels`** | `DensityHeatmap.cu` in `updateDensityHeatmap`: `uRes * uRes` | Medium | At `resolution = 65536`, `uint32_t(65536) * uint32_t(65536) = 0` (exactly, due to 2²² modular wrap). The result is silently 0, causing a zero-sized kernel launch that leaves prior-frame accumulation data visible — a stale-data bug, not a crash. `initDensityHeatmap` only checks `resolution > 0`; a practical upper-bound guard (e.g., `resolution > 4096`) is warranted. |
| **Negative scalar values clipped silently** | `heatmap.frag`: `clamp(d, 0.0, 1.0)` | Low (today) / High (when signed fields added) | Signed fields (vorticity, divergence) would appear identical to zero without a diverging colour map. Should be noted in the `GpuScalarFieldInput` API comment and addressed in Stage 2. |
| **Null device pointer dereference** | `scatterDensityKernel` | Low | No null-guard in kernel. If `GpuScalarFieldInput.particleCount > 0` and any pointer is null, kernel faults. Must be a documented `@pre` on `updateDensityHeatmap`. |
| **`discardCountBuf` read after partial kernel failure** | `updateDensityHeatmap` | Low | If the scatter kernel errors and `CUDA_CHECK` aborts, the `cudaMemcpy` for `hostDiscards` is never reached. This is acceptable (abort is the right failure mode) but should be noted. |

### Prototype/Testing Notes

- No prototype required: the scatter kernel body is trivially confirmed to be field-agnostic
  by direct inspection. The proposed `GpuScalarFieldInput` view struct requires no GPU
  validation — it is a plain POD view type.
- Existing 83-test suite in `DensityHeatmapTest.cpp` exercises the init/destroy lifecycle
  with GL+CUDA context; these tests will pass unchanged under Stage 1 (only the
  `updateDensityHeatmap` call-site changes, not the struct or lifecycle functions).
- The `scatterDensityKernel` rename (`density` → `scalarValues`) is internal to the `.cu`
  translation unit and is not visible at the ABI boundary.

### External Resources

- CUDA SDK particle simulation samples — demonstrate CUDA-GL interop with surface objects
- [ADR-001](../adr/0001-spatial-indexing-strategy.md) — precedent for strategy-pattern interface design
  in this codebase
- Phase 6a ExecPlan — `DensityHeatmapInput` W-18 context:
  `.github/planning/execplans/2026-03-16-phase-6a-review-remediation.md`

---

## Decision

### Recommendation

**Staged Option A → B (Stage 2 now confirmed, not speculative).**

- **Stage 1 (implement now — closes W-18):** Introduce `GpuScalarFieldInput` view struct
  (fields specified above, including `minValue`/`maxValue`/`overrideRange`). Change
  `updateDensityHeatmap` to accept `const GpuScalarFieldInput&` instead of
  `const FluidSPHModel&`. Rename the `density` parameter in `scatterDensityKernel` to
  `scalarValues`. Add auto-compute reduction path for `overrideRange == false`.
  Zero net behaviour change for the existing density overlay (caller passes
  `overrideRange = true` with current `maxDensity` value).

- **Stage 2 (confirmed for Phase 7+ — when `pressure[]` or a second scalar field is added):**
  Rename `DensityHeatmap` → `GpuScalarField` owning its pipeline. Expose
  `renderScalarField(const GpuScalarFieldInput&)` as the public API. Store active instances
  in `std::vector<GpuScalarField>` to support N simultaneous overlays. Add `u_colourMap`
  uniform for diverging fields when signed fields land. Write ADR before implementation.

**All three open questions resolved (2026-03-16):**
1. ✅ Multiple overlays: **confirmed target** — density vs. pressure comparison required.
   Stage 2 must use `std::vector<GpuScalarField>`.
2. ✅ Signed fields: **deferred** — vorticity/divergence tracked in `plan.md` as a separate
   TODO; `u_colourMap` uniform is not needed for Stage 2 unless a signed field is added concurrently.
3. ✅ Normalization range: **Option C** — `overrideRange` flag in `GpuScalarFieldInput`.
   When `true`: use `minValue`/`maxValue`. When `false`: auto-compute via device reduction.

### Rationale

- The scatter kernel and CUDA-GL interop lifecycle are confirmed field-agnostic; Option A
  delivers full decoupling with a trivial change (view struct + param rename).
- Option B is confirmed for Stage 2 based on the explicit multi-overlay requirement
  (density vs. pressure comparison). `std::vector<GpuScalarField>` is the clean solution.
- The `overrideRange` flag in `GpuScalarFieldInput` satisfies both the interactive (slider
  control → `overrideRange = true`) and exploratory (unknown range → `overrideRange = false`
  auto-compute) use cases without requiring two different struct types.
- The fragment shader limitation (signed-field clipping) is correctly deferred — signed
  fields (vorticity, divergence) are not on the immediate roadmap; `u_colourMap` will be
  added when a signed field is introduced. Tracked in `plan.md`.
- Existing 83-test suite is unaffected: lifecycle functions are unchanged; only the
  `updateDensityHeatmap` signature changes, which the tests do not call directly in headless CI.
- Using `GpuScalarFieldInput` (not `DensityHeatmapInput`) in Stage 1 costs nothing today and
  avoids a rename when Stage 2 generalises the pipeline.

### Implementation Notes

**Stage 1 — concrete changes (all within `psim::rendering`):**

1. Add `GpuScalarFieldInput` struct to a new **`.cuh`** header
   `src/rendering/GpuScalarFieldInput.cuh` — `.cuh` is required because `float2` is a CUDA
   vector type (see Finding 2). Placing it in `.hpp` would create a CUDA toolkit dependency
   for any C++-only translation unit including the header.
2. Change `updateDensityHeatmap` signature in `DensityHeatmap.cuh` and `DensityHeatmap.cu`:
   `void updateDensityHeatmap(DensityHeatmap& heatmap, const GpuScalarFieldInput& input);`
3. Inside `updateDensityHeatmap`:
   - Replace `model.*` field accesses with `input.*`.
   - Add reduction branch: when `input.overrideRange == false`, launch a min/max reduction
     kernel over `input.scalarValues[0..N-1]`, copy results D→H, supply as normalisation range.
     When `input.overrideRange == true`, use `input.minValue` / `input.maxValue` directly.
   - Guard: if `input.overrideRange == true` and `input.maxValue == input.minValue`, treat as
     `maxValue = minValue + 1.0F` (avoid divide-by-zero in normalisation).
4. Rename `density` parameter to `scalarValues` in `scatterDensityKernel` (`.cu` internal).
5. Update the one call-site (likely `Application.cpp` / `main.cpp`) to build a
   `GpuScalarFieldInput` from the `FluidSPHModel` fields with `overrideRange = true` and
   current `heatmap.maxDensity` as `maxValue` (preserves existing behaviour exactly).
6. Add `resolution > 4096` upper-bound check in `initDensityHeatmap` to address the
   `uint32_t` overflow edge case (at `resolution = 65536`, `uint32_t * uint32_t` wraps to
   exactly 0, causing a zero-sized kernel launch that produces stale-frame heatmap data).
   Document the guard in Doxygen `@pre`.

**Stage 2 — confirmed for Phase 7+ (trigger: addition of `pressure[]` or any second scalar field):**

- Rename `DensityHeatmap` → `GpuScalarField`. Move texture/VAO/VBO/accumBuffer ownership into
  the new type. `GpuScalarFieldInput` (from Stage 1) becomes the per-call input contract.
- Public API: `renderScalarField(const GpuScalarFieldInput&)` replaces
  `updateDensityHeatmap` + `renderDensityHeatmap` pair.
- Active fields stored as `std::vector<GpuScalarField>` in `Application` / rendering layer;
  density and pressure overlays can be enabled/disabled independently.
- Update `heatmap.frag` with `uniform int u_colourMap` (0 = sequential, 1 = diverging)
  **only if** a signed scalar field is introduced in the same phase. If not, defer further.
- Write ADR documenting the `GpuScalarField` generalisation before implementation begins.
- Update `plan.md` Stage 2 TODO when ExecPlan is created.

### Follow-up Actions

- [x] Confirm Option A preferred for Stage 1 (done by this spike)
- [x] Confirm Option B confirmed for Stage 2 (user decision 2026-03-16 — multi-overlay requirement)
- [x] Confirm normalisation strategy: Option C `overrideRange` flag (user decision 2026-03-16)
- [x] Confirm signed fields deferred (user decision 2026-03-16 — tracked in `plan.md`)
- [ ] Create ExecPlan for Stage 1: `GpuScalarFieldInput.cuh` + `updateDensityHeatmap` signature
      change + `overrideRange` reduction branch + `resolution > 4096` guard (closes W-18).
      **ExecPlan's first milestone must be a RED phase commit** containing at minimum:
      - `GpuScalarFieldInput_DefaultConstruct_AllFieldsZero`
      - `UpdateDensityHeatmap_ZeroParticleCount_IsNoOp`
      - `UpdateDensityHeatmap_NullPositionPtr_WithNonZeroCount_Aborts`
      - `UpdateDensityHeatmap_OverrideRangeTrue_UsesProvidedMinMax`
      - `UpdateDensityHeatmap_OverrideRangeFalse_AutoComputesRange`
- [ ] Update `plan.md` W-18 TODO: replace with Stage 1 ExecPlan reference (W-18 fully closed by Stage 1)
- [ ] Update `plan.md` `GpuScalarField` TODO: mark as confirmed for Phase 7+, link to this spike
- [ ] Add `@pre particleCount == 0 is valid; scatter pass is a no-op` to `updateDensityHeatmap`
      Doxygen in `DensityHeatmap.cuh`.
- [ ] Add `@note Values above maxDensity saturate to full red; no warning is emitted` to the
      `DensityHeatmap.maxDensity` field Doxygen in `DensityHeatmap.cuh`.
- [ ] When Phase 7 adds `pressure[]` or a second scalar buffer: create ADR for `GpuScalarField`
      abstraction + Stage 2 ExecPlan. Trigger `u_colourMap` uniform addition **only if** a
      signed field is included in the same phase.

---

## Status History

| Date | Status | Notes |
|------|--------|-------|
| 2026-03-16 | 🔴 Not Started | Spike created — triggered by Phase 6a review observation |
| 2026-03-16 | ✅ Complete | Full codebase audit complete. Recommendation: staged Option A → B. Stage 1 ExecPlan required. Expert C++ + Code Reviewer agent close-off: all blocking issues resolved in spike text (.cuh extension decision, overflow threshold, namespace, TDD RED phase). |
| 2026-03-16 | ✅ Complete (decisions recorded) | User confirmed: (1) Option B confirmed — multi-overlay required (density vs. pressure); (2) signed fields deferred; (3) normalisation = Option C `overrideRange` flag with auto-compute fallback. Spike fully closed. |

---

_Last updated: 2026-03-16_
