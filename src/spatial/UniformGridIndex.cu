#include "core/CudaUtils.hpp"
#include "spatial/UniformGridIndex.cuh"

#include <cstdio>
#include <cstdlib>
#include <limits>
#include <thrust/device_ptr.h>
#include <thrust/scan.h>

namespace psim::spatial
{

// ============================================================================
// Device helpers
// ============================================================================

/// @brief Computes the flat cell index for a particle position.
///
/// @param x          Particle x coordinate.
/// @param y          Particle y coordinate.
/// @param domainMinX Domain minimum x.
/// @param domainMinY Domain minimum y.
/// @param cellSize   Cell side length.
/// @param gridWidth  Number of cells along X.
/// @param gridHeight Number of cells along Y.
/// @return Flat cell index, or -1 if outside the domain.
__device__ int cellIndexDevice(
    float x, float y, float domainMinX, float domainMinY, float cellSize, int gridWidth, int gridHeight)
{
    int cx = static_cast<int>((x - domainMinX) / cellSize);
    int cy = static_cast<int>((y - domainMinY) / cellSize);
    if (cx < 0 || cx >= gridWidth || cy < 0 || cy >= gridHeight)
    {
        return -1;
    }
    return cy * gridWidth + cx;
}

// ============================================================================
// Kernels
// ============================================================================

/// @brief Pass 1 — atomically increment the count for each particle's cell.
///
/// @param posX          Device array of particle x coordinates.
/// @param posY          Device array of particle y coordinates.
/// @param particleCount Number of particles.
/// @param cellCounts    [totalCells] output — incremented per-cell particle count.
/// @param domainMinX    Domain minimum x.
/// @param domainMinY    Domain minimum y.
/// @param cellSize      Cell side length.
/// @param gridWidth     Number of cells along X.
/// @param gridHeight    Number of cells along Y.
__global__ void countParticlesKernel(const float* posX,
                                     const float* posY,
                                     int particleCount,
                                     int* cellCounts,
                                     float domainMinX,
                                     float domainMinY,
                                     float cellSize,
                                     int gridWidth,
                                     int gridHeight)
{
    int tid = static_cast<int>(blockIdx.x) * static_cast<int>(blockDim.x) + static_cast<int>(threadIdx.x);
    if (tid >= particleCount)
    {
        return;
    }
    int cell = cellIndexDevice(posX[tid], posY[tid], domainMinX, domainMinY, cellSize, gridWidth, gridHeight);
    if (cell >= 0)
    {
        atomicAdd(&cellCounts[cell], 1);
    }
}

/// @brief Pass 3 — scatter particle indices into `sortedIndices` using `cellStarts`.
///
/// Each particle atomically claims a slot in its cell's region of `sortedIndices`
/// using a second pass over `cellCounts` (re-incremented from 0).
///
/// @param posX           Device array of particle x coordinates.
/// @param posY           Device array of particle y coordinates.
/// @param particleCount  Number of particles.
/// @param cellStarts     [totalCells] exclusive prefix sum of original counts.
/// @param cellCounts     [totalCells] will be reused as per-cell write cursor (must be zeroed before this kernel).
/// @param sortedIndices  [particleCount] output — each element is a particle index.
/// @param domainMinX     Domain minimum x.
/// @param domainMinY     Domain minimum y.
/// @param cellSize       Cell side length.
/// @param gridWidth      Number of cells along X.
/// @param gridHeight     Number of cells along Y.
__global__ void scatterParticlesKernel(const float* posX,
                                       const float* posY,
                                       int particleCount,
                                       const int* cellStarts,
                                       int* cellCounts,
                                       int* sortedIndices,
                                       float domainMinX,
                                       float domainMinY,
                                       float cellSize,
                                       int gridWidth,
                                       int gridHeight)
{
    int tid = static_cast<int>(blockIdx.x) * static_cast<int>(blockDim.x) + static_cast<int>(threadIdx.x);
    if (tid >= particleCount)
    {
        return;
    }
    int cell = cellIndexDevice(posX[tid], posY[tid], domainMinX, domainMinY, cellSize, gridWidth, gridHeight);
    if (cell >= 0)
    {
        int slot = cellStarts[cell] + atomicAdd(&cellCounts[cell], 1);
        sortedIndices[slot] = tid;
    }
}

/// @brief Pass 4 — for each query point, iterate the 3×3 cell neighbourhood
///        and collect neighbours within `radius`.
///
/// @param queryX         Device array of query x coordinates.
/// @param queryY         Device array of query y coordinates.
/// @param queryCount     Number of query points.
/// @param posX           Device array of indexed particle x coordinates.
/// @param posY           Device array of indexed particle y coordinates.
/// @param cellCounts     [totalCells] per-cell particle count.
/// @param cellStarts     [totalCells] per-cell start offset in sortedIndices.
/// @param sortedIndices  [particleCount] sorted particle indices.
/// @param outIndices     [queryCount * maxPerParticle] output neighbour indices.
/// @param outCounts      [queryCount] output neighbour counts.
/// @param outTruncated   Single-element device flag; set to 1 if any truncation occurs.
/// @param maxPerParticle Maximum neighbours to write per query point.
/// @param radius         Neighbour query radius.
/// @param domainMinX     Domain minimum x.
/// @param domainMinY     Domain minimum y.
/// @param cellSize       Cell side length.
/// @param gridWidth      Number of cells along X.
/// @param gridHeight     Number of cells along Y.
__global__ void queryNeighboursKernel(const float* queryX,
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
                                      SelfExclusionMode selfMode)
{
    int tid = static_cast<int>(blockIdx.x) * static_cast<int>(blockDim.x) + static_cast<int>(threadIdx.x);
    if (tid >= queryCount)
    {
        return;
    }

    float qx = queryX[tid];
    float qy = queryY[tid];
    float r2 = radius * radius;

    // SelfExclusionMode::UseTid  → exclude the particle whose index equals this thread index.
    // SelfExclusionMode::None    → no self-exclusion (external query points not in the index).
    int excludeIdx = (selfMode == SelfExclusionMode::UseTid) ? tid : -1;
    int cx = static_cast<int>((qx - domainMinX) / cellSize);
    int cy = static_cast<int>((qy - domainMinY) / cellSize);

    int count = 0;
    int* myOut = outIndices + tid * maxPerParticle;

    // Iterate 3x3 neighbourhood (clamped to grid bounds)
    int cxMin = max(0, cx - 1);
    int cxMax = min(gridWidth - 1, cx + 1);
    int cyMin = max(0, cy - 1);
    int cyMax = min(gridHeight - 1, cy + 1);

    for (int ny = cyMin; ny <= cyMax; ++ny)
    {
        for (int nx = cxMin; nx <= cxMax; ++nx)
        {
            int cell = ny * gridWidth + nx;
            int start = cellStarts[cell];
            int ncnt = cellCounts[cell];
            for (int k = 0; k < ncnt; ++k)
            {
                int pidx = sortedIndices[start + k];
                // Skip self
                if (pidx == excludeIdx)
                {
                    continue;
                }
                float dx = posX[pidx] - qx;
                float dy = posY[pidx] - qy;
                float d2 = dx * dx + dy * dy;
                if (d2 < r2)
                {
                    if (count < maxPerParticle)
                    {
                        myOut[count] = pidx;
                    }
                    else
                    {
                        atomicOr(outTruncated, 1);
                    }
                    ++count;
                }
            }
        }
    }
    outCounts[tid] = min(count, maxPerParticle);
}

// ============================================================================
// UniformGridIndex implementation
// ============================================================================

UniformGridIndex::UniformGridIndex(float cellSize, float2 domainMin, float2 domainMax)
    : cellSize_{cellSize},
      domainMin_{domainMin},
      domainMax_{domainMax},
      gridWidth_{0},
      gridHeight_{0},
      totalCells_{0}
{
    if (!(cellSize > 0.0F))
    {
        std::fprintf(stderr, "UniformGridIndex: cellSize must be positive (got %f)\n", static_cast<double>(cellSize));
        std::abort();
    }
    if (!(domainMin.x < domainMax.x))
    {
        std::fprintf(stderr, "UniformGridIndex: domain x range must be positive (min=%f >= max=%f)\n",
                     static_cast<double>(domainMin.x), static_cast<double>(domainMax.x));
        std::abort();
    }
    if (!(domainMin.y < domainMax.y))
    {
        std::fprintf(stderr, "UniformGridIndex: domain y range must be positive (min=%f >= max=%f)\n",
                     static_cast<double>(domainMin.y), static_cast<double>(domainMax.y));
        std::abort();
    }

    // Compute grid dimensions — ceiling division so all particles in domain fit
    gridWidth_ = static_cast<int>((domainMax.x - domainMin.x) / cellSize + 1.0F);
    gridHeight_ = static_cast<int>((domainMax.y - domainMin.y) / cellSize + 1.0F);
    totalCells_ = gridWidth_ * gridHeight_;

    // Pre-allocate cell arrays once (they do not depend on particle count)
    cellCounts_.allocate(static_cast<std::size_t>(totalCells_));
    cellStarts_.allocate(static_cast<std::size_t>(totalCells_));
}

// ----------------------------------------------------------------------------

void UniformGridIndex::rebuild(ParticlePositionsView positions)
{
    if (positions.x == nullptr)
    {
        std::fprintf(stderr, "UniformGridIndex::rebuild: positions.x must be a valid device pointer\n");
        std::abort();
    }
    if (positions.y == nullptr)
    {
        std::fprintf(stderr, "UniformGridIndex::rebuild: positions.y must be a valid device pointer\n");
        std::abort();
    }
    if (positions.count == 0U)
    {
        std::fprintf(stderr, "UniformGridIndex::rebuild: positions.count must be > 0\n");
        std::abort();
    }
    if (positions.count > static_cast<std::size_t>(std::numeric_limits<int>::max()))
    {
        std::fprintf(stderr,
                     "UniformGridIndex::rebuild: particle count %zu exceeds int range (%d max)\n",
                     positions.count,
                     std::numeric_limits<int>::max());
        std::abort();
    }

    const auto N = positions.count;
    particleCount_ = N;

    // (Re)allocate particle-size buffers if count changed
    if (sortedIndices_.count() != N)
    {
        sortedIndices_.allocate(N);
        posX_.allocate(N);
        posY_.allocate(N);
    }

    // Cache positions (needed by query kernel for distance filtering)
    CUDA_CHECK(cudaMemcpy(posX_.get(), positions.x, N * sizeof(float), cudaMemcpyDeviceToDevice));
    CUDA_CHECK(cudaMemcpy(posY_.get(), positions.y, N * sizeof(float), cudaMemcpyDeviceToDevice));

    // --- Pass 1: zero cellCounts, then count particles per cell ---
    CUDA_CHECK(cudaMemset(cellCounts_.get(), 0, static_cast<std::size_t>(totalCells_) * sizeof(int)));

    constexpr int BLOCK = 256;
    int grid = (static_cast<int>(N) + BLOCK - 1) / BLOCK;

    countParticlesKernel<<<grid, BLOCK>>>(posX_.get(),
                                          posY_.get(),
                                          static_cast<int>(N),
                                          cellCounts_.get(),
                                          domainMin_.x,
                                          domainMin_.y,
                                          cellSize_,
                                          gridWidth_,
                                          gridHeight_);
    CUDA_CHECK(cudaGetLastError());

    // --- Pass 2: exclusive prefix sum → cellStarts ---
    {
        thrust::device_ptr<int> pCounts(cellCounts_.get());
        thrust::device_ptr<int> pStarts(cellStarts_.get());
        thrust::exclusive_scan(pCounts, pCounts + totalCells_, pStarts);
        // Surface any device error raised by the Thrust scan (Thrust may throw
        // thrust::system_error internally — CUDA_CHECK catches sticky errors here).
        CUDA_CHECK(cudaGetLastError());
        CUDA_CHECK(cudaDeviceSynchronize());
    }

    // --- Pass 3: zero cellCounts again (used as write cursors), then scatter ---
    CUDA_CHECK(cudaMemset(cellCounts_.get(), 0, static_cast<std::size_t>(totalCells_) * sizeof(int)));

    scatterParticlesKernel<<<grid, BLOCK>>>(posX_.get(),
                                            posY_.get(),
                                            static_cast<int>(N),
                                            cellStarts_.get(),
                                            cellCounts_.get(),
                                            sortedIndices_.get(),
                                            domainMin_.x,
                                            domainMin_.y,
                                            cellSize_,
                                            gridWidth_,
                                            gridHeight_);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());

