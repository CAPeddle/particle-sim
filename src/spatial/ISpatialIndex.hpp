#pragma once

#include <cstddef>
#include <cstdint>

namespace psim::spatial {

/// Non-owning view of particle positions on device memory.
/// Caller retains ownership and must ensure validity for duration of use.
struct ParticlePositionsView {
    const float* x;         ///< Device pointer to x coordinates
    const float* y;         ///< Device pointer to y coordinates
    std::size_t count;      ///< Number of particles
};

/// Non-owning view of neighbour output buffers on device memory.
/// Caller allocates and owns these buffers.
struct NeighbourOutputView {
    int* indices;           ///< [maxPerParticle * particleCount] - neighbour indices per particle
    int* counts;            ///< [particleCount] - actual neighbour count per particle
    std::size_t maxPerParticle;  ///< Maximum neighbours to return per particle
};

/// Parameters for neighbour queries.
struct QueryParams {
    float radius;           ///< Query radius - all particles within this distance are neighbours
};

/// Result metadata returned after a query operation.
struct QueryResult {
    bool truncated;         ///< True if any particle's neighbours exceeded maxPerParticle
    int maxCountObserved;   ///< Largest neighbour count encountered (may exceed maxPerParticle)
};

/// Abstract interface for spatial indexing structures that support radius-based
/// neighbour queries in continuous 2D space.
///
/// This interface is intended for models with dynamic, radius-based neighbourhoods
/// (e.g., SPH fluid simulation). Grid-based models (e.g., Game of Life) should use
/// direct grid arithmetic instead - see ADR-001.
///
/// Thread Safety:
/// - rebuild() and query methods must not be called concurrently
/// - After rebuild() completes, the index is immutable until the next rebuild()
/// - Multiple query calls between rebuilds are safe
///
/// Memory Ownership:
/// - Caller owns all device memory for positions and output buffers
/// - Implementation owns internal structures (cell arrays, sorted indices)
/// - Views are non-owning and valid only for the duration of the call
class ISpatialIndex {
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
    /// @return Result metadata including truncation status
    /// @pre rebuild() has been called
    /// @pre output buffers sized for at least the number of indexed particles
    [[nodiscard]]
    virtual QueryResult queryNeighbours(
        NeighbourOutputView output,
        QueryParams params
    ) const = 0;

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
    [[nodiscard]]
    virtual QueryResult queryFromPoints(
        ParticlePositionsView queryPoints,
        NeighbourOutputView output,
        QueryParams params
    ) const = 0;

protected:
    ISpatialIndex() = default;
};

} // namespace psim::spatial
