# Comparative Analysis: fluid-sim vs particle-sim

## 1. Project Overview

| Aspect | fluid-sim | particle-sim |
|--------|-----------|--------------|
| **Location** | `/home/cpeddle/projects/personal/fluid-sim` | `/mnt/c/projects/personal/particle-sim` |
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

The fluid-sim issues a separate draw call for each particle and each background cell. The particle-sim batches all 100K particles into a single VBO draw call.

---

## 3. Extensibility Analysis

### 3.1 Adding a New Simulation Model

#### fluid-sim — Major Refactor Required

There is no abstraction for "simulation model". The `MovingCircle` class hard-codes:
- Physics (gravity + boundary bounce in `update()`)
- Influence function (cubic falloff in `influence()`)
- Visual representation (inherits `sf::CircleShape`)

Adding a different particle type (e.g., Game of Life cells) would require:
1. Creating a new particle class that also inherits from an SFML shape
2. Modifying `main.cpp` to handle the new type
3. Duplicating or modifying `BackGroundDisplay`, `SimProperties`, `MovingCircleFactory`
4. No shared interface exists to abstract over different models

#### particle-sim — Designed for It (Strategy Pattern)

The framework is explicitly designed around `ISimulationModel` (planned interface). Each model:
- Defines its own particle struct (`FluidParticle`, `GridCell`)
- Implements its own update kernel
- Chooses its own spatial strategy (ISpatialIndex for continuous, grid arithmetic for discrete)
- Declares runtime parameters with metadata for generic UI rendering

Adding a new model is additive — implement the interface, register it, done.

### 3.2 Adding Runtime Parameters

#### fluid-sim — Partial Support, Fragile

Configuration is loaded at startup from TOML via `ConfigReader`. Some parameters can be changed at runtime via keyboard callbacks in `EventHandler` (gravity, influence range). But:
- Adding a new parameter requires modifying `ConfigReader`, `EventHandler`, and any class that uses it
- No generic parameter system — each parameter is a hand-wired chain
- `EnvironmentProperties` stores values as public members, any class can mutate them

#### particle-sim — Generic Parameter System Planned

The CLAUDE.md describes a two-level configuration:
- **Model-level** (startup): particle structure, rules, neighbourhood logic
- **Parameter-level** (runtime): thresholds, coefficients, forces, radii

Parameters carry metadata for automatic UI rendering via ImGui. Not yet implemented, but the architecture supports it cleanly.

### 3.3 Adding Spatial Indexing Strategies

#### fluid-sim — Ad-hoc Grid

`Grid.hpp/cpp` implements a simple spatial hash grid using `unordered_map<int, unordered_map<int, vector<shared_ptr<MovingCircle>>>>`. It works but:
- Tightly coupled to `MovingCircle` (not generic)
- No interface — can't swap in a different spatial strategy
- Redundant: `BackGroundDisplay` builds its *own* separate grid (a nested `vector<vector<vector<shared_ptr>>>`)
- Memory-heavy: nested hash maps with shared_ptr indirection

#### particle-sim — Abstract Interface with Documented Contracts

`ISpatialIndex.hpp` defines a clean abstract interface with:
- `ParticlePositionsView` and `NeighbourOutputView` using non-owning device pointers
- `rebuild()` / `queryNeighbours()` / `queryFromPoints()` methods
- Documented thread safety, memory ownership, pre/post conditions
- Designed for GPU execution (device pointers throughout)
- ADR-001 explains *why* this interface exists and what alternatives were considered

---

## 4. Design Patterns & Principles

### 4.1 SOLID Principles

| Principle | fluid-sim | particle-sim |
|-----------|-----------|--------------|
| **Single Responsibility** | Violated: `MovingCircle` handles physics AND rendering (inherits `sf::CircleShape`). `BackGroundDisplay` handles density calculation AND drawing AND grid management. | Respected: Rendering (OpenGL), compute (CUDA kernels), spatial indexing (ISpatialIndex), and UI (ImGui) are separate concerns. |
| **Open/Closed** | Violated: Adding behaviour requires modifying existing classes. No extension points. | Respected: `ISimulationModel` and `ISpatialIndex` are designed as extension points. New models are additive. |
| **Liskov Substitution** | Not applicable — no meaningful inheritance hierarchies (except `sf::CircleShape` misuse). | Applicable: `ISpatialIndex` implementations must honour the documented contracts. |
| **Interface Segregation** | No interfaces defined. Classes depend on concrete types. | `ISpatialIndex` is focused — only radius queries. Grid models don't implement it (they don't need to). |
| **Dependency Inversion** | Violated: High-level code (`main.cpp`) directly depends on concrete classes. `MovingCircle` depends directly on SFML. | Partially respected: `ISpatialIndex` defines an abstraction. But `main.cpp` still directly manages OpenGL/CUDA setup (framework init code is inherently concrete). |

