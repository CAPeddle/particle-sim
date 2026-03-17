# ExecPlan: Phase 6a — Post-Review Remediation

**Date:** 2026-03-16  
**Status:** Complete  
**Parent plan:** [Phase 6 — Density Heatmap Visualisation](2026-03-12-phase-6-density-heatmap.md)  
**Review source:** Code review conducted 2026-03-16 by expert-cpp and code-reviewer agents (see parent plan Decision Log for link)

---

## Purpose / Big Picture

Phase 6 delivered `DensityHeatmap` — a CUDA-GL interop overlay that renders SPH density as a colour heatmap. A subsequent expert code review identified **10 ERRORs** and **19 WARNINGs** across correctness, safety, API quality, and test coverage. This plan addresses all ERRORs and WARNINGs with the exception of W-18 (deferred to a dedicated rendering-decoupling phase; tracked in `plan.md`).

**Scope:** Corrections only — no new features are introduced. The externally visible behaviour of the heatmap overlay is unchanged; the goal is correctness, robustness, and standards compliance.

**Terms (in addition to those defined in Phase 6):**
- **CUDA sticky error** — A CUDA error deposited in per-context state by a failed kernel launch. Only visible via `cudaGetLastError()`; subsequent CUDA API calls may succeed and mask the failure.
- **`std::expected<T, E>`** — C++23 sum type representing either a successful value `T` or an error `E`. Used in place of exceptions per project policy.
- **`std::error_code`** — Standard error type from `<system_error>`; used as the error channel for `std::expected` when no additional context is needed.
- **Uniform location** — An integer handle returned by `glGetUniformLocation` that identifies a GLSL uniform variable in a compiled shader program. Stable for the lifetime of the program.
- **Surface object (`cudaSurfaceObject_t`)** — A CUDA handle wrapping a mapped `cudaArray_t` that permits per-texel writes from device code via `surf2Dwrite`.

---

## Progress

- [x] `Prerequisites verified` — 2026-03-16: baseline 77/77 passing, format clean
- [x] `RED tests added` — 2026-03-16: 6 compile errors confirmed (3× void return, 3× missing struct fields)
- [x] `GREEN implementation completed` — 2026-03-16: all 6 steps implemented; 83/83 passing
- [x] `REFACTOR + validation completed` — 2026-03-16: clang-format clean; tidy clean via .cpp TU; all acceptance criteria pass
- [x] `Code review — zero ERRORs` — 2026-03-16: dual review (code-reviewer + expert-cpp); 0 ERRORs, 5 WARNINGs all resolved before close

---

## Surprises & Discoveries

1. **`CMAKE_CUDA_STANDARD 23` unsupported by CMake 3.28 + nvcc 13.2** — CMake's CUDA standard table does not include CUDA 13.2, so `set(CMAKE_CUDA_STANDARD 23)` silently failed. Fixed by reverting to `CMAKE_CUDA_STANDARD 20` (maximum nvcc 13.2 accepts natively) and adding `-Xcompiler=-std=c++23` to `CMAKE_CUDA_FLAGS` so GCC's host-compilation pass uses C++23. All `std::expected`, concepts, and C++23 features in `.cu`/`.cuh` host code now compile correctly.

2. **`cudaErrorInvalidContext` is a Driver API enum, not Runtime API** — `cudaError_t` (Runtime API) does not include `cudaErrorInvalidContext`. Replaced with `cudaErrorCudartUnloading` (runtime shutting down) and `cudaErrorContextIsDestroyed` (explicit teardown) per CUDA Runtime API documentation.

3. **clang-tidy cannot lint `.cuh` files directly via nvcc compile_commands** — Running `clang-tidy -p build/ *.cuh` fails with CUDA compiler-flag errors because clang cannot parse nvcc flags. The correct approach is to lint headers via an including `.cpp` TU: `clang-tidy -p build/ tests/unit/rendering/DensityHeatmapTest.cpp` picks up `DensityHeatmap.cuh` through `HeaderFilterRegex`. Plan tidy commands updated accordingly.

4. **Phase 6a introduced 6 new DensityHeatmap tests** — All skip in headless (GLFW/CUDA unavailable) but compile and are registered: total test count increased from 77 → 83.

---

