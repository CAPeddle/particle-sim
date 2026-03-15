#pragma once

#include "core/SimConstants.hpp"

#include <cuda_runtime.h>

namespace psim::core
{

/// @brief Apply domain boundary conditions to a single particle in-place.
///
/// @param x        Particle x position (read/write).
/// @param y        Particle y position (read/write).
/// @param vx       Particle x velocity (read/write).
/// @param vy       Particle y velocity (read/write).
/// @param minX     Left boundary of the domain.
/// @param maxX     Right boundary of the domain.
/// @param minY     Bottom boundary of the domain.
/// @param maxY     Top boundary of the domain.
/// @param mode     @ref BoundaryMode::Reflect or @ref BoundaryMode::Wrap.
/// @param damping  Energy retention factor applied on bounce, in (0, 1].
///                 1.0 = fully elastic; 0.0 = fully inelastic. Only used in Reflect mode.
///
/// @details
/// **Reflect** — When a particle exceeds a wall, the perpendicular velocity
/// component is negated and multiplied by `damping`. The position is clamped to
/// the wall. Both left/top and right/bottom walls are handled (fixes the original
/// fluid-sim bug that omitted clamping on the left and top walls).
///
/// **Wrap** — The particle position is mapped to the opposite edge via domain-size
/// subtraction/addition. Velocity is unchanged.
///
/// @pre  minX < maxX, minY < maxY.
/// @pre  damping ∈ (0, 1] (unchecked in device code; validated at call site).
///
/// @note Callable from both host (CPU tests) and device (CUDA kernels).
// NOLINTNEXTLINE(bugprone-easily-swappable-parameters)
__host__ __device__ __forceinline__ void applyBoundary(float& x,
                                                       float& y,
                                                       float& vx,
                                                       float& vy,
                                                       float  minX,
                                                       float  maxX,
                                                       float  minY,
                                                       float  maxY,
                                                       BoundaryMode mode,
                                                       float  damping)
{
    if (mode == BoundaryMode::Reflect)
    {
        if (x > maxX) { vx *= -damping; x = maxX; }
        if (x < minX) { vx *= -damping; x = minX; }
        if (y > maxY) { vy *= -damping; y = maxY; }
        if (y < minY) { vy *= -damping; y = minY; }
    }
    else
    {
        float const w = maxX - minX;
        float const h = maxY - minY;
        if (x > maxX) { x -= w; }
        if (x < minX) { x += w; }
        if (y > maxY) { y -= h; }
        if (y < minY) { y += h; }
    }
}

} // namespace psim::core
