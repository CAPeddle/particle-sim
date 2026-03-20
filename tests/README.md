# Test Harness Notes

## Windows death-test workaround

On Windows, one `EXPECT_DEATH` constructor test in `UniformGridIndexTest` can hang when launched through CTest (`ctest` + `gtest_discover_tests` process orchestration). To keep the default suite reliable, that test is skipped from default CTest discovery on Windows and must be run manually.

Excluded from default `ctest` on Windows:
- `UniformGridIndexTest.Constructor_ZeroCellSize_Aborts`
- `UniformGridIndexTest.Constructor_NegativeCellSize_Aborts`
- `UniformGridIndexTest.Constructor_InvertedDomain_Aborts`

All three share the same root cause: the `EXPECT_DEATH` subprocess model used by GoogleTest
deadlocks under CTest's process orchestration on Windows.

### Default suite

Run the normal suite as usual:

```bash
ctest --test-dir build --output-on-failure
```

### Manual death-test execution (required on Windows)

Run the workaround target (covers all three excluded tests):

```bash
cmake --build build --target run_uniform_grid_death_tests
```

If you need to run them directly:

```bash
./build/tests/particle_sim_tests.exe --gtest_filter=UniformGridIndexTest.Constructor_ZeroCellSize_Aborts:UniformGridIndexTest.Constructor_NegativeCellSize_Aborts:UniformGridIndexTest.Constructor_InvertedDomain_Aborts
```

### Important note

Treat this as a test-runner/platform issue, not a functional pass condition for constructor validation. The constructor abort behavior is still validated; it is just executed via direct gtest process launch on Windows.