## Decision Log

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | `initDensityHeatmap` returns `std::expected<void, std::error_code>` | Per project standard: no exceptions; all fallible functions must propagate errors. Shader compile failures and GL resource failures are recoverable; CUDA registration failures retain `CUDA_CHECK` / `abort` since a missing CUDA device is unrecoverable in this context. |
| 2 | Shader paths use `std::string_view` parameters | C++23 idiomatic; avoids raw `const char*`; zero-overhead over string literals at call sites. No heap allocation. |
| 3 | `scatterRandomParticles` moves to `tests/fixtures/SphTestHelpers.hpp` as `seedParticlesRandom` | It is a demo/test utility with no physical meaning; it must not be part of the production model API. Making it test-only removes it from `particle_sim` binary and narrows the public API surface. |
| 4 | Fragment shader gains `uniform float u_alpha` | Hardcoded `0.85` prevented runtime overlay transparency control without recompilation. |
| 5 | Reverse shader-then-CUDA init order in `initDensityHeatmap` | Ensures that any early-return on shader failure leaves zero CUDA resources registered; prevents the resource-leak on partial init. |
| 6 | `DensityHeatmapInput` view struct deferred | Decoupling `updateDensityHeatmap` from `FluidSPHModel` field layout is architecturally correct but expands scope beyond defect remediation. Tracked in `plan.md` for a dedicated rendering-decoupling phase. |
| 7 | Out-of-domain particles are **discarded** (not clamped) in `scatterDensityKernel` (EC-1) | Clamping boundary-escaping particles to the edge texel produced a misleading density spike artefact at domain edges. Discarding is the correct default; the frequency of discards is counted via an atomic device counter and reported via a single host-side `fprintf` after each kernel pass. The physics causing particles to escape is a known Phase 4/5 issue tracked separately. Doxygen on `scatterDensityKernel` and `updateDensityHeatmap` must be updated to document this discard semantics and the counter output format. |
| 8 | `loadSource` converts `std::string_view` to `std::filesystem::path` internally (EC-2) | `std::ifstream` has no `string_view` constructor. `std::filesystem::path{path}` is the idiomatic C++23 conversion — zero extra string allocation, consistent with `binaryDir` path handling already in `main.cpp`. `std::string{path}` is forbidden here (unnecessary heap allocation). |
| 9 | `destroyDensityHeatmap` resets cached uniform location fields to `-1` (EC-3) | Ensures post-destroy state is fully consistent with default-constructed state. `Destroy_AfterInit_SetsTextureIdToZero` assertions in Step 1b are extended to check all three uniform location fields are `-1` after destroy. |
| 10 | `surf2Dwrite` byte-offset is `static_cast<int>(x * sizeof(float))` with `x` as `uint32_t` (EC-4) | The multiplication is performed in unsigned arithmetic (no signed-overflow risk); the cast to `int` is only at the `surf2Dwrite` call site where the API requires it. This is the safest option: no mixed-sign arithmetic, no truncation risk within valid texture dimensions (≤ 4096 × 4096 in this project). |
| 11 | `SphTestHelpers.hpp` has a hard `#error` compile guard for non-CUDA TUs (EC-5) | A documentation comment alone cannot prevent accidental inclusion from `.cpp` files. A `#ifndef __CUDACC__ #error ... #endif` guard turns a silent ABI mismatch into a hard compile error, consistent with the project's fail-fast policy. |

---

## Context and Orientation

### Files modified by this plan

| File | Change summary |
|------|---------------|
| `src/rendering/DensityHeatmap.cuh` | Add `uniformDensityTexLoc`/`uniformMaxDensityLoc`/`uniformAlphaLoc`/`discardCountBuf` fields; `alpha` field; change `initDensityHeatmap` signature; `std::string_view` paths; fix `@post`; add destructor assert; fix `NOLINT` |
| `src/rendering/DensityHeatmap.cu` | CUDA_CHECK after all kernel launches; cudaDeviceSynchronize before unmap; reverse init order; glGetError checks; consistent error strategy; cache uniform locations; fix out-of-domain early return; domain-extent guard; uint32_t idx in clear/write kernels |
| `shaders/heatmap.frag` | Add `uniform float u_alpha`; replace hardcoded `0.85` |
| `src/models/FluidSPHModel.cuh` | Remove `scatterRandomParticles` declaration |
| `src/models/FluidSPHModel.cu` | Remove `scatterRandomParticles` implementation; remove `<random>`, `<vector>` includes |
| `tests/fixtures/SphTestHelpers.hpp` | New file — `seedParticlesRandom` (renamed from `scatterRandomParticles`) |
| `tests/unit/rendering/DensityHeatmapTest.cpp` | gladLoadGL guard; CUDA device guard; expand init/destroy assertions; add 7 new test cases; update call sites for `std::expected` signature |
| `src/main.cpp` | Use `std::expected` return; per-frame SPH rebuild + computeDensity; binaryDir-based shader paths; remove redundant `if (heatmap.enabled)` outer guard; upload `u_alpha` uniform; use `seedParticlesRandom` from fixtures |
| `tests/CMakeLists.txt` | Expose `tests/fixtures/` include path to `particle_sim_tests` and `particle_sim_gpu_tests` |

### Review findings addressed per step

| Step | ERRORs addressed | WARNINGs addressed |
|------|------------------|--------------------|
| Step 1 (RED tests) | E-9, E-10 | W-6, W-7, W-12, W-13, W-14 |
| Step 2 (CUDA kernel safety) | E-1, E-2 | W-3, W-8 |
| Step 3 (init overhaul) | E-4, E-5, E-6 | W-4, W-9, W-11 |
| Step 4 (destructor + API) | E-3 | W-1, W-2, W-5, W-10, W-17 |
| Step 5 (scatterRandomParticles) | E-7 | W-19 |
| Step 6 (SPH loop + shader paths) | E-8 | W-15, W-16 |

---

## Plan of Work

Six implementation steps, each targeting a distinct concern, preceded by a RED test step and followed by a verification + code review step. All steps operate on the Phase 6 baseline (77/77 tests passing, `main` branch).

**Ordering rationale:** RED tests first (Step 1) establishes the failure baseline. CUDA kernel safety (Step 2) is independent of API changes. The `std::expected` + error handling overhaul (Step 3) changes the function signatures, which the RED tests in Step 1 were written to anticipate. Destructor + API polish (Step 4) builds on the reworked init. `scatterRandomParticles` relocation (Step 5) is isolated. SPH loop fixes (Step 6) are isolated to `main.cpp`.

