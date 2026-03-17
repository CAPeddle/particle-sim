// FluidSPHModelOps.cpp
//
// Implements computeDensity(). This translation unit is compiled by g++, NOT
// nvcc, so it can include <expected> from GCC 13's libstdc++.
//
// The TU split mirrors UniformGridIndexQueries.cpp.
// See ADR-001: docs/adr/0001-spatial-indexing-strategy.md

#include "models/FluidSPHModel.cuh"
#include "spatial/ISpatialIndex.hpp"
#include "spatial/UniformGridIndex.cuh"

#include <cstdio>
#include <cstdlib>
namespace psim::models
{

/// @brief Queries neighbours for all particles and computes density.
///
/// Steps:
///   1. Build `NeighbourOutputView` from the model's pre-allocated neighbour buffers.
///   2. Call `index.queryNeighbours` (returns `std::expected`; handled here in .cpp).
///   3. Delegate to `detail::launchComputeDensityKernel` (defined in FluidSPHModel.cu).
///
/// @pre initFluidModel has been called on model.
/// @pre index.rebuild() has been called with positions that match model.posX/posY.
void computeDensity(FluidSPHModel& model, const psim::spatial::UniformGridIndex& index)
{
    const FluidSPHParams& params = model.params;

    const psim::spatial::NeighbourOutputView output{
        model.neighbourIndices.get(), model.neighbourCounts.get(), static_cast<std::size_t>(params.maxNeighbours)};

    const psim::spatial::QueryParams queryParams{params.influenceRadius};

    // Use explicit non-virtual dispatch to avoid the nvcc/g++ vtable mismatch.
    // The UniformGridIndex vtable compiled by nvcc omits the #ifndef __CUDACC__-
    // guarded methods, so calling through the vtable from g++ code crashes.
    // Qualified-id syntax suppresses virtual dispatch and emits a direct call.
    // See ADR-001 and ISpatialIndex.hpp for the toolchain background.
    auto result = index.psim::spatial::UniformGridIndex::queryNeighbours(output, queryParams);
    if (!result.has_value())
    {
        // NOLINT(cert-err33-c) — fail-fast path; return value of fputs is irrelevant before std::abort()
        static_cast<void>(
            std::fputs("computeDensity: queryNeighbours failed (index not built or invalid buffer)\n", stderr));
        std::abort();
    }

    detail::launchComputeDensityKernel(model.posX.get(),
                                       model.posY.get(),
                                       model.neighbourIndices.get(),
                                       model.neighbourCounts.get(),
                                       static_cast<int>(params.maxNeighbours),
                                       params.influenceRadius,
                                       params.mass,
                                       model.density.get(),
                                       params.particleCount);
}

} // namespace psim::models
