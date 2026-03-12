# Configure AI Governance Infrastructure from Generic Starter Kit

This ExecPlan is a living document. Keep `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` up to date as work proceeds.

This plan must be maintained according to `.github/planning/PLANS.md` and aligned with `.github/copilot-instructions.md`.

**Date:** 2026-03-12  
**Status:** ✅ Complete  
**Owner:** Agent  
**Refs:** Initial setup — no ticket

---

## Purpose / Big Picture

Configure the full AI governance infrastructure for particle-sim by adapting the generic starter kit files in `Generic/` to the project's specific needs (C++23 + CUDA 20, `psim::` namespace, particle simulation domain).

After completion:
- **clang-format** and **clang-tidy** enforce code quality on every edit
- **Agent definitions** guide Copilot toward project-specific patterns
- **Quality gate hook** runs automatically on agent session stop
- **Build-and-test skill** provides step-by-step build instructions
- **ExecPlan templates** enable structured planning for complex work

**Term definitions:**
- *Generic folder:* `Generic/` directory containing template AI governance files with placeholders
- *Quality gate:* An automated hook that runs clang-format and clang-tidy on modified files
- *ExecPlan:* A self-contained implementation plan following `.github/planning/PLANS.md`
- *Agent:* A Copilot agent configuration file (e.g., `developer.agent.md`)
- *Skill:* A reusable agent guidance document for specific tasks (e.g., `build-and-test`)

---

## Progress

- [x] (2026-03-12 15:30 UTC) Initial plan drafted.
- [x] (2026-03-12 15:58 UTC) Create `.clang-format` in project root — adapted from Generic template
- [x] (2026-03-12 15:58 UTC) Create `.clang-tidy` in project root — adapted for camelCase methods, `src/` header filter
- [x] (2026-03-12 15:58 UTC) Create `AGENTS.md` in project root — adapted for particle-sim with CUDA notes
- [x] (2026-03-12 16:01 UTC) Create `.github/agents/` directory and all 6 agent files
- [x] (2026-03-12 16:02 UTC) Create `.github/hooks/` directory with quality gate JSON and scripts (CUDA-aware)
- [x] (2026-03-12 16:04 UTC) Create `.github/instructions/cpp.instructions.md` — adapted for CUDA files
- [x] (2026-03-12 16:04 UTC) Create `.github/planning/PLANS.md` — adapted for particle-sim
- [x] (2026-03-12 16:04 UTC) Create `.github/planning/execplans/_TEMPLATE.md`
- [x] (2026-03-12 16:04 UTC) Create `.github/skills/build-and-test/SKILL.md` — filled with actual build commands
- [x] (2026-03-12 16:08 UTC) Validation: All files created and verified
- [ ] Validation: clang-format test — requires tool installation (`sudo apt install clang-format`)

---

## Surprises & Discoveries

*(Fill in during execution)*

---

## Decision Log

- **Decision:** Use camelCase for functions/methods instead of PascalCase.  
  **Rationale:** Existing codebase already uses camelCase (see `rebuild()`, `queryAll()`). Maintain consistency.  
  **Date/Author:** 2026-03-12, Agent

- **Decision:** Keep `#pragma once` instead of include guards.  
  **Rationale:** Existing codebase already uses `#pragma once`. Maintain consistency.  
  **Date/Author:** 2026-03-12, Agent

- **Decision:** Exclude `.cu` files from clang-tidy enforcement.  
  **Rationale:** clang-tidy has limited CUDA support. Focus on `.cpp`/`.hpp` files.  
  **Date/Author:** 2026-03-12, Agent

---

## Outcomes & Retrospective

*(Complete this section after the plan closes.)*

---

## Context and Orientation

The `Generic/` folder contains a reusable AI governance starter kit with placeholder values:
- `[PROJECT_NAME]` → `particle-sim`
- `[NAMESPACE]` → `psim`
- `[TICKET_PREFIX]` → `PS`
- `[BUILD_COMMAND]` → `cmake --build build`
- `[TEST_COMMAND]` → (tests not yet integrated, placeholder)