---

## Concrete Steps

### Step 0 — Verify prerequisites

Confirm Phase 6 is complete and the baseline is clean:

```bash
cd /home/cpeddle/projects/personal/particle-sim
cmake --build build --target particle_sim particle_sim_gpu_tests
```

Expected: zero errors, zero warnings.

```bash
cd build && ctest --output-on-failure 2>&1 | tail -4
```

Expected: `100% tests passed, 0 tests failed out of 77`

```bash
cd ..
clang-format --dry-run --Werror \
  src/rendering/DensityHeatmap.cuh \
  src/rendering/DensityHeatmap.cu \
  tests/unit/rendering/DensityHeatmapTest.cpp \
  src/main.cpp 2>&1 && echo "format clean"
```

Expected: `format clean`

If any check fails, resolve the Phase 6 baseline before proceeding.

---

### Step 1 — RED tests

**Goal:** Write all new and expanded test cases before touching implementation. Some tests will compile but expose unguarded behaviour; others (those testing the `std::expected` return) will fail to compile — that compilation failure is the RED state.

**Files to edit:** `tests/unit/rendering/DensityHeatmapTest.cpp`

#### 1a — TestFixture hardening (SetUp)

Replace the `gladLoadGL` call with a guarded version:

```cpp
if (gladLoadGL(glfwGetProcAddress) == 0) {
    GTEST_SKIP() << "GLAD failed to load GL (headless)";
}
```

Add CUDA device guard before any `initDensityHeatmap` call:

```cpp
int deviceCount = 0;
if (cudaGetDeviceCount(&deviceCount) != cudaSuccess || deviceCount == 0) {
    GTEST_SKIP() << "No CUDA device available";
}
```

#### 1b — Expand existing assertions

`Init_ValidResolution_CreatesNonZeroTextureId` — after init, also assert:
```cpp
EXPECT_NE(heatmap.shaderProgram, 0U);
EXPECT_NE(heatmap.quadVao, 0U);
EXPECT_NE(heatmap.quadVbo, 0U);
EXPECT_NE(heatmap.accumBuffer.get(), nullptr);
EXPECT_NE(heatmap.countBuffer.get(), nullptr);
```

`Destroy_AfterInit_SetsTextureIdToZero` — after destroy, also assert:
```cpp
EXPECT_EQ(heatmap.shaderProgram, 0U);
EXPECT_EQ(heatmap.quadVao, 0U);
EXPECT_EQ(heatmap.quadVbo, 0U);
EXPECT_EQ(heatmap.cudaTexResource, nullptr);
```

#### 1c — New test cases

Add these test functions (all use `TEST_F(DensityHeatmapTest, ...)`):

| Test name | What it verifies | Expected RED reason |
|-----------|-----------------|---------------------|
| `Init_ReturnsSuccess_WhenValidArgs` | `initDensityHeatmap` returns `has_value() == true` | Fails to compile — signature still `void` |
| `Init_ReturnsError_WhenShaderPathInvalid` | Bad shader paths → returned `std::expected` has error; `textureId == 0` (after destroy) | Fails to compile — signature still `void` |
| `Init_NegativeResolution_ReturnsError` | `resolution <= 0` returns error without crashing | Crashes (CUDA abort on current code) |
| `Update_WhenDisabled_DoesNotCrash` | `heatmap.enabled = false`; call `updateDensityHeatmap`; no crash | Should pass (behaviour exists but untested — still include for GREEN coverage) |
| `Render_WhenEnabled_DoesNotCrash` | Set `enabled = true`; call `renderDensityHeatmap`; no crash | Should pass; include for coverage |
| `Destroy_WithoutInit_IsNoOp` | Default-constructed heatmap; call `destroyDensityHeatmap`; `textureId` stays `0` | Should pass; include for coverage |

**Verify RED state:**

```bash
cd /home/cpeddle/projects/personal/particle-sim
cmake --build build --target particle_sim_gpu_tests 2>&1 | grep "error:" | head -10
```

Expected: compilation errors on the `std::expected` call sites in the two new `Init_Returns*` tests. All other new tests should compile cleanly (those that test behaviour, not signature).

**Commit as RED.** Do not implement anything yet.

---

### Step 2 — CUDA kernel safety

**Goal:** Fix E-1, E-2, W-3, W-8. All changes in `DensityHeatmap.cu`; no API surface changes.

**File:** `src/rendering/DensityHeatmap.cu`

#### 2a — `cudaGetLastError` after every kernel launch (E-1)

After each `<<<>>>` launch in `updateDensityHeatmap`, add:
```cpp
CUDA_CHECK(cudaGetLastError());
```
Three launches total: `clearAccumKernel`, `scatterDensityKernel`, `writeTextureKernel`.

#### 2b — Sync before surface destroy + unmap (E-2)

After `writeTextureKernel` launch and before `cudaDestroySurfaceObject`:
```cpp
CUDA_CHECK(cudaDeviceSynchronize());
```

#### 2c — Domain-extent zero-division guard (W-3)

In `scatterDensityKernel`, after computing `domainW` and `domainH`:
```cpp
if (domainW <= 0.0F || domainH <= 0.0F) { return; }
```

