# Design Discussion Summary

This document captures key decisions and context from the initial architecture discussion.

## Project Scope

**Goal**: A particle simulation *framework* supporting runtime model selection, not a single simulation.

**Initial Models**:
1. Game of Life (cellular automata)
2. SPH Fluid Simulation (smoothed particle hydrodynamics)

## Key Architectural Decisions

### Particles Own Their Behaviour

Each particle type understands the impact of adjacent particles:

```cpp
struct FluidParticle {
    Vec2 position;
    Vec2 velocity;
    float density;
    float pressure;
    
    void computeDensity(std::span<const FluidParticle*> neighbours, const FluidParams& params);
    Vec2 computeForces(std::span<const FluidParticle*> neighbours, const FluidParams& params) const;
    void integrate(Vec2 acceleration, float dt);
};
```

Parameters are shared (owned by the model), particles reference them.

### Separate Particle Types Per Model

No variant/union particle type. Each model has its own concrete particle struct:
- `GridCell` for Game of Life
- `FluidParticle` for SPH

Abstraction lives at `ISimulationModel` level, not particle level. Keeps data tightly packed.

### Two Levels of Configuration

| Level | When Changed | Examples |
|-------|--------------|----------|
| **Model** | At startup / restart | Particle structure, rules, neighbourhood logic |
| **Parameters** | While running | Thresholds, coefficients, forces, radii |

Parameters exposed with metadata for generic UI rendering.

### Threading: GPU Does the Work

With CUDA, no CPU threading for particle updates:

```
Main Thread:
  glfwPollEvents()
  processInput() / updateImGui()
  mapCudaResources()
  launchSimulationKernels()  // GPU work
  unmapCudaResources()
  cudaDeviceSynchronize()
  renderParticles()          // OpenGL
  glfwSwapBuffers()
```

Double-buffering happens in VRAM (ping-pong device pointers).

### Spatial Indexing Split

**Grid-based models** (GoL): Use direct grid arithmetic. No spatial index needed.

**Continuous-space models** (SPH): Use `ISpatialIndex` with uniform grid implementation.

This avoids forcing different spatial semantics through one abstraction.

## GPU Gotchas Identified

| Issue | Mitigation |
|-------|------------|
| Memory coalescing | Struct-of-Arrays layout |
| Warp divergence | Fixed max neighbours, padding |
| Atomic contention | Counting sort construction |
| Register pressure | Profile, split kernels if needed |
| Multi-pass sync | Kernel launches as barriers |

## Technology Stack Rationale

| Original | Changed To | Reason |
|----------|------------|--------|
| SFML | OpenGL + GLFW | CUDA-GL interop avoids CPU↔GPU round-trip |
| `std::execution::par` | CUDA | GPU handles parallelism; simpler CPU code |
| OpenMP | Not used | CUDA replaces need for CPU threading |

## Open Design Questions

1. **Periodic boundaries**: Support for toroidal wrap in `ISpatialIndex`?
2. **Dynamic bounds**: `rebuild()` accept explicit bounds or compute from positions?
3. **3D**: Template on dimension now or defer?
4. **Error handling**: Return values vs debug assertions?

## Next Implementation Steps

1. Set up CMake with CUDA, GLFW, GLAD, ImGui
2. Implement `UniformGridIndex` (counting sort construction)
3. Implement minimal `ISimulationModel` interface
4. Create CUDA-GL interop rendering pipeline
5. Implement Game of Life as first model (simpler, validates framework)
6. Implement SPH fluid as second model (exercises spatial index)

## WSL vs Windows Development

**CUDA on WSL2**: Works well with recent drivers. NVIDIA provides WSL2-specific support.

**Recommendation**: Native Windows may be simpler for CUDA + OpenGL interop debugging. WSL2 is viable if you prefer Linux tooling.

Either way, ensure:
- CUDA Toolkit 13.x installed
- Visual Studio 2022 (MSVC) or appropriate GCC/Clang
- CMake 3.28+
