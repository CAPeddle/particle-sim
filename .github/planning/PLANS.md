# ExecPlans — particle-sim

This document defines how to write and execute an **ExecPlan** in this repository.

An ExecPlan is a self-contained implementation plan that an agent or developer can follow end-to-end without any prior chat context.

---

## When an ExecPlan is Required

Create an ExecPlan before implementation when work includes any of:

- Multi-file feature work or significant refactor
- Cross-module changes with non-trivial dependency impact
- Non-trivial bug fixes with unclear root cause
- Work requiring multiple milestones, prototypes, or rollback planning

For small, single-file, low-risk fixes, an ExecPlan is optional.

---

## Repository Requirements

Every ExecPlan must align with `.github/copilot-instructions.md`:

- **TDD is mandatory for all new code.** Write failing tests (RED) *before* any implementation code exists. The `Progress` checklist must contain a `RED tests added` entry that precedes the `GREEN implementation` entry.
- **Code review is mandatory.** Every plan that creates or modifies code must include a code-review step in `Concrete Steps` and `Progress`. No plan is complete until code-review reports zero ERRORs.
- Use project naming (`psim::`, camelCase methods), architecture, and safety constraints throughout.
- **Define every project-specific term on first use.** Do not assume the reader has prior knowledge of this codebase. A contributor encountering the plan for the first time must be able to execute it without external references.

---

## Mandatory Sections

Each ExecPlan must contain these sections:

1. `Purpose / Big Picture`
2. `Progress` (checkbox list with timestamps)
3. `Surprises & Discoveries`
4. `Decision Log`
5. `Outcomes & Retrospective`
6. `Context and Orientation`
7. `Plan of Work`
8. `Concrete Steps`
9. `Validation and Acceptance`
10. `Idempotence and Recovery`
11. `Artifacts and Notes`
12. `Interfaces and Dependencies`

---

## Required Quality Bar

- **Self-contained and novice-friendly.** A contributor with no prior context must be able to execute the plan.
- **Observable acceptance criteria.** Describe behaviour observable from outside the change — test pass output, command output, file produced — never internal checks like "function returns X" or "variable is set".
- **Commands include working directory and expected output.**
- **Risky operations include retry/rollback guidance.**
- **The plan stays current** as work proceeds.

### Mandatory Progress Checkpoints (for any plan that creates or modifies code)

The `Progress` list must contain these four checkpoints in order:

1. `RED tests added` — failing tests committed before any implementation
2. `GREEN implementation completed` — code written to pass the tests
3. `REFACTOR + validation completed`
4. `Code review — zero ERRORs` — code-reviewer agent (or human) sign-off

A plan missing any of these four checkpoints is incomplete regardless of build/test status.

---

## Jargon and Terms

Define every project-specific term on first use in the plan. Do not reference acronyms, internal system names, or architectural concepts without defining them in the plan body.

---

## Location and Naming

- Store active ExecPlans under `.github/planning/execplans/`.
- Name with date + short action-oriented slug:
  - `YYYY-MM-DD-short-action-oriented-title.md`
  - Example: `2026-04-01-implement-uniform-grid-index.md`

---

## Living Document Policy

At each meaningful stop point:
- Update `Progress` with timestamped status
- Add key decisions to `Decision Log`
- Record unexpected behaviour in `Surprises & Discoveries`
- Keep commands, acceptance criteria, and outcomes in sync with reality

At completion, update `Outcomes & Retrospective` with:
- **Patterns to promote** — coding, testing, or workflow patterns worth adding to `copilot-instructions.md`
- **Reusable findings** — research conclusions worth preserving in `.github/planning/investigations/`
- **New anti-patterns** — failure modes, wrong approaches, or gotchas to document as warnings

---

## Task Sizing

Agent sessions degrade in quality as context fills. ExecPlan tasks must be sized to prevent this.

**Atomic task rule:** Each item in `Concrete Steps` must be completable in a single healthy agent session. If a step requires reading many files, writing many files, multiple build/test cycles, and follow-up fixes — it is too large. Split it.

**Signs a step is too large:**
- A single step takes more than ~20 tool calls
- The step requires holding more than 5–6 files in reasoning simultaneously
- The step mixes research, implementation, and validation in one unit

If an in-progress plan has over-large steps, split them and record the split in `Surprises & Discoveries`.
