// clang-format off
// GLAD must be included before any GL headers (cuda_gl_interop.h pulls in
// GL/gl.h on Linux; GLAD must define __gl_h_ first to prevent conflicts).
#include <glad/gl.h>
// clang-format on

#include "rendering/DensityHeatmap.cuh"
#include "rendering/GpuScalarFieldInput.cuh"

#include <cassert>
#include <cfloat>
#include <cstdint>
#include <cstdio>
#include <cuda_gl_interop.h>
#include <cuda_runtime.h>
#include <expected>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <string_view>
#include <system_error>

namespace psim::rendering
{

// ---------------------------------------------------------------------------
// Internal shader helpers (static — not part of public API)
// ---------------------------------------------------------------------------

static std::string loadSource(std::string_view path)
{
    std::ifstream file(std::filesystem::path{path});
    if (!file.is_open())
    {
        std::fprintf(stderr, "DensityHeatmap: failed to open shader '%s'\n", std::string{path}.c_str());
        return {};
    }
    std::ostringstream buf;
    buf << file.rdbuf();
    return buf.str();
}

static unsigned int compileStage(unsigned int type, const char* src)
{
    unsigned int shader = glCreateShader(type);
    glShaderSource(shader, 1, &src, nullptr);
    glCompileShader(shader);

    int ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (ok == 0)
    {
        char log[512];
        glGetShaderInfoLog(shader, 512, nullptr, log);
        std::fprintf(stderr, "DensityHeatmap: shader compile error: %s\n", log);
        glDeleteShader(shader);
        return 0U;
    }
    return shader;
}

static unsigned int linkProgram(std::string_view vertPath, std::string_view fragPath)
{
    const std::string vertSrc = loadSource(vertPath);
    const std::string fragSrc = loadSource(fragPath);
    if (vertSrc.empty() || fragSrc.empty())
    {
        return 0U;
    }

    unsigned int vert = compileStage(GL_VERTEX_SHADER, vertSrc.c_str());
    unsigned int frag = compileStage(GL_FRAGMENT_SHADER, fragSrc.c_str());

    if (vert == 0U || frag == 0U)
    {
        if (vert != 0U)
        {
            glDeleteShader(vert);
        }
        if (frag != 0U)
        {
            glDeleteShader(frag);
        }
        return 0U;
    }

    unsigned int prog = glCreateProgram();
    glAttachShader(prog, vert);
    glAttachShader(prog, frag);
    glLinkProgram(prog);

    int ok = 0;
    glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    glDeleteShader(vert);
    glDeleteShader(frag);

    if (ok == 0)
    {
        char log[512];
        glGetProgramInfoLog(prog, 512, nullptr, log);
        std::fprintf(stderr, "DensityHeatmap: shader link error: %s\n", log);
        glDeleteProgram(prog);
        return 0U;
    }
    return prog;
}

// ---------------------------------------------------------------------------
// CUDA kernels
// ---------------------------------------------------------------------------

/// @brief Zero-fills the per-texel accumulator and count buffers.
///
/// @param accum  Device float array [size].
/// @param counts Device int array [size].
/// @param size   Total number of texels (resolution²).
__global__ void clearAccumKernel(float* accum, int* counts, uint32_t size)
{
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size)
    {
        return;
    }
    accum[idx] = 0.0F;
    counts[idx] = 0;
}

/// @brief Atomically updates a global float with the minimum of current and candidate.
///
/// Uses atomicCAS on the underlying int representation to support signed float
/// comparisons correctly.
__device__ void atomicMinFloat(float* address, float candidate)
{
    // NOLINTBEGIN(cppcoreguidelines-pro-type-reinterpret-cast)
    int* addressAsInt = reinterpret_cast<int*>(address);
    int oldValue = *addressAsInt;

    while (candidate < __int_as_float(oldValue))
    {
        const int assumed = oldValue;
        oldValue = atomicCAS(addressAsInt, assumed, __float_as_int(candidate));
        if (oldValue == assumed)
        {
            break;
        }
    }
    // NOLINTEND(cppcoreguidelines-pro-type-reinterpret-cast)
}