#### 2d — Out-of-domain particle discard + logging (W-2, Decision 7)

Particles outside the normalised domain `[0,1)` are **discarded** (not clamped). Clamping produced misleading density spikes at domain edges. The frequency of discards is reported diagnostically so the physics causing escapes can be identified during review.

Add an `atomicAdd` discard counter: pass a `uint32_t* discardCount` parameter (device pointer, zeroed by the caller before the kernel), populated only when a particle is discarded:
```cpp
// Kernel parameter added: uint32_t* discardCount
if (nx < 0.0F || nx >= 1.0F || ny < 0.0F || ny >= 1.0F) {
    atomicAdd(discardCount, 1U);
    return;
}
```
In `updateDensityHeatmap`, after `cudaDeviceSynchronize` (Step 2b), copy the discard counter to host and log:
```cpp
uint32_t hostDiscards = 0U;
CUDA_CHECK(cudaMemcpy(&hostDiscards, heatmap.discardCountBuf.get(), sizeof(uint32_t), cudaMemcpyDeviceToHost));
if (hostDiscards > 0U) {
    std::fprintf(stderr,
        "DensityHeatmap: %u/%u particle(s) out of domain and discarded [frame update]\n",
        hostDiscards, particleCount);
}
```
Add a `psim::core::CudaBuffer<uint32_t> discardCountBuf` field to the `DensityHeatmap` struct (allocated to 1 element at init).

Update the Doxygen on `scatterDensityKernel` and `updateDensityHeatmap` to document discard semantics. The existing Doxygen line *"Particles outside the domain are clamped to the boundary texel"* must be removed and replaced with the discard + logging description.

#### 2e — Unsigned index type in `clearAccumKernel` and `writeTextureKernel` (W-8)

Change `int idx` to `uint32_t idx` in `clearAccumKernel`, and `int x`/`int y` to `uint32_t` in `writeTextureKernel`, matching the pattern used in `scatterDensityKernel`. Guard comparisons become unsigned comparisons against `static_cast<uint32_t>(size)` / `static_cast<uint32_t>(resolution)`.

For the `surf2Dwrite` byte-offset (Decision 10), the cast is applied to the whole expression after unsigned arithmetic:
```cpp
surf2Dwrite(value, surface,
            static_cast<int>(x * sizeof(float)),
            static_cast<int>(y));
```
The multiplication `x * sizeof(float)` is unsigned; the outer `static_cast<int>` narrows only at the API boundary. Valid texture dimensions (≤ 4096²) guarantee no truncation.

**Verify:**
```bash
cmake --build build --target particle_sim particle_sim_gpu_tests 2>&1 | grep "error:" | head -10
```
Expected: zero errors (kernel changes only — no API changes yet, Red tests still fail to compile on the `std::expected` call sites).

---

### Step 3 — `initDensityHeatmap` overhaul

**Goal:** Fix E-4, E-5, E-6, W-4, W-9, W-11. This is the largest step — touches the header, the implementation, `main.cpp`, and test file.

**Risk:** Changing `initDensityHeatmap` signature cascades to every call site. There are three: `DensityHeatmap.cu` (implementation), `main.cpp`, and `DensityHeatmapTest.cpp`. Verify all three are updated before building.

**Rollback:** `git stash` before starting; restash if build is broken mid-step.

#### 3a — Add `<expected>` and `<system_error>` includes to `DensityHeatmap.cuh`

At the top of `DensityHeatmap.cuh`, after the existing headers:
```cpp
#include <expected>
#include <system_error>
```

Also add `<filesystem>` to `DensityHeatmap.cu` for the `loadSource` path conversion (Decision 8). Update `loadSource` signature and body:

```cpp
static std::string loadSource(std::string_view path)
{
    std::ifstream file(std::filesystem::path{path}); // Decision 8: path via std::filesystem
    ...
}
```

Update `linkProgram` signature to accept `std::string_view vertPath, std::string_view fragPath` and propagate throughout. No intermediate `std::string` allocation.

#### 3b — Change function signature in `DensityHeatmap.cuh` (E-4, W-9, W-10)

From:
```cpp
void initDensityHeatmap(DensityHeatmap& heatmap, int resolution, const char* vertPath, const char* fragPath);
```
To:
```cpp
/// @brief Creates GL texture, registers with CUDA, compiles shaders, builds VAO/VBO.
///
/// @param heatmap    Target struct. Must not be already initialised (textureId == 0).
/// @param resolution Texture width and height in texels. Must be > 0.
/// @param vertPath   Path to `heatmap.vert` vertex shader source file.
/// @param fragPath   Path to `heatmap.frag` fragment shader source file.
///
/// @return `std::expected<void, std::error_code>` — error if resolution <= 0, any GL
///         resource creation fails, or shader compilation/linking fails. CUDA
///         registration failures call `std::abort()` via `CUDA_CHECK` (unrecoverable).
///
/// @pre An active OpenGL 4.6 + CUDA context exists on the calling thread.
/// @pre heatmap.textureId == 0.
/// @post On success: heatmap.textureId != 0, shaderProgram != 0, quadVao != 0, quadVbo != 0.
/// @post On error: all partially-created resources are released; heatmap is back to default state.
[[nodiscard]] std::expected<void, std::error_code>
initDensityHeatmap(DensityHeatmap& heatmap, int resolution, std::string_view vertPath, std::string_view fragPath);
```

