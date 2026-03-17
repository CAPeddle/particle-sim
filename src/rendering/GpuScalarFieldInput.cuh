#pragma once

#include <cstdint>
#include <cuda_runtime.h>

namespace psim::rendering
{

/// @brief Non-owning view of device-side scalar field data for GPU heatmap accumulation.
///
/// Passed to `updateDensityHeatmap` each frame in place of a concrete model type.
/// Decouples the rendering pipeline from `FluidSPHModel` internals — any simulation
/// model can drive the heatmap by constructing this struct from its device buffers.
///
/// **Normalisation:**
/// - `overrideRange == true`: normalise using `[minValue, maxValue]` as supplied.
/// - `overrideRange == false`: auto-compute min/max from `scalarValues` via device
///   reduction (adds one `cudaMemcpy` device→host per frame).
///
/// @note All device pointers must be non-null when `particleCount > 0`.
/// @note `particleCount == 0` is valid; the scatter pass is a no-op.
/// @note This struct is non-owning. It must not outlive the allocations that back
///       `posX`, `posY`, and `scalarValues`.
/// @note When `overrideRange == true` and `maxValue == minValue`, the implementation
///       adds a small epsilon to `maxValue` to avoid division by zero.
struct GpuScalarFieldInput
{
    // NOLINTBEGIN(misc-non-private-member-variables-in-classes)
    const float* posX{nullptr};         ///< Device x-position array [particleCount].
    const float* posY{nullptr};         ///< Device y-position array [particleCount].
    const float* scalarValues{nullptr}; ///< Device per-particle scalar [particleCount].
    uint32_t particleCount{0};          ///< Number of particles.
    float2 domainMin{};                 ///< Domain lower-left corner (world units).
    float2 domainMax{};                 ///< Domain upper-right corner (world units).
    float minValue{0.0F};               ///< Lower normalisation bound (`overrideRange == true`).
    float maxValue{1.0F};               ///< Upper normalisation bound (`overrideRange == true`).
    bool overrideRange{false};          ///< true = use minValue/maxValue; false = auto-compute.
    // NOLINTEND(misc-non-private-member-variables-in-classes)
};

} // namespace psim::rendering