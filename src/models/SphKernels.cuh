#pragma once

#include <cuda_runtime.h>

namespace psim::models
{

/// @brief Cubic smoothing kernel W(r, h) = max(0, (h - r) / h)^3
///
/// Delivers a smooth, non-negative weight that falls monotonically from 1.0
/// at r = 0 to 0.0 at r = h (the influence radius boundary).
///
/// @param distance Distance between particles (r). Must be >= 0.
/// @param radius   Influence radius (h). Must be > 0.
///
/// @return Kernel weight in [0, 1]. Zero when distance >= radius.
///
/// @note This is an unnormalised form. The function is used consistently
///       throughout the SPH pipeline; an absolute density scale is not
///       required for the pressure/viscosity force ratios.
///
/// @pre distance >= 0.
/// @pre radius > 0.
__device__ __forceinline__ float smoothingKernel(float distance, float radius)
{
    if (distance >= radius)
    {
        return 0.0F;
    }
    float q = (radius - distance) / radius;
    return q * q * q;
}

/// @brief Analytic radial gradient of the smoothing kernel: dW/dr
///
/// Returns the rate of change of W with respect to distance. The result is
/// always <= 0 because the kernel decreases monotonically with distance.
///
/// Formula: dW/dr = -3 * ((h - r) / h)^2 * (1/h)
///
/// @param distance Distance between particles (r). Must be >= 0.
/// @param radius   Influence radius (h). Must be > 0.
///
/// @return Gradient magnitude (negative). Zero when distance >= radius.
///
/// @pre distance >= 0.
/// @pre radius > 0.
__device__ __forceinline__ float smoothingKernelGradient(float distance, float radius)
{
    if (distance >= radius)
    {
        return 0.0F;
    }
    float q = (radius - distance) / radius;
    return -3.0F * q * q / radius;
}

} // namespace psim::models