/// @brief Atomically updates a global float with the maximum of current and candidate.
///
/// Uses atomicCAS on the underlying int representation to support signed float
/// comparisons correctly.
__device__ void atomicMaxFloat(float* address, float candidate)
{
    // NOLINTBEGIN(cppcoreguidelines-pro-type-reinterpret-cast)
    int* addressAsInt = reinterpret_cast<int*>(address);
    int oldValue = *addressAsInt;

    while (candidate > __int_as_float(oldValue))
    {
        const int assumed = oldValue;
        oldValue = atomicCAS(addressAsInt, assumed, __float_as_int(candidate));
        if (oldValue == assumed)
        {
            break;
        }
    }
    // NOLINTEND(cppcoreguidelines-pro-type-reinterpret-cast)
}

/// @brief Parallel reduction to find min and max over a float array.
///
/// Uses one block-local shared-memory reduction per block and atomically
/// combines block outputs into global `outMin` and `outMax`.
///
/// @param values Device float array [count].
/// @param count  Number of elements.
/// @param outMin Device float[1] initialised to +FLT_MAX.
/// @param outMax Device float[1] initialised to -FLT_MAX.
__global__ void minMaxReductionKernel(const float* values, uint32_t count, float* outMin, float* outMax)
{
    extern __shared__ float sdata[];
    float* sMin = sdata;
    float* sMax = sdata + blockDim.x;

    const uint32_t tid = threadIdx.x;
    const uint32_t idx = blockIdx.x * blockDim.x + tid;

    float localMin = FLT_MAX;
    float localMax = -FLT_MAX;
    if (idx < count)
    {
        localMin = values[idx];
        localMax = values[idx];
    }

    sMin[tid] = localMin;
    sMax[tid] = localMax;
    __syncthreads();

    for (uint32_t stride = blockDim.x / 2U; stride > 0U; stride >>= 1U)
    {
        if (tid < stride)
        {
            sMin[tid] = sMin[tid] < sMin[tid + stride] ? sMin[tid] : sMin[tid + stride];
            sMax[tid] = sMax[tid] > sMax[tid + stride] ? sMax[tid] : sMax[tid + stride];
        }
        __syncthreads();
    }

    if (tid == 0U)
    {
        atomicMinFloat(outMin, sMin[0]);
        atomicMaxFloat(outMax, sMax[0]);
    }
}

/// @brief Scatters each particle's SPH density into its covering texel.
///
/// Each thread handles one particle.  Particles outside the normalised domain [0,1)
/// are discarded; discard count is written to `discardCount`.
/// Multiple particles in the same texel are accumulated via `atomicAdd`;
/// `writeTextureKernel` will average them.
///
/// @param posX          Device x-position array [particleCount].
/// @param posY          Device y-position array [particleCount].
/// @param scalarValues  Device scalar array [particleCount].
/// @param accum         Device accumulator [resolution²].
/// @param counts        Device count [resolution²].
/// @param domainMin     Domain lower-left corner.
/// @param domainMax     Domain upper-right corner.
/// @param resolution    Texture width == height.
/// @param particleCount Number of particles.
/// @param discardCount  Device counter incremented for each out-of-domain particle.
__global__ void scatterDensityKernel(const float* posX,
                                     const float* posY,
                                     const float* scalarValues,
                                     float* accum,
                                     int* counts,
                                     float2 domainMin,
                                     float2 domainMax,
                                     int resolution,
                                     uint32_t particleCount,
                                     uint32_t* discardCount)
{
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= particleCount)
    {
        return;
    }

    float domainW = domainMax.x - domainMin.x;
    float domainH = domainMax.y - domainMin.y;

    if (domainW <= 0.0F || domainH <= 0.0F)
    {
        return;
    }

    // Normalised [0, 1] coordinates within the domain
    float nx = (posX[idx] - domainMin.x) / domainW;
    float ny = (posY[idx] - domainMin.y) / domainH;

    if (nx < 0.0F || nx >= 1.0F || ny < 0.0F || ny >= 1.0F)
    {
        atomicAdd(discardCount, 1U);
        return;
    }
    int tx = static_cast<int>(nx * static_cast<float>(resolution));
    int ty = static_cast<int>(ny * static_cast<float>(resolution));

    int texel = ty * resolution + tx;
    atomicAdd(&accum[texel], scalarValues[idx]);
    atomicAdd(&counts[texel], 1);
}

