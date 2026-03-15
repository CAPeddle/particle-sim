#pragma once

#include <cstdint>

namespace psim::core
{

/// @brief Boundary handling mode for particle domain edges.
///
/// Passed to boundary kernels at runtime — allows mode switching via
/// configuration or ImGui without recompilation.
enum class BoundaryMode : int
{
    /// Particle wraps to the opposite edge (current swirl demo behaviour).
    Wrap = 0,
    /// Particle velocity is reflected and scaled by damping; position is clamped.
    Reflect = 1,
};

/// @brief Maximum neighbours tracked per particle.
///
/// Shared canonical constant used by spatial index queries and SPH pressure/
/// viscosity passes. Increase if profiling shows truncation at high densities.
inline constexpr std::uint32_t MAX_NEIGHBOURS = 64U;

/// @brief Maximum number of particles supported by the simulation.
///
/// Used to size statically-declared device arrays and validate config values.
inline constexpr std::uint32_t MAX_PARTICLES = 1'000'000U;

} // namespace psim::core
