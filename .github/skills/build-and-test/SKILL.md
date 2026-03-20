---
name: build-and-test
description: Step-by-step guide for setting up dependencies, building the project, and running tests. Use this when asked to build, run tests, set up the project, or troubleshoot build failures.
---

# Building and Testing particle-sim

---

## Prerequisites

- **CMake 3.29+** with Ninja generator (3.29 required for CUDA arch probe fix)
- **CUDA Toolkit 13.2** (nvcc, CUDA runtime)
- **LLVM clang-cl 18+** (Windows primary — `winget install LLVM.LLVM`)
- **Visual Studio 2022+** (Windows — required for MSVC headers/libs; any edition)
- **GCC 13+** or **Clang 18+** (Linux only — unsupported for this project; reference only)
- **OpenGL 4.6** compatible GPU driver (NVIDIA native driver on Windows)
- **NVIDIA RTX 4050 Laptop** (SM 89 / Ada Lovelace) or compatible GPU

> WSL2 is **not supported**. `glfwCreateWindow` fails — no NVIDIA OpenGL EGL ICD in WSL2.
> See `DEVELOPMENT.md` for details.

All builds run from the **repository root**.

---

## Step 1 — Dependencies (FetchContent)

Dependencies are downloaded automatically via CMake FetchContent:
- **GLFW 3.4** — windowing
- **GLAD 2.0.8** — OpenGL loader (4.6 Core)
- **Dear ImGui 1.91.6** — UI

No manual dependency setup required. FetchContent handles everything on first configure.

---

## Step 2 — Configure (CMake)

**Windows (primary):** Run inside a Visual Studio Developer shell (or after `vcvarsall.bat x64`):

```powershell
# Debug build (recommended for development)
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CUDA_HOST_COMPILER=clang-cl

# Release build
cmake -B build-release -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_HOST_COMPILER=clang-cl
```

**Linux (reference only, unsupported):**
```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
```

> `CMAKE_EXPORT_COMPILE_COMMANDS=ON` is set automatically for clang-tidy support.

Expected outcome: exits 0, generates `build/compile_commands.json`.

**Known failure modes:**
- `CMake 3.29 or higher is required` → Upgrade CMake (`winget install Kitware.CMake`)
- `CUDA not found` → Ensure CUDA Toolkit is installed and `nvcc` is in PATH
- `ptxas fatal: sm_52` → CMake < 3.29 with CUDA 13.2; upgrade CMake
- MSVC environment missing → Run configure inside a VS Developer shell

---

## Step 3 — Build

```bash
# Debug
cmake --build build --parallel

# Release
cmake --build build-release --parallel
```

Expected outcome: exits 0, produces `build/particle_sim` executable.

**Known failure modes:**
- `Missing include` → Update `target_include_directories` in CMakeLists.txt
- CUDA compilation errors → Check SM architecture matches GPU (SM 89 for RTX 4050)

---

## Step 4 — Run

```powershell
# Windows
.\build\particle_sim.exe
```

Expected outcome: Opens a window with particle visualization and ImGui controls.

---

## Step 5 — Run Tests

```powershell
# Full suite (Windows) — three EXPECT_DEATH tests are excluded on Windows (see note below)
ctest --test-dir build --output-on-failure

# Run a specific test suite
ctest --test-dir build -R "SuiteName" --output-on-failure

# List all tests without running
ctest --test-dir build -N
```

**Windows death-test workaround:** Three `UniformGridIndexTest` constructor death tests are
excluded from default CTest discovery on Windows to avoid hanging. Run them separately:

```powershell
cmake --build build --target run_uniform_grid_death_tests
```

See `tests/README.md` for full details.

---

## Step 6 — Sanitizer Builds

### ASan + UBSan via `ENABLE_SANITIZERS` (Windows — clang-cl)

The project provides a CMake option that applies the correct sanitizer flags per compiler:

```powershell
# Configure
cmake -B build_asan -G Ninja `
      -DCMAKE_BUILD_TYPE=RelWithDebInfo `
      -DCMAKE_CUDA_HOST_COMPILER=clang-cl `
      -DCMAKE_CXX_COMPILER=clang-cl `
      -DENABLE_SANITIZERS=ON

# Build
cmake --build build_asan --parallel

# Run tests
ctest --test-dir build_asan --output-on-failure
```

> **Runtime requirement:** Ensure `%LLVM%\bin` is in `PATH` so
> `clang_rt.asan_dynamic-x86_64.dll` is found at startup. Set `ASAN_SYMBOLIZER_PATH`
> for symbol resolution.

### ASan + UBSan (Linux — GCC/Clang, unsupported platform, reference only)

```bash
cmake -B build_asan -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DENABLE_SANITIZERS=ON
cmake --build build_asan --parallel
```

**Important:** Sanitizers only instrument CPU code. For CUDA memory errors use:
```bash
compute-sanitizer ./build/particle_sim.exe
```

---

## Step 7 — Run clang-format

```bash
# Check all files (dry run)
find src -name '*.cpp' -o -name '*.hpp' -o -name '*.cu' -o -name '*.cuh' | \
    xargs clang-format --dry-run --Werror --style=file:.clang-format

# Fix all files in-place
find src -name '*.cpp' -o -name '*.hpp' -o -name '*.cu' -o -name '*.cuh' | \
    xargs clang-format -i --style=file:.clang-format
```

---

## Step 8 — Run clang-tidy

```bash
# Requires compile_commands.json from Step 2
# Note: Only run on .cpp/.hpp files — .cu has limited support
find src -name '*.cpp' -o -name '*.hpp' | xargs clang-tidy -p build/
```

Zero findings required. All warnings are hard errors (see `.clang-tidy`).

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `compile_commands.json not found` | CMake not run | Run `cmake -B build -G Ninja` |
| `clang-tidy: command not found` | LLVM tools not in PATH | Install LLVM and add to PATH |
| `CUDA error: no kernel image` | Wrong SM architecture | Verify `CMAKE_CUDA_ARCHITECTURES=89` in CMakeLists.txt |
| OpenGL context creation fails | Missing GPU driver | Update NVIDIA drivers |
| ImGui not displaying | GLFW/OpenGL init failed | Check `glfw_error_callback` output |
| Sanitizer crash in CUDA code | Sanitizers don't support CUDA | Use `compute-sanitizer` instead |
