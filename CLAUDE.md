# Particle Simulation Framework

A professional-grade, GPU-accelerated particle simulation framework in modern C++.

## Project Vision

A **particle simulation framework** (not a single simulation) that supports runtime model selection. Each model defines particle properties, neighbourhood semantics, and update rules. The framework provides shared infrastructure: rendering, parameter UI, spatial indexing, and GPU execution.

## Target Use Cases

1. **Game of Life**: Discrete grid, binary state, Moore neighbourhood (8 adjacent cells)
2. **SPH Fluid Simulation**: Continuous 2D space, radius-based neighbours, density/pressure/viscosity forces

## Technology Stack

| Component | Technology |
|-----------|------------|
| Language | C++23 |
| GPU Compute | CUDA 13.2 |
| Rendering | OpenGL (via GLAD) |
| Windowing | GLFW |
| UI | Dear ImGui |
| Data Transfer | CUDA-OpenGL interop (zero-copy) |
| Build | CMake |

## Development Environment

- **Hardware**: Dell XPS 15 9530, Intel i7-13700H (20 threads), NVIDIA RTX 4050 Laptop (6GB VRAM)
- **OS**: Windows 11 Pro
- **Target**: Can develop in WSL or native Windows

## Architecture Principles

- **Strategy Pattern**: Models implement `ISimulationModel` interface, swappable at startup
- **Particles own behaviour**: Each particle type understands the impact of adjacent particles
- **Separation of concerns**: 
  - Grid-based models (GoL) use direct grid arithmetic for neighbours
  - Continuous-space models (SPH) use `ISpatialIndex` for radius queries
- **Struct-of-Arrays**: Particle data laid out for GPU memory coalescing
- **Double buffering**: Ping-pong buffers in VRAM for synchronous updates

## Key Design Decisions

See `docs/adr/` for Architecture Decision Records.

- **ADR-001**: Spatial indexing uses uniform grid with counting sort construction; grid-based models bypass this entirely

## Project Structure

```
particle-sim/
├── CMakeLists.txt
├── CLAUDE.md                    # This file
├── docs/
│   └── adr/                     # Architecture Decision Records
├── src/
│   ├── core/
│   │   ├── Application.hpp      # Main loop, GLFW setup
│   │   ├── ISimulationModel.hpp # Abstract model interface
│   │   └── Parameter.hpp        # Runtime parameter system
│   ├── models/
│   │   ├── GameOfLifeCUDA.hpp/cu
│   │   └── FluidSPHCUDA.hpp/cu
│   ├── spatial/
│   │   ├── ISpatialIndex.hpp    # Neighbour query interface
│   │   └── UniformGridIndex.cu  # GPU implementation
│   ├── rendering/
│   │   ├── Renderer.hpp
│   │   └── CudaGLInterop.hpp
│   ├── ui/
│   │   └── ImGuiLayer.hpp
│   └── main.cpp
├── shaders/
│   ├── particle.vert
│   └── particle.frag
└── tests/
```

## GPU-Specific Considerations

### Memory Coalescing
Use Struct-of-Arrays layout. Threads in a warp access contiguous memory.

### Warp Divergence
Fixed maximum neighbour counts with padding. Process particles with similar neighbour counts together where possible.

### Atomic Contention
Counting sort for spatial index construction (count → prefix sum → scatter) to avoid per-particle atomics.

### Synchronisation
Multi-pass algorithms (e.g., SPH density then forces) use separate kernel launches as implicit barriers.

## Current Status

**Phase**: Architecture and interface design

### Predecessor Project

This project supersedes [CAPeddle/fluid-sim](https://github.com/CAPeddle/fluid-sim) (now deprecated), a CPU-based SFML/C++17 particle simulator. A comparative analysis identified 7 transferable features including a TOML config system, SPH smoothing kernel, density calculation, boundary collision, and debug visualisation.

- **Full comparison**: `docs/fluid-sim-comparison.md`
- **Actionable migration backlog**: `docs/fluid-sim-migration.md` — prioritised list of features to port with original source code, known bugs, and CUDA adaptation notes

### Next Steps
1. Implement `ISpatialIndex` interface and `UniformGridIndex`
2. Implement basic `ISimulationModel` interface
3. Set up CMake with CUDA support
4. Create minimal rendering pipeline with CUDA-GL interop

## Open Questions

1. **Periodic boundaries**: Should `ISpatialIndex` support toroidal wrap-around?
2. **Dynamic domain bounds**: Should `rebuild()` accept explicit bounds or compute from positions?
3. **3D readiness**: Template on dimension now, or defer?
4. **Error handling**: Return values vs debug assertions for invariant violations?

## References

- Architecture skill: See `/mnt/skills/user/architecture-fundamentals/` for ADR templates and trade-off frameworks
- CUDA samples: Particle simulation examples in CUDA SDK
- SPH reference: Müller et al., "Particle-Based Fluid Simulation for Interactive Applications"
