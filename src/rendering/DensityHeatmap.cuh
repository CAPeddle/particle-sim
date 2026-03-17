#pragma once

#include "core/CudaUtils.hpp"
#include "rendering/GpuScalarFieldInput.cuh"

// NOLINT(misc-include-cleaner): cuda_runtime.h is required for cudaGraphicsResource;
// include-cleaner cannot trace the type to this TU because CudaUtils.hpp provides
// the header transitively, yet the type is used directly in this struct.
#include <cassert>
#include <cuda_runtime.h> // NOLINT(misc-include-cleaner)
#include <expected>       // NOLINT(misc-include-cleaner) — used by initDensityHeatmap return type
#include <string_view>
#include <system_error> // NOLINT(misc-include-cleaner) — used by initDensityHeatmap return type

namespace psim::rendering
{

/// @brief Toggleable SPH density heatmap overlay.
///
/// Renders the per-particle density field as a fullscreen colour quad behind
/// the particle layer (blue = low density → red = high density). Intended as
/// a debug/validation tool for SPH physics; off by default.
///
/// **Lifecycle:** Call `initDensityHeatmap` once after the GL + CUDA context
/// exists; call `destroyDensityHeatmap` before the context is torn down.
/// Update and rendering are driven each frame by `updateDensityHeatmap` and
/// `renderDensityHeatmap`.
///
/// **Scalar mapping:** Each particle's pre-computed `scalarValues[]` value is
/// scattered (splatted) into the texel that covers its world-space position.
/// Multiple particles in the same texel are averaged.
///
/// **Normalisation strategy:**
/// - `overrideRange == true`: uses caller-provided `minValue`/`maxValue`
///   (typically from UI controls).
/// - `overrideRange == false`: auto-computes min/max from input scalar data
///   each frame via a device reduction.
///
/// The resolved range is stored in `computedMin` / `computedMax` and uploaded
/// by `renderDensityHeatmap` as shader uniforms.
///
/// @note Thread-safety: not thread-safe. All calls must be made from the
///       thread owning the GL + CUDA device context.
/// @note Destructor asserts `textureId == 0` in Debug builds; always call
///       `destroyDensityHeatmap` before the object goes out of scope.
struct DensityHeatmap
{
    // NOLINTBEGIN(misc-non-private-member-variables-in-classes)

    /// @brief Default heatmap texture resolution (width == height), in texels.
    static constexpr int DEFAULT_RESOLUTION = 256;
    /// @brief Default max-density reference value (maps to full red).
    static constexpr float DEFAULT_MAX_DENSITY = 100.0F;
    /// @brief Default overlay alpha (0 = fully transparent, 1 = opaque).
    static constexpr float DEFAULT_ALPHA = 0.85F;

    unsigned int textureId{0};                      ///< OpenGL GL_TEXTURE_2D handle (GL_R32F).
    cudaGraphicsResource* cudaTexResource{nullptr}; // NOLINT(misc-include-cleaner) — type from cuda_runtime.h above
    ///< CUDA-GL interop registration.
    unsigned int shaderProgram{0};      ///< Compiled heatmap GLSL program.
    unsigned int quadVao{0};            ///< VAO for the fullscreen quad.
    unsigned int quadVbo{0};            ///< VBO for the fullscreen quad vertices.
    int resolution{DEFAULT_RESOLUTION}; ///< Texture width == height in texels.
    bool enabled{false};                ///< Render heatmap this frame when true.
    float defaultMaxValue{DEFAULT_MAX_DENSITY};
    ///< User-facing default upper reference value (e.g. UI slider).

    // Per-frame accumulation buffers — pre-allocated to resolution² at init
    psim::core::CudaBuffer<float> accumBuffer;        ///< Per-texel density sum [resolution²].
    psim::core::CudaBuffer<int> countBuffer;          ///< Per-texel particle count [resolution²].
    psim::core::CudaBuffer<uint32_t> discardCountBuf; ///< Per-frame discard counter [1 element].

