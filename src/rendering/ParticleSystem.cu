// GLAD must be included before any GL headers
#include <glad/gl.h>

#include "ParticleSystem.cuh"

#include <cstdio>
#include <cmath>

// Check CUDA errors
#define CUDA_CHECK(call) \
    do { \
        cudaError_t err = call; \
        if (err != cudaSuccess) { \
            std::fprintf(stderr, "CUDA error at %s:%d: %s\n", \
                __FILE__, __LINE__, cudaGetErrorString(err)); \
            return false; \
        } \
    } while(0)

#define CUDA_CHECK_VOID(call) \
    do { \
        cudaError_t err = call; \
        if (err != cudaSuccess) { \
            std::fprintf(stderr, "CUDA error at %s:%d: %s\n", \
                __FILE__, __LINE__, cudaGetErrorString(err)); \
            return; \
        } \
    } while(0)

// Kernel: Update particle positions
// Simple circular motion with noise for demo
__global__ void updateParticlesKernel(
    float4* positions,
    float2* velocities,
    std::uint32_t count,
    float time,
    float dt
) {
    unsigned int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= count) return;

    float4 pos = positions[idx];
    float2 vel = velocities[idx];

    // Apply velocity
    pos.x += vel.x * dt;
    pos.y += vel.y * dt;

    // Boundary wrap-around
    if (pos.x > 1.0f) pos.x -= 2.0f;
    if (pos.x < -1.0f) pos.x += 2.0f;
    if (pos.y > 1.0f) pos.y -= 2.0f;
    if (pos.y < -1.0f) pos.y += 2.0f;

    // Add some swirl based on position
    float angle = atan2f(pos.y, pos.x);
    float dist = sqrtf(pos.x * pos.x + pos.y * pos.y);

    // Gentle rotational velocity component
    float swirlStrength = 0.3f * (1.0f - dist);
    vel.x += -pos.y * swirlStrength * dt;
    vel.y += pos.x * swirlStrength * dt;

    // Damping
    vel.x *= 0.999f;
    vel.y *= 0.999f;

    // Update color based on velocity (stored in z,w)
    float speed = sqrtf(vel.x * vel.x + vel.y * vel.y);
    pos.z = 0.2f + speed * 2.0f;  // Blue channel
    pos.w = 1.0f;                  // Alpha

    positions[idx] = pos;
    velocities[idx] = vel;
}

// Kernel: Initialize particles in a grid pattern with random velocities
__global__ void initParticlesKernel(
    float4* positions,
    float2* velocities,
    std::uint32_t count,
    std::uint32_t seed
) {
    unsigned int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= count) return;

    // Simple LCG random
    unsigned int state = idx + seed;
    auto randf = [&state]() -> float {
        state = state * 1664525u + 1013904223u;
        return (state & 0xFFFFFF) / float(0xFFFFFF);
    };

    // Distribute in a circle
    float angle = randf() * 2.0f * 3.14159265f;
    float radius = sqrtf(randf()) * 0.8f;

    float4 pos;
    pos.x = cosf(angle) * radius;
    pos.y = sinf(angle) * radius;
    pos.z = 0.5f;  // Color: blue
    pos.w = 1.0f;  // Alpha

    float2 vel;
    vel.x = (randf() - 0.5f) * 0.5f;
    vel.y = (randf() - 0.5f) * 0.5f;

    positions[idx] = pos;
    velocities[idx] = vel;
}

bool particleSystemInit(ParticleSystem& ps, std::uint32_t particleCount) {
    ps.count = particleCount;
    ps.time = 0.0f;

    // Create OpenGL VBO
    glGenBuffers(1, &ps.vbo);
    glBindBuffer(GL_ARRAY_BUFFER, ps.vbo);

    // Allocate buffer: float4 per particle (x, y, colorIntensity, alpha)
    std::size_t bufferSize = particleCount * sizeof(float4);
    glBufferData(GL_ARRAY_BUFFER, bufferSize, nullptr, GL_DYNAMIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);

    // Register VBO with CUDA
    CUDA_CHECK(cudaGraphicsGLRegisterBuffer(
        &ps.cudaVboResource,
        ps.vbo,
        cudaGraphicsMapFlagsWriteDiscard
    ));

    // Allocate velocity buffer (device only, not shared with GL)
    CUDA_CHECK(cudaMalloc(&ps.d_velocities, particleCount * sizeof(float2)));

    // Initialize particles
    float4* d_positions = nullptr;
    std::size_t mappedSize = 0;

    CUDA_CHECK(cudaGraphicsMapResources(1, &ps.cudaVboResource, 0));
    CUDA_CHECK(cudaGraphicsResourceGetMappedPointer(
        reinterpret_cast<void**>(&d_positions),
        &mappedSize,
        ps.cudaVboResource
    ));

    int blockSize = 256;
    int numBlocks = (particleCount + blockSize - 1) / blockSize;

    initParticlesKernel<<<numBlocks, blockSize>>>(
        d_positions,
        ps.d_velocities,
        particleCount,
        42  // seed
    );

    CUDA_CHECK(cudaDeviceSynchronize());
    CUDA_CHECK(cudaGraphicsUnmapResources(1, &ps.cudaVboResource, 0));

    return true;
}

void particleSystemDestroy(ParticleSystem& ps) {
    if (ps.cudaVboResource) {
        cudaGraphicsUnregisterResource(ps.cudaVboResource);
        ps.cudaVboResource = nullptr;
    }

    if (ps.d_velocities) {
        cudaFree(ps.d_velocities);
        ps.d_velocities = nullptr;
    }

    if (ps.vbo) {
        glDeleteBuffers(1, &ps.vbo);
        ps.vbo = 0;
    }

    ps.count = 0;
}

void particleSystemUpdate(ParticleSystem& ps, float dt) {
    if (ps.count == 0 || !ps.cudaVboResource) return;

    ps.time += dt;

    float4* d_positions = nullptr;
    std::size_t mappedSize = 0;

    CUDA_CHECK_VOID(cudaGraphicsMapResources(1, &ps.cudaVboResource, 0));
    CUDA_CHECK_VOID(cudaGraphicsResourceGetMappedPointer(
        reinterpret_cast<void**>(&d_positions),
        &mappedSize,
        ps.cudaVboResource
    ));

    int blockSize = 256;
    int numBlocks = (ps.count + blockSize - 1) / blockSize;

    updateParticlesKernel<<<numBlocks, blockSize>>>(
        d_positions,
        ps.d_velocities,
        ps.count,
        ps.time,
        dt
    );

    CUDA_CHECK_VOID(cudaDeviceSynchronize());
    CUDA_CHECK_VOID(cudaGraphicsUnmapResources(1, &ps.cudaVboResource, 0));
}
