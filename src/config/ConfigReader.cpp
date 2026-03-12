// ConfigReader.cpp — the ONLY translation unit that includes <toml.hpp>.
// toml11 symbols do not propagate to any caller of ConfigReader.hpp.

#include "config/ConfigReader.hpp"

#include "config/ConfigError.hpp"
#include "config/ConfigValue.hpp"

#include <exception>
#include <expected>
#include <functional>
#include <memory>
#include <string>
#include <string_view>
#include <toml.hpp>

namespace psim::config
{

// ---------------------------------------------------------------------------
// Pimpl implementation struct
// ---------------------------------------------------------------------------

struct ConfigReader::Impl
{
    toml::value root; ///< Parsed TOML document.
    bool loaded{
        false}; // NOLINT(readability-redundant-member-init) — explicit false for cppcoreguidelines-pro-type-member-init
};

// ---------------------------------------------------------------------------
// Special member definitions (defined here where Impl is complete)
// ---------------------------------------------------------------------------

ConfigReader::ConfigReader()
    : impl{std::make_unique<Impl>()}
{
}

ConfigReader::~ConfigReader() = default;

ConfigReader::ConfigReader(ConfigReader&&) noexcept = default;

ConfigReader& ConfigReader::operator=(ConfigReader&&) noexcept = default;

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

namespace
{

/// @brief Navigate a dot-delimited section path and return the leaf table.
///
/// "framework"        → root["framework"]
/// "framework.window" → root["framework"]["window"]
///
/// @return ConfigError if any path component is absent or not a table.
[[nodiscard]] std::expected<std::reference_wrapper<const toml::value>, ConfigError> findSection(
    const toml::value& root, std::string_view section)
{
    std::reference_wrapper<const toml::value> current{root};
    std::string_view remaining = section;

    while (!remaining.empty())
    {
        const auto dot = remaining.find('.');
        const auto part = (dot == std::string_view::npos) ? remaining : remaining.substr(0, dot);
        remaining = (dot == std::string_view::npos) ? std::string_view{} : remaining.substr(dot + 1U);

        try
        {
            current = std::cref(toml::find(current.get(), std::string{part}));
        }
        catch (const std::exception& ex)
        {
            return std::unexpected(
                ConfigError{std::string{"Section not found: '"} + std::string{part} + "' — " + ex.what()});
        }
    }

    return current;
}

} // namespace

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

std::expected<void, ConfigError> ConfigReader::load(std::string_view path)
{
    try
    {
        impl->root = toml::parse(std::string{path});
        impl->loaded = true;
        return {};
    }
    catch (const std::exception& ex)
    {
        impl->loaded = false;
        return std::unexpected(ConfigError{ex.what()});
    }
}

bool ConfigReader::isLoaded() const noexcept
{
    return impl && impl->loaded;
}

// ---------------------------------------------------------------------------
// Template definitions (bodies visible only inside this TU)
// ---------------------------------------------------------------------------

template <ConfigValue T>
std::expected<T, ConfigError> ConfigReader::get(std::string_view section, std::string_view key) const
{
    if (!isLoaded())
    {
        return std::unexpected(ConfigError{"ConfigReader::get() called before successful load()"});
    }

    auto sectionResult = findSection(impl->root, section);
    if (!sectionResult)
    {
        return std::unexpected(sectionResult.error());
    }

    try
    {
        return toml::find<T>(sectionResult->get(), std::string{key});
    }
    catch (const std::exception& ex)
    {
        return std::unexpected(ConfigError{std::string{"Key '"} + std::string{key} + "' in section '" +
                                           std::string{section} + "': " + ex.what()});
    }
}

template <ConfigValue T>
T ConfigReader::getOrDefault(std::string_view section, std::string_view key, T defaultValue) const
{
    auto result = get<T>(section, key);
    if (result.has_value())
    {
        return *std::move(result);
    }
    return defaultValue;
}

// ---------------------------------------------------------------------------
// Explicit template instantiations
// ---------------------------------------------------------------------------

template std::expected<float, ConfigError> ConfigReader::get<float>(std::string_view, std::string_view) const;

template std::expected<int, ConfigError> ConfigReader::get<int>(std::string_view, std::string_view) const;

template std::expected<bool, ConfigError> ConfigReader::get<bool>(std::string_view, std::string_view) const;

template std::expected<std::string, ConfigError> ConfigReader::get<std::string>(std::string_view,
                                                                                std::string_view) const;

template float ConfigReader::getOrDefault<float>(std::string_view, std::string_view, float) const;

template int ConfigReader::getOrDefault<int>(std::string_view, std::string_view, int) const;

template bool ConfigReader::getOrDefault<bool>(std::string_view, std::string_view, bool) const;

template std::string ConfigReader::getOrDefault<std::string>(std::string_view, std::string_view, std::string) const;

} // namespace psim::config
