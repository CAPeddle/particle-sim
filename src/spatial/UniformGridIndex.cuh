#pragma once

#include "core/CudaUtils.hpp"
#include "spatial/ISpatialIndex.hpp"

#include <cstddef>
#include <cuda_runtime.h>
#ifndef __CUDACC__
#include <expected>
#endif

namespace psim::spatial
{

/// @brief Controls whether a query point excludes itself from its own neighbour results.
///
/// Passed to `launchQueryKernel` and `runQuery` to avoid the per-call integer sentinel.
///
/// - `UseTid`: Each query thread excludes the indexed particle whose index equals the
///             thread's own id. Used by `queryNeighbours` where query[i] == particle[i].
/// - `None`:   No self-exclusion. Used by `queryFromPoints` where query points are
///             arbitrary positions, not members of the indexed set.
enum class SelfExclusionMode : int
{
    UseTid = 0, ///< Exclude particle at position `tid` (self in queryNeighbours)
    None = -1   ///< No self-exclusion (arbitrary external query points)
};

/// @brief GPU-accelerated uniform-grid spatial index using counting sort construction.
///
/// Divides a 2D domain into equal-size cells. Each particle is assigned to exactly
/// one cell. Neighbour queries inspect the 3×3 cell neighbourhood around a query
/// point, then filter by Euclidean distance.
///
/// **Construction algorithm (counting sort spatial hash):**
/// 1. Hash each particle position to a cell index.
/// 2. Count particles per cell (atomic increment).
/// 3. Prefix sum (exclusive scan) on counts → per-cell start offsets.
/// 4. Scatter particle indices into sorted array using start offsets.
///
/// @note cellSize should be ≥ the query radius used at query time. Smaller cells
///       reduce false-positive candidates; larger cells guarantee no false negatives.
///
/// @note Thread-safety: Not thread-safe. External synchronisation required between
///       rebuild() and query calls.
///
/// @par Memory ownership
/// - All device memory for cellCounts, cellStarts, sortedIndices is owned by this object.
/// - Position views and output views are non-owning (caller retains ownership).
///
/// @par ADR reference: docs/adr/0001-spatial-indexing-strategy.md
class UniformGridIndex : public ISpatialIndex
{
public:
    /// @brief Constructs a UniformGridIndex for a fixed domain.
    ///
    /// @param cellSize Side length of each grid cell (must be > 0).
    /// @param domainMin Minimum corner of the simulation domain (inclusive).
    /// @param domainMax Maximum corner of the simulation domain (exclusive).
    ///
    /// @pre cellSize > 0.
    /// @pre domainMin.x < domainMax.x and domainMin.y < domainMax.y.
    UniformGridIndex(float cellSize, float2 domainMin, float2 domainMax);

    ~UniformGridIndex() override = default;

    UniformGridIndex(const UniformGridIndex&) = delete;
    UniformGridIndex& operator=(const UniformGridIndex&) = delete;
    UniformGridIndex(UniformGridIndex&&) = default;
    UniformGridIndex& operator=(UniformGridIndex&&) = default;

    /// @brief Rebuilds the spatial index from current particle positions.
    ///
    /// Runs three CUDA kernel passes: hash → prefix sum → scatter.
    /// After this call, queryNeighbours() and queryFromPoints() are valid.
    ///
    /// @param positions Non-owning view of particle positions on device.
    ///
    /// @pre positions.x and positions.y are valid device pointers.
    /// @pre positions.count > 0.
    ///
    /// @post empty() == false; particleCount() == positions.count.
    void rebuild(ParticlePositionsView positions) override;

    /// @brief Query neighbours for all indexed particles.
    ///
    /// For each particle i, writes neighbour indices to
    /// `output.indices[i * output.maxPerParticle .. +output.maxPerParticle]`
    /// and the actual count to `output.counts[i]`.
    ///
    /// @param output Caller-allocated device buffers for results.
    /// @param params Query parameters (radius).
    ///
    /// @return QueryResult on success. On error:
    ///   - SpatialIndexError::NotBuilt if rebuild() has not been called.
    ///   - SpatialIndexError::InvalidBuffer if output.indices or output.counts is null.
    ///
    /// @note QueryResult::maxCountObserved is always 0 (deferred to profiling phase).
    ///       See plan.md — "Profiling Phase — maxCountObserved".
#ifndef __CUDACC__
    [[nodiscard]]
    std::expected<QueryResult, SpatialIndexError> queryNeighbours(NeighbourOutputView output,
                                                                  QueryParams params) const override;
#endif

