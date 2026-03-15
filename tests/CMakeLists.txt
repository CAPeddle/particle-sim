add_executable(particle_sim_tests
    unit/SmokeTest.cpp
    unit/core/BoundaryUtilsTest.cpp
    unit/core/ParameterTest.cpp
    unit/core/ISimulationModelTest.cpp
    unit/config/ConfigReaderTest.cpp
    unit/spatial/UniformGridIndexTest.cpp
    ${CMAKE_SOURCE_DIR}/src/config/ConfigReader.cpp
    ${CMAKE_SOURCE_DIR}/src/spatial/UniformGridIndex.cu
    ${CMAKE_SOURCE_DIR}/src/spatial/UniformGridIndexQueries.cpp
)

target_link_libraries(particle_sim_tests PRIVATE
    gtest_main
    gmock
    toml11::toml11
    CUDA::cudart_static
)

set_target_properties(particle_sim_tests PROPERTIES
    CUDA_SEPARABLE_COMPILATION ON
    LINKER_LANGUAGE CUDA
)

target_include_directories(particle_sim_tests PRIVATE
    ${CMAKE_SOURCE_DIR}/src
)

target_compile_definitions(particle_sim_tests PRIVATE
    FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures"
)

target_compile_options(particle_sim_tests PRIVATE
    $<$<COMPILE_LANGUAGE:CXX>:-Wall -Wextra -Wpedantic -Wshadow -Wconversion>
    $<$<COMPILE_LANGUAGE:CUDA>:--expt-relaxed-constexpr>
    $<$<COMPILE_LANGUAGE:CUDA>:-allow-unsupported-compiler>
)

include(GoogleTest)
gtest_discover_tests(particle_sim_tests)

# ============================================================================
# GPU integration tests (separate executable -- requires a CUDA device)
# ============================================================================

add_executable(particle_sim_gpu_tests
    gpu/core/BoundaryTest.cu
    gpu/spatial/UniformGridIndexGpuTest.cpp
    gpu/models/SphKernelsTest.cu
    gpu/models/FluidDensityTest.cu
    ${CMAKE_SOURCE_DIR}/src/spatial/UniformGridIndex.cu
    ${CMAKE_SOURCE_DIR}/src/spatial/UniformGridIndexQueries.cpp
    ${CMAKE_SOURCE_DIR}/src/models/FluidSPHModel.cu
    ${CMAKE_SOURCE_DIR}/src/models/FluidSPHModelOps.cpp
)

set_target_properties(particle_sim_gpu_tests PROPERTIES
    CUDA_SEPARABLE_COMPILATION ON
    LINKER_LANGUAGE CUDA
)

target_link_libraries(particle_sim_gpu_tests PRIVATE
    gtest_main
    gmock
    CUDA::cudart_static
)

target_include_directories(particle_sim_gpu_tests PRIVATE
    ${CMAKE_SOURCE_DIR}/src
)

target_compile_options(particle_sim_gpu_tests PRIVATE
    $<$<COMPILE_LANGUAGE:CUDA>:--expt-relaxed-constexpr>
    $<$<COMPILE_LANGUAGE:CUDA>:-allow-unsupported-compiler>
)

gtest_discover_tests(particle_sim_gpu_tests
    PROPERTIES LABELS "gpu"
)
