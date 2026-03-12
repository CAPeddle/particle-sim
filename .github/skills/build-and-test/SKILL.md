---
name: build-and-test
description: Step-by-step guide for setting up dependencies, building the project, and running tests. Use this when asked to build, run tests, set up the project, or troubleshoot build failures.
---

# Building and Testing particle-sim

---

## Prerequisites

- **CMake 3.28+** with Ninja generator
- **CUDA Toolkit 13.1** (nvcc, CUDA runtime)
- **GCC 13+** or **Clang 18+** (Linux/WSL)
- **MSVC 2022+** (Windows native)
- **OpenGL 4.6** compatible GPU driver
- **NVIDIA RTX 4050 Laptop** (SM 89 / Ada Lovelace) or compatible GPU

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

```bash
# Debug build configuration
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug

# Release build configuration
cmake -B build-release -G Ninja -DCMAKE_BUILD_TYPE=Release
```

> `CMAKE_EXPORT_COMPILE_COMMANDS=ON` is set automatically in CMakeLists.txt for clang-tidy support.

Expected outcome: exits 0, generates `build/compile_commands.json`.

**Known failure modes:**
- `CUDA not found` → Ensure CUDA Toolkit is installed and `nvcc` is in PATH
- `Unsupported compiler` → The project sets `-allow-unsupported-compiler` for CUDA; this is expected

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

```bash
# Run the particle simulation
./build/particle_sim
```

Expected outcome: Opens a window with particle visualization and ImGui controls.

---

## Step 5 — Run Tests

> **Note:** GoogleTest integration is planned but not yet implemented.

```bash
# Once tests are integrated:
ctest --test-dir build --output-on-failure

# Run a specific test suite
ctest --test-dir build -R "SuiteName"

# List all tests without running
ctest --test-dir build -N
```

---

## Step 6 — Sanitizer Builds

### ASan + UBSan (CPU code only — CUDA incompatible)

```bash
cmake -B build-asan -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer"
cmake --build build-asan --parallel
./build-asan/particle_sim
```

**Important:** Sanitizers only work on CPU code. CUDA kernels cannot be instrumented with ASan/MSan/TSan.

For CUDA memory checking, use NVIDIA's `compute-sanitizer`:
```bash
compute-sanitizer ./build/particle_sim
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
