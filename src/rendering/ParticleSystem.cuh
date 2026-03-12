#pragma once

#include <cuda_runtime.h>
#include <cuda_gl_interop.h>

#include <cstdint>

struct ParticleSystem {
    // OpenGL buffer ID
    unsigned int vbo = 0;

    // CUDA graphics resource for interop
    cudaGraphicsResource* cudaVboResource = nullptr;

    // Particle count
    std::uint32_t count = 0;

    // Device pointer to velocity data (not shared with GL)
    float2* d_velocities = nullptr;

    // Simulation time
    float time = 0.0f;
};

// Initialize particle system with given count
// Creates VBO and registers with CUDA
bool particleSystemInit(ParticleSystem& ps, std::uint32_t particleCount);

// Cleanup resources
void particleSystemDestroy(ParticleSystem& ps);

// Update particles using CUDA kernel
// Maps the GL buffer, runs kernel, unmaps
void particleSystemUpdate(ParticleSystem& ps, float dt);