/// @brief Averages accumulated density and writes one float per texel to the surface.
///
/// Texels with no particles emit 0.  The stored value is the raw average density;
/// normalisation by `u_minValue`/`u_maxValue` is performed in `heatmap.frag`.
///
/// @param accum    Device accumulator [resolution²].
/// @param counts   Device count [resolution²].
/// @param surface  CUDA surface object wrapping the registered GL texture.
/// @param resolution Texture width == height.
__global__ void writeTextureKernel(const float* accum,
                                   const int* counts,
                                   cudaSurfaceObject_t surface,
                                   uint32_t resolution)
{
    uint32_t x = blockIdx.x * blockDim.x + threadIdx.x;
    uint32_t y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= resolution || y >= resolution)
    {
        return;
    }

    uint32_t texel = y * resolution + x;
    float value = (counts[texel] > 0) ? (accum[texel] / static_cast<float>(counts[texel])) : 0.0F;

    // surf2Dwrite byte offset = x * sizeof(float); cast to int as required by API
    surf2Dwrite(value, surface, static_cast<int>(x * sizeof(float)), static_cast<int>(y));
}

// ---------------------------------------------------------------------------
// Public lifecycle functions
// ---------------------------------------------------------------------------

[[nodiscard]] std::expected<void, std::error_code> initDensityHeatmap(DensityHeatmap& heatmap,
                                                                      int resolution,
                                                                      std::string_view vertPath,
                                                                      std::string_view fragPath)
{
    assert(heatmap.textureId == 0U && "initDensityHeatmap called on already-initialised heatmap");

    if (resolution <= 0)
    {
        return std::unexpected(std::make_error_code(std::errc::invalid_argument));
    }

    if (resolution > 4096)
    {
        return std::unexpected(std::make_error_code(std::errc::invalid_argument));
    }

    // --- Step 1: Compile + link shaders first (fail fast, zero CUDA resources on error) ---
    heatmap.shaderProgram = linkProgram(vertPath, fragPath);
    if (heatmap.shaderProgram == 0U)
    {
        std::fprintf(stderr, "DensityHeatmap: shader compilation failed\n");
        return std::unexpected(std::make_error_code(std::errc::invalid_argument));
    }

    // Cache uniform locations immediately after link
    heatmap.uniformDensityTexLoc = glGetUniformLocation(heatmap.shaderProgram, "u_densityTex");
    heatmap.uniformMinValueLoc = glGetUniformLocation(heatmap.shaderProgram, "u_minValue");
    heatmap.uniformMaxValueLoc = glGetUniformLocation(heatmap.shaderProgram, "u_maxValue");
    heatmap.uniformAlphaLoc = glGetUniformLocation(heatmap.shaderProgram, "u_alpha");

    heatmap.resolution = resolution;
    const auto texelCount = static_cast<std::size_t>(resolution) * static_cast<std::size_t>(resolution);

    // --- Step 2: Create GL_R32F texture (single-channel float, bilinear filtered) ---
    glGenTextures(1, &heatmap.textureId);
    glBindTexture(GL_TEXTURE_2D, heatmap.textureId);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R32F, resolution, resolution, 0, GL_RED, GL_FLOAT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindTexture(GL_TEXTURE_2D, 0);

    if (GLenum glErr = glGetError(); glErr != GL_NO_ERROR)
    {
        std::fprintf(stderr, "DensityHeatmap: glTexImage2D error: 0x%x\n", glErr);
        glDeleteTextures(1, &heatmap.textureId);
        heatmap.textureId = 0U;
        glDeleteProgram(heatmap.shaderProgram);
        heatmap.shaderProgram = 0U;
        heatmap.uniformDensityTexLoc = -1;
        heatmap.uniformMinValueLoc = -1;
        heatmap.uniformMaxValueLoc = -1;
        heatmap.uniformAlphaLoc = -1;
        return std::unexpected(std::make_error_code(std::errc::io_error));
    }

    // --- Step 3: Register texture with CUDA for surface load/store (abort on failure) ---
    CUDA_CHECK(cudaGraphicsGLRegisterImage(
        &heatmap.cudaTexResource, heatmap.textureId, GL_TEXTURE_2D, cudaGraphicsRegisterFlagsSurfaceLoadStore));

    // --- Step 4: Allocate per-frame accumulation buffers on the device ---
    heatmap.accumBuffer.allocate(texelCount);
    heatmap.countBuffer.allocate(texelCount);
    heatmap.discardCountBuf.allocate(1);
    heatmap.rangeBuffer.allocate(2);

    // --- Step 5: Build fullscreen-quad VAO/VBO (6 vertices: 2 triangles, xy + uv) ---
    // clang-format off
    static constexpr float QUAD_VERTS[] = {
        -1.0F, -1.0F,  0.0F, 0.0F,
         1.0F, -1.0F,  1.0F, 0.0F,
         1.0F,  1.0F,  1.0F, 1.0F,
        -1.0F, -1.0F,  0.0F, 0.0F,
         1.0F,  1.0F,  1.0F, 1.0F,
        -1.0F,  1.0F,  0.0F, 1.0F,
    };
    // clang-format on

    glGenVertexArrays(1, &heatmap.quadVao);
    glGenBuffers(1, &heatmap.quadVbo);

    // CR-3: validate GL allocations before binding (fail-fast, avoid modifying VAO 0)
    if (heatmap.quadVao == 0U || heatmap.quadVbo == 0U)
    {
        destroyDensityHeatmap(heatmap);
        return std::unexpected(std::make_error_code(std::errc::io_error));
    }

    glBindVertexArray(heatmap.quadVao);
    glBindBuffer(GL_ARRAY_BUFFER, heatmap.quadVbo);
    glBufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(sizeof(QUAD_VERTS)), QUAD_VERTS, GL_STATIC_DRAW);

    // Attribute 0 — clip-space position (vec2)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * static_cast<GLsizei>(sizeof(float)), nullptr);
    glEnableVertexAttribArray(0);

    // Attribute 1 — texture UV (vec2)
    glVertexAttribPointer(
        1,
        2,
        GL_FLOAT,
        GL_FALSE,
        4 * static_cast<GLsizei>(sizeof(float)),
        reinterpret_cast<const void*>(2U * sizeof(float))); // NOLINT(cppcoreguidelines-pro-type-reinterpret-cast)
    glEnableVertexAttribArray(1);

    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArray(0);

    return {};
}