    int uniformDensityTexLoc{-1};              ///< Cached location of u_densityTex uniform.
    int uniformMinValueLoc{-1};                ///< Cached location of u_minValue uniform.
    int uniformMaxValueLoc{-1};                ///< Cached location of u_maxValue uniform.
    int uniformAlphaLoc{-1};                   ///< Cached location of u_alpha uniform.
    float alpha{DEFAULT_ALPHA};                ///< Overlay transparency (0 = fully transparent, 1 = opaque).
    float computedMin{0.0F};                   ///< Effective lower normalisation bound for current frame.
    float computedMax{DEFAULT_MAX_DENSITY};    ///< Effective upper normalisation bound for current frame.
    psim::core::CudaBuffer<float> rangeBuffer; ///< 2-element device buffer: [0]=min, [1]=max.

    // NOLINTEND(misc-non-private-member-variables-in-classes)

    // Rule of Five — non-copyable, non-movable: raw GL + CUDA handles require
    // explicit init/destroy; move would leave source with dangling handles.
    DensityHeatmap() = default;
    ~DensityHeatmap()
    {
        // Debug guard: GL + CUDA resources must have been explicitly released
        // via destroyDensityHeatmap() before this object is destroyed.
        assert(textureId == 0U && "DensityHeatmap destroyed without calling destroyDensityHeatmap");
    }
    DensityHeatmap(const DensityHeatmap&) = delete;
    DensityHeatmap& operator=(const DensityHeatmap&) = delete;
    DensityHeatmap(DensityHeatmap&&) = delete;
    DensityHeatmap& operator=(DensityHeatmap&&) = delete;
};

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// @brief Creates GL texture, registers with CUDA, compiles shaders, builds VAO/VBO.
///
/// @param heatmap    Target struct. Must not be already initialised (textureId == 0).
/// @param resolution Texture width and height in texels. Must be > 0.
/// @param vertPath   Path to `heatmap.vert` vertex shader source file.
/// @param fragPath   Path to `heatmap.frag` fragment shader source file.
///
/// @return `std::expected<void, std::error_code>` — error if resolution <= 0, any GL
///         resource creation fails, or shader compilation/linking fails. CUDA
///         registration failures call `std::abort()` via `CUDA_CHECK` (unrecoverable).
///
/// @pre An active OpenGL 4.6 + CUDA context exists on the calling thread.
/// @pre heatmap.textureId == 0.
/// @pre resolution <= 4096.
/// @post On success: heatmap.textureId != 0, shaderProgram != 0, quadVao != 0, quadVbo != 0.
/// @post On error: all partially-created resources are released; heatmap is back to default state.
[[nodiscard]] std::expected<void, std::error_code> initDensityHeatmap(DensityHeatmap& heatmap,
                                                                      int resolution,
                                                                      std::string_view vertPath,
                                                                      std::string_view fragPath);

/// @brief Scatters per-particle scalar values into the heatmap texture and resolves
///        the normalisation range.
///
/// Each particle's `scalarValues[]` value is accumulated into the texel covering
/// its position; texels with multiple particles are averaged. Runs three CUDA
/// kernel passes: clear → [optional min/max reduction] → scatter → write-to-surface.
/// Writes `computedMin` / `computedMax` for use by `renderDensityHeatmap`.
///
/// @param heatmap  Initialised heatmap; no-op if `enabled == false`.
/// @param input    Non-owning view of device particle data and normalisation hints.
///
/// @pre initDensityHeatmap has been called on `heatmap`.
/// @pre input.particleCount == 0 OR (input.posX, input.posY, input.scalarValues are all non-null).
/// @pre input.domainMax.x > input.domainMin.x and input.domainMax.y > input.domainMin.y.
/// @note input.particleCount == 0 is valid; the scatter pass is a no-op.
void updateDensityHeatmap(DensityHeatmap& heatmap, const GpuScalarFieldInput& input);

/// @brief Draws the fullscreen quad textured with the last density update.
///
/// Must be called after `updateDensityHeatmap` and before the particle layer
/// so it renders as a background.
///
/// @param heatmap    Initialised heatmap; no-op if `enabled == false`.
///
/// @pre initDensityHeatmap has been called on `heatmap`.
void renderDensityHeatmap(const DensityHeatmap& heatmap);

/// @brief Releases all GL and CUDA resources owned by the heatmap.
///
/// Safe to call on a default-constructed or already-destroyed heatmap.
/// Resets `textureId` to 0.
///
/// @pre GL + CUDA context must still be current (resources require context to free).
/// @post heatmap.textureId == 0.
/// @post computedMin/computedMax are reset to defaults.
void destroyDensityHeatmap(DensityHeatmap& heatmap);

} // namespace psim::rendering