Also update `loadSource` helper (or replace with an overload) to accept `std::string_view`.

#### 3c — Rewrite `initDensityHeatmap` body in `DensityHeatmap.cu` (E-4, E-5, E-6, W-4, W-11)

New init order (shaders first, CUDA last — W-4):

1. Validate `resolution > 0`; return `std::unexpected(std::make_error_code(std::errc::invalid_argument))` on failure.
2. **Compile + link shaders** (`linkProgram`) — return `std::unexpected(std::make_error_code(std::errc::invalid_argument))` on failure.
3. **Create GL texture** (`glGenTextures`, `glTexImage2D`) — check `glGetError()` after `glTexImage2D`; on failure delete the texture, delete the shader program, return error (E-5).
4. **Register texture with CUDA** (`cudaGraphicsGLRegisterImage`) — `CUDA_CHECK` (abort on failure; texture + shader already created, so abort is consistent).
5. **Allocate accumulation buffers** (`accumBuffer.allocate`, `countBuffer.allocate`).
6. **Create VAO/VBO** — check GL handles are non-zero after `glGenVertexArrays`/`glGenBuffers` (E-5).
7. Set `heatmap.resolution`, cache uniform locations (see Step 4a).

If any step 3–6 fails, call `destroyDensityHeatmap(heatmap)` before returning the error to ensure clean rollback (E-3/W-4).

Update the `@post` Doxygen as specified in 3b.

#### 3d — Fix `destroyDensityHeatmap` error comment (W-11)

Change:
```cpp
// Swallow error — safe to ignore on context teardown
```
To:
```cpp
// Ignore cudaErrorInvalidContext (context already torn down) but log any other error
cudaError_t err = cudaGraphicsUnregisterResource(heatmap.cudaTexResource);
if (err != cudaSuccess && err != cudaErrorInvalidContext) {
    std::fprintf(stderr, "DensityHeatmap: cudaGraphicsUnregisterResource error: %s\n",
                 cudaGetErrorString(err));
}
```
(Remove `static_cast<void>(...)` wrapper.)

#### 3e — Update call sites

**`src/main.cpp`:**
```cpp
auto heatmapResult = psim::rendering::initDensityHeatmap(
    heatmap, HEATMAP_RESOLUTION,
    (binaryDir / "shaders/heatmap.vert").string(),   // note: binaryDir fix is Step 6
    (binaryDir / "shaders/heatmap.frag").string());
if (!heatmapResult) {
    std::fprintf(stderr, "Failed to init heatmap: %s\n", heatmapResult.error().message().c_str());
    // Continue without heatmap — not fatal
}
```

**`tests/unit/rendering/DensityHeatmapTest.cpp`:**  
Update all `initDensityHeatmap(...)` calls to capture and assert the result:
```cpp
auto result = psim::rendering::initDensityHeatmap(
    heatmap, TEST_HEATMAP_RESOLUTION,
    SHADER_DIR "/heatmap.vert", SHADER_DIR "/heatmap.frag");
ASSERT_TRUE(result.has_value()) << result.error().message();
```
For the `Init_ReturnsError_WhenShaderPathInvalid` test, pass `"nonexistent.vert"` and assert `!result.has_value()`.  
For the `Init_NegativeResolution_ReturnsError` test, pass `resolution = -1` and assert `!result.has_value()`.

**Verify:**
```bash
cmake --build build --target particle_sim particle_sim_gpu_tests 2>&1 | grep -E "error:|warning:" | head -20
```
Expected: zero errors (the two previously-failing RED tests now compile and pass GREEN). Run:
```bash
cd build && ctest --output-on-failure 2>&1 | tail -5
```
Expected: ≥ 77 tests pass (new tests add to the count; DensityHeatmap tests still Skipped in headless).

---

### Step 4 — Destructor guard + API + performance fixes

**Goal:** Fix E-3, W-1, W-2 (already done in Step 2), W-5, W-10, W-17.

**Files:** `DensityHeatmap.cuh`, `DensityHeatmap.cu`, `shaders/heatmap.frag`, `src/main.cpp`

#### 4a — Cache uniform locations in struct (W-1)

Add fields to `DensityHeatmap` struct:
```cpp
int uniformDensityTexLoc{-1};  ///< Cached location of u_densityTex uniform.
int uniformMaxDensityLoc{-1};  ///< Cached location of u_maxDensity uniform.
int uniformAlphaLoc{-1};       ///< Cached location of u_alpha uniform.
```

Populate in `initDensityHeatmap` after shader link succeeds:
```cpp
heatmap.uniformDensityTexLoc = glGetUniformLocation(heatmap.shaderProgram, "u_densityTex");
heatmap.uniformMaxDensityLoc = glGetUniformLocation(heatmap.shaderProgram, "u_maxDensity");
heatmap.uniformAlphaLoc      = glGetUniformLocation(heatmap.shaderProgram, "u_alpha");
```

Replace `glGetUniformLocation` calls in `renderDensityHeatmap` with the cached values.

**Decision 9 — Reset on destroy:** `destroyDensityHeatmap` must reset all three fields to `-1` after releasing the shader program, mirroring their default-constructed state:
```cpp
heatmap.uniformDensityTexLoc = -1;
heatmap.uniformMaxDensityLoc = -1;
heatmap.uniformAlphaLoc      = -1;
```

