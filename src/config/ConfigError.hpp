#pragma once

#include <string>

namespace psim::config
{

/// @brief Error type returned by ConfigReader operations.
///
/// @details
/// Used as the error payload in std::expected<T, ConfigError> returns.
/// Contains a human-readable description of the failure.
struct ConfigError
{
    std::string message; ///< Human-readable error description.
};

} // namespace psim::config
