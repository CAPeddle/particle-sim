#pragma once
// This file contains inline CUDA device calls (CUDA_CHECK / cudaMemcpy).
// It must only be included from .cu translation units compiled by nvcc.
#ifndef __CUDACC__
#error "SphTestHelpers.hpp must only be included from .cu files compiled by nvcc."
#endif

#include "models/FluidSPHModel.cuh"

#include <cstdint>
#include <random>
#include <vector>

namespace psim::test
{

/// @brief Fills particle positions with random values within domain bounds.
///
/// Seeds the RNG from `seed` for reproducibility. Intended for test fixture
/// setup only — has no physical meaning.
///
/// @param model  Initialised FluidSPHModel with valid device buffers.
/// @param seed   RNG seed.
inline void seedParticlesRandom(psim::models::FluidSPHModel& model, uint32_t seed)
{
    const uint32_t count = model.params.particleCount;
    std::mt19937 rng{seed};
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

} // namespace psim::test
