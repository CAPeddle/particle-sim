# CMake 3.29+ is required: earlier versions hardcode sm_52 in the CUDA
# compiler-ID probe, which CUDA 13.2 removed from ptxas.  3.29.0 was the
# first release to honour CMAKE_CUDA_ARCHITECTURES during the probe.
cmake_minimum_required(VERSION 3.29)

# Allow unsupported compiler for CUDA (VS 2026 not yet officially supported)
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -allow-unsupported-compiler")

# RTX 4050 Laptop = Ada Lovelace = SM 89
# Must be set BEFORE project() so CMake 3.29+'s CUDA compiler-ID probe uses
# this architecture instead of any baseline default.
set(CMAKE_CUDA_ARCHITECTURES 89)

project(particle_sim LANGUAGES C CXX CUDA)

# C++ and CUDA standards
# CMAKE_CXX_STANDARD 23 enables full C++23 for all .cpp TUs (g++ / clang++).
# CMAKE_CUDA_STANDARD 20 is the maximum nvcc 13.2 accepts via --std; device code
# is therefore C++20.  To enable C++23 host features (std::expected, std::string_view
# etc.) inside .cu TUs, we additionally pass -Xcompiler=-std=c++23 which overrides
# the host-compiler invocation that nvcc generates from its own --std=c++20.
# Because GCC uses the last -std flag on the command line, c++23 wins for host code.
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 20)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)
if(MSVC)
    set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -Xcompiler=/std:c++latest")
else()
    set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -Xcompiler=-std=c++23")
endif()

# Export compile commands for IDE support
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Find required packages
find_package(OpenGL REQUIRED)
find_package(CUDAToolkit REQUIRED)

include(FetchContent)