    built_ = true;
}

// ----------------------------------------------------------------------------

// NOTE: queryNeighbours(), queryFromPoints(), runQuery() are defined in
// UniformGridIndexQueries.cpp (compiled by g++/MSVC, not nvcc) because they
// return std::expected<> which nvcc 12.0 cannot compile.

// ----------------------------------------------------------------------------
// launchQueryKernel — defined here (in .cu) so nvcc compiles the <<<>>> syntax.
// Callable from any C++ translation unit via the declaration in UniformGridIndex.cuh.
// ----------------------------------------------------------------------------

namespace detail
{

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
                       SelfExclusionMode mode)
{
    constexpr int BLOCK = 256;
    int grid = (queryCount + BLOCK - 1) / BLOCK;

    queryNeighboursKernel<<<grid, BLOCK>>>(queryX,
                                           queryY,
                                           queryCount,
                                           posX,
                                           posY,
                                           cellCounts,
                                           cellStarts,
                                           sortedIndices,
                                           outIndices,
                                           outCounts,
                                           outTruncated,
                                           maxPerParticle,
                                           radius,
                                           domainMinX,
                                           domainMinY,
                                           cellSize,
                                           gridWidth,
                                           gridHeight,
                                           mode);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());
}

} // namespace detail

// ----------------------------------------------------------------------------

bool UniformGridIndex::empty() const noexcept
{
    return !built_;
}

std::size_t UniformGridIndex::particleCount() const noexcept
{
    return particleCount_;
}

} // namespace psim::spatial
