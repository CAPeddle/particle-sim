#pragma once

#include "core/Parameter.hpp"

#include <cstdint>
#include <span>
#include <string_view>

namespace psim::core
{

/// @brief Abstract interface for simulation models.
///
/// Each simulation model (SPH fluid, Game of Life, etc.) implements this
/// interface. The framework calls init() once at startup, update() each frame,
/// and destroy() on shutdown or model swap.
///
/// @details
/// ### Lifecycle
/// - init()    → update() [0..N] → destroy()
/// - destroy() must leave the model in a state where init() may be called again.
///
/// ### Parameter System
/// Models declare their runtime parameters via parameters(). The ImGui layer
/// iterates the returned span and auto-generates controls (sliders, checkboxes).
///
/// ### Strategy Pattern
/// ISimulationModel is the strategy interface. Concrete models are the
/// strategies. The Application holds a pointer to the active strategy and calls
/// through this interface without knowing the concrete type.
///
/// @pre All methods must be called from the render/simulation thread.
///
/// @note Thread-safety: Not thread-safe. All methods must be called from the
///       render/simulation thread.
class ISimulationModel
{
public:
    virtual ~ISimulationModel() = default;

    ISimulationModel(const ISimulationModel&) = delete;
    ISimulationModel& operator=(const ISimulationModel&) = delete;
    ISimulationModel(ISimulationModel&&) = default;
    ISimulationModel& operator=(ISimulationModel&&) = default;

    /// @brief Initialize the model (allocate GPU memory, set up initial state).
    ///
    /// @param particleCount Number of particles to allocate. Must be > 0.
    ///
    /// @return true on success, false on failure (e.g. GPU out of memory).
    ///
    /// @pre particleCount > 0
    /// @post On success, model is ready for update() calls.
    [[nodiscard]] virtual bool init(std::uint32_t particleCount) = 0;

    /// @brief Advance the simulation by one time step.
    ///
    /// @param deltaTime Delta time in seconds. Must be > 0.
    ///
    /// @pre init() returned true.
    /// @pre deltaTime > 0.0f
    virtual void update(float deltaTime) = 0;

    /// @brief Release all resources (GPU memory, OpenGL buffers).
    ///
    /// @post Model is in an uninitialized state. init() may be called again.
    virtual void destroy() = 0;

    /// @brief Returns a non-owning view of this model's runtime parameters.
    ///
    /// @return Span over parameter entries owned by the model.
    ///         Valid for the lifetime of this model instance.
    ///
    /// @note The span is invalidated if the model is destroyed.
    [[nodiscard]] virtual std::span<const ParameterEntry> parameters() const = 0;

    /// @brief Returns the display name of this model (e.g. "SPH Fluid").
    ///
    /// @return Non-owning view of a static string literal.
    [[nodiscard]] virtual std::string_view name() const = 0;

protected:
    ISimulationModel() = default;
};

} // namespace psim::core
