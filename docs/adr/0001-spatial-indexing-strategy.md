# ADR-001: Spatial Indexing Strategy for Continuous-Space Models

## Status
Proposed

## Context

The particle simulation framework supports multiple models with different 
spatial structures:

- **Game of Life**: Discrete grid, fixed 8-cell Moore neighbourhood, 
  positions are integer coordinates
- **SPH Fluid**: Continuous 2D space, radius-based neighbourhood, 
  positions are floating-point, neighbours vary per particle

Both run on GPU via CUDA. Neighbour queries occur every frame and are 
performance-critical.

### Forces

1. **Divergent spatial semantics**: Grid adjacency vs radius queries are 
   fundamentally different operations
2. **GPU efficiency**: Memory coalescing, warp divergence, and atomic 
   contention must be managed
3. **Framework extensibility**: Future models may have other spatial 
   structures (3D, periodic boundaries, hierarchical)
4. **Interface simplicity**: Models should not pay complexity cost for 
   features they don't use

### Key Insight

Attempting to unify grid-based and radius-based queries behind a single 
interface adds abstraction without benefit. Grid neighbours are computed 
arithmetically; radius neighbours require spatial data structures.

## Decision

### 1. Scope of ISpatialIndex

`ISpatialIndex` provides **radius-based neighbour queries for continuous-space 
models only**. 

Grid-based models (Game of Life, other cellular automata) will manage their 
own spatial structure directly — the grid itself is the natural representation.

### 2. Implementation: Uniform Grid with Counting Sort

The initial `ISpatialIndex` implementation will be `UniformGridIndex`:

- **Cell size**: Configurable, should be ≥ query radius for single-cell + 
  neighbours query pattern
- **Construction**: Counting sort approach (count → prefix sum → scatter) 
  to avoid per-particle atomic contention
- **Particle layout**: Struct-of-Arrays for memory coalescing
- **Neighbour limit**: Fixed maximum per particle; queries report if truncated

### 3. Interface Contract

See `src/spatial/ISpatialIndex.hpp` for the full interface definition.

### 4. Memory Ownership

- Caller (the model) owns all device memory for positions and output buffers
- `ISpatialIndex` owns its internal structures (cell arrays, sorted indices)
- Views are non-owning and valid only for the duration of the call

### 5. Thread Safety

- `rebuild()` and `queryNeighbours()` must not be called concurrently
- After `rebuild()` completes, the index is immutable until next `rebuild()`
- Multiple query calls between rebuilds are safe (const interface)

## Consequences

### Positive

- **Clarity**: Interface does one thing well — radius queries for continuous space
- **Simplicity for grid models**: GoL uses natural grid arithmetic, no abstraction overhead
- **Predictable performance**: Uniform grid has O(1) expected query time
- **Extensible**: New spatial index implementations (spatial hash, BVH) can 
  implement the same interface
- **GPU-friendly**: Design accounts for coalescing, divergence, and atomic patterns

### Negative

- **No unified abstraction**: Adding a new model requires deciding which 
  spatial approach it uses
- **Memory overhead**: Uniform grid allocates for full domain even if sparse
- **Cell size tuning**: Optimal cell size depends on particle density and 
  query radius; may need runtime adjustment

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Cell size misconfiguration degrades query performance | Medium | Medium | Validate cell size ≥ radius; warn if ratio is suboptimal |
| Sparse domains waste memory | Low | Medium | Document when to prefer spatial hash; consider alternative implementation |
| Max neighbours exceeded frequently | Medium | High | Return `truncated` flag; caller can increase limit or handle gracefully |
| Interface insufficient for 3D models | Low | Medium | Design for 2D now; ensure interface can extend (add z pointer, or template on dimension) |

## Alternatives Considered

### Unified interface for grid and continuous models

Rejected: Adds complexity without benefit. Grid neighbours are O(1) arithmetic; 
spatial index adds overhead for no gain.

### Spatial hash instead of uniform grid

Deferred: Spatial hash handles sparse domains better but has less predictable 
memory patterns. Start with uniform grid; profile before optimising.

### Template on dimension (2D vs 3D)

Deferred: Start with 2D implementation. Interface uses explicit x/y pointers 
which can extend to x/y/z. Revisit if 3D model is added.

## Revisit Triggers

- Adding a 3D model → consider templating or z-pointer extension
- Particle counts exceed 50K and memory becomes constraint → evaluate spatial hash
- Profiling shows >15% frame time in spatial index → optimise or change approach
- Model needs periodic boundary conditions → extend interface for domain wrapping

## Known Limitations

### nvcc/g++ vtable mismatch for `#ifndef __CUDACC__`-guarded virtual methods

**Symptom:** SIGSEGV at a virtual dispatch site when a g++-compiled translation unit calls a virtual method on a `UniformGridIndex&` reference, where that method is declared `virtual` in the base class but guarded by `#ifndef __CUDACC__` in the interface header.

**Root cause:** nvcc compiles `UniformGridIndex.cu` with `__CUDACC__` defined. The virtual methods inside `#ifndef __CUDACC__` guards (`queryNeighbours`, `queryFromPoints`) are invisible to nvcc, so the vtable it emits has no slots for them. Any g++-compiled TU that calls these methods through a vtable pointer — including a concrete `UniformGridIndex&` reference the compiler cannot devirtualise — reads a wrong or absent slot and crashes.

**Current workaround (Phase 4):** Use qualified-id syntax at the call site to suppress virtual dispatch:
```cpp
// Direct call — bypasses vtable, avoids the missing-slot crash.
auto result = index.psim::spatial::UniformGridIndex::queryNeighbours(output, queryParams);
```
This requires the caller to depend on the concrete type (`UniformGridIndex`) rather than the abstract interface (`ISpatialIndex`). That is acceptable here because `FluidSPHModelOps.cpp` already takes a `const UniformGridIndex&` — the TU-split pattern requires it.

**Preferred long-term fix:** Add a non-virtual `queryNeighboursDirect` method to `UniformGridIndex` outside all `#ifndef __CUDACC__` guards, returning a plain POD result. The `.cpp` consumer calls this directly; no vtable involvement, no qualified-id dependency. Tracked in `plan.md`.

**See also:** `src/spatial/ISpatialIndex.hpp` — compilation contract note in class Doxygen; `src/models/FluidSPHModelOps.cpp` — workaround usage with inline explanation.
