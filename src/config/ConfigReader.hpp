#pragma once

#include "config/ConfigError.hpp"
#include "config/ConfigValue.hpp"

#include <expected>
#include <memory>
#include <string>
#include <string_view>

namespace psim::config
{

/// @brief Loads and queries a TOML configuration file.
///
/// @details
/// All access is exception-free via std::expected<T, ConfigError>.
/// The parsed document is owned by this object; callers receive typed C++
/// values and never interact with toml11 types directly.
///
/// Template methods are explicitly instantiated for ConfigValue types
/// (float, int, bool, std::string) in ConfigReader.cpp. Instantiating with
/// any other type produces a linker error.
///
/// Dot-notation is supported in section names: "framework.window" navigates
/// to the nested TOML table [framework.window].
///
/// ### Isolation guarantee
/// toml11 headers are included only in ConfigReader.cpp. Including
/// ConfigReader.hpp never pulls in toml11 symbols.
///
/// @note ConfigReader is move-only (owns the Pimpl impl).
class ConfigReader
{
public:
    ConfigReader();
    ~ConfigReader();

    ConfigReader(const ConfigReader&) = delete;
    ConfigReader& operator=(const ConfigReader&) = delete;

    ConfigReader(ConfigReader&&) noexcept;
    ConfigReader& operator=(ConfigReader&&) noexcept;

    /// @brief Load and parse a TOML file from the filesystem.
    ///
    /// @param path Filesystem path to the .toml file (absolute or relative to cwd).
    ///
    /// @return std::expected<void, ConfigError> — ConfigError on file-not-found
    ///         or parse error. On success, the object transitions to loaded state.
    ///
    /// @post isLoaded() == true on success.
    [[nodiscard]] std::expected<void, ConfigError> load(std::string_view path);

    /// @brief Read a typed value from a two-level table.key path.
    ///
    /// @tparam T  Target C++ type — must satisfy ConfigValue.
    /// @param section  Top-level TOML table name. Supports dot-notation for
    ///                 nested tables (e.g. "framework.window").
    /// @param key      Key within that table.
    ///
    /// @return Value on success, ConfigError if the key is absent or the TOML
    ///         type is incompatible with T.
    ///
    /// @pre isLoaded() == true.
    template <ConfigValue T>
    [[nodiscard]] std::expected<T, ConfigError> get(std::string_view section, std::string_view key) const;

    /// @brief Read a typed value, returning a caller-supplied default if absent.
    ///
    /// @tparam T  Target C++ type — must satisfy ConfigValue.
    /// @param section      Top-level TOML table name (dot-notation supported).
    /// @param key          Key within that table.
    /// @param defaultValue Value returned when the key is absent or on any error.
    ///
    /// @pre isLoaded() == true.
    template <ConfigValue T>
    [[nodiscard]] T getOrDefault(std::string_view section, std::string_view key, T defaultValue) const;

    /// @brief Returns true after a successful load() call.
    [[nodiscard]] bool isLoaded() const noexcept;

private:
    struct Impl;
    std::unique_ptr<Impl> impl;
};

// ---------------------------------------------------------------------------
// Extern template declarations — suppress implicit instantiation in all TUs.
// Explicit instantiations live in ConfigReader.cpp.
// ---------------------------------------------------------------------------

extern template std::expected<float, ConfigError> ConfigReader::get<float>(std::string_view, std::string_view) const;

extern template std::expected<int, ConfigError> ConfigReader::get<int>(std::string_view, std::string_view) const;

extern template std::expected<bool, ConfigError> ConfigReader::get<bool>(std::string_view, std::string_view) const;

extern template std::expected<std::string, ConfigError> ConfigReader::get<std::string>(std::string_view,
                                                                                       std::string_view) const;

extern template float ConfigReader::getOrDefault<float>(std::string_view, std::string_view, float) const;

extern template int ConfigReader::getOrDefault<int>(std::string_view, std::string_view, int) const;

extern template bool ConfigReader::getOrDefault<bool>(std::string_view, std::string_view, bool) const;

extern template std::string ConfigReader::getOrDefault<std::string>(std::string_view,
                                                                    std::string_view,
                                                                    std::string) const;

} // namespace psim::config
