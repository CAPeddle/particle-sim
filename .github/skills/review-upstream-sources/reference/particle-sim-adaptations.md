# particle-sim Adaptation Notes

Intentional local customizations that differ from the Generic governance template.
When reviewing upstream changes, **do not overwrite** these — they are deliberate.

This file is shared between the `review-upstream-sources` and `adopt-template-updates` skills.

| Area | particle-sim Convention | Generic Convention | Reason |
|------|------------------------|--------------------|--------|
| Methods/functions | `camelCase` | `PascalCase` | CUDA kernel naming consistency |
| Private members | `camelCase` (no prefix) | `_camelCase` | Established codebase convention |
| Docstrings | `/// @brief` | `/*! */` | Doxygen `///` style preferred |
| Headers | `#pragma once` | `#ifndef` guards | Already established |
| Directory layout | `src/` (no `include/`) | `include/` + `src/` | GPU project — all headers in `src/` |
| Sanitizers | ASan + UBSan only | ASan + MSan + TSan + UBSan | CUDA incompatible with MSan/TSan |
| Package manager | FetchContent | Conan 2.x | CUDA deps not well-supported by Conan |
| CMake version | 3.29+ | 4.x | CUDA 13.2 compatibility |
| CUDA sections | Present throughout | Absent | Core project requirement |