void updateDensityHeatmap(DensityHeatmap& heatmap, const GpuScalarFieldInput& input)
{
    constexpr float RANGE_EPSILON = 1.0e-5F;

    if (!heatmap.enabled || heatmap.textureId == 0U)
    {
        return;
    }

    if (input.particleCount > 0U && (input.posX == nullptr || input.posY == nullptr || input.scalarValues == nullptr))
    {
        std::fprintf(
            stderr, "updateDensityHeatmap: null device pointer with particleCount = %u\n", input.particleCount);
        std::abort();
    }

    if (input.domainMax.x <= input.domainMin.x || input.domainMax.y <= input.domainMin.y)
    {
        std::fprintf(stderr,
                     "updateDensityHeatmap: invalid domain bounds (min=(%f,%f), max=(%f,%f))\n",
                     input.domainMin.x,
                     input.domainMin.y,
                     input.domainMax.x,
                     input.domainMax.y);
        std::abort();
    }

    const uint32_t uRes = static_cast<uint32_t>(heatmap.resolution);
    const uint32_t totalTexels = uRes * uRes; // EP-1: uint32_t to avoid signed int overflow UB

    constexpr uint32_t BLOCK_1D = 256U;

    if (input.overrideRange)
    {
        heatmap.computedMin = input.minValue;
        heatmap.computedMax = (input.maxValue <= input.minValue) ? (input.minValue + RANGE_EPSILON) : input.maxValue;
    }
    else if (input.particleCount > 0U)
    {
        float initRange[2] = {FLT_MAX, -FLT_MAX};
        CUDA_CHECK(cudaMemcpy(heatmap.rangeBuffer.get(), initRange, 2U * sizeof(float), cudaMemcpyHostToDevice));

        const uint32_t gridReduce = (input.particleCount + BLOCK_1D - 1U) / BLOCK_1D;
        const uint32_t sharedMemBytes = 2U * BLOCK_1D * static_cast<uint32_t>(sizeof(float));
        minMaxReductionKernel<<<gridReduce, BLOCK_1D, sharedMemBytes>>>(
            input.scalarValues, input.particleCount, heatmap.rangeBuffer.get(), heatmap.rangeBuffer.get() + 1);
        CUDA_CHECK(cudaGetLastError());

        float hostRange[2] = {0.0F, 1.0F};
        CUDA_CHECK(cudaMemcpy(hostRange, heatmap.rangeBuffer.get(), 2U * sizeof(float), cudaMemcpyDeviceToHost));
        heatmap.computedMin = hostRange[0];
        heatmap.computedMax = (hostRange[1] <= hostRange[0]) ? (hostRange[0] + RANGE_EPSILON) : hostRange[1];
    }
    else
    {
        heatmap.computedMin = 0.0F;
        heatmap.computedMax = 1.0F;
    }

    // --- Pass 1: clear accumulator and reset discard counter ---
    CUDA_CHECK(cudaMemset(heatmap.discardCountBuf.get(), 0, sizeof(uint32_t)));
    clearAccumKernel<<<(totalTexels + BLOCK_1D - 1U) / BLOCK_1D, BLOCK_1D>>>(
        heatmap.accumBuffer.get(), heatmap.countBuffer.get(), totalTexels);
    CUDA_CHECK(cudaGetLastError());

    // --- Pass 2: scatter particle scalar values ---
    if (input.particleCount > 0U)
    {
        const uint32_t gridParticles = (input.particleCount + BLOCK_1D - 1U) / BLOCK_1D;
        scatterDensityKernel<<<gridParticles, BLOCK_1D>>>(input.posX,
                                                          input.posY,
                                                          input.scalarValues,
                                                          heatmap.accumBuffer.get(),
                                                          heatmap.countBuffer.get(),
                                                          input.domainMin,
                                                          input.domainMax,
                                                          static_cast<int>(uRes),
                                                          input.particleCount,
                                                          heatmap.discardCountBuf.get());
        CUDA_CHECK(cudaGetLastError());
    }

    // --- Pass 3: map CUDA resource, create surface object, write texture ---
    CUDA_CHECK(cudaGraphicsMapResources(1, &heatmap.cudaTexResource, nullptr));

    cudaArray_t texArray = nullptr;
    CUDA_CHECK(cudaGraphicsSubResourceGetMappedArray(&texArray, heatmap.cudaTexResource, 0, 0));

    cudaResourceDesc resDesc{};
    resDesc.resType = cudaResourceTypeArray;
    resDesc.res.array.array = texArray;

    cudaSurfaceObject_t surfObj = 0;
    CUDA_CHECK(cudaCreateSurfaceObject(&surfObj, &resDesc));

    const auto uRes16 = static_cast<unsigned int>((static_cast<int>(uRes) + 15) / 16);
    dim3 block2d(16, 16);
    dim3 grid2d(uRes16, uRes16);
    writeTextureKernel<<<grid2d, block2d>>>(heatmap.accumBuffer.get(), heatmap.countBuffer.get(), surfObj, uRes);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());

    uint32_t hostDiscards = 0U;
    CUDA_CHECK(cudaMemcpy(&hostDiscards, heatmap.discardCountBuf.get(), sizeof(uint32_t), cudaMemcpyDeviceToHost));
    if (hostDiscards > 0U)
    {
        std::fprintf(stderr,
                     "DensityHeatmap: %u/%u particle(s) out of domain and discarded [frame update]\n",
                     hostDiscards,
                     input.particleCount);
    }

    CUDA_CHECK(cudaDestroySurfaceObject(surfObj));
    CUDA_CHECK(cudaGraphicsUnmapResources(1, &heatmap.cudaTexResource, nullptr));
}