### 4.2 Design Patterns Used

| Pattern | fluid-sim | particle-sim |
|---------|-----------|--------------|
| **Factory** | `MovingCircleFactory` creates particles (Factory Method). Decent use — separates construction from use. | Not yet implemented, but `ISimulationModel` conceptually acts as a factory for particle data. |
| **Strategy** | Not used. | Core pattern. `ISimulationModel` and `ISpatialIndex` are strategy interfaces — implementations are swappable. |
| **Observer** | Not used. Events handled procedurally in `EventHandler`. | ImGui provides implicit observation through its immediate-mode API. |
| **Struct-of-Arrays** | Not used. Each `MovingCircle` is a full object with SFML base class overhead. | Planned and designed for. Particle data arranged for GPU memory coalescing (separate x, y, velocity arrays). |
| **Double Buffering** | Not used. Particles update in-place. | Planned. Ping-pong device buffers for synchronous GPU updates. |
| **RAII** | Partially: `shared_ptr` used extensively (sometimes excessively). No custom RAII for resources. | `ParticleSystem` manages GPU resource lifecycle (VBO, CUDA registration, device memory) with init/destroy functions (not yet RAII-wrapped). |

### 4.3 Code Quality Observations

#### fluid-sim

| Issue | Location | Severity |
|-------|----------|----------|
| Global variable shadows member | `BackgroundDisplay.cpp` line 10: `int m_display_gridSize = 10;` | High — Declares a global that shadows the class member of the same name |
| Uninitialized variable | `SimProperties.hpp`: `float density;` used before initialization in `calculateDensity()` | High — Undefined behaviour |
| Dead code | `if (1 == 2)` block in `BackgroundDisplay.cpp` | Medium — Debug code left in |
| Excessive use of `shared_ptr` | Throughout — particles stored as `shared_ptr<MovingCircle>` even when unique ownership suffices | Medium — Unnecessary heap allocation and reference counting |
| Mixed naming conventions | `m_display_gridSize` vs `gridSize` vs `m_environment` | Low |
| Header-only classes with logic | `EventHandler.hpp`, `SimProperties.hpp`, `Environment.hpp` — full implementation in headers | Low — Compilation coupling |
| Console debug output | `std::cout` throughout event handling and density calculation | Low |
| Unused function parameters | `EventHandler::adjustVariableWithKeyPress` takes `key_event` but uses `sf::Keyboard::isKeyPressed` instead | Low |
| Copy-by-value where reference intended | `calculateDensity` and `calculateDensityGradient` take `vector<shared_ptr>` by value | Medium — Copies the entire vector each call |

#### particle-sim

| Issue | Location | Severity |
|-------|----------|----------|
| No RAII for GPU resources | `ParticleSystem` uses manual init/destroy | Medium — Risk of leaks on error paths |
| `main.cpp` is monolithic | All OpenGL/CUDA/ImGui setup in one function | Medium — But acceptable for bootstrap code |
| Hard-coded constants | Particle count (100K), swirl strength, damping | Low — Parameter system planned |
| `printf` over structured logging | Throughout | Low — Early development |
| VAO setup duplicated | Reset button re-creates VAO bindings | Low |

---

## 5. Performance Architecture

| Aspect | fluid-sim | particle-sim |
|--------|-----------|--------------|
| **Computation** | CPU, single-threaded | GPU, massively parallel (CUDA) |
| **Particle Scaling** | O(n²) density calculation limits to ~100s of particles | 100K particles at 60fps |
| **Memory Layout** | Array-of-Structures (each `MovingCircle` is a full object) | Struct-of-Arrays (planned) for GPU coalescing |
| **Spatial Complexity** | O(n × grid_cells) for density; O(n) for grid assignment | O(n) for uniform grid rebuild; O(1) expected per query |
| **Rendering Overhead** | One draw call per particle + per grid cell | One draw call for all particles |
| **Memory Transfers** | N/A (CPU only) | Zero-copy via CUDA-GL interop |