The particle-sim project differs from the generic template in:
1. **CUDA support** — `.cu`/`.cuh` files need special handling (excluded from clang-tidy)
2. **Naming conventions** — functions use camelCase, not PascalCase
3. **Headers** — use `#pragma once`, not include guards
4. **Package manager** — uses FetchContent, not Conan
5. **Sanitizers** — limited to ASan/UBSan (CUDA code cannot use MSan/TSan)

Files already created:
- ✅ `.github/copilot-instructions.md` — completed in prior session

Files to create (this plan):
- `.clang-format`
- `.clang-tidy`
- `AGENTS.md`
- `.github/agents/*.agent.md` (5 files)
- `.github/hooks/quality-gate.json`
- `.github/hooks/scripts/quality-gate.sh`
- `.github/hooks/scripts/quality-gate.ps1`
- `.github/instructions/cpp.instructions.md`
- `.github/planning/PLANS.md`
- `.github/planning/execplans/_TEMPLATE.md`
- `.github/skills/build-and-test/SKILL.md`

---

## Plan of Work

1. **Configuration files** — `.clang-format` and `.clang-tidy` at project root
2. **Root agent guidance** — `AGENTS.md` at project root
3. **Agent definitions** — 5 agents in `.github/agents/`
4. **Quality gate hook** — hook config + scripts in `.github/hooks/`
5. **Path-scoped instructions** — C++ file rules in `.github/instructions/`
6. **Planning infrastructure** — PLANS.md and template in `.github/planning/`
7. **Build skill** — Step-by-step build guide in `.github/skills/`
8. **Validation** — Run clang-format on existing code, verify hook structure

---

## Concrete Steps

### Step 1 — Create `.clang-format`

**Agent:** `developer`  
**Files:** `.clang-format`  
**Action:** Copy from `Generic/.clang-format`, replace `[PROJECT_NAME]` with `particle-sim`, adjust comment header.  
**Depends on:** None  
**Working directory:** repo root  
**Expected output:** File created at `.clang-format`

### Step 2 — Create `.clang-tidy`

**Agent:** `developer`  
**Files:** `.clang-tidy`  
**Action:** Copy from `Generic/.clang-tidy`, replace `[PROJECT_NAME]` with `particle-sim`. Adjust naming conventions:
- Change `FunctionCase: CamelCase` → `FunctionCase: camelCase`
- Change `MethodCase: CamelCase` → `MethodCase: camelCase`
- Remove `MemberPrefix: '_'` (particle-sim uses no prefix)
- Update `HeaderFilterRegex` to match `src/.*\.(h|hpp|cuh)$`  
**Depends on:** None  
**Working directory:** repo root  
**Expected output:** File created at `.clang-tidy`

### Step 3 — Create `AGENTS.md`

**Agent:** `developer`  
**Files:** `AGENTS.md`  
**Action:** Copy from `Generic/AGENTS.md`, no placeholders to replace.  
**Depends on:** None  
**Working directory:** repo root  
**Expected output:** File created at `AGENTS.md`

### Step 4 — Create agent definitions

**Agent:** `developer`  
**Files:**
- `.github/agents/README.md`
- `.github/agents/overlord.agent.md`
- `.github/agents/developer.agent.md`
- `.github/agents/debugger.agent.md`
- `.github/agents/testing.agent.md`
- `.github/agents/code-reviewer.agent.md`

**Action:** Copy all files from `Generic/.github/agents/`. For each agent file:
- Replace `[PROJECT_NAME]` → `particle-sim`
- Replace `[NAMESPACE]` → `psim`
- Adjust naming convention references where needed (camelCase methods)
- Add CUDA-specific notes where relevant  
**Depends on:** None  
**Working directory:** repo root  
**Expected output:** 6 files created in `.github/agents/`

### Step 5 — Create quality gate hook

**Agent:** `developer`  
**Files:**
- `.github/hooks/quality-gate.json`
- `.github/hooks/scripts/quality-gate.sh`
- `.github/hooks/scripts/quality-gate.ps1`

**Action:** Copy from `Generic/.github/hooks/`. Adjust `quality-gate.sh` to:
- Add `.cu` to extensions list for clang-format (CUDA files can be formatted)
- Skip `.cu` files for clang-tidy (limited support)  
**Depends on:** None  
**Working directory:** repo root  
**Expected output:** 3 files created, scripts executable

### Step 6 — Create C++ file instructions

