# [Short action-oriented title]

This ExecPlan is a living document. Keep `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` up to date as work proceeds.

This plan must be maintained according to `.github/planning/PLANS.md` and aligned with `.github/copilot-instructions.md`.

**Date:** YYYY-MM-DD  
**Status:** 🔄 In Progress | ✅ Complete | ❌ Blocked  
**Owner:** Agent or developer name  
**Refs:** PS-XXXX

---

## Purpose / Big Picture

Explain what users or the system gains after this change and how to observe it working from outside the code.

**Term definitions** (define any project-specific term used in this plan):
- *Term:* Definition.

---

## Progress

- [ ] (YYYY-MM-DD HH:MM UTC) Initial plan drafted.
- [ ] (YYYY-MM-DD HH:MM UTC) RED tests added — failing tests committed, no implementation yet.
- [ ] (YYYY-MM-DD HH:MM UTC) GREEN implementation completed — all RED tests now pass.
- [ ] (YYYY-MM-DD HH:MM UTC) REFACTOR + validation completed.
- [ ] (YYYY-MM-DD HH:MM UTC) Code review — `code-reviewer` agent (or human) sign-off, zero ERRORs.
- [ ] (YYYY-MM-DD HH:MM UTC) Compound — `Outcomes & Retrospective` filled; learnings applied to governance files (or "no updates needed").
- [ ] (YYYY-MM-DD HH:MM UTC) Scratch files removed — `rm -rf build/_tmp` *(skip if no scratch files were created)*.

---

## Surprises & Discoveries

- Observation: _Unexpected behaviour or insight._  
  Evidence: _Concise output, error, or test result._

---

## Decision Log

- Decision: _What was decided._  
  Rationale: _Why this path was chosen over alternatives._  
  Date/Author: _YYYY-MM-DD, name_

---

## Outcomes & Retrospective

*(Complete this section after the plan closes.)*

**What was achieved:**

**What remains (if anything):**

**Patterns to promote** (add to `copilot-instructions.md`):

**Reusable findings** (worth preserving in `.github/planning/investigations/`):

**New anti-patterns** (failure modes or wrong approaches to document as warnings):

---

## Context and Orientation

Describe the relevant current state for a reader with no prior context. Name files and modules by repository-relative path. Define any term not defined in the glossary above.

---

## Plan of Work

Describe the sequence of edits in concrete terms. For each logical unit of work, name the file, target function/module, and intended change.

> **TDD order is mandatory.** The first implementation steps must be test files written to fail (RED). Only after tests fail does implementation begin (GREEN). Code review is the final gate — include it as the last concrete step.

---

## Concrete Steps

Each step specifies the delegated agent, exact commands, working directory, and expected output.

### Step 1 — Write RED Tests
- **Agent:** `testing`
- **Files:** `tests/unit/<subsystem>/<Feature>Test.cpp`
- **Action:** Write failing tests for each observable behaviour. Commit the failing tests.
- **Depends on:** None
- **Working directory:** repo root
- **Expected output:** Tests compile and fail with meaningful failure messages (not compile errors).

### Step 2 — Implement GREEN
- **Agent:** `developer`
- **Files:** `src/...`
- **Action:** Implement the minimum code needed to make the RED tests pass.
- **Depends on:** Step 1
- **Working directory:** repo root
- **Expected output:** All RED tests pass. No regressions.

### Step 3 — Refactor and Validate
- **Agent:** `developer`
- **Action:** Refactor without breaking tests. Run clang-format, clang-tidy, and sanitizer builds.
- **Depends on:** Step 2
- **Commands:**
  ```bash
  clang-format -i --style=file:.clang-format <changed files>
  clang-tidy -p build/ <changed .cpp/.hpp files>
  cmake --build build && ctest --test-dir build --output-on-failure
  ```
- **Expected output:** Zero format violations, zero tidy findings, all tests pass.

### Step 4 — Code Review
- **Agent:** `code-reviewer`
- **Action:** Full review against `copilot-instructions.md`, C++ Core Guidelines, and sanitizer compliance.
- **Depends on:** Step 3
- **Expected output:** Review report with zero ERRORs.

### Step 5 — Compound
- **Agent:** `overlord` (or current agent)
- **Action:** Complete `Outcomes & Retrospective`. For each finding:
  - **Patterns to promote** → add to `copilot-instructions.md` or relevant skill/agent files
  - **Reusable findings** → preserve in `.github/planning/investigations/` or skill reference files
  - **New anti-patterns** → document as warnings in governance files
- **Depends on:** Step 4
- **Expected output:** Governance files updated (or "no updates needed" recorded in Progress).

---

## Validation and Acceptance

Acceptance criteria must be observable from outside the code:

- `cmake --build build && ctest --test-dir build --output-on-failure` exits 0 and all named tests pass
- `clang-format --dry-run --Werror` exits 0 for all changed files
- `clang-tidy -p build/` exits 0 for all changed `.cpp`/`.hpp` files
- ASan + UBSan build exits 0 (for CPU code)
- Code review reports zero ERRORs

---

## Idempotence and Recovery

Steps that can be re-run safely:
- Build steps: re-running with same inputs produces same output
- Test runs: idempotent — no side effects on the test environment

Recovery if a step fails:
- If GREEN fails: re-run failing tests to identify new failures; do not modify RED tests to make them pass
- If clang-tidy fails: fix the finding; do not suppress without justification

---

## Artifacts and Notes

- Branch: `feature/<short-slug>`
- Refs: PS-XXXX
- Scratch files (if any): `build/_tmp/` — this directory is gitignored; remove on plan completion with `rm -rf build/_tmp`.

---

## Interfaces and Dependencies

List modules, classes, or external systems this plan touches:

| Component | Type | Impact |
|-----------|------|--------|
| `src/...` | Implementation | Internal change |
| `tests/...` | Tests | New / modified tests |