void renderDensityHeatmap(const DensityHeatmap& heatmap)
{
    if (!heatmap.enabled || heatmap.textureId == 0U || heatmap.shaderProgram == 0U)
    {
        return;
    }

    glUseProgram(heatmap.shaderProgram);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, heatmap.textureId);
    glUniform1i(heatmap.uniformDensityTexLoc, 0);
    glUniform1f(heatmap.uniformMinValueLoc, heatmap.computedMin);
    glUniform1f(heatmap.uniformMaxValueLoc, heatmap.computedMax);
    glUniform1f(heatmap.uniformAlphaLoc, heatmap.alpha);

    glBindVertexArray(heatmap.quadVao);
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glBindVertexArray(0);

    glBindTexture(GL_TEXTURE_2D, 0);
    glUseProgram(0);
}

void destroyDensityHeatmap(DensityHeatmap& heatmap)
{
    if (heatmap.cudaTexResource != nullptr)
    {
        cudaError_t unregErr = cudaGraphicsUnregisterResource(heatmap.cudaTexResource);
        // Silence context-teardown errors (runtime unloading or explicit context destroy);
        // these occur when destroy is called during process shutdown and are harmless.
        if (unregErr != cudaSuccess && unregErr != cudaErrorCudartUnloading && unregErr != cudaErrorContextIsDestroyed)
        {
            std::fprintf(
                stderr, "DensityHeatmap: cudaGraphicsUnregisterResource error: %s\n", cudaGetErrorString(unregErr));
        }
        heatmap.cudaTexResource = nullptr;
    }

    if (heatmap.textureId != 0U)
    {
        glDeleteTextures(1, &heatmap.textureId);
        heatmap.textureId = 0U;
    }

    if (heatmap.shaderProgram != 0U)
    {
        glDeleteProgram(heatmap.shaderProgram);
        heatmap.shaderProgram = 0U;
        heatmap.uniformDensityTexLoc = -1;
        heatmap.uniformMinValueLoc = -1;
        heatmap.uniformMaxValueLoc = -1;
        heatmap.uniformAlphaLoc = -1;
    }

    if (heatmap.quadVao != 0U)
    {
        glDeleteVertexArrays(1, &heatmap.quadVao);
        heatmap.quadVao = 0U;
    }

    if (heatmap.quadVbo != 0U)
    {
        glDeleteBuffers(1, &heatmap.quadVbo);
        heatmap.quadVbo = 0U;
    }

    heatmap.accumBuffer.free();
    heatmap.countBuffer.free();
    heatmap.discardCountBuf.free();
    heatmap.rangeBuffer.free();
    heatmap.computedMin = 0.0F;
    heatmap.computedMax = DensityHeatmap::DEFAULT_MAX_DENSITY;
}

} // namespace psim::rendering
