---
name: conventional-commit
description: >
  Workflow for generating Conventional Commit messages for particle-sim.
  Inspects staged changes and produces a well-formed commit message using
  the project's allowed types and scopes.
---

# Conventional Commit — particle-sim

Generate a correctly formatted Conventional Commit message for the current staged changes.

---

## Workflow

1. Run `git status` to review changed files.
2. Run `git diff --cached` to inspect staged changes (or `git diff` for unstaged).
3. Stage your changes with `git add <file>` if not already staged.
4. Construct the commit message using the structure below.
5. Run the commit:

```bash
git commit -m "type(scope): description"
```

---

## Commit Message Structure

```
<type>(<scope>): <short imperative description>

[optional body — more detail]

[optional footer — BREAKING CHANGE or Refs: PS-XXXX]
```

---

## Allowed Types

| Type | When to use |
|------|-------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `refactor` | Code change that is neither a fix nor a feature |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `docs` | Documentation only |
| `build` | CMake, dependencies, toolchain changes |
| `ci` | CI/CD configuration |
| `chore` | Housekeeping (renaming, cleanup) |
| `revert` | Revert a prior commit |

---

## particle-sim Scopes

| Scope | Area |
|-------|------|
| `core` | `src/core/` — Application, ISimulationModel, Parameter |
| `spatial` | `src/spatial/` — ISpatialIndex, UniformGridIndex |
| `rendering` | `src/rendering/` — Renderer, ParticleSystem, CUDA-GL interop |
| `models` | `src/models/` — GameOfLifeCUDA, FluidSPHCUDA |
| `config` | `src/config/` — ConfigReader, config.toml |
| `ui` | `src/ui/` — ImGuiLayer |
| `build` | CMakeLists.txt, FetchContent, toolchain |
| `docs` | docs/, ADRs, spikes, CLAUDE.md |

---

## Examples

```
feat(spatial): add UniformGridIndex rebuild with counting sort

fix(rendering): correct CUDA-GL interop sync after particle update

refactor(core): extract parameter validation into separate method

perf(models): coalesce SPH density kernel memory access

test(config): add ConfigReader fixture for missing_key case

build(core): add toml11 v4.4.0 FetchContent dependency

docs(spatial): add ADR-0002 for uniform grid cell size selection

Refs: PS-0012
```

---

## Validation

- **type**: Must be one of the allowed types above
- **scope**: Optional but recommended; use project scopes
- **description**: Required; use imperative mood ("add", not "added")
- **body**: Optional; use for additional context or rationale
- **footer**: Use `BREAKING CHANGE:` for API breaks; use `Refs: PS-XXXX` for ticket references
- **Breaking changes**: Append `!` after scope — `feat(core)!:` — and add `BREAKING CHANGE:` in footer