**Step 1b additions (Decision 9):** Expand `Destroy_AfterInit_SetsTextureIdToZero` to also assert:
```cpp
EXPECT_EQ(heatmap.uniformDensityTexLoc, -1);
EXPECT_EQ(heatmap.uniformMaxDensityLoc, -1);
EXPECT_EQ(heatmap.uniformAlphaLoc,      -1);
```

#### 4b — Add `u_alpha` uniform to shader and render path (W-17)

**`shaders/heatmap.frag`** — add uniform and replace literal:
```glsl
uniform float u_alpha;
// ...
fragColor = vec4(c, u_alpha);  // was: vec4(c, 0.85)
```

**`DensityHeatmap.cuh`** — add field (default matches old hardcoded value):
```cpp
float alpha{0.85F};  ///< Overlay transparency (0 = fully transparent, 1 = opaque).
```

**`DensityHeatmap.cu`** — in `renderDensityHeatmap`:
```cpp
glUniform1f(heatmap.uniformAlphaLoc, heatmap.alpha);
```

**`src/main.cpp`** — optionally add an ImGui slider for `heatmap.alpha` alongside the existing Max Density slider.

#### 4c — Fix NOLINT comment on reinterpret_cast (W-5)

In `initDensityHeatmap` VAO setup, change the trailing comment to an inline suppression:
```cpp
reinterpret_cast<const void*>(2U * sizeof(float))  // NOLINT(cppcoreguidelines-pro-type-reinterpret-cast)
```

#### 4d — Add destructor assertion (E-3)

In `DensityHeatmap.cuh`, update the destructor:
```cpp
~DensityHeatmap()
{
    // Debug guard: GL + CUDA resources must have been explicitly released
    // via destroyDensityHeatmap() before this object is destroyed.
    assert(textureId == 0U && "DensityHeatmap destroyed without calling destroyDensityHeatmap");
}
```

Update the Doxygen on the struct: note that the destructor asserts `textureId == 0` in Debug builds.

**Verify:**
```bash
cmake --build build --target particle_sim particle_sim_gpu_tests 2>&1 | grep "error:" | head -10
cd build && ctest --output-on-failure 2>&1 | tail -5
```
Expected: clean build, all tests pass.

---

### Step 5 — Relocate `scatterRandomParticles`

**Goal:** Fix E-7, W-19. Moves the demo utility out of the production API.

**Files:** `FluidSPHModel.cuh`, `FluidSPHModel.cu`, new `tests/fixtures/SphTestHelpers.hpp`, `src/main.cpp`, `tests/CMakeLists.txt`

#### 5a — Create `tests/fixtures/SphTestHelpers.hpp`

New file with a single function (Decision 11 — hard CUDA TU guard at the top):

```cpp
#pragma once
// This file contains inline CUDA device calls (CUDA_CHECK / cudaMemcpy).
// It must only be included from .cu translation units compiled by nvcc.
#ifndef __CUDACC__
#  error "SphTestHelpers.hpp must only be included from .cu files compiled by nvcc."
#endif

#include "models/FluidSPHModel.cuh"
#include <cstdint>
#include <random>
#include <vector>

namespace psim::test
{

/// @brief Fills particle positions with random values in the domain bounds.
///
/// Seeds the RNG from `seed` for reproducibility. Intended for test fixture
/// setup only — has no physical meaning.
///
/// @param model  Initialised FluidSPHModel with valid device buffers.
/// @param seed   RNG seed.
inline void seedParticlesRandom(psim::models::FluidSPHModel& model, uint32_t seed)
{
    const uint32_t count = model.params.particleCount;
    std::mt19937 rng{seed};
    std::uniform_real_distribution<float> distX{model.params.domainMin.x, model.params.domainMax.x};
    std::uniform_real_distribution<float> distY{model.params.domainMin.y, model.params.domainMax.y};

    std::vector<float> hX(count);
    std::vector<float> hY(count);
    for (uint32_t i = 0; i < count; ++i) {
        hX[i] = distX(rng);
        hY[i] = distY(rng);
    }
    CUDA_CHECK(cudaMemcpy(model.posX.get(), hX.data(), count * sizeof(float), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(model.posY.get(), hY.data(), count * sizeof(float), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemset(model.velX.get(), 0, count * sizeof(float)));
    CUDA_CHECK(cudaMemset(model.velY.get(), 0, count * sizeof(float)));
}

} // namespace psim::test
```

**Note:** Decision 11 provides a hard `#ifndef __CUDACC__ #error` guard; the comment above is the backstop but the compile-time guard is the enforcement mechanism.

#### 5b — Remove from `FluidSPHModel.cuh` and `FluidSPHModel.cu`

- Delete the `scatterRandomParticles` declaration from `FluidSPHModel.cuh`
- Delete the `scatterRandomParticles` implementation from `FluidSPHModel.cu`
- Remove the `#include <random>` and `#include <vector>` that were added solely for it (confirm no other use in the file before removing)

#### 5c — Update `src/main.cpp`

Replace:
```cpp
psim::models::scatterRandomParticles(sphModel, SPH_DEMO_RNG_SEED);
```
With direct host-side initialization in a `.cu`-compiled context. Since `main.cpp` is g++-compiled, the simplest approach is to add a thin wrapper function `initSphDemo(FluidSPHModel& model)` in `FluidSPHModel.cu` that encapsulates the seeded scatter call internally (using the same logic) — this keeps `main.cpp` CUDA-free.