---

## 6. Documentation & Maintainability

| Aspect | fluid-sim | particle-sim |
|--------|-----------|--------------|
| **README** | Template from SFML project, not customized | CLAUDE.md serves as living architecture document |
| **Architecture Docs** | None | `docs/DESIGN_DISCUSSION.md` captures rationale; `docs/adr/` contains decision records |
| **ADRs** | None | ADR-001 documents spatial indexing decision with alternatives, consequences, and revisit triggers |
| **Code Comments** | Sparse; some TODO comments | Interface contracts documented with `@pre`/`@post` conditions, thread safety notes |
| **Design Notes** | `notes.txt` — two sentences about density | CLAUDE.md open questions section tracks design decisions yet to be made |

---

## 7. Dependency Management

Both projects use CMake FetchContent for dependency management, which is a solid modern approach.

| Dependency | fluid-sim | particle-sim |
|------------|-----------|--------------|
| **Windowing** | SFML 2.6.x | GLFW 3.4 |
| **Rendering** | SFML (built-in) | OpenGL 4.6 via GLAD 2.0.8 |
| **UI** | None (keyboard shortcuts) | Dear ImGui 1.91.6 |
| **GPU Compute** | None | CUDA Toolkit (system-installed) |
| **Config** | toml11 v4.1.0 | None yet |
| **Total Dependencies** | 2 | 4 (+ CUDA system dep) |

---

## 8. Summary of Key Differences

### What fluid-sim Does Better
1. **Working configuration system** — TOML-based config with runtime TOML parsing, ready to use
2. **Complete feature** — Density calculation with background heatmap visualisation actually works end-to-end
3. **Simpler to understand** — Lower barrier to entry, straightforward code flow
4. **Factory pattern** — `MovingCircleFactory` is a clean separation of particle construction

### What particle-sim Does Better
1. **Architecture-first thinking** — Interfaces, ADRs, and design documents before code
2. **GPU acceleration** — 1000x more particles feasible via CUDA
3. **Zero-copy rendering** — CUDA-GL interop eliminates CPU↔GPU data transfer
4. **Extensibility** — Strategy pattern with `ISimulationModel` and `ISpatialIndex` designed for multiple models
5. **Separation of concerns** — Rendering, compute, spatial indexing, and UI are decoupled
6. **Modern C++** — C++23, proper namespacing (`psim::spatial`), non-owning views instead of `shared_ptr`
7. **Professional documentation** — ADRs, design discussion, living architecture document
8. **UI** — ImGui provides a proper control panel vs keyboard shortcuts

### Evolution Path

The particle-sim is clearly an evolution of the learnings from fluid-sim:
- SFML replaced with OpenGL for GPU interop capability
- CPU particle loop replaced with CUDA kernels
- Monolithic design replaced with interface-based framework thinking
- Ad-hoc spatial grid replaced with designed `ISpatialIndex` abstraction
- Tribal knowledge in `notes.txt` replaced with structured ADRs
- The design discussion explicitly references moving away from SFML and `std::execution::par` in favour of CUDA

The fluid-sim served its purpose as a learning exercise; the particle-sim builds on those lessons with professional software engineering practices.

---

## 9. Transferable Aspects — fluid-sim → particle-sim

The following concrete elements from fluid-sim are worth porting or adapting into particle-sim. They represent working implementations of features particle-sim currently lacks.

### 9.1 TOML Configuration System (High Priority)

particle-sim currently hard-codes values (particle count, damping, swirl strength). fluid-sim has a working `ConfigReader` backed by toml11 that loads structured config at startup.

**What to transfer:**
- The pattern of a `ConfigReader` class that parses a TOML file and exposes typed accessors
- The two-section config structure (`[simulation]` for framework settings, `[environment]` for physics parameters)
- The toml11 dependency (already proven to work with CMake FetchContent)

**Adaptation needed:**
- Integrate with the planned `Parameter` metadata system so ImGui can render controls automatically
- Store config on device memory where needed for CUDA kernels
- Extend to support per-model config sections (e.g., `[model.sph]`, `[model.gameoflife]`)

**Reference:** `inc/ConfigReader.hpp`, `src/ConfigReader.cpp`, `resources/config.toml`

### 9.2 Influence / Smoothing Kernel Function (High Priority)

The cubic falloff influence function in `MovingCircle::influence()` is a working SPH-style smoothing kernel:

