cmake_minimum_required(VERSION 3.28)

# Allow unsupported compiler for CUDA (VS 2026 not yet officially supported)
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -allow-unsupported-compiler")

project(particle_sim LANGUAGES C CXX CUDA)

# C++ and CUDA standards
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 20)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)

# RTX 4050 Laptop = Ada Lovelace = SM 89
set(CMAKE_CUDA_ARCHITECTURES 89)

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

enable_testing()
add_subdirectory(tests)

# ============================================================================
# Main executable
# ============================================================================
add_executable(particle_sim
    src/main.cpp
    src/rendering/ParticleSystem.cu
    src/config/ConfigReader.cpp
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
    target_compile_options(particle_sim PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-Wall -Wextra -Wpedantic>)
endif()

# CUDA-specific flags
target_compile_options(particle_sim PRIVATE
    $<$<COMPILE_LANGUAGE:CUDA>:--expt-relaxed-constexpr>
    $<$<COMPILE_LANGUAGE:CUDA>:-allow-unsupported-compiler>
)

# Copy config.toml next to the binary after each build
add_custom_command(TARGET particle_sim POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_SOURCE_DIR}/config.toml
        $<TARGET_FILE_DIR:particle_sim>/config.toml
    COMMENT "Copying config.toml to binary directory"
)
