# Comparative Analysis: fluid-sim vs particle-sim

> **Origin**: This analysis was conducted in March 2026 to compare the predecessor project
> ([CAPeddle/fluid-sim](https://github.com/CAPeddle/fluid-sim), now deprecated) with this project.
> The fluid-sim repo has been archived with a pointer back here.
>
> **Actionable items** extracted from this analysis are in [fluid-sim-migration.md](fluid-sim-migration.md).

---

## 1. Project Overview

| Aspect | fluid-sim | particle-sim |
|--------|-----------|--------------|
| **Repository** | [CAPeddle/fluid-sim](https://github.com/CAPeddle/fluid-sim) (DEPRECATED) | This project |
| **Purpose** | A configurable 2D particle/fluid simulator | A GPU-accelerated particle simulation *framework* |
| **Language Standard** | C++17 | C++23 / CUDA 13.1 |
| **Rendering** | SFML 2.6.x | OpenGL 4.6 (via GLAD) + GLFW + Dear ImGui |
| **Compute** | CPU-only | CUDA GPU kernels |
| **Build System** | CMake 3.28 (FetchContent) | CMake 3.28 (FetchContent + CUDA) |
| **Particle Count** | ~15 (configurable, but CPU-bound) | 100,000 (GPU-accelerated) |
| **Maturity** | Working prototype with density visualisation | Early framework with working CUDA-GL interop demo |
| **Config** | TOML file (`config.toml`) | Hard-coded values (parameter system planned) |
| **Documentation** | README (template-based), `notes.txt` | CLAUDE.md, ADRs, DESIGN_DISCUSSION.md |

---

## 2. Architecture Comparison

### 2.1 High-Level Architecture

#### fluid-sim — Monolithic, Imperative

```
main.cpp
  ├── ConfigReader          (reads TOML config)
  ├── EnvironmentProperties  (gravity, damping, influence range)
  ├── MovingCircleFactory    (creates particles)
  ├── MovingCircle[]         (particles with update logic)
  ├── BackGroundDisplay      (density heatmap rendering)
  ├── Grid                   (spatial partitioning)
  ├── SimProperties          (static density calculations)
  ├── EventHandler           (keyboard/mouse input)
  └── VectorDrawable         (debug arrow rendering)
```

The architecture is **procedural with objects**. `main.cpp` orchestrates everything directly: it creates objects, runs the game loop, calls update on each particle, and draws. There is no abstraction layer between simulation logic and rendering — the `MovingCircle` class inherits from `sf::CircleShape`, tightly coupling the domain model to the rendering framework.

#### particle-sim — Framework-Oriented, Layered

```
main.cpp
  ├── GLFW/OpenGL/ImGui     (windowing + rendering + UI)
  ├── ParticleSystem         (CUDA-GL interop wrapper)
  │   ├── VBO (shared)       (positions in GPU memory)
  │   └── d_velocities       (velocities in GPU memory)
  ├── ISpatialIndex          (abstract interface — planned)
  │   └── UniformGridIndex   (counting sort — planned)
  └── ISimulationModel       (abstract interface — planned)
      ├── GameOfLifeCUDA     (planned)
      └── FluidSPHCUDA       (planned)
```

The architecture is **framework-first**: it defines interfaces and contracts before implementations. The separation between rendering (OpenGL), compute (CUDA), UI (ImGui), and spatial indexing (ISpatialIndex) is clearly delineated. The CUDA-GL interop means particle data lives entirely on the GPU — no CPU↔GPU copying.

### 2.2 Data Flow

#### fluid-sim
```
CPU: Read config → Create particles → Each frame:
  CPU: Update each particle position (sequential loop)
  CPU: Calculate density grid (O(particles × grid_cells))
  CPU: Color background cells
  CPU: Draw particles via SFML
  CPU: Handle events
```

Every operation is CPU-bound and sequential. The density calculation in `BackgroundDisplay.cpp` iterates over every particle for every grid cell — an O(n×m) operation that becomes the bottleneck.

#### particle-sim
```
GPU: Initialize 100K particles via CUDA kernel → Each frame:
  GPU: Map VBO to CUDA address space (zero-copy)
  GPU: Launch update kernel (parallel over all particles)
  GPU: Unmap VBO
  GPU: OpenGL renders VBO directly as point sprites
  CPU: ImGui overlay for controls
```

The data never leaves GPU memory. The CUDA-GL interop maps the OpenGL VBO directly into CUDA's address space, the kernel writes positions, and OpenGL reads them for rendering — no `memcpy` involved.

### 2.3 Rendering Pipeline

| Aspect | fluid-sim | particle-sim |
|--------|-----------|--------------|
| **Library** | SFML (high-level 2D) | OpenGL 4.6 Core + custom shaders |
| **Particle Representation** | `sf::CircleShape` (per-particle draw call) | Point sprites (single `glDrawArrays` for all) |
| **Background** | Density heatmap via `sf::RectangleShape` per cell | Shader-based (fragment shader computes colour) |
| **Draw Calls per Frame** | O(particles + grid_cells) | O(1) for particles + ImGui overlay |
| **UI** | Keyboard shortcuts only | ImGui panel (pause, speed, reset, FPS) |
| **FPS Display** | `sf::Text` overlay | ImGui `io.Framerate` |

---

## 3. Extensibility Analysis

### 3.1 Adding a New Simulation Model

#### fluid-sim — Major Refactor Required

There is no abstraction for "simulation model". The `MovingCircle` class hard-codes physics, influence function, and visual representation (inherits `sf::CircleShape`). Adding a different particle type requires modifying multiple files with no shared interface.

#### particle-sim — Designed for It (Strategy Pattern)

The framework is explicitly designed around `ISimulationModel` (planned interface). Each model defines its own particle struct, update kernel, spatial strategy, and runtime parameters. Adding a new model is additive.

### 3.2 Adding Runtime Parameters

#### fluid-sim — Partial Support, Fragile

TOML config at startup, keyboard callbacks for runtime changes. Adding a parameter requires modifying `ConfigReader`, `EventHandler`, and the consuming class. No generic parameter system.

#### particle-sim — Generic Parameter System Planned

Two-level configuration (model-level at startup, parameter-level at runtime). Parameters carry metadata for automatic ImGui rendering.

### 3.3 Adding Spatial Indexing Strategies

#### fluid-sim — Ad-hoc Grid

Simple spatial hash grid using nested `unordered_map` with `shared_ptr`. Tightly coupled to `MovingCircle`, no interface. `BackGroundDisplay` builds its own redundant grid.

#### particle-sim — Abstract Interface with Documented Contracts

`ISpatialIndex.hpp` with non-owning device pointer views, documented thread safety, memory ownership contracts, and ADR-001 explaining design rationale.

---

## 4. Design Patterns & Principles

### 4.1 SOLID Principles

| Principle | fluid-sim | particle-sim |
|-----------|-----------|--------------|
| **Single Responsibility** | Violated: `MovingCircle` = physics + rendering. `BackGroundDisplay` = density + drawing + grid. | Respected: Rendering, compute, spatial indexing, and UI are separate. |
| **Open/Closed** | Violated: No extension points. | Respected: `ISimulationModel` and `ISpatialIndex` are extension points. |
| **Liskov Substitution** | N/A — no meaningful inheritance. | Applicable: `ISpatialIndex` implementations honour documented contracts. |
| **Interface Segregation** | No interfaces. Classes depend on concrete types. | `ISpatialIndex` is focused — only radius queries. Grid models don't need it. |
| **Dependency Inversion** | Violated: `main.cpp` depends on concrete classes. | Partially respected: `ISpatialIndex` defines abstraction. Bootstrap code is inherently concrete. |

### 4.2 Design Patterns

| Pattern | fluid-sim | particle-sim |
|---------|-----------|--------------|
| **Factory** | `MovingCircleFactory` — decent separation of construction. | Not yet implemented; `ISimulationModel` will act as factory. |
| **Strategy** | Not used. | Core pattern. `ISimulationModel` + `ISpatialIndex` are swappable. |
| **Struct-of-Arrays** | Not used. Each particle is a full object with SFML overhead. | Planned for GPU memory coalescing. |
| **Double Buffering** | Not used. In-place updates. | Planned. Ping-pong device buffers. |

### 4.3 Key Code Quality Issues in fluid-sim

| Issue | Severity |
|-------|----------|
| Global variable `m_display_gridSize` shadows class member | High |
| Uninitialized `density` variable in `calculateDensity()` — UB | High |
| `calculateDensity`/`calculateDensityGradient` take `vector<shared_ptr>` by value | Medium |
| `if (1 == 2)` dead code block | Medium |
| Excessive `shared_ptr` where unique ownership suffices | Medium |

---

## 5. Performance Architecture

| Aspect | fluid-sim | particle-sim |
|--------|-----------|--------------|
| **Computation** | CPU, single-threaded | GPU, massively parallel (CUDA) |
| **Particle Scaling** | O(n²) — limits to ~100s | 100K at 60fps |
| **Memory Layout** | Array-of-Structures | Struct-of-Arrays (planned) |
| **Spatial Complexity** | O(n × grid_cells) | O(n) rebuild, O(1) query |
| **Rendering Overhead** | O(n) draw calls | O(1) draw calls |
| **Memory Transfers** | N/A (CPU only) | Zero-copy via CUDA-GL interop |

---

## 6. Conclusion

particle-sim is a deliberate architectural evolution that applies professional engineering practices to the lessons learned from the fluid-sim prototype. fluid-sim served its purpose as a learning exercise. The transferable implementations (config system, smoothing kernel, density calculation, boundary physics, heatmap visualisation) are documented with adaptation notes in [fluid-sim-migration.md](fluid-sim-migration.md).