Name it `initSphDemoParticles(FluidSPHModel& model)` declared in `FluidSPHModel.cuh` (with clear Doxygen noting it is a demo entrypoint for Phase 6 integration, not part of the simulation model API). This trades one wrong API placement for a correctly-scoped but still-production-compiled function. Document it as `@deprecated — to be removed when Phase 7 provides a proper spawn system`.

#### 5d — Update `tests/CMakeLists.txt`

Add `tests/fixtures/` to the include path for `particle_sim_gpu_tests`:
```cmake
target_include_directories(particle_sim_gpu_tests PRIVATE ${CMAKE_SOURCE_DIR}/tests)
```

**Verify:**
```bash
cmake --build build --target particle_sim particle_sim_gpu_tests 2>&1 | grep "error:" | head -10
cd build && ctest --output-on-failure 2>&1 | tail -5
```
Expected: clean build, all tests pass.

---

### Step 6 — SPH per-frame update + shader path resolution

**Goal:** Fix E-8, W-15, W-16.

**File:** `src/main.cpp`

#### 6a — Per-frame SPH density update (E-8)

Inside the main loop, after `particleSystemUpdate`, add:
```cpp
// Update SPH density from current particle positions
{
    const psim::spatial::ParticlePositionsView posView{
        sphModel.posX.get(), sphModel.posY.get(), particleCount};
    sphIndex.rebuild(posView);
}
psim::models::computeDensity(sphModel, sphIndex);
```

This replaces the static one-time computation at startup. The startup computation can be removed (the first frame will compute it).

**Performance note:** `computeDensity` currently calls `cudaDeviceSynchronize` internally (tracked in `plan.md` as a future perf TODO). This is acceptable for this phase.

#### 6b — Resolve shader paths relative to `binaryDir` (W-16)

Verify `binaryDir` is already computed in `main.cpp` for config path resolution. Apply the same pattern:
```cpp
const auto heatmapVertPath = (binaryDir / "shaders" / "heatmap.vert").string();
const auto heatmapFragPath = (binaryDir / "shaders" / "heatmap.frag").string();
auto heatmapResult = psim::rendering::initDensityHeatmap(
    heatmap, HEATMAP_RESOLUTION, heatmapVertPath, heatmapFragPath);
```

#### 6c — Remove redundant enabled guard (W-15)

Change:
```cpp
if (heatmap.enabled)
{
    psim::rendering::updateDensityHeatmap(heatmap, sphModel);
    psim::rendering::renderDensityHeatmap(heatmap);
}
```
To:
```cpp
psim::rendering::updateDensityHeatmap(heatmap, sphModel);
psim::rendering::renderDensityHeatmap(heatmap);
```
The `enabled` guard is authoritative inside both functions; the outer guard is redundant duplication.

**Verify:**
```bash
cmake --build build --target particle_sim particle_sim_gpu_tests 2>&1 | grep "error:" | head -10
cd build && ctest --output-on-failure 2>&1 | tail -5
```
Expected: clean build, all tests pass.

---

### Step 7 — REFACTOR + validation

Run the full quality gate:

```bash
cd /home/cpeddle/projects/personal/particle-sim

# Format all modified files
clang-format -i \
  src/rendering/DensityHeatmap.cuh \
  src/rendering/DensityHeatmap.cu \
  src/models/FluidSPHModel.cuh \
  src/models/FluidSPHModel.cu \
  src/main.cpp \
  tests/unit/rendering/DensityHeatmapTest.cpp \
  tests/fixtures/SphTestHelpers.hpp

# Verify format clean
clang-format --dry-run --Werror \
  src/rendering/DensityHeatmap.cuh \
  src/rendering/DensityHeatmap.cu \
  src/models/FluidSPHModel.cuh \
  src/models/FluidSPHModel.cu \
  src/main.cpp \
  tests/unit/rendering/DensityHeatmapTest.cpp \
  tests/fixtures/SphTestHelpers.hpp 2>&1 && echo "format clean"

# clang-tidy on all non-CUDA modified files
clang-tidy -p build/ \
  src/rendering/DensityHeatmap.cuh \
  tests/unit/rendering/DensityHeatmapTest.cpp \
  src/models/FluidSPHModel.cuh 2>&1 | grep "error:" | head -20

# Full build + all tests
cmake --build build --target particle_sim particle_sim_gpu_tests
cd build && ctest --output-on-failure 2>&1 | tail -8
```

Expected final test output:
```
100% tests passed, 0 tests failed out of NN
```
Where NN ≥ 77 (new tests from Step 1 add to the count).

---

### Step 8 — Code review

Delegate to **both** the `code-reviewer` and `expert-cpp` agents with the full diff of this plan's changes against the Phase 6 baseline.

- `code-reviewer` — architectural correctness, API quality, error handling, test coverage, SOLID/RAII compliance
- `expert-cpp` — C++23 idiom correctness, CUDA safety, clang-tidy / UBSan exposures, edge cases in new code

Both reviews must report **zero ERRORs** before this plan is complete.

