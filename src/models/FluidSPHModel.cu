#include "models/FluidSPHModel.cuh"
#include "models/SphKernels.cuh"

#include <cstdint>
#include <cuda_runtime.h>
#include <random>
#include <vector>

namespace psim::models
{

// ---------------------------------------------------------------------------
// Density kernel
// ---------------------------------------------------------------------------

/// @brief Computes per-particle density via SPH summation.
///
/// For each particle i:
///   ρ_i = m * W(0, h)                              ← self-contribution
///         + Σ_{j in neighbours[i]} m * W(|x_i - x_j|, h)
///
/// Self-contribution is added explicitly because `queryNeighbours` uses
/// `SelfExclusionMode::UseTid` and therefore does not include particle i in
/// its own neighbour list.
///
/// @param posX              Device array of x-positions [count].
/// @param posY              Device array of y-positions [count].
/// @param neighbourIndices  Row-major [count × maxNeighbours] neighbour index table.
/// @param neighbourCounts   Actual number of valid entries per row [count].
/// @param maxNeighbours     Row stride in neighbourIndices.
/// @param influenceRadius   SPH smoothing radius h.
/// @param mass              Uniform particle mass m.
/// @param outDensity        Output density array [count] (write-only).
/// @param count             Number of particles.
__global__ void computeDensityKernel(const float* posX,
                                     const float* posY,
                                     const int* neighbourIndices,
                                     const int* neighbourCounts,
                                     int maxNeighbours,
                                     float influenceRadius,
                                     float mass,
                                     float* outDensity,
                                     uint32_t count)
{
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= count)
    {
        return;
    }

    float px = posX[idx];
    float py = posY[idx];

    // Self-contribution: particle i is in its own density support
    float density = mass * smoothingKernel(0.0F, influenceRadius);

    int nCount = neighbourCounts[idx];
    for (int n = 0; n < nCount; ++n)
    {
        int j = neighbourIndices[static_cast<int>(idx) * maxNeighbours + n];
        float dx = posX[j] - px;
        float dy = posY[j] - py;
        float d = sqrtf(dx * dx + dy * dy);
        density += mass * smoothingKernel(d, influenceRadius);
    }

    outDensity[idx] = density;
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

void initFluidModel(FluidSPHModel& model, const FluidSPHParams& params)
{
    if (params.particleCount == 0U)
    {
        std::fprintf(stderr, "initFluidModel: params.particleCount must be > 0\n");
        std::abort();
    }
    if (params.influenceRadius <= 0.0F)
    {
        std::fprintf(stderr, "initFluidModel: params.influenceRadius must be > 0\n");
        std::abort();
    }
    if (params.maxNeighbours == 0U)
    {
        std::fprintf(stderr, "initFluidModel: params.maxNeighbours must be > 0\n");
        std::abort();
    }

    model.params = params;

    model.posX.allocate(params.particleCount);
    model.posY.allocate(params.particleCount);
    model.velX.allocate(params.particleCount);
    model.velY.allocate(params.particleCount);
    model.density.allocate(params.particleCount);

    const std::size_t nbufSize =
        static_cast<std::size_t>(params.particleCount) * static_cast<std::size_t>(params.maxNeighbours);
    model.neighbourIndices.allocate(nbufSize);
    model.neighbourCounts.allocate(params.particleCount);
}

void initSphDemoParticles(FluidSPHModel& model)
{
    constexpr uint32_t DEMO_SEED = 42U;
    const uint32_t count = model.params.particleCount;

    std::mt19937 rng{DEMO_SEED};
    std::uniform_real_distribution<float> distX{model.params.domainMin.x, model.params.domainMax.x};
    std::uniform_real_distribution<float> distY{model.params.domainMin.y, model.params.domainMax.y};

    std::vector<float> hX(count);
    std::vector<float> hY(count);
    for (uint32_t i = 0; i < count; ++i)
    {
        hX[i] = distX(rng);
        hY[i] = distY(rng);
    }

    CUDA_CHECK(cudaMemcpy(model.posX.get(), hX.data(), count * sizeof(float), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(model.posY.get(), hY.data(), count * sizeof(float), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemset(model.velX.get(), 0, count * sizeof(float)));
    CUDA_CHECK(cudaMemset(model.velY.get(), 0, count * sizeof(float)));
}

void destroyFluidModel(FluidSPHModel& model)
{
    model.posX.free();
    model.posY.free();
    model.velX.free();
    model.velY.free();
    model.density.free();
    model.neighbourIndices.free();
    model.neighbourCounts.free();
}

// ---------------------------------------------------------------------------
// Kernel launcher bridge (POD interface — callable from .cpp TUs)
// ---------------------------------------------------------------------------

namespace detail
{

void launchComputeDensityKernel(const float* posX,
                                const float* posY,
                                const int* neighbourIndices,
                                const int* neighbourCounts,
                                int maxNeighbours,
                                float influenceRadius,
                                float mass,
                                float* outDensity,
                                uint32_t count)
{
    constexpr int BLOCK_SIZE = 256;
    int blocks = (static_cast<int>(count) + BLOCK_SIZE - 1) / BLOCK_SIZE;

    computeDensityKernel<<<blocks, BLOCK_SIZE>>>(
        posX, posY, neighbourIndices, neighbourCounts, maxNeighbours, influenceRadius, mass, outDensity, count);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());
}

} // namespace detail

} // namespace psim::models