**Agent:** `developer`  
**Files:** `.github/instructions/cpp.instructions.md`  
**Action:** Copy from `Generic/.github/instructions/cpp.instructions.md`. Adapt for particle-sim:
- Replace `[PROJECT_NAME]` → `particle-sim`
- Add CUDA file extensions to `applyTo` frontmatter (`.cu`, `.cuh`)
- Change function naming from PascalCase to camelCase
- Add CUDA-specific section for kernels and device functions  
**Depends on:** None  
**Working directory:** repo root  
**Expected output:** File created at `.github/instructions/cpp.instructions.md`

### Step 7 — Create planning infrastructure

**Agent:** `developer`  
**Files:**
- `.github/planning/PLANS.md`
- `.github/planning/execplans/_TEMPLATE.md`

**Action:** Copy from Generic. Replace `[PROJECT_NAME]` → `particle-sim`, `[TICKET_PREFIX]` → `PS`, `[TEST_COMMAND]` → `ctest --test-dir build --output-on-failure`.  
**Depends on:** None  
**Working directory:** repo root  
**Expected output:** 2 files created in `.github/planning/`

### Step 8 — Create build-and-test skill

**Agent:** `developer`  
**Files:** `.github/skills/build-and-test/SKILL.md`  
**Action:** Create skill with actual particle-sim build commands:
- Prerequisites: CMake 3.28+, Ninja, CUDA Toolkit 13.1, GCC 13+/Clang 18+
- Configure: `cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`
- Build: `cmake --build build`
- Run: `./build/particle_sim`
- Tests: (to be added when GoogleTest integrated)
- Sanitizers: ASan+UBSan only (CUDA incompatible with MSan/TSan)  
**Depends on:** None  
**Working directory:** repo root  
**Expected output:** File created at `.github/skills/build-and-test/SKILL.md`

### Step 9 — Validation

**Agent:** `developer`  
**Action:**
1. Run `clang-format --dry-run --Werror --style=file:.clang-format src/main.cpp` — verify no errors
2. Verify all files created with correct structure
3. List `.github/` directory to confirm complete setup  
**Depends on:** Steps 1–8  
**Working directory:** repo root  
**Expected output:** clang-format exits 0 (or reports fixable formatting issues)

---

## Validation and Acceptance

Acceptance criteria observable from outside the code:

- [ ] `ls .clang-format .clang-tidy AGENTS.md` — all three files exist
- [ ] `ls .github/agents/` — shows 6 files (README + 5 agents)
- [ ] `ls .github/hooks/` — shows `quality-gate.json` and `scripts/` directory
- [ ] `ls .github/instructions/` — shows `cpp.instructions.md`
- [ ] `ls .github/planning/` — shows `PLANS.md` and `execplans/` with `_TEMPLATE.md`
- [ ] `ls .github/skills/build-and-test/` — shows `SKILL.md`
- [ ] `clang-format --dry-run --style=file:.clang-format src/main.cpp` — exits 0 or shows fixable formatting
- [ ] `grep -q "particle-sim" .clang-format` — project name present
- [ ] `grep -q "psim" .clang-tidy` — namespace present in header filter

---

## Idempotence and Recovery

All steps are idempotent — re-running creates or overwrites files with same content.

Recovery if a step fails:
- If file creation fails: Check directory exists, create with `mkdir -p`
- If placeholder replacement missed: Search files for remaining `[` brackets

---

## Artifacts and Notes

- No branch required — initial setup
- Files from `Generic/` are templates; delete `Generic/` folder after setup if desired

---

## Interfaces and Dependencies

| Component | Type | Impact |
|-----------|------|--------|
| `.clang-format` | Config | Formatting rules for all C++/CUDA files |
| `.clang-tidy` | Config | Linting rules for `.cpp`/`.hpp` files |
| `AGENTS.md` | Doc | Agent guidance and ExecPlan trigger policy |
| `.github/agents/*` | Config | Copilot agent definitions |
| `.github/hooks/*` | Config | Quality gate automation |
| `.github/instructions/*` | Config | Path-scoped Copilot rules |
| `.github/planning/*` | Doc | ExecPlan infrastructure |
| `.github/skills/*` | Doc | Agent skill documents |
