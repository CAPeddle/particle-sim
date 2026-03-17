# Development Setup Guide

This guide covers setting up the particle-sim development environment for WSL Linux and Windows native builds.

## Quick Start

### WSL Linux (Primary Development Environment)

**Prerequisites:**
- WSL 2 with Ubuntu 22.04 LTS or later
- CUDA Toolkit 13.2
- CMake 3.28+
- Ninja build system
- GCC 13+ or Clang 18+

**Setup Steps:**

```bash
# 1. Install CUDA 13.2 (see CUDA 13.2 Installation section below)

# 2. Verify CUDA installation
nvcc --version

# 3. Install CMake 3.28+ and Ninja
sudo apt update && sudo apt install -y cmake ninja-build build-essential

# 4. Clone and configure
git clone https://github.com/CAPeddle/particle-sim.git
cd particle-sim
mkdir -p build
cd build

# 5. Configure with CMake
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release ..

# 6. Build
cmake --build .

# 7. Run tests
ctest

# 8. Run the application
./particle_sim
```

### Windows Native

**Prerequisites:**
- Windows 11 Pro or later
- CUDA Toolkit 13.2 (Windows native installer)
- Visual Studio 2022 Community Edition or Professional
- CMake 3.28+ (installer or Scoop/Chocolatey)
- Ninja build system

**Setup Steps:**

Same as WSL but use Visual Studio as the generator:

```bash
cmake -G "Visual Studio 17 2022" -DCMAKE_BUILD_TYPE=Release ..
cmake --build . --config Release
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

### Windows Native Installation

1. Download the CUDA 13.2 installer from [NVIDIA CUDA Toolkit Downloads](https://developer.nvidia.com/cuda-toolkit-archive)
2. Run the installer and follow on-screen prompts
3. Select "Custom Installation" and ensure CUDA Compiler is checked
4. Verify installation:
   ```cmd
   nvcc --version
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

Configure with:

```bash
cmake -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_COMPILER=g++-13 \
  ..
```

**Key CMake Variables:**
- `CMAKE_BUILD_TYPE`: `Debug` or `Release` (default: Release)
- `CMAKE_CXX_STANDARD`: Fixed to C++23
- `CMAKE_CUDA_STANDARD`: Fixed to CUDA 20
- `CMAKE_CUDA_ARCHITECTURES`: Fixed to SM 89 (RTX 4050)

---

## Development Workflow

### Building

```bash
cd build
cmake --build . -- -v  # Verbose output
```

### Running Tests

```bash
cd build
ctest --output-on-failure
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

**With AddressSanitizer:**

```bash
cmake -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" ..
cmake --build .
./build/particle_sim
```

---

## Troubleshooting

### CUDA not found by CMake

Make sure CUDA is in your PATH:

```bash
which nvcc
```

If not, add to `~/.bashrc`:

```bash
export PATH=/usr/local/cuda-13.2/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-13.2/lib64:$LD_LIBRARY_PATH
```

### clang-format / clang-tidy not found

```bash
sudo apt install clang-format clang-tools
```

### CMake version too old

```bash
wget https://cmake.org/files/v3.28/cmake-3.28.3-linux-x86_64.tar.gz
tar -xvf cmake-3.28.3-linux-x86_64.tar.gz
sudo mv cmake-3.28.3-linux-x86_64 /opt/cmake-3.28
export PATH=/opt/cmake-3.28/bin:$PATH
```

### Build failures on Windows

Ensure Visual Studio 2022 is installed with C++ development tools:
- Visual Studio Installer → Modify → Desktop development with C++

---

## Learning Resources

- [NVIDIA CUDA C++ Programming Guide](https://docs.nvidia.com/cuda/cuda-c-programming-guide/)
- [CUDA Samples](https://github.com/NVIDIA/cuda-samples)
- [CMake Documentation](https://cmake.org/cmake/help/latest/)
- [Modern C++ Features](https://en.cppreference.com/w/cpp)

---

## Contributing

See [copilot-instructions.md](.github/copilot-instructions.md) for code style, naming conventions, and architecture guidelines.
