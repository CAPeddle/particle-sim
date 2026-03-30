# Agent Guidance

This repository uses **ExecPlans** for complex, multi-step implementation work.

## Repository Structure

- **`.github/agents/`** — Agent definition files
- **`.github/hooks/`** — `agentStop` quality gate (clang-format + clang-tidy)
- **`.github/instructions/`** — Path-specific C++ coding rules
- **`.github/planning/`** — ExecPlan standard, templates, and active plans
- **`.github/skills/`** — Agent reusable skills
- **`AGENTS.md`** (this file) — Agent guidance and ExecPlan trigger policy

## ExecPlans

When writing complex features or significant refactors, use an ExecPlan from `.github/planning/PLANS.md` from design to implementation.

An ExecPlan **must** be created before implementation begins, maintained as a living document during execution, and validated with concrete build/test evidence before completion.

### When an ExecPlan is required

**Default: use an ExecPlan.** Create an ExecPlan **before any work begins** — including investigation, evaluation, or research steps that precede implementation — when any of the following applies:

- Multi-file feature work or significant refactor
- Cross-module changes with non-trivial dependency impact
- Non-trivial bug fixes with unclear root cause
- Any work requiring multiple milestones, prototypes, or rollback planning
- **Investigation-first tasks** — tasks where the first step is to explore, evaluate options, or compile findings before implementing. The ExecPlan must exist before the investigation begins, not only before the implementation phase.
- **Governance or documentation work** spanning multiple files

> **Common failure mode:** A prompt phrased as "investigate first, then implement" may be treated as not requiring an ExecPlan until implementation starts. This is incorrect — any multi-step task (including one that begins with research or evaluation) requires an ExecPlan before the first step.

An ExecPlan may be skipped **only** for truly trivial, single-step operations (e.g., fixing a typo in one file, committing already-staged changes). When in doubt, create the plan — the overhead is low and the traceability is valuable.

### Compound step

Every completed ExecPlan must end with a **Compound step**: review `Outcomes & Retrospective` and apply learnings to governance files. This is how the project gets smarter over time. See `.github/planning/PLANS.md` for enforcement details.

For detailed guidance on ExecPlan structure and requirements, see [.github/planning/PLANS.md](.github/planning/PLANS.md).

## Quality Gate

Every agent session triggers `.github/hooks/quality-gate.json` on stop.  
The gate runs **clang-format** and **clang-tidy** on all modified C++ files.  
The session exit is non-zero if either tool reports a violation.

Fix all violations before closing the session. Do not suppress checks inline without a code comment explaining why.

## Scratch Files

When a task requires throwaway compilation tests, prototype snippets, or one-off validation harnesses, write them to **`build/_tmp/`** (relative to the repo root) instead of `/tmp`.

- `build/` is already gitignored — scratch files stay out of git and out of the workspace root.
- The directory is inside the workspace, so no sandbox write-permission prompt is required.
- Create the directory if it does not exist: `mkdir -p build/_tmp`
- **Clean up after the ExecPlan is complete.** The final step of every ExecPlan that used scratch files must run `rm -rf build/_tmp` and record that in `Progress`.

## CUDA-Specific Notes

- **clang-format** runs on `.cu` files — CUDA source can be formatted
- **clang-tidy** skips `.cu` files — limited CUDA support in clang-tidy
- GPU kernels follow different naming: `camelCaseKernel` suffix
- All CUDA API calls must be wrapped with error-checking macro `CUDA_CHECK`
