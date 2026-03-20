# Development Setup Guide

This guide covers setting up the particle-sim development environment.

> **Primary platform: Windows native (MSVC 2022 + LLVM clang-cl + CUDA 13.2)**
>
> WSL2 is **not supported** for this project. CUDA-GL interop requires a native NVIDIA OpenGL
> context; WSL2 exposes only the CUDA compute path (Mesa/Zink, no NVIDIA EGL ICD).
> See [WSL2 limitation note](#wsl2-unsupported) at the bottom of this document.

## Quick Start

### Windows Native (Primary Development Environment)

**Prerequisites:**

| Tool | Minimum | Install |  
|---|---|---|
| Windows | 11 Pro | — |
| NVIDIA driver | 595.x | [NVIDIA Driver Downloads](https://www.nvidia.com/drivers) |
| CUDA Toolkit | 13.2 | [CUDA Archive](https://developer.nvidia.com/cuda-toolkit-archive) |
| Visual Studio | 2022 (any edition) | Required for MSVC headers/libs |
| LLVM / clang-cl | 18+ | `winget install LLVM.LLVM` |
| CMake | **3.29+** | `winget install Kitware.CMake` |
| Ninja | any | `winget install Ninja-build.Ninja` |
| Git | any | `winget install Git.Git` |

**Setup Steps (PowerShell, run from repo root):**

```powershell
# 1. Clone
git clone git@github.com-personal:CAPeddle/particle-sim.git
cd particle-sim

# 2. Open a Visual Studio Developer command prompt for the MSVC environment
#    then configure (clang-cl as the nvcc host compiler)
cmd /c "call `"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat`" x64 && \
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CUDA_HOST_COMPILER=clang-cl"

# 3. Build
cmake --build build --parallel

# 4. Run tests (see Windows death-test note below)
ctest --test-dir build --output-on-failure

# 5. Run death tests manually (excluded from ctest on Windows)
cmake --build build --target run_uniform_grid_death_tests

# 6. Launch
.\build\particle_sim.exe
```

---

## CUDA 13.2 Installation

### WSL Linux Installation

NVIDIA provides a dedicated CUDA repository for WSL. This ensures compatibility with the WSL GPU drivers.

**Step 1: Download and install the repository pin**

```bash
wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-wsl-ubuntu.pin
sudo mv cuda-wsl-ubuntu.pin /etc/apt/preferences.d/cuda-repository-pin-600
```

**Step 2: Download the CUDA 13.2 DEB package** (3.3 GB)

```bash
wget https://developer.download.nvidia.com/compute/cuda/13.2.0/local_installers/cuda-repo-wsl-ubuntu-13-2-local_13.2.0-1_amd64.deb
```

**Step 3: Install the DEB package**

```bash
sudo dpkg -i cuda-repo-wsl-ubuntu-13-2-local_13.2.0-1_amd64.deb
```

**Step 4: Copy the JPEG keyring from the local repository**

```bash
sudo cp /var/cuda-repo-wsl-ubuntu-13-2-local/cuda-*-keyring.gpg /usr/share/keyrings/
```

**Step 5: Update package manager and install CUDA toolkit**

```bash
sudo apt-get update
sudo apt-get -y install cuda-toolkit-13-2
```

**Step 6: Verify installation**

```bash
nvcc --version
```

Expected output: `nvcc: NVIDIA (R) Cuda compiler driver Version 13.2.x`

**Step 7: Update your shell configuration** (if not already done)

Add to `~/.bashrc` or `~/.zshrc`:

```bash
export PATH=/usr/local/cuda-13.2/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-13.2/lib64:$LD_LIBRARY_PATH
```

Then reload:

```bash
source ~/.bashrc
```

### Windows Native Installation (Primary)

1. Download the CUDA 13.2 Windows installer from [NVIDIA CUDA Toolkit Archive](https://developer.nvidia.com/cuda-toolkit-archive)
2. Run the `.exe` installer; select **Custom Installation**, ensure **CUDA Compiler** and **CUDA Runtime** are checked
3. Verify:
   ```powershell
   nvcc --version
   # Expected: Cuda compilation tools, release 13.2, V13.2.51
   ```

### WSL2 / Linux Installation (unsupported — reference only)

WSL2 is not a supported build target. CUDA compute works but `glfwCreateWindow` always
returns `nullptr` because the NVIDIA OpenGL EGL ICD is absent. Do not attempt to run
`particle_sim` in WSL2.

If you need a Linux reference for CI purposes, the WSL2 CUDA install used historically is:

```bash
wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-wsl-ubuntu.pin
sudo mv cuda-wsl-ubuntu.pin /etc/apt/preferences.d/cuda-repository-pin-600
wget https://developer.download.nvidia.com/compute/cuda/13.2.0/local_installers/cuda-repo-wsl-ubuntu-13-2-local_13.2.0-1_amd64.deb
sudo dpkg -i cuda-repo-wsl-ubuntu-13-2-local_13.2.0-1_amd64.deb
sudo cp /var/cuda-repo-wsl-ubuntu-13-2-local/cuda-*-keyring.gpg /usr/share/keyrings/
sudo apt-get update && sudo apt-get -y install cuda-toolkit-13-2
```

---

## Project Configuration

### Technology Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| **Language** | C++23 | CPU code with modern features |
| **GPU Compute** | CUDA 13.2 | GPU kernels and memory management |
| **Graphics** | OpenGL 4.6 | Rendering via GLAD loader |
| **Windowing** | GLFW 3.4 | Cross-platform window management |
| **UI** | Dear ImGui 1.91.6 | Runtime parameter control |
| **Build** | CMake 3.28+ + Ninja | Cross-platform build system |
| **Testing** | GoogleTest + GoogleMock | Unit and integration tests |
| **GPU Target** | SM 89 | NVIDIA RTX 4050 Laptop (Ada Lovelace) |

### CMake Build Options

**Windows (primary):**
```powershell
# Standard Debug build (run inside VS Developer shell or after vcvarsall.bat)
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CUDA_HOST_COMPILER=clang-cl

# Release build
cmake -B build-release -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_HOST_COMPILER=clang-cl
```

**Key CMake Variables:**
- `CMAKE_BUILD_TYPE`: `Debug`, `RelWithDebInfo`, or `Release`
- `CMAKE_CUDA_HOST_COMPILER`: Set to `clang-cl` on Windows (nvcc host C++23 support)
- `ENABLE_SANITIZERS`: `ON` to enable ASan + UBSan on CPU code (see Sanitizer Builds below)
- `CMAKE_CXX_STANDARD`: Fixed to C++23
- `CMAKE_CUDA_STANDARD`: Fixed to CUDA 20
- `CMAKE_CUDA_ARCHITECTURES`: Fixed to SM 89 (RTX 4050)

---

## Development Workflow

### Building

```powershell
# Standard
cmake --build build --parallel

# Verbose output
cmake --build build --parallel -- -v
```

### Running Tests

```powershell
ctest --test-dir build --output-on-failure
```

### Windows note: death-test workaround

On Windows, all three `UniformGridIndexTest` constructor death tests may hang when run through
`ctest`. They are excluded from default Windows CTest discovery and must be run manually.

Excluded tests:
- `UniformGridIndexTest.Constructor_ZeroCellSize_Aborts`
- `UniformGridIndexTest.Constructor_NegativeCellSize_Aborts`
- `UniformGridIndexTest.Constructor_InvertedDomain_Aborts`

Default suite (Windows):

```bash
ctest --test-dir build --output-on-failure
```

Manual death-test workaround target (Windows — runs all three):

```bash
cmake --build build --target run_uniform_grid_death_tests
```

Run specific test:

```bash
ctest -R SpatialIndex --output-on-failure
```

### Code Quality

**Format code with clang-format:**

```bash
clang-format -i --style=file:.clang-format src/core/ISimulationModel.hpp
```

Format all C++ files:

```bash
find src -name "*.cpp" -o -name "*.hpp" -o -name "*.cu" -o -name "*.cuh" | xargs clang-format -i --style=file:.clang-format
```

**Lint with clang-tidy:**

```bash
clang-tidy -p build/ src/core/ISimulationModel.hpp
```

The project enforces strict linting; all warnings are treated as errors.

### Debugging

**With GDB:**

```bash
gdb ./build/particle_sim
(gdb) run
```

**With Valgrind (CPU code only):**

```bash
valgrind --leak-check=full ./build/particle_sim
```

**With AddressSanitizer + UBSan (Windows — clang-cl):**

```powershell
# Configure with ENABLE_SANITIZERS option (handles clang-cl flags automatically)
cmake -B build_asan -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo `
      -DCMAKE_CUDA_HOST_COMPILER=clang-cl `
      -DCMAKE_CXX_COMPILER=clang-cl `
      -DENABLE_SANITIZERS=ON
cmake --build build_asan --parallel
ctest --test-dir build_asan --output-on-failure
```

> **Note:** Ensure `%LLVM%\bin` is in `PATH` so `clang_rt.asan_dynamic-x86_64.dll` is
> found at runtime. Set `ASAN_SYMBOLIZER_PATH` for symbol resolution.

---

## Troubleshooting

### CUDA not found by CMake (Windows)

Ensure `nvcc` is in `PATH`:

```powershell
nvcc --version
# If not found: add C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.2\bin to PATH
```

### clang-cl not found

```powershell
winget install LLVM.LLVM
# Then add C:\Program Files\LLVM\bin to PATH
clang-cl --version
```

### CMake version too old

This project requires CMake **3.29+** (older versions fail the CUDA compiler-ID probe with
`ptxas fatal: sm_52 not defined`).

```powershell
winget install Kitware.CMake
cmake --version
```

### MSVC environment not active

nvcc requires MSVC headers/libs to be in the environment. Run configure inside a Visual
Studio Developer shell or call `vcvarsall.bat x64` before `cmake`:

```powershell
cmd /c "call `"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat`" x64 && cmake -B build -G Ninja -DCMAKE_CUDA_HOST_COMPILER=clang-cl"
```

### OpenGL / GLFW window fails to create

1. `nvidia-smi` — confirms the NVIDIA driver is loaded
2. Running over RDP? The GPU may fall back to Microsoft Basic Display Adapter. Run locally
   or enable hardware GPU acceleration in RDP session settings.
3. Confirm OpenGL 4.6 Core support with `wglinfo`.

---

## WSL2 (Unsupported) {#wsl2-unsupported}

WSL2 **cannot** run `particle_sim`. Root cause: the NVIDIA OpenGL EGL ICD
(`libEGL_nvidia.so`) is absent in the WSL2 GLVND registry — only `libEGL_mesa.so`
(Zink / Vulkan-backed) is registered. `glfwCreateWindow` always returns `nullptr`.

CUDA compute works in WSL2, but CUDA-GL interop (`cudaGraphicsGLRegisterImage`) requires
both the GL context and the CUDA context to be on the same physical device via the NVIDIA
native driver. This is not possible in WSL2.

**Do not file bug reports for WSL2 GL failures.** Use Windows native.

---

## Learning Resources

- [NVIDIA CUDA C++ Programming Guide](https://docs.nvidia.com/cuda/cuda-c-programming-guide/)
- [CUDA Samples](https://github.com/NVIDIA/cuda-samples)
- [CMake Documentation](https://cmake.org/cmake/help/latest/)
- [Modern C++ Features](https://en.cppreference.com/w/cpp)

---

## Contributing

See [copilot-instructions.md](.github/copilot-instructions.md) for code style, naming conventions, and architecture guidelines.
