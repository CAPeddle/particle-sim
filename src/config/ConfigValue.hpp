#pragma once

#include "core/Parameter.hpp"

namespace psim::config
{

/// @brief Concept restricting ConfigReader::get<T>() to supported C++ types.
///
/// The supported set is a superset of psim::core::ParameterValue:
/// - float       — TOML floating-point
/// - int         — TOML integer (narrowing cast from int64_t)
/// - bool        — TOML boolean
/// - std::string — TOML string
///
/// Attempting to instantiate get<T>() with an unsupported type produces a
/// clear compile-time error via the concept constraint.
template <typename T>
concept ConfigValue = psim::core::ParameterValue<T>;

} // namespace psim::config
