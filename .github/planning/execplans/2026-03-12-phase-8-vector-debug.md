# ExecPlan: Phase 8 — Vector/Arrow Debug Visualisation

**Date:** 2026-03-12  
**Status:** Not Started  
**Prerequisite:** [Phase 4 — SPH Smoothing Kernel + Density](2026-03-12-phase-4-sph-smoothing-kernel-density.md) (SPH model has force vector data) and [Phase 6 — Density Heatmap](2026-03-12-phase-6-density-heatmap.md) (debug visualisation pattern established) — all Progress checkboxes in both plans must be ticked before starting this plan.

---

## Purpose / Big Picture

Adds an optional debug overlay that draws per-particle force vectors (pressure, viscosity) as world-space line segments rendered via OpenGL instanced line rendering. This makes the direction and magnitude of per-particle forces visible, complementing the density heatmap from Phase 6.

**Terms:**
- **Instanced rendering** — Single `glDrawArraysInstanced` call that draws N copies of a base shape (a line from origin to `[1,0]`), each transformed by a per-instance model matrix. Efficient for >1K arrows.
- **Force vector** — A 2D vector (dx, dy) representing the net force on a particle in world space. Visualised as an arrow scaled by magnitude and oriented in the force direction.
- **Arrow geometry** — A line segment from the particle position to `position + direction * scale`, plus a small arrowhead. Can be approximated with two line segments.

---

## Progress

- [ ] `Prerequisites verified` — [Phase 4](2026-03-12-phase-4-sph-smoothing-kernel-density.md) and [Phase 6](2026-03-12-phase-6-density-heatmap.md) show all checkboxes ticked; `src/models/FluidSPHModel.cuh` and `src/rendering/DensityHeatmap.cuh` exist
- [ ] `RED tests added`
- [ ] `GREEN implementation completed`
- [ ] `REFACTOR + validation completed`
- [ ] `Code review — zero ERRORs`

---

## Decision Log

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Instanced line rendering (not per-arrow draw calls) | O(1) draw calls regardless of particle count; scales to 100K particles. |
| 2 | Force vectors copied host→device only when debug overlay is enabled | Avoids D2H transfer every frame in production mode. |
| 3 | Arrow scale configurable via ImGui slider | Forces vary greatly in magnitude; fixed scale hides small forces or clips large ones. |
| 4 | Only pressure and viscosity vectors initially | Gravity is uniform; rendering it provides no per-particle insight. |
| 5 | Toggle per force type | Ability to visualise pressure only, viscosity only, or total force. |

---

## Context and Orientation

**What this plan adds:**
- `src/rendering/ArrowRenderer.hpp/.cpp` — GL instanced line renderer. Takes a `std::span<float4>` (position + direction encoded as `float4`) and renders arrows.
- `shaders/arrow.vert` + `shaders/arrow.frag` — instanced vertex shader transforms base segment; fragment shader colours by force type.
- `src/models/FluidSPHModel.cu` — adds optional `d_pressureForce` and `d_viscosityForce` CudaBuffers; populated by their respective kernels (placeholders until those kernels exist).
- `main.cpp` — ImGui debug section for arrow overlay toggle, scale, and force selection.
- `tests/unit/rendering/ArrowRendererTest.cpp` — lifecycle tests only.

---

## Concrete Steps

### Step 0 — Verify prerequisites

Open [Phase 4](2026-03-12-phase-4-sph-smoothing-kernel-density.md) and [Phase 6](2026-03-12-phase-6-density-heatmap.md) and confirm all checkboxes are ticked in both.

Verify the key artifacts exist:

```bash
ls src/models/FluidSPHModel.cuh src/rendering/DensityHeatmap.cuh
```

Confirm all tests pass:

```bash
cmake --build build --target particle_sim_tests && cd build && ctest --output-on-failure
```

If either check fails, do not proceed — resolve the blocking phase first.

### Step 1 — Arrow geometry

A single arrow = 3 vertices: tail point, head point (`tail + dir * len`), arrowhead triangle.  
For simplicity: render as two GL_LINES per arrow (shaft + one-sided head) using instancing.

### Step 2 — `ArrowRenderer`

```cpp
class ArrowRenderer
{
public:
    ArrowRenderer()  = default;
    ~ArrowRenderer() = default;
    ArrowRenderer(const ArrowRenderer&)            = delete;
    ArrowRenderer& operator=(const ArrowRenderer&) = delete;
    ArrowRenderer(ArrowRenderer&&)                 = default;
    ArrowRenderer& operator=(ArrowRenderer&&)      = default;

    [[nodiscard]] bool init();
    void destroy();

    /// @brief Draw arrows from position + direction data.
    /// @param vectors span of float4: (x, y, dx, dy) per particle.
    /// @param scale   World-space scale multiplier for vector length.
    /// @param color   Arrow colour (RGBA).
    void draw(std::span<const float4> vectors, float scale, float4 color);

private:
    unsigned int vao_{0};
    unsigned int vbo_{0};  // per-instance float4 buffer
    unsigned int shaderProgram_{0};
    std::size_t  capacity_{0};
};
```

### Step 3 — RED tests

- `init()` returns `true`.
- `destroy()` sets `vao_ = 0`.
- Double-destroy is safe (guarded by zero-check).
- `draw()` with empty span does not crash.

### Step 4 — Shaders

`shaders/arrow.vert` — receives `(x, y, dx, dy)` per instance; computes shaft start and end in clip space.  
`shaders/arrow.frag` — outputs uniform `u_color`.

### Step 5 — Integration into main loop

When enabled, copy force vectors from device to host each frame (only when overlay active). Call `arrowRenderer.draw(...)` after particles, before ImGui.

---

## Validation and Acceptance

| # | Check | Observable Evidence |
|---|-------|---------------------|
| 1 | Tests pass | `ctest -R ArrowRenderer` — PASSED |
| 2 | Arrows render | Enable toggle → coloured arrows visible on particles |
| 3 | Scale slider works | Dragging scale in ImGui changes arrow length proportionally |
| 4 | Disabled = zero overhead | FPS unchanged when overlay is off (no D2H copy) |

---

## Artifacts and Notes

- `src/rendering/ArrowRenderer.hpp`
- `src/rendering/ArrowRenderer.cpp`
- `shaders/arrow.vert`
- `shaders/arrow.frag`
- `tests/unit/rendering/ArrowRendererTest.cpp`

---

## Interfaces and Dependencies

**Depends on:** Phase 4 (force data), Phase 6 (debug overlay pattern).  
**Required by:** Nothing — terminal plan item.
