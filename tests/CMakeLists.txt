# ==============================================================================
# CPU unit tests (no GPU code)
# ==============================================================================
add_executable(
    particle_sim_tests
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

target_link_libraries(particle_sim_tests PRIVATE gtest_main gmock toml11::toml11 CUDA::cudart_static)

# Keep linker language as CXX while allowing CUDA object files in the executable.
# This prevents nvcc from being forced on all files.
set_target_properties(
    particle_sim_tests
    PROPERTIES CUDA_SEPARABLE_COMPILATION ON LINKER_LANGUAGE CXX
)

target_include_directories(particle_sim_tests PRIVATE ${CMAKE_SOURCE_DIR}/src)

target_compile_definitions(
    particle_sim_tests
    PRIVATE FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures"
)

# Compiler warnings (C/C++ only, not CUDA)
if(MSVC)
    target_compile_options(particle_sim_tests PRIVATE $<$<COMPILE_LANGUAGE:CXX>:/W4>)
else()
    target_compile_options(particle_sim_tests PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-Wall -Wextra -Wpedantic -Wshadow -Wconversion>)
endif()

# CUDA-specific flags
target_compile_options(
    particle_sim_tests
    PRIVATE
        $<$<COMPILE_LANGUAGE:CUDA>:--expt-relaxed-constexpr>
        $<$<COMPILE_LANGUAGE:CUDA>:-allow-unsupported-compiler>
)

include(GoogleTest)
if(WIN32)
    # On Windows, all three UniformGridIndexTest EXPECT_DEATH constructor tests can
    # hang under ctest/gtest_discover_tests process orchestration. Exclude all three
    # from default CTest discovery to prevent the suite from blocking.
    gtest_discover_tests(
        particle_sim_tests
        DISCOVERY_MODE PRE_TEST
        TEST_FILTER
            "-UniformGridIndexTest.Constructor_ZeroCellSize_Aborts:UniformGridIndexTest.Constructor_NegativeCellSize_Aborts:UniformGridIndexTest.Constructor_InvertedDomain_Aborts"
    )

    # Combined workaround target for all three excluded death tests.
    # Execute directly via gtest binary rather than through ctest to avoid the hang.
    add_custom_target(
        run_uniform_grid_death_tests
        COMMAND
            $<TARGET_FILE:particle_sim_tests>
            --gtest_filter=UniformGridIndexTest.Constructor_ZeroCellSize_Aborts:UniformGridIndexTest.Constructor_NegativeCellSize_Aborts:UniformGridIndexTest.Constructor_InvertedDomain_Aborts
            --gtest_color=yes
        DEPENDS particle_sim_tests
        WORKING_DIRECTORY $<TARGET_FILE_DIR:particle_sim_tests>
        USES_TERMINAL
        COMMENT "Running all three excluded Windows death tests directly (no ctest)"
    )
else()
    gtest_discover_tests(particle_sim_tests)
endif()

# ==============================================================================
# GPU integration tests (separate executable -- requires a CUDA device  )
# ==============================================================================

add_executable(
    particle_sim_gpu_tests
    gpu/core/BoundaryTest.cu
    gpu/spatial/UniformGridIndexGpuTest.cpp
    gpu/models/SphKernelsTest.cu
    gpu/models/FluidDensityTest.cu
    unit/rendering/DensityHeatmapTest.cpp
    ${CMAKE_SOURCE_DIR}/src/spatial/UniformGridIndex.cu
    ${CMAKE_SOURCE_DIR}/src/spatial/UniformGridIndexQueries.cpp
    ${CMAKE_SOURCE_DIR}/src/models/FluidSPHModel.cu
    ${CMAKE_SOURCE_DIR}/src/models/FluidSPHModelOps.cpp
    ${CMAKE_SOURCE_DIR}/src/rendering/DensityHeatmap.cu
)

set_target_properties(
    particle_sim_gpu_tests
    PROPERTIES CUDA_SEPARABLE_COMPILATION ON LINKER_LANGUAGE CXX
)

target_link_libraries(
    particle_sim_gpu_tests
    PRIVATE gtest_main gmock CUDA::cudart_static OpenGL::GL glfw glad_gl46
)

target_include_directories(
    particle_sim_gpu_tests
    PRIVATE ${CMAKE_SOURCE_DIR}/src ${CMAKE_SOURCE_DIR}/tests
)

target_compile_definitions(
    particle_sim_gpu_tests
    PRIVATE SHADER_DIR="${CMAKE_SOURCE_DIR}/shaders"
)

# Compiler warnings (C/C++ only, not CUDA)
if(MSVC)
    target_compile_options(particle_sim_gpu_tests PRIVATE $<$<COMPILE_LANGUAGE:CXX>:/W4>)
else()
    target_compile_options(particle_sim_gpu_tests PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-Wall -Wextra -Wpedantic -Wshadow -Wconversion>)
endif()

# CUDA-specific flags
target_compile_options(
    particle_sim_gpu_tests
    PRIVATE
        $<$<COMPILE_LANGUAGE:CUDA>:--expt-relaxed-constexpr>
        $<$<COMPILE_LANGUAGE:CUDA>:-allow-unsupported-compiler>
)

gtest_discover_tests(particle_sim_gpu_tests PROPERTIES LABELS "gpu")

# ==============================================================================
# Sanitizer flags for test executables
# ENABLE_SANITIZERS and SANITIZER_* variables are set in the root CMakeLists.txt.
# CXX-only guard ensures flags never reach nvcc device compilation.
# ==============================================================================
if(ENABLE_SANITIZERS)
    foreach(test_target particle_sim_tests particle_sim_gpu_tests)
        target_compile_options(${test_target} PRIVATE
            $<$<COMPILE_LANGUAGE:CXX>:${SANITIZER_COMPILE_FLAGS}>
        )
        target_link_options(${test_target} PRIVATE ${SANITIZER_LINK_FLAGS})
    endforeach()
endif()
