# ExecPlan: Phase 6 — Density Heatmap Visualisation

**Date:** 2026-03-12  
**Status:** Not Started  
**Prerequisite:** [Phase 4 — SPH Smoothing Kernel + Density](2026-03-12-phase-4-sph-smoothing-kernel-density.md) and [Phase 3 — UniformGridIndex](2026-03-12-phase-3-uniform-grid-index.md) — all Progress checkboxes in both plans must be ticked before starting this plan.

---

## Purpose / Big Picture

Adds a toggleable debug overlay that renders the SPH density field as a colour heatmap (blue = low density → red = high density) underneath the particle layer. This is the primary visual validation tool for SPH physics — it makes density gradients visible without writing debug output.

**Terms:**
- **Density heatmap** — A fullscreen quad rendered by a fragment shader that samples a 2D GPU density texture. Each texel corresponds to one grid cell; colour maps normalised density to a blue→red gradient.
- **2D texture** — OpenGL `GL_TEXTURE_2D` object. The CUDA density kernel writes values into a CUDA-registered texture, which OpenGL reads as a fullscreen background.
- **Fullscreen quad** — Two triangles covering the entire NDC space (-1 to +1), rendered before particles so it appears behind them.

---

## Progress

- [ ] `Prerequisites verified` — [Phase 4](2026-03-12-phase-4-sph-smoothing-kernel-density.md) and [Phase 3](2026-03-12-phase-3-uniform-grid-index.md) show all checkboxes ticked; `src/models/FluidSPHModel.cuh` and `src/spatial/UniformGridIndex.cuh` exist
- [ ] `RED tests added`
- [ ] `GREEN implementation completed`
- [ ] `REFACTOR + validation completed`
- [ ] `Code review — zero ERRORs`

---

## Decision Log

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Density field written to GL texture via CUDA-texture interop (not mapped PBO) | Textures sample with hardware bilinear filtering — smoother heatmap at low resolution. |
| 2 | Heatmap resolution configurable (default 256×256) | Coarser = faster, finer = more detail. Read from config `[framework.debug] heatmap_resolution`. |
| 3 | Toggle via ImGui checkbox, off by default | Performance overhead when on; should not run in production mode. |

---

## Context and Orientation

**What this plan adds:**
- `src/rendering/DensityHeatmap.cuh/.cu` — manages GL texture, CUDA registration, kernel to write density values.
- `shaders/heatmap.vert` + `shaders/heatmap.frag` — fullscreen quad + blue-red colour mapping.
- `main.cpp` integration — render heatmap before particles when enabled.
- `tests/unit/rendering/DensityHeatmapTest.cpp` — tests texture init/destroy lifecycle.

---

## Concrete Steps

### Step 0 — Verify prerequisites

Open [Phase 4](2026-03-12-phase-4-sph-smoothing-kernel-density.md) and [Phase 3](2026-03-12-phase-3-uniform-grid-index.md) and confirm all checkboxes are ticked in both.

Verify the key artifacts exist:

```bash
ls src/models/FluidSPHModel.cuh src/spatial/UniformGridIndex.cuh
```

Confirm all tests pass:

```bash
cmake --build build --target particle_sim_tests && cd build && ctest --output-on-failure
```

If either check fails, do not proceed — resolve the blocking phase first.

### Step 1 — `shaders/heatmap.frag`

```glsl
#version 460 core
uniform sampler2D u_densityTex;
uniform float     u_maxDensity;
in  vec2 v_uv;
out vec4 fragColor;

void main() {
    float d = texture(u_densityTex, v_uv).r / max(u_maxDensity, 1e-5);
    vec3  c = mix(vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), clamp(d, 0.0, 1.0));
    fragColor = vec4(c, 0.7);
}
```

### Step 2 — CUDA kernel: `writeDensityTextureKernel`

For each cell (i, j), sample the density field: sum particle densities at the cell centre using `UniformGridIndex::queryFromPoints`.  
Write normalised density into the `float` texture surface.

### Step 3 — `DensityHeatmap` lifecycle

```cpp
struct DensityHeatmap {
    unsigned int          textureId{0};
    cudaGraphicsResource* cudaTexResource{nullptr};
    unsigned int          shaderProgram{0};
    unsigned int          quadVao{0};
    int                   resolution{256};
    bool                  enabled{false};
};
```

- `initDensityHeatmap(DensityHeatmap&, int resolution)` — creates GL texture, registers with CUDA.
- `updateDensityHeatmap(DensityHeatmap&, const FluidSPHModel&, const UniformGridIndex&)` — runs CUDA kernel.
- `renderDensityHeatmap(const DensityHeatmap&)` — draws fullscreen quad.
- `destroyDensityHeatmap(DensityHeatmap&)` — unregisters + deletes GL texture.

### Step 4 — RED tests (lifecycle only — rendering not unit testable)

- `initDensityHeatmap` returns valid texture ID.
- Double-init does not leak (destroy + init pattern).
- `destroyDensityHeatmap` sets `textureId = 0`.

---

## Validation and Acceptance

| # | Check | Observable Evidence |
|---|-------|---------------------|
| 1 | Heatmap renders when enabled | Enable checkbox in ImGui → blue background with red blobs at particle clusters |
| 2 | Heatmap off by default | No visual change to existing rendering when checkbox unchecked |
| 3 | No GL errors | `glGetError()` called after each heatmap draw; zero errors reported |
| 4 | Tests pass | `ctest -R DensityHeatmap` — PASSED |

---

## Artifacts and Notes

- `src/rendering/DensityHeatmap.cuh`
- `src/rendering/DensityHeatmap.cu`
- `shaders/heatmap.vert`
- `shaders/heatmap.frag`
- `tests/unit/rendering/DensityHeatmapTest.cpp`

---

## Interfaces and Dependencies

**Depends on:** Phase 4 (density array), Phase 3 (queryFromPoints).  
**Required by:** Nothing downstream — this is a pure debug tool.
