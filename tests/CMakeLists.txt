add_executable(particle_sim_tests
    unit/SmokeTest.cpp
    unit/core/ParameterTest.cpp
    unit/core/ISimulationModelTest.cpp
    unit/config/ConfigReaderTest.cpp
    ${CMAKE_SOURCE_DIR}/src/config/ConfigReader.cpp
)

target_link_libraries(particle_sim_tests PRIVATE
    gtest_main
    gmock
    toml11::toml11
)

target_include_directories(particle_sim_tests PRIVATE
    ${CMAKE_SOURCE_DIR}/src
)

target_compile_definitions(particle_sim_tests PRIVATE
    FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures"
)

target_compile_options(particle_sim_tests PRIVATE
    $<$<COMPILE_LANGUAGE:CXX>:-Wall -Wextra -Wpedantic -Wshadow -Wconversion>
)

include(GoogleTest)
gtest_discover_tests(particle_sim_tests)