```cpp
float impact = std::max(0.f, influenceRange - distance) / influenceRange;
impact = std::pow(impact, 3);
```

**What to transfer:**
- The concept of a parameterised smoothing kernel with configurable influence range
- The cubic polynomial kernel shape (common in SPH literature)

**Adaptation needed:**
- Implement as a `__device__` function for CUDA
- Parameterise the kernel type (cubic, Wendland, poly6, spiky) as part of the SPH model configuration
- Normalise properly for 2D (fluid-sim does not normalise, which means density values are relative rather than physical)

**Reference:** `src/MovingCircle.cpp` — `MovingCircle::influence()`

### 9.3 Density & Density Gradient Calculation (High Priority)

`SimProperties` provides static methods for density and gradient computation using finite differences:

```cpp
// Density: sum of mass * influence for all neighbours
// Gradient: finite-difference approximation with step size 0.1
```

**What to transfer:**
- The density-as-sum-of-influences approach (standard SPH density estimation)
- The finite-difference gradient approximation as a reference implementation

**Adaptation needed:**
- Replace finite-difference gradient with analytic kernel gradient (more accurate, no step-size tuning)
- Run as CUDA kernel — each thread computes density for one particle
- Use `ISpatialIndex` neighbour queries instead of iterating all particles

**Reference:** `inc/SimProperties.hpp`

### 9.4 Density Heatmap Visualisation (Medium Priority)

`BackGroundDisplay::calculateDensityAndColorBackground()` renders a per-cell density heatmap with a blue-to-red gradient. This is valuable for debugging SPH simulations.

**What to transfer:**
- The concept of a background density visualisation layer
- Blue-to-red gradient mapping based on normalised density

**Adaptation needed:**
- Implement as a compute shader or CUDA kernel that writes to a texture
- Render the texture as a fullscreen quad behind the particle layer
- Make it togglable via ImGui

**Reference:** `src/BackgroundDisplay.cpp` — `calculateDensityAndColorBackground()`

### 9.5 Boundary Collision with Damping (Medium Priority)

`MovingCircle::update()` implements boundary reflection with configurable damping — particles bounce off walls and lose energy.

**What to transfer:**
- The boundary reflection logic with velocity inversion and damping factor
- The pattern of configurable damping coefficient

**Adaptation needed:**
- Implement as part of the CUDA update kernel
- Support both reflection and wrap-around boundaries (particle-sim currently has wrap-around only)
- Make boundary mode selectable per model

**Reference:** `src/MovingCircle.cpp` — `MovingCircle::update()`

### 9.6 Factory / Spawn Patterns (Low Priority)

`MovingCircleFactory` provides `createBox()` (grid arrangement) and `fillRandom()` (random scatter) — useful initial particle distributions.

**What to transfer:**
- Box/grid spawn pattern (particles in rows and columns with configurable spacing)
- Random fill spawn pattern within bounds
- The concept of a factory that separates particle construction from simulation

**Adaptation needed:**
- Implement as CUDA init kernels (particle-sim already has `initParticlesKernel` for random circle distribution)
- Add grid pattern, dam-break pattern, and other SPH-standard initial conditions

**Reference:** `src/MovingCircleFactory.cpp`

### 9.7 Vector/Arrow Debug Visualisation (Low Priority)

`VectorDrawable` draws arrows showing density gradients — useful for debugging force fields.

**What to transfer:**
- The concept of rendering force/gradient vectors as arrows overlaid on the simulation

**Adaptation needed:**
- Implement as an OpenGL line-drawing pass with instancing
- Toggle via ImGui debug panel

**Reference:** `inc/Vector.hpp`

### Summary Table

| Aspect | Priority | Effort to Port | Value to particle-sim |
|--------|----------|---------------|----------------------|
| TOML config system | High | Medium | Eliminates hard-coded constants; enables saved configurations |
| Smoothing kernel | High | Low | Direct reuse as `__device__` function for SPH model |
| Density calculation | High | Medium | Core SPH algorithm already proven to work |
| Density heatmap | Medium | Medium | Essential debugging/visualisation tool for SPH |
| Boundary collision | Medium | Low | Missing feature — only wrap-around exists currently |
| Factory/spawn patterns | Low | Low | Init kernels already exist; just add more patterns |
| Vector debug drawing | Low | Medium | Nice-to-have debug overlay |
