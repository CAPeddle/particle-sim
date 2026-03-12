#pragma once

#include <concepts>
#include <string_view>
#include <variant>

namespace psim::core
{

/// @brief Concept restricting Parameter<T> to types renderable by ImGui.
///
/// Only float (slider/drag), int (slider/drag), and bool (checkbox) are
/// supported. Using any other type produces a clear compile-time error.
template <typename T>
concept ParameterValue = std::same_as<T, float> || std::same_as<T, int> || std::same_as<T, bool>;

/// @brief Runtime parameter with metadata for UI rendering and serialization.
///
/// @tparam T Value type — must satisfy ParameterValue (float, int, or bool).
///
/// @details
/// Models declare an array of these and return a non-owning span via
/// ISimulationModel::parameters(). The ImGui layer iterates the span and
/// renders each entry as an appropriate control (slider, drag, checkbox).
///
/// For bool parameters, minValue, maxValue, and step are structurally present
/// but semantically unused by the ImGui layer (it renders a checkbox instead).
///
/// @pre name and description must point to storage that outlives this struct
///      (typically string literals).
///
/// @note Thread-safety: Not thread-safe. Read/write only from the render thread.
template <ParameterValue T>
struct Parameter
{
    T value;                      ///< Current value.
    T minValue;                   ///< Minimum bound (slider range).
    T maxValue;                   ///< Maximum bound (slider range).
    T step;                       ///< Step size (drag control increment).
    std::string_view name;        ///< Display name shown in ImGui.
    std::string_view description; ///< Tooltip text shown on hover.
};

/// @brief Type-erased container for any Parameter<T>.
///
/// Allows heterogeneous collections of parameters without virtual dispatch.
/// Use std::visit to retrieve the concrete type.
///
/// @note Adding a new ParameterValue type requires extending this alias and
///       updating all std::visit callsites.
using ParameterEntry = std::variant<Parameter<float>, Parameter<int>, Parameter<bool>>;

} // namespace psim::core