# ============================================================================
# GLFW
# ============================================================================
set(GLFW_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GLFW_INSTALL OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
    glfw
    GIT_REPOSITORY https://github.com/glfw/glfw.git
    GIT_TAG        3.4
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(glfw)

# ============================================================================
# GLAD (OpenGL loader)
# ============================================================================
FetchContent_Declare(
    glad
    GIT_REPOSITORY https://github.com/Dav1dde/glad.git
    GIT_TAG        v2.0.8
    GIT_SHALLOW    TRUE
    SOURCE_SUBDIR  cmake
)
FetchContent_MakeAvailable(glad)

# Generate GLAD for OpenGL 4.6 Core
glad_add_library(glad_gl46 STATIC REPRODUCIBLE API gl:core=4.6)

# ============================================================================
# Dear ImGui
# ============================================================================
FetchContent_Declare(
    imgui
    GIT_REPOSITORY https://github.com/ocornut/imgui.git
    GIT_TAG        v1.91.6
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(imgui)

# ImGui doesn't have CMake support, so we create a library manually
add_library(imgui STATIC
    ${imgui_SOURCE_DIR}/imgui.cpp
    ${imgui_SOURCE_DIR}/imgui_demo.cpp
    ${imgui_SOURCE_DIR}/imgui_draw.cpp
    ${imgui_SOURCE_DIR}/imgui_tables.cpp
    ${imgui_SOURCE_DIR}/imgui_widgets.cpp
    # GLFW + OpenGL3 backends
    ${imgui_SOURCE_DIR}/backends/imgui_impl_glfw.cpp
    ${imgui_SOURCE_DIR}/backends/imgui_impl_opengl3.cpp
)

target_include_directories(imgui PUBLIC
    ${imgui_SOURCE_DIR}
    ${imgui_SOURCE_DIR}/backends
)

target_link_libraries(imgui PUBLIC
    glfw
    glad_gl46
    OpenGL::GL
)

# ============================================================================
# toml11 (TOML config parsing)
# ============================================================================
FetchContent_Declare(
    toml11
    GIT_REPOSITORY https://github.com/ToruNiina/toml11.git
    GIT_TAG        v4.4.0
    GIT_SHALLOW    TRUE
)
set(TOML11_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
set(TOML11_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(toml11)

if(MSVC AND TARGET toml11)
    get_target_property(toml11InterfaceOptions toml11 INTERFACE_COMPILE_OPTIONS)
    if(toml11InterfaceOptions)
        set(filteredToml11InterfaceOptions "")
        foreach(option IN LISTS toml11InterfaceOptions)
            if(option STREQUAL "/utf-8" OR option STREQUAL "/Zc:preprocessor" OR option STREQUAL "/experimental:preprocessor")
                list(APPEND filteredToml11InterfaceOptions "$<$<COMPILE_LANGUAGE:CXX>:${option}>")
            else()
                list(APPEND filteredToml11InterfaceOptions "${option}")
            endif()
        endforeach()
        set_property(TARGET toml11 PROPERTY INTERFACE_COMPILE_OPTIONS "${filteredToml11InterfaceOptions}")
    endif()
endif()

# ============================================================================
# GoogleTest
# ============================================================================
FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        v1.15.2
    GIT_SHALLOW    TRUE
)
# Suppress GoogleTest's own install rules
set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

# ============================================================================
# Sanitizers
# ============================================================================
# Enable with: cmake -DENABLE_SANITIZERS=ON
# Applies ASan + UBSan to CXX compilation only.  CUDA device code is never
# instrumented (CUDA and sanitizers are incompatible at the device level).
# Generator expression $<$<COMPILE_LANGUAGE:CXX>:...> guards all flags so
# they never reach nvcc.
option(ENABLE_SANITIZERS "Enable ASan + UBSan for CPU code (not CUDA device code)" OFF)

if(ENABLE_SANITIZERS)
    if(MSVC AND CMAKE_CXX_COMPILER_ID MATCHES "Clang")
        # clang-cl on Windows: ASan + most UBSan checks.
        # -fno-sanitize=vptr: vptr requires consistent RTTI linkage across
        # all TUs including CUDA-linked objects; excluded until that is audited.
        set(SANITIZER_COMPILE_FLAGS
            -fsanitize=address,undefined
            -fsanitize-recover=all
            -fno-omit-frame-pointer
            -fno-sanitize=vptr
        )
        set(SANITIZER_LINK_FLAGS
            -fsanitize=address,undefined
        )
    elseif(NOT MSVC AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        # GCC / native Clang on Linux.
        set(SANITIZER_COMPILE_FLAGS
            -fsanitize=address,undefined
            -fsanitize-recover=all
            -fno-omit-frame-pointer
        )
        set(SANITIZER_LINK_FLAGS
            -fsanitize=address,undefined
        )
    else()
        message(WARNING
            "ENABLE_SANITIZERS=ON but no sanitizer flags are known for "
            "compiler '${CMAKE_CXX_COMPILER_ID}'. Sanitizers will not be applied.")
        # Force the option off so downstream if(ENABLE_SANITIZERS) blocks skip.
        set(ENABLE_SANITIZERS OFF CACHE BOOL "" FORCE)
    endif()
endif()

enable_testing()
add_subdirectory(tests)

# ============================================================================
# Main executable
# ============================================================================
add_executable(particle_sim
    src/main.cpp
    src/rendering/ParticleSystem.cu
    src/rendering/DensityHeatmap.cu
    src/config/ConfigReader.cpp
    src/spatial/UniformGridIndex.cu
    src/spatial/UniformGridIndexQueries.cpp
    src/models/FluidSPHModel.cu
    src/models/FluidSPHModelOps.cpp
)

target_include_directories(particle_sim PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(particle_sim PRIVATE
    OpenGL::GL
    glfw
    glad_gl46
    imgui
    CUDA::cudart
    toml11::toml11
)

# Compiler warnings (C/C++ only, not CUDA)
if(MSVC)
    target_compile_options(particle_sim PRIVATE $<$<COMPILE_LANGUAGE:CXX>:/W4>)
else()
    target_compile_options(particle_sim PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-Wall -Wextra -Wpedantic -Wshadow -Wconversion>)
endif()

# CUDA-specific flags
target_compile_options(particle_sim PRIVATE
    $<$<COMPILE_LANGUAGE:CUDA>:--expt-relaxed-constexpr>
    $<$<COMPILE_LANGUAGE:CUDA>:-allow-unsupported-compiler>
)

# Sanitizer flags (CXX only — device code is never instrumented)
if(ENABLE_SANITIZERS)
    target_compile_options(particle_sim PRIVATE
        $<$<COMPILE_LANGUAGE:CXX>:${SANITIZER_COMPILE_FLAGS}>
    )
    target_link_options(particle_sim PRIVATE ${SANITIZER_LINK_FLAGS})
endif()

# Copy config.toml next to the binary after each build
add_custom_command(TARGET particle_sim POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_SOURCE_DIR}/config.toml
        $<TARGET_FILE_DIR:particle_sim>/config.toml
    COMMENT "Copying config.toml to binary directory"
)

# Copy shaders directory next to the binary after each build
add_custom_command(TARGET particle_sim POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_CURRENT_SOURCE_DIR}/shaders
        $<TARGET_FILE_DIR:particle_sim>/shaders
    COMMENT "Copying shaders to binary directory"
)
