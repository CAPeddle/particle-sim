#pragma once

#include "core/CudaUtils.hpp"
#include "core/SimConstants.hpp"
#include "spatial/ISpatialIndex.hpp"

#include <cstddef>
#include <cstdint>
#include <cuda_runtime.h>

// Forward declaration to avoid pulling the full UniformGridIndex header
// (and its #ifndef __CUDACC__ guards) into every TU that includes this file.
namespace psim::spatial
{
class UniformGridIndex;
} // namespace psim::spatial

namespace psim::models
{

/// @brief Default maximum neighbours tracked per particle in the SPH model.
/// @note Alias of @ref psim::core::MAX_NEIGHBOURS — the canonical constant is in SimConstants.hpp.
inline constexpr uint32_t DEFAULT_MAX_NEIGHBOURS = psim::core::MAX_NEIGHBOURS;

/// @brief POD configuration parameters for the SPH fluid model.
///
/// These values mirror the `[model.sph]` section of `config.toml` and are
/// consumed by `initFluidModel`. All fields must be set before calling init.
struct FluidSPHParams
{
    uint32_t particleCount = 0U;                     ///< Total number of fluid particles.
    float influenceRadius = 0.0F;                    ///< SPH smoothing radius h (world units).
    float mass = 1.0F;                               ///< Uniform particle mass m.
    float2 domainMin = {0.0F, 0.0F};                 ///< Domain lower-left corner.
    float2 domainMax = {1.0F, 1.0F};                 ///< Domain upper-right corner.
    uint32_t maxNeighbours = DEFAULT_MAX_NEIGHBOURS; ///< Maximum neighbours tracked per particle.
};

/// @brief SPH fluid model data using Struct-of-Arrays GPU layout.
///
/// Owns all device-side particle state buffers. Move-only; copying is disabled
/// because buffers own CUDA device memory (Rule of Five via RAII).
///
/// Layout is Struct-of-Arrays for coalesced warp accesses:
/// ```
///   posX[0] posX[1] ... posX[N-1]   // contiguous
///   posY[0] posY[1] ... posY[N-1]   // contiguous
///   ...
/// ```
///
/// The `neighbourIndices` and `neighbourCounts` arrays are reused every frame
/// to avoid per-frame allocations.
///
/// @note Call `initFluidModel` to allocate device memory; it is not allocated
///       by the constructor. Call `destroyFluidModel` (or allow destruction)
///       to release memory.
///
/// @note Thread-safety: Not thread-safe. Do not call `computeDensity` concurrently.
struct FluidSPHModel
{
    // NOLINTBEGIN(misc-non-private-member-variables-in-classes)
    // FluidSPHModel is a data-bag struct with public SoA buffers by design.
    // All mutation is through free functions (initFluidModel, computeDensity,
    // destroyFluidModel). The Rule-of-Five declarations make clang-tidy treat
    // this as a "class", triggering the check; the pattern is intentional.

    FluidSPHParams params{}; ///< Copied from `initFluidModel` parameters.

    // -----------------------------------------------------------------------
    // Particle state — device memory, one element per particle
    // -----------------------------------------------------------------------
    psim::core::CudaBuffer<float> posX;    ///< Particle x-positions.
    psim::core::CudaBuffer<float> posY;    ///< Particle y-positions.
    psim::core::CudaBuffer<float> velX;    ///< Particle x-velocities.
    psim::core::CudaBuffer<float> velY;    ///< Particle y-velocities.
    psim::core::CudaBuffer<float> density; ///< Per-particle density ρ_i. Device-only.

    // -----------------------------------------------------------------------
    // Neighbour query buffers — device memory, re-used each frame
    // -----------------------------------------------------------------------
    /// Flattened array [particleCount * maxNeighbours]: neighbourIndices[i * maxNeighbours + n]
    /// holds the n-th neighbour index of particle i.
    psim::core::CudaBuffer<int> neighbourIndices;
    /// neighbourCounts[i] holds the actual number of neighbours for particle i.
    psim::core::CudaBuffer<int> neighbourCounts;
    // NOLINTEND(misc-non-private-member-variables-in-classes)

