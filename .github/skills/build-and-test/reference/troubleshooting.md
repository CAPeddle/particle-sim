# Troubleshooting Guide — Build and Test

Quick-reference for common build, test, and tooling failures.

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `compile_commands.json not found` | CMake not run | Run `cmake -B build -G Ninja` |
| `clang-tidy: command not found` | LLVM tools not in PATH | Install LLVM and add to PATH |
| `CUDA error: no kernel image` | Wrong SM architecture | Verify `CMAKE_CUDA_ARCHITECTURES=89` in CMakeLists.txt |
| OpenGL context creation fails | Missing GPU driver | Update NVIDIA drivers |
| ImGui not displaying | GLFW/OpenGL init failed | Check `glfw_error_callback` output |
| Sanitizer crash in CUDA code | Sanitizers don't support CUDA | Use `compute-sanitizer` instead |
| `CMake 3.29 or higher is required` | CMake version too old | Upgrade CMake (`winget install Kitware.CMake`) |
| `CUDA not found` | CUDA Toolkit not installed | Install CUDA Toolkit, ensure `nvcc` in PATH |
| `ptxas fatal: sm_52` | CMake < 3.29 with CUDA 13.2 | Upgrade CMake to 3.29+ |
| MSVC environment missing | VS Developer shell not active | Run configure inside a VS Developer shell |
| `Missing include` | Header not in target includes | Update `target_include_directories` in CMakeLists.txt |
| CUDA compilation errors | SM arch mismatch | Check SM architecture matches GPU (SM 89 for RTX 4050) |
