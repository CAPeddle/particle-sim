#pragma once

#include "config/ConfigError.hpp"
#include "config/ConfigReader.hpp"
#include "core/Parameter.hpp"

#include <expected>
#include <string_view>

namespace psim::config
{

/// @brief Populate a Parameter<T> value field from a TOML config entry.
///
/// @details
/// Reads the value at [section].key from the given ConfigReader and writes it
/// into param.value. All other Parameter fields (minValue, maxValue, step,
/// name, description) are left unchanged, so models can declare their
/// parameter metadata once and let the config system fill in the current value
/// at startup without touching any metadata.
///
/// Returns ConfigError (without modifying param) if the key is absent or
/// has an incompatible TOML type.
///
/// @tparam T  Must satisfy psim::core::ParameterValue.
///
/// @param reader  A loaded ConfigReader. Behaviour is undefined if
///                reader.isLoaded() == false.
/// @param section Top-level TOML table name (dot-notation supported).
/// @param key     Key within that table.
/// @param param   Output parameter whose value field is updated on success.
///
/// @return std::expected<void, ConfigError> — error does not modify param.
///
/// @pre reader.isLoaded() == true.
template <psim::core::ParameterValue T>
[[nodiscard]] std::expected<void, ConfigError> loadParameter(const ConfigReader& reader,
                                                             std::string_view section,
                                                             std::string_view key,
                                                             psim::core::Parameter<T>& param)
{
    auto result = reader.get<T>(section, key);
    if (!result)
    {
        return std::unexpected(result.error());
    }
    param.value = *std::move(result);
    return {};
}

} // namespace psim::config
