#pragma once

#include <cstddef>
#include <cstdint>
// std::expected is C++23 / GCC-13+ — not available in nvcc 12.0 front-end.
// Guard so this header remains parseable by the CUDA device compiler.
#ifndef __CUDACC__
#include <expected>
#endif

namespace psim::spatial
{

/// @brief Error codes for spatial index operations.
///
/// Returned via `std::expected` on precondition failures.
enum class SpatialIndexError : std::uint8_t
{
    /// rebuild() has not been called before a query method.
    NotBuilt,
    /// A provided buffer was null or insufficiently sized.
    InvalidBuffer,
};

/// Non-owning view of particle positions on device memory.
/// Caller retains ownership and must ensure validity for duration of use.
struct ParticlePositionsView
{
    const float* x;    ///< Device pointer to x coordinates
    const float* y;    ///< Device pointer to y coordinates
    std::size_t count; ///< Number of particles
};

/// Non-owning view of neighbour output buffers on device memory.
/// Caller allocates and owns these buffers.
struct NeighbourOutputView
{
    int* indices;               ///< [maxPerParticle * particleCount] - neighbour indices per particle
    int* counts;                ///< [particleCount] - actual neighbour count per particle
    std::size_t maxPerParticle; ///< Maximum neighbours to return per particle
};

/// Parameters for neighbour queries.
struct QueryParams
{
    float radius; ///< Query radius - all particles within this distance are neighbours
};

/// Result metadata returned after a query operation.
struct QueryResult
{
    bool truncated;       ///< True if any particle's neighbours exceeded maxPerParticle
    int maxCountObserved; ///< Largest neighbour count encountered. @note Currently always 0;
                          ///< implementation is deferred to the profiling phase. See plan.md.
};

/// Abstract interface for spatial indexing structures that support radius-based
/// neighbour queries in continuous 2D space.
///
/// This interface is intended for models with dynamic, radius-based neighbourhoods
/// (e.g., SPH fluid simulation). Grid-based models (e.g., Game of Life) should use
/// direct grid arithmetic instead - see ADR-001.
///
/// @note **Compilation contract for CUDA translation units:**
/// The query methods (`queryNeighbours`, `queryFromPoints`) are guarded by
/// `#ifndef __CUDACC__` and are therefore **not visible to nvcc-compiled `.cu` files**.
/// In CUDA classes that call these methods, the call site must be in a `.cpp`
/// translation unit (compiled by g++ / MSVC). Pass output buffers from the
/// `.cpp` layer down to kernels via a plain-POD launcher function.
/// See `UniformGridIndex.cuh` and `UniformGridIndexQueries.cpp` for the canonical
/// implementation of this pattern.
///
/// @note Thread Safety:
/// - rebuild() and query methods must not be called concurrently
/// - After rebuild() completes, the index is immutable until the next rebuild()
/// - Multiple query calls between rebuilds are safe
///
/// @note Memory Ownership:
/// - Caller owns all device memory for positions and output buffers
/// - Implementation owns internal structures (cell arrays, sorted indices)
/// - Views are non-owning and valid only for the duration of the call
class ISpatialIndex
{
public:
    virtual ~ISpatialIndex() = default;

    // Prevent copying - implementations manage GPU resources
    ISpatialIndex(const ISpatialIndex&) = delete;
    ISpatialIndex& operator=(const ISpatialIndex&) = delete;
    ISpatialIndex(ISpatialIndex&&) = default;
    ISpatialIndex& operator=(ISpatialIndex&&) = default;

    /// Rebuild the spatial index from current particle positions.
    ///
    /// Must be called before any query operations, and again whenever
    /// particle positions have changed.
    ///
    /// @param positions View of particle positions on device
    /// @pre positions.x and positions.y are valid device pointers
    /// @pre positions.count > 0
    /// @post Index is valid for queries until next rebuild() call
    virtual void rebuild(ParticlePositionsView positions) = 0;

    /// Query neighbours for all indexed particles.
    ///
    /// For each particle at index i, finds all other particles within the
    /// query radius and writes their indices to output.indices starting at
    /// offset (i * output.maxPerParticle). The actual count is written to
    /// output.counts[i].
    ///
    /// @param output View of output buffers on device (caller-allocated)
    /// @param params Query parameters including radius
    /// @return QueryResult on success, or SpatialIndexError::NotBuilt if rebuild() has not been called,
    ///         or SpatialIndexError::InvalidBuffer if output buffers are invalid.
    /// @pre rebuild() has been called
    /// @pre output buffers sized for at least the number of indexed particles
#ifndef __CUDACC__
    [[nodiscard]]
    virtual std::expected<QueryResult, SpatialIndexError> queryNeighbours(NeighbourOutputView output,
                                                                          QueryParams params) const = 0;
#endif

    /// Query neighbours from arbitrary points (not necessarily indexed particles).
    ///
    /// Similar to queryNeighbours(), but queries from specified points rather
    /// than the indexed particle positions. Useful for sampling or visualisation.
    ///
    /// @param queryPoints Positions to query from (device memory)
    /// @param output View of output buffers on device (caller-allocated)
    /// @param params Query parameters including radius
    /// @return Result metadata including truncation status
    /// @pre rebuild() has been called
    /// @pre output buffers sized for queryPoints.count particles
#ifndef __CUDACC__
    [[nodiscard]]
    virtual std::expected<QueryResult, SpatialIndexError> queryFromPoints(ParticlePositionsView queryPoints,
                                                                          NeighbourOutputView output,
                                                                          QueryParams params) const = 0;
#endif

protected:
    ISpatialIndex() = default;
};

} // namespace psim::spatial
