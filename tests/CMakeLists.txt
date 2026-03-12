add_executable(particle_sim_tests
    unit/SmokeTest.cpp
    unit/core/ParameterTest.cpp
    unit/core/ISimulationModelTest.cpp
)

target_link_libraries(particle_sim_tests PRIVATE
    gtest_main
    gmock
)

target_include_directories(particle_sim_tests PRIVATE
    ${CMAKE_SOURCE_DIR}/src
)

target_compile_options(particle_sim_tests PRIVATE
    $<$<COMPILE_LANGUAGE:CXX>:-Wall -Wextra -Wpedantic -Wshadow -Wconversion>
)

include(GoogleTest)
gtest_discover_tests(particle_sim_tests)