    /// @brief Query neighbours from arbitrary query points.
    ///
    /// For each query point q[i], writes indices of indexed particles within
    /// `params.radius` to `output.indices[i * output.maxPerParticle ..]`.
    ///
    /// @param queryPoints Device positions to query from (may differ from indexed positions).
    /// @param output Caller-allocated device buffers for results.
    /// @param params Query parameters (radius).
    ///
    /// @return QueryResult on success. On error:
    ///   - SpatialIndexError::NotBuilt if rebuild() has not been called.
    ///   - SpatialIndexError::InvalidBuffer if any pointer is null.
#ifndef __CUDACC__
    [[nodiscard]]
    std::expected<QueryResult, SpatialIndexError> queryFromPoints(ParticlePositionsView queryPoints,
                                                                  NeighbourOutputView output,
                                                                  QueryParams params) const override;
#endif

    // -----------------------------------------------------------------------
    // State inspection
    // -----------------------------------------------------------------------

    /// @brief Returns true if no particles have been indexed (rebuild() not yet called).
    [[nodiscard]] bool empty() const noexcept;

    /// @brief Returns the number of particles in the current index.
    [[nodiscard]] std::size_t particleCount() const noexcept;

private:
    float cellSize_;
    float2 domainMin_;
    float2 domainMax_;
    int gridWidth_;  ///< Number of cells along X axis.
    int gridHeight_; ///< Number of cells along Y axis.
    int totalCells_; ///< gridWidth_ * gridHeight_.

    std::size_t particleCount_ = 0; ///< Set by rebuild().
    bool built_ = false;

    // Device memory owned by this index
    psim::core::CudaBuffer<int> cellCounts_;    ///< [totalCells_]
    psim::core::CudaBuffer<int> cellStarts_;    ///< [totalCells_] — exclusive prefix sum of cellCounts_
    psim::core::CudaBuffer<int> sortedIndices_; ///< [particleCount_] — sorted particle indices

    // Cached device copy of particle positions (set during rebuild, used in queries)
    psim::core::CudaBuffer<float> posX_; ///< [particleCount_]
    psim::core::CudaBuffer<float> posY_; ///< [particleCount_]

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    /// @brief Runs a GPU query kernel from `queryX`/`queryY` against the built index.
    ///
    /// @param queryX,queryY  Device arrays of query coordinates.
    /// @param queryCount     Number of query points.
    /// @param output         Caller-allocated output buffers.
    /// @param params         Query parameters (radius).
    /// @param mode           Whether to exclude each thread's own particle.
#ifndef __CUDACC__
    [[nodiscard]]
    std::expected<QueryResult, SpatialIndexError> runQuery(const float* queryX,
                                                           const float* queryY,
                                                           std::size_t queryCount,
                                                           NeighbourOutputView output,
                                                           QueryParams params,
                                                           SelfExclusionMode mode) const;
#endif
};

// ---------------------------------------------------------------------------
// Free function: kernel launcher callable from C++ (.cpp) translation units.
// Defined in UniformGridIndex.cu (compiled by nvcc).
//
// In the `detail` sub-namespace to signal "implementation bridge — do not call
// from outside this spatial module".
//
// NOTE(toolchain): This TU split is a permanent workaround for nvcc's EDG
// frontend being unable to parse GCC 13's <expected> header, even in CUDA 13.2
// with -std=c++20. This limitation is architectural (EDG vs libstdc++ C++23
// internals) and cannot be resolved by upgrading nvcc alone. The split will
// only become removable if NVIDIA adopts clang as the host compiler frontend.
// Tracked in: docs/adr/0001-spatial-indexing-strategy.md
// ---------------------------------------------------------------------------

namespace detail
{
///
/// @details All parameters are plain POD types so this function can be called
///          from a C++ (.cpp) translation unit that is not compiled by nvcc.
///
/// @param queryX,queryY          Device arrays of query point coordinates.
/// @param queryCount             Number of query points.
/// @param posX,posY              Device arrays of indexed particle coordinates.
/// @param cellCounts             Device array of per-cell particle counts.
/// @param cellStarts             Device array of per-cell start offsets.
/// @param sortedIndices          Device sorted particle index array.
/// @param outIndices             Device output neighbour index array.
/// @param outCounts              Device output neighbour count array.
/// @param outTruncated           Device int flag; set to 1 if any slot was truncated.
/// @param maxPerParticle         Maximum neighbours per query point.
/// @param radius                 Query radius.
/// @param domainMinX,domainMinY  Domain minimum coordinates.
/// @param cellSize               Cell side length.
/// @param gridWidth,gridHeight   Grid dimensions.
/// @param mode                   Self-exclusion policy (see SelfExclusionMode).
void launchQueryKernel(const float* queryX,
                       const float* queryY,
                       int queryCount,
                       const float* posX,
                       const float* posY,
                       const int* cellCounts,
                       const int* cellStarts,
                       const int* sortedIndices,
                       int* outIndices,
                       int* outCounts,
                       int* outTruncated,
                       int maxPerParticle,
                       float radius,
                       float domainMinX,
                       float domainMinY,
                       float cellSize,
                       int gridWidth,
                       int gridHeight,
                       SelfExclusionMode mode);

} // namespace detail

} // namespace psim::spatial