    // -----------------------------------------------------------------------
    // Special members — Rule of Five (move-only via RAII CudaBuffer)
    // -----------------------------------------------------------------------
    FluidSPHModel() = default;
    ~FluidSPHModel() = default;
    FluidSPHModel(const FluidSPHModel&) = delete;
    FluidSPHModel& operator=(const FluidSPHModel&) = delete;
    FluidSPHModel(FluidSPHModel&&) noexcept = default;
    FluidSPHModel& operator=(FluidSPHModel&&) noexcept = default;
};

// ---------------------------------------------------------------------------
// Lifecycle functions
// ---------------------------------------------------------------------------

/// @brief Allocates device memory for all particle buffers.
///
/// @param model  The model to initialise. Must not already have allocated buffers.
/// @param params Configuration to apply. All fields must be valid.
///
/// @pre params.particleCount > 0.
/// @pre params.influenceRadius > 0.
/// @pre params.maxNeighbours > 0.
///
/// @post All CudaBuffer members of model are allocated.
/// @post model.params is populated from params.
void initFluidModel(FluidSPHModel& model, const FluidSPHParams& params);

/// @brief Computes per-particle density ρ_i = Σ_j m * W(|x_i - x_j|, h).
///
/// Queries the spatial index for each particle's neighbours, then launches
/// `computeDensityKernel`. Self-contribution (W(0, h)) is always included.
///
/// @param model  Model with valid posX/posY device arrays.
/// @param index  Pre-built spatial index over model.posX/posY.
///
/// @pre initFluidModel has been called on `model`.
/// @pre The spatial index has been built from the same positions as model.posX/posY
///      (i.e., the caller has called `index.rebuild(...)` with model positions).
///
/// @post model.density contains valid ρ values for all particles.
///
/// @note This function is implemented in FluidSPHModelOps.cpp (not the .cu file)
///       to avoid including `std::expected` in an nvcc-compiled translation unit.
///       See ADR-001 for the nvcc / GCC-13 toolchain split rationale.
void computeDensity(FluidSPHModel& model, const psim::spatial::UniformGridIndex& index);

/// @brief Releases all device buffers owned by the model.
///
/// After this call the model is in the same state as a default-constructed one.
/// Safe to call multiple times (subsequent calls are no-ops).
///
/// @note CudaBuffer destructor already handles freeing. This function is provided
///       for explicit, ordered teardown in performance-sensitive paths.
void destroyFluidModel(FluidSPHModel& model);

// ---------------------------------------------------------------------------
// Internal bridge — called by FluidSPHModelOps.cpp, implemented in FluidSPHModel.cu
// ---------------------------------------------------------------------------

namespace detail
{

/// @brief Launches `computeDensityKernel` on the current CUDA device.
///
/// Accepts only POD types so it can be called from a `.cpp` translation unit
/// (compiled by g++) and implemented in the `.cu` translation unit (compiled
/// by nvcc). This is the same TU-split pattern used by `launchQueryKernel` in
/// `UniformGridIndex.cuh`.
///
/// @param posX              Device array of x-positions [count].
/// @param posY              Device array of y-positions [count].
/// @param neighbourIndices  Device array [count * maxNeighbours].
/// @param neighbourCounts   Device array [count].
/// @param maxNeighbours     Stride between rows in neighbourIndices.
/// @param influenceRadius   SPH influence radius h.
/// @param mass              Uniform particle mass m.
/// @param outDensity        Device output array [count].
/// @param count             Number of particles.
void launchComputeDensityKernel(const float* posX,
                                const float* posY,
                                const int* neighbourIndices,
                                const int* neighbourCounts,
                                int maxNeighbours,
                                float influenceRadius,
                                float mass,
                                float* outDensity,
                                uint32_t count);

} // namespace detail

} // namespace psim::models
