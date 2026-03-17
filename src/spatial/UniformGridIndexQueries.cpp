/// @file UniformGridIndexQueries.cpp
/// @brief Host-only query method implementations for UniformGridIndex.
///
/// This translation unit is compiled exclusively by the C++ host compiler (GCC/MSVC),
/// never by nvcc. It implements the std::expected-returning interface methods that
/// cannot be compiled by nvcc 12.0 (which lacks C++23 std::expected support).
///
/// The CUDA kernels and device-side code live in UniformGridIndex.cu.
/// The kernel launch helper `launchQueryKernel()` is declared in UniformGridIndex.cuh
/// and defined in UniformGridIndex.cu — callable from this file because it uses
/// only plain POD types in its signature.

#ifdef __CUDACC__
#error "UniformGridIndexQueries.cpp must not be compiled by nvcc. Check CMakeLists.txt."
#endif

#include "spatial/UniformGridIndex.cuh"

#include <cuda_runtime.h>
#include <expected>

namespace psim::spatial
{

// ----------------------------------------------------------------------------

std::expected<QueryResult, SpatialIndexError> UniformGridIndex::queryNeighbours(NeighbourOutputView output,
                                                                                QueryParams params) const
{
    if (!built_)
    {
        return std::unexpected(SpatialIndexError::NotBuilt);
    }
    if (output.indices == nullptr || output.counts == nullptr)
    {
        return std::unexpected(SpatialIndexError::InvalidBuffer);
    }
    return runQuery(posX_.get(), posY_.get(), particleCount_, output, params, SelfExclusionMode::UseTid);
}

// ----------------------------------------------------------------------------

std::expected<QueryResult, SpatialIndexError> UniformGridIndex::queryFromPoints(ParticlePositionsView queryPoints,
                                                                                NeighbourOutputView output,
                                                                                QueryParams params) const
{
    if (!built_)
    {
        return std::unexpected(SpatialIndexError::NotBuilt);
    }
    if (queryPoints.x == nullptr || queryPoints.y == nullptr || output.indices == nullptr || output.counts == nullptr)
    {
        return std::unexpected(SpatialIndexError::InvalidBuffer);
    }
    return runQuery(queryPoints.x, queryPoints.y, queryPoints.count, output, params, SelfExclusionMode::None);
}

// ----------------------------------------------------------------------------

/// @brief Runs the neighbour-query kernel and returns the result.
///
/// Delegates the actual `<<<>>>` kernel launch to `launchQueryKernel()`
/// which is defined in `UniformGridIndex.cu` (compiled by nvcc).
std::expected<QueryResult, SpatialIndexError> UniformGridIndex::runQuery(const float* queryX,
                                                                         const float* queryY,
                                                                         std::size_t queryCount,
                                                                         NeighbourOutputView output,
                                                                         QueryParams params,
                                                                         SelfExclusionMode mode) const
{
    // Device flag for truncation detection — RAII-managed, freed on scope exit.
    psim::core::CudaBuffer<int> truncatedFlag(1);
    CUDA_CHECK(cudaMemset(truncatedFlag.get(), 0, sizeof(int)));

    // Delegate kernel launch to the nvcc-compiled translation unit
    detail::launchQueryKernel(queryX,
                              queryY,
                              static_cast<int>(queryCount),
                              posX_.get(),
                              posY_.get(),
                              cellCounts_.get(),
                              cellStarts_.get(),
                              sortedIndices_.get(),
                              output.indices,
                              output.counts,
                              truncatedFlag.get(),
                              static_cast<int>(output.maxPerParticle),
                              params.radius,
                              domainMin_.x,
                              domainMin_.y,
                              cellSize_,
                              gridWidth_,
                              gridHeight_,
                              mode);

    int hTruncated = 0;
    CUDA_CHECK(cudaMemcpy(&hTruncated, truncatedFlag.get(), sizeof(int), cudaMemcpyDeviceToHost));

    // maxCountObserved deferred to profiling phase — see plan.md
    QueryResult result{};
    result.truncated = (hTruncated != 0);
    result.maxCountObserved = 0;
    return result;
}

} // namespace psim::spatial