Update the `Progress` checklist with a timestamp and reviewer findings in `Surprises & Discoveries`. If either reviewer reports ERRORs, return to the responsible step and fix before re-reviewing. A second round-trip review is mandatory after any ERROR fix.

---

## Validation and Acceptance

| # | Check | Observable Evidence |
|---|-------|---------------------|
| 1 | Build clean | `cmake --build build --target particle_sim particle_sim_gpu_tests` — zero errors, zero warnings |
| 2 | All tests pass | `ctest --output-on-failure` — `100% tests passed, 0 tests failed out of NN` |
| 3 | New DensityHeatmap tests in count | `ctest -R DensityHeatmap --verbose` — lists ≥ 9 test names (3 original + 6 new) |
| 4 | clang-format clean | `clang-format --dry-run --Werror` on all modified files — no output |
| 5 | clang-tidy clean | `clang-tidy -p build/ src/rendering/DensityHeatmap.cuh tests/unit/rendering/DensityHeatmapTest.cpp src/models/FluidSPHModel.cuh` — zero error lines on new code |
| 6 | `scatterRandomParticles` removed from production API | `grep -r "scatterRandomParticles" src/` — no results |
| 7 | `seedParticlesRandom` in test fixtures only | `grep -r "seedParticlesRandom" .` — results only under `tests/` and `src/main.cpp` (via `initSphDemoParticles` bridge) |
| 8 | `initDensityHeatmap` returns `std::expected` | `grep "std::expected" src/rendering/DensityHeatmap.cuh` — one result on the function declaration |
| 9 | No CWD-relative shader paths in `main.cpp` | `grep '"shaders/' src/main.cpp` — no results (paths now built via `binaryDir`) |
| 10 | Code review — zero ERRORs | Reviewer agent output: no lines starting with `ERROR` |

---

## Idempotence and Recovery

- **Rollback point:** `git stash` before each step. If a step produces broken compilation mid-way, `git stash pop` to restore baseline.
- **Step 3 is highest risk** (signature change cascades to three files). Open all three files in separate tabs before starting. If compilation fails midway, check all three have been updated.
- **Step 5** removes a function used by `main.cpp`. Build `particle_sim` first after removing from the header; do not attempt to build `particle_sim_gpu_tests` until the new `tests/fixtures/SphTestHelpers.hpp` exists.
- **clang-format** must be run after every edit — the `— NOLINT` comment style (Step 4c) can be reformatted away by a stray format run.

---

## Artifacts and Notes

**Modified:**
- `src/rendering/DensityHeatmap.cuh`
- `src/rendering/DensityHeatmap.cu`
- `shaders/heatmap.frag`
- `src/models/FluidSPHModel.cuh`
- `src/models/FluidSPHModel.cu`
- `src/main.cpp`
- `tests/unit/rendering/DensityHeatmapTest.cpp`
- `tests/CMakeLists.txt`

**New:**
- `tests/fixtures/SphTestHelpers.hpp`

---

## Interfaces and Dependencies

**Depends on:**
- Phase 6 — `DensityHeatmap` struct, CUDA kernels, GL lifecycle (this plan modifies all of these)
- Phase 4 — `FluidSPHModel`, `computeDensity` (used in Step 6 per-frame loop)
- Phase 3 — `UniformGridIndex::rebuild` (used in Step 6 per-frame loop)

**Required by:** Nothing downstream — Phase 6a is a correctness pass on a debug tool.

**Deferred (tracked in `plan.md`):**
- W-18 — `DensityHeatmapInput` view struct to decouple `updateDensityHeatmap` from `FluidSPHModel` field layout. Scheduled for a dedicated rendering-decoupling phase.

---

## Outcomes & Retrospective

**Completed 2026-03-16. All 10 ERRORs and 18/19 WARNINGs resolved (W-18 deferred per plan).**

**Test delta:** 77 → 83 tests (6 new `DensityHeatmap` lifecycle tests; all skip in headless — correct behaviour).

**Key changes shipped:**
- `initDensityHeatmap` returns `[[nodiscard]] std::expected<void, std::error_code>` with shaders-first init order and full rollback on any failure path
- `DensityHeatmap` destructor asserts `textureId == 0` in Debug builds (fail-fast ownership guard)
- CUDA kernel safety: `CUDA_CHECK(cudaGetLastError())` after all 3 kernel launches; `cudaDeviceSynchronize()` before surface destroy
- Out-of-domain particle discard with per-frame atomic counter + `fprintf` diagnostic
- Uniform locations cached in struct; `u_alpha` shader uniform added; `float alpha{DEFAULT_ALPHA}` field
- `scatterRandomParticles` removed from production API; `initSphDemoParticles` bridge added; `SphTestHelpers.hpp` created with hard `#ifndef __CUDACC__ #error` guard
- Per-frame `sphIndex.rebuild` + `computeDensity` in main loop
- All shader paths resolved via `binaryDir` (no CWD-relative strings)

**Infrastructure discoveries (recorded for future phases):**
- `CMAKE_CUDA_STANDARD 23` silently fails with nvcc 13.2; `-Xcompiler=-std=c++23` is the correct workaround
- `cudaErrorInvalidContext` is Driver API only; runtime teardown errors are `cudaErrorCudartUnloading` / `cudaErrorContextIsDestroyed`
- clang-tidy must lint CUDA headers via an including `.cpp` TU — running tidy directly on `.cuh` fails on nvcc compile flags
