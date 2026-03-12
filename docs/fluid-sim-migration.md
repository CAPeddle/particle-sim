# Backlog: Transferable Features from fluid-sim

> **Source project**: [CAPeddle/fluid-sim](https://github.com/CAPeddle/fluid-sim) (now deprecated)
>
> **Context**: particle-sim is the successor to fluid-sim, a CPU-based SFML/C++17 particle simulator. A comparative analysis was performed and the fluid-sim project was deprecated. This document captures the concrete implementations worth porting, with original source code and adaptation notes.
>
> **Full comparison**: See [docs/fluid-sim-comparison.md](fluid-sim-comparison.md) for the architectural analysis.

---

## 1. TOML Configuration System — HIGH PRIORITY

**Status**: Not started

**Problem in particle-sim**: Particle count (100K), swirl strength, damping, and all simulation parameters are hard-coded in `main.cpp` and CUDA kernels. No way to save/load configurations or change parameters without recompiling.

**What fluid-sim had**: A working `ConfigReader` class using [toml11](https://github.com/ToruNiina/toml11) v4.1.0 that loads structured config at startup. Two-section layout separating framework settings from physics parameters.

### Original Config File (fluid-sim)

```toml
# config.toml
[simulation]
fontPath = "resources/3230-font.ttf"
resolution.width = 600
resolution.height = 400
grid = 10
particle.radius = 5.0

[environment]
gravity = { x = 0.0, y = 0.0 }
damping = 0.5
influenceRange = 40.0
```

### Original Implementation Pattern (fluid-sim)

```cpp
// ConfigReader.hpp
class ConfigReader {
public:
    ConfigReader(const std::string& filePath);
    std::pair<float, float> getGravity() const;
    int getGridSize() const;
    float getParticleRadius() const;
    float getInfluenceRange() const;
    float getDamping() const;
    std::pair<unsigned int, unsigned int> getResolution() const;
private:
    std::string m_filePath;
    toml::value m_root;
};

// ConfigReader.cpp — constructor
ConfigReader::ConfigReader(const std::string& filePath) : m_filePath(filePath) {
    try {
        m_root = toml::parse(m_filePath);
    } catch (const toml::syntax_error& e) {
        std::cerr << "Failed to parse TOML file: " << e.what() << std::endl;
    }
}

// Typed accessors
float ConfigReader::getInfluenceRange() const {
    return m_root.at("environment").at("influenceRange").as_floating();
}
```

### Adaptation for particle-sim

- **Integrate with the planned `Parameter` metadata system**: Each config value should be wrapped in a `Parameter<T>` that carries min/max/step metadata for ImGui rendering
- **Per-model sections**: Extend the TOML layout to support `[model.sph]`, `[model.gameoflife]` etc., loaded by the active `ISimulationModel`
- **Device-side constants**: Parameters needed in CUDA kernels should be copied to device constant memory or passed as kernel arguments
- **CMake**: Add toml11 via FetchContent (proven to work — see fluid-sim's CMakeLists.txt)

### Proposed Config Structure

```toml
[framework]
resolution = { width = 1280, height = 720 }
vsync = true

[framework.rendering]
point_size = 3.0
background_color = { r = 0.05, g = 0.05, b = 0.08 }

[model.sph]
particle_count = 100000
gravity = { x = 0.0, y = -9.81 }
damping = 0.999
influence_radius = 0.05
rest_density = 1000.0
gas_constant = 2000.0
viscosity = 250.0

[model.gameoflife]
grid_width = 256
grid_height = 256
initial_density = 0.3
```

---

## 2. SPH Smoothing Kernel — HIGH PRIORITY

**Status**: Not started

**Problem in particle-sim**: The current demo kernel uses ad-hoc swirl forces. No SPH physics implemented yet.

**What fluid-sim had**: A working cubic falloff influence function — a simple smoothing kernel suitable for SPH density estimation.

### Original Implementation (fluid-sim)

```cpp
// MovingCircle.cpp
float MovingCircle::influence(const sf::Vector2f &point) const {
    sf::Vector2f center = getPosition();
    float distance = std::hypot(center.x - point.x, center.y - point.y);
    if (distance > m_environment->influenceRange) return 0;

    float impact = std::max(0.f, m_environment->influenceRange - distance) / m_environment->influenceRange;
    impact = std::pow(impact, 3);
    return impact;
}
```

### Adaptation for particle-sim

Port as a `__device__` function. The kernel shape is `W(r, h) = max(0, (h - r) / h)^3`.

```cuda
__device__ float smoothingKernel(float distance, float influenceRadius) {
    if (distance > influenceRadius) return 0.0f;
    float normalized = (influenceRadius - distance) / influenceRadius;
    return normalized * normalized * normalized; // cubic falloff
}
```

**Improvements to make**:
- Add normalisation constant for 2D (fluid-sim omits this, so density values are relative, not physical)
- Implement the kernel gradient analytically rather than via finite differences
- Support multiple kernel types (poly6, spiky, Wendland) selectable via config
- The analytic gradient of this kernel is: `dW/dr = -3 * ((h - r) / h)^2 * (1/h)` for `r < h`

---

## 3. Density & Density Gradient Calculation — HIGH PRIORITY

**Status**: Not started

**Problem in particle-sim**: No SPH force computation exists yet.

**What fluid-sim had**: Static methods for computing density at a point (sum of smoothing kernel contributions) and a finite-difference density gradient.

### Original Implementation (fluid-sim)

```cpp
// SimProperties.hpp
static double calculateDensity(const sf::Vector2f& ref_point,
                               std::vector<std::shared_ptr<MovingCircle>> circles) {
    float mass = 1;
    float density; // BUG: uninitialized — should be 0.0f
    for (const auto& circle : circles) {
        density += mass * circle->influence(ref_point);
    }
    return density;
}

static sf::Vector2f calculateDensityGradient(const sf::Vector2f& ref_point,
                                             std::vector<std::shared_ptr<MovingCircle>> circles) {
    const float stepSize = 0.1;
    float deltaX = calculateDensity(ref_point + sf::Vector2f(stepSize, 0), circles)
                 - calculateDensity(ref_point, circles);
    float deltaY = calculateDensity(ref_point + sf::Vector2f(0, stepSize), circles)
                 - calculateDensity(ref_point, circles);
    return sf::Vector2f(deltaX, deltaY);
}
```

### Known Bugs in Original
- `density` is **uninitialized** — undefined behaviour. Must initialise to `0.0f`
- `circles` vector passed **by value** — copies the entire vector on each call. Should be `const&`
- Finite-difference gradient is expensive (3× the cost of analytic gradient) and introduces step-size sensitivity

### Adaptation for particle-sim

Implement as a CUDA kernel where each thread computes density for one particle using ISpatialIndex neighbours:

```cuda
__global__ void computeDensityKernel(
    const float* pos_x, const float* pos_y,
    const int* neighbour_indices, const int* neighbour_counts,
    int maxNeighbours, float influenceRadius, float mass,
    float* out_density, uint32_t count
) {
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= count) return;

    float px = pos_x[idx], py = pos_y[idx];
    float density = 0.0f;

    int nCount = neighbour_counts[idx];
    for (int n = 0; n < nCount; ++n) {
        int j = neighbour_indices[idx * maxNeighbours + n];
        float dx = pos_x[j] - px;
        float dy = pos_y[j] - py;
        float dist = sqrtf(dx * dx + dy * dy);
        density += mass * smoothingKernel(dist, influenceRadius);
    }

    out_density[idx] = density;
}
```

Use the analytic kernel gradient instead of finite differences for the pressure force computation.

---

## 4. Density Heatmap Visualisation — MEDIUM PRIORITY

**Status**: Not started

**Problem in particle-sim**: No debug visualisation of scalar fields (density, pressure).

**What fluid-sim had**: A background display that colors each grid cell based on normalised density — blue (low) to red (high). Useful for visually verifying SPH density fields.

### Original Approach (fluid-sim)
- Divides window into grid cells, computes density at each cell centre
- Normalises density to [0, 255] range based on max observed density
- Draws `sf::RectangleShape` per cell with blue→red gradient

### Adaptation for particle-sim

- Implement as a CUDA kernel that writes density values to a 2D texture
- Render the texture as a fullscreen quad behind the particle layer (OpenGL)
- Toggle on/off via ImGui checkbox
- Colour mapping: `vec3 color = mix(vec3(0, 0, 1), vec3(1, 0, 0), normalized_density)` in a fragment shader
- Grid resolution should be configurable (coarser = faster, finer = more detail)

---

## 5. Boundary Collision with Damping — MEDIUM PRIORITY

**Status**: Not started (particle-sim only has wrap-around)

**Problem in particle-sim**: Particles use wrap-around boundaries (teleport to opposite edge). For SPH fluid simulation, reflection with energy loss (damping) is more physically correct.

### Original Implementation (fluid-sim)

```cpp
// MovingCircle.cpp — update()
m_particleProperties.velocity += m_environment->gravity * deltaTime;
currentPosition += m_particleProperties.velocity * deltaTime;

// Right wall
if (currentPosition.x + getRadius() > windowSize.x) {
    m_particleProperties.velocity.x *= -1 * m_environment->damping;
    currentPosition.x = windowSize.x - m_particleProperties.radius;
}
// Left wall
else if (currentPosition.x < getRadius()) {
    m_particleProperties.velocity.x *= -1 * m_environment->damping;
}
// Bottom wall
if (currentPosition.y + getRadius() > windowSize.y) {
    m_particleProperties.velocity.y *= -1 * m_environment->damping;
    currentPosition.y = windowSize.y - m_particleProperties.radius;
}
// Top wall
else if (currentPosition.y < getRadius()) {
    m_particleProperties.velocity.y *= -1 * m_environment->damping;
}
```

### Known Issues in Original
- Left and top wall collisions don't clamp position (particle can escape)
- Damping factor should be `< 1.0` for energy loss but code doesn't enforce this

### Adaptation for particle-sim

Add to the existing CUDA update kernel as a configurable boundary mode:

```cuda
enum class BoundaryMode { WrapAround, Reflect };

// In kernel:
if (boundaryMode == BoundaryMode::Reflect) {
    if (pos.x > bounds.x) { vel.x *= -damping; pos.x = bounds.x; }
    if (pos.x < -bounds.x) { vel.x *= -damping; pos.x = -bounds.x; }
    if (pos.y > bounds.y) { vel.y *= -damping; pos.y = bounds.y; }
    if (pos.y < -bounds.y) { vel.y *= -damping; pos.y = -bounds.y; }
} else {
    // existing wrap-around logic
}
```

Make boundary mode and damping configurable via TOML + ImGui.

---

## 6. Factory / Spawn Patterns — LOW PRIORITY

**Status**: Partially done (particle-sim has random circle spawn)

**What fluid-sim had**: `MovingCircleFactory` with `createBox()` (grid layout) and `fillRandom()` (scatter).

### Useful Patterns to Add

- **Grid/box spawn**: Particles in rows and columns with configurable spacing — useful for dam-break scenarios
- **Dam-break**: Dense block of particles on one side, empty on other — classic SPH test case
- **Falling column**: Particles above centre, gravity pulls them down — tests pressure

### Adaptation

Add as alternative init kernels selectable via config:

```toml
[model.sph]
initial_condition = "dam_break"  # or "grid", "random_circle", "random_fill"
```

---

## 7. Vector/Arrow Debug Visualisation — LOW PRIORITY

**Status**: Not started

**What fluid-sim had**: `VectorDrawable` class that draws arrows from a start point to an end point, used to visualise density gradient vectors at click locations.

### Adaptation for particle-sim

- Implement as an optional OpenGL line-drawing pass with instancing
- Draw force vectors (pressure, viscosity) per particle or at grid sample points
- Toggle via ImGui debug panel
- Lower priority — density heatmap (#4) provides most of the debug value

---

## Implementation Order

Recommended sequence for implementing these features:

1. **TOML config system** (#1) — Unblocks all other items by removing hard-coded values
2. **Boundary collision** (#5) — Quick win, improves current demo immediately
3. **Smoothing kernel** (#2) — Foundation for SPH physics
4. **Density calculation** (#3) — First real SPH computation, uses ISpatialIndex
5. **Density heatmap** (#4) — Visual validation of density field
6. **Spawn patterns** (#6) — Better test scenarios for SPH
7. **Vector debug** (#7) — Nice-to-have debug tool
