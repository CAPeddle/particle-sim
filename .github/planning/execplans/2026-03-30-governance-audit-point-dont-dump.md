# Governance Audit — Point Don't Dump Skill Refactoring

This ExecPlan is a living document. Keep `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` up to date as work proceeds.

This plan must be maintained according to `.github/planning/PLANS.md` and aligned with `.github/copilot-instructions.md`.

**Date:** 2026-03-30  
**Status:** ✅ Complete  
**Owner:** Copilot agent  
**Refs:** N/A — governance maintenance

---

## Purpose / Big Picture

Align all particle-sim governance files with the "Point Don't Dump" skill authoring standard from the Generic governance template. After this plan completes:

1. All 7 skills use correct `---` YAML frontmatter (not `` ```skill `` fences)
2. All skills follow the three-layer structure (Description → Process → Reference/Scripts)
3. Skills that are better suited as instructions are converted
4. A `validate-agents.instructions.md` file enforces frontmatter conformance
5. The "context-load heuristic" and "Skill Authoring Standard" are documented in project governance
6. `source-tracking.json` dates are corrected

**Term definitions:**
- *Point Don't Dump:* A skill authoring principle where SKILL.md bodies contain decision trees with pointers to Layer 3 reference files, rather than inlining all content.
- *Three-layer structure:* Layer 1 = YAML frontmatter (always loaded for discovery), Layer 2 = SKILL.md body (loaded on invocation), Layer 3 = reference/scripts files (loaded on demand).
- *Context-load heuristic:* Reactive or diagnostic content should live in a skill or knowledge file, not in always-on instructions (copilot-instructions.md).
- *validate-agents instruction:* A path-scoped `.instructions.md` that auto-applies when editing agent or skill files, enforcing frontmatter conformance.

---

## Progress

- [x] (2026-03-30 14:00 UTC) Initial plan drafted.
- [x] (2026-03-30) Step 1 — Frontmatter fixed on 3 skills (```skill → ---), trailing code fences removed, non-standard fields removed.
- [x] (2026-03-30) Step 2 — validate-agents.instructions.md adopted from upstream.
- [x] (2026-03-30) Step 3 — Skill Authoring Standard — "Point Don't Dump" added to agents/README.md.
- [x] (2026-03-30) Step 4 — Context-load heuristic added to copilot-instructions.md.
- [x] (2026-03-30) Step 5 — source-tracking.json dates corrected (2026-03-20 → 2026-03-30).
- [x] (2026-03-30) Step 6 — review-upstream-sources refactored: seed sources → reference/seed-sources.md, adaptations → reference/particle-sim-adaptations.md.
- [x] (2026-03-30) Step 7 — adopt-template-updates refactored: customizations table → shared pointer to adaptations, scripts → reference/comparison-scripts.md.
- [x] (2026-03-30) Step 8 — build-and-test refactored: troubleshooting → reference/troubleshooting.md.
- [x] (2026-03-30) Step 9 — create-architectural-decision-record refactored: template → reference/adr-template.md. validate-agent-tools refactored: roster → reference/agent-roster.md.
- [x] (2026-03-30) Step 10 — create-technical-spike refactored: template → reference/spike-template.md.
- [x] (2026-03-30) Step 11 — Validation complete: all 7 SKILL.md start with ---, 6 skills have Layer 3 references, no orphan files, instruction file exists.

---

## Surprises & Discoveries

_(Update as work proceeds.)_

---

## Decision Log

- Decision: Use plain `---` frontmatter, not `` ```skill `` fences.  
  Rationale: GitHub Copilot agent skills spec requires plain YAML frontmatter. Code fences are not parsed correctly.  
  Date/Author: 2026-03-30, audit

- Decision: Non-standard frontmatter fields (`argument-hint`, `user-invokable`, `disable-model-invocation`) will be removed.  
  Rationale: validate-agents instruction from zoom_copilot_config enforces only `name` and `description` as required fields. Non-standard fields are silently ignored or cause parse issues.  
  Date/Author: 2026-03-30, audit

---

## Outcomes & Retrospective

**What was achieved:**
- All 7 SKILL.md files now use correct `---` YAML frontmatter
- 6 skills refactored to three-layer "Point Don't Dump" structure with Layer 3 reference files
- `conventional-commit` kept as-is (compact enough, no extraction needed)
- `validate-agents.instructions.md` created — auto-applies to agent/skill files
- Skill Authoring Standard documented in agents/README.md
- Context-load heuristic documented in copilot-instructions.md
- source-tracking.json dates corrected

**What remains (if anything):**
- None — all acceptance criteria met

**Patterns to promote:**
- Three-layer skill structure reduces context load and improves agent precision
- Shared reference files (particle-sim-adaptations.md) avoid duplication between skills
- validate-agents instruction as a path-scoped auto-validation pattern

**Reusable findings:**
- Skills with embedded templates >30 lines benefit strongly from Layer 3 extraction
- Tables >5 rows are good extraction candidates per the standard
- PowerShell comparison scripts work well as Layer 3 reference (readable + executable)

**New anti-patterns:**
- `` ```skill `` code fences for SKILL.md frontmatter (use plain `---` YAML)
- Non-standard frontmatter fields (only `name` and `description` are required)

---

## Context and Orientation

### Current State

particle-sim has 7 skills in `.github/skills/`:

| # | Skill | Frontmatter | Non-std fields | Layer 3 dirs | Lines | Assessment |
|---|-------|-------------|---------------|-------------|-------|------------|
| 1 | `review-upstream-sources` | `` ```skill `` ❌ | None | None ❌ | ~115 | Refactor: extract source registry + adaptation table to Layer 3 |
| 2 | `adopt-template-updates` | `` ```skill `` ❌ | None | None ❌ | ~105 | Refactor: extract customizations table + hash scripts to Layer 3 |
| 3 | `validate-agent-tools` | `` ```skill `` ❌ | `argument-hint`, `user-invokable`, `disable-model-invocation` ❌ | None ❌ | ~80 | Refactor: fix frontmatter, extract agent roster + ref sources to Layer 3 |
| 4 | `build-and-test` | `---` ✅ | None ✅ | None ⚠️ | ~155 | Evaluate: large but well-structured; extract troubleshooting to Layer 3 |
| 5 | `conventional-commit` | `---` ✅ | None ✅ | None | ~100 | Evaluate: could be an instruction (always-on for commit context). Short enough for Layer 2. Keep as skill. |
| 6 | `create-architectural-decision-record` | `---` ✅ | None ✅ | None ⚠️ | ~120 | Evaluate: extract ADR template to Layer 3 |
| 7 | `create-technical-spike` | `---` ✅ | None ✅ | None ⚠️ | ~175 | Evaluate: extract spike template to Layer 3 (large embedded template) |

### Assessment Summary

- **3 skills** need frontmatter fixes (`` ```skill `` → `---`)
- **1 skill** has non-standard frontmatter fields to remove
- **5 skills** would benefit from Layer 3 extraction (embedded templates, reference tables, or scripts >5 lines)
- **2 skills** are compact enough to keep as-is after frontmatter fix (`conventional-commit`, `validate-agent-tools`)
- **0 skills** should become instructions — `conventional-commit` was considered but benefits from being invokable on demand rather than always-on

### Missing Governance Files

- `validate-agents.instructions.md` — exists in upstream, not in particle-sim
- Skill Authoring Standard — documented in Generic README.md, not in particle-sim
- Context-load heuristic — referenced in zoom_copilot_config, not in particle-sim copilot-instructions

---

## Plan of Work

1. Fix frontmatter on 3 skills (mechanical)
2. Adopt `validate-agents.instructions.md` from upstream
3. Add Skill Authoring Standard to agents/README.md
4. Add context-load heuristic to copilot-instructions.md
5. Fix source-tracking.json dates
6. Refactor skills with Layer 3 extraction (5 skills)
7. Validate all changes

---

## Concrete Steps

### Step 1 — Fix Skill Frontmatter (3 skills)

- **Files:** `review-upstream-sources/SKILL.md`, `adopt-template-updates/SKILL.md`, `validate-agent-tools/SKILL.md`
- **Action:** Replace `` ```skill\n---\n...\n---\n `` wrapper with plain `---\n...\n---` YAML. Remove non-standard fields from validate-agent-tools.
- **Depends on:** None
- **Expected output:** All 7 SKILL.md files start with `---` on line 1.

### Step 2 — Adopt validate-agents.instructions.md

- **Files:** Create `.github/instructions/validate-agents.instructions.md`
- **Action:** Adapt upstream file from `C:\projects\zoom_copilot_config\.github\instructions\validate-agents.instructions.md` with particle-sim paths.
- **Depends on:** None
- **Expected output:** Instruction auto-applies to `**/.github/agents/*.agent.md` and `**/.github/skills/*/SKILL.md`.

### Step 3 — Add Skill Authoring Standard

- **Files:** `.github/agents/README.md`
- **Action:** Add "Skill Authoring Standard — Point Don't Dump" section with three-layer table and guidelines, adapted from Generic README.md.
- **Depends on:** None

### Step 4 — Add Context-Load Heuristic

- **Files:** `.github/copilot-instructions.md`
- **Action:** Add a subsection under Architecture or API Surface explaining: reactive/diagnostic content → skill, not always-on instructions.
- **Depends on:** None

### Step 5 — Fix source-tracking.json

- **Files:** `.github/skills/review-upstream-sources/source-tracking.json`
- **Action:** Update all `last_reviewed` dates from `2026-03-20` to `2026-03-30`.
- **Depends on:** None

### Step 6 — Refactor review-upstream-sources (Layer 3 extraction)

- **Files:** `review-upstream-sources/SKILL.md`, new `reference/` dir
- **Action:** Extract seed source registry tables to `reference/seed-sources.md`, adaptation notes table to `reference/particle-sim-adaptations.md`. Replace inline content with pointers + slim summaries.
- **Depends on:** Step 1

### Step 7 — Refactor adopt-template-updates (Layer 3 extraction)

- **Files:** `adopt-template-updates/SKILL.md`, new `reference/` and `scripts/` dirs
- **Action:** Extract customizations-to-preserve table to `reference/particle-sim-customizations.md` (shared with review-upstream-sources via pointer). Extract PowerShell hash/diff scripts to `scripts/`.
- **Depends on:** Step 1

### Step 8 — Refactor build-and-test (Layer 3 extraction)

- **Files:** `build-and-test/SKILL.md`, new `reference/` dir
- **Action:** Extract troubleshooting table to `reference/troubleshooting.md`. Keep core steps inline (they are the decision tree).
- **Depends on:** None

### Step 9 — Refactor create-architectural-decision-record (Layer 3 extraction)

- **Files:** `create-architectural-decision-record/SKILL.md`, new `reference/` dir
- **Action:** Extract ADR markdown template to `reference/adr-template.md`.
- **Depends on:** None

### Step 10 — Refactor create-technical-spike (Layer 3 extraction)

- **Files:** `create-technical-spike/SKILL.md`, new `reference/` dir
- **Action:** Extract spike markdown template to `reference/spike-template.md`.
- **Depends on:** None

### Step 11 — Validation

- **Action:** Verify all SKILL.md files start with `---`, no non-standard frontmatter, Layer 3 files referenced from Layer 2, no orphan files.
- **Depends on:** Steps 1-10
- **Commands:**
  ```powershell
  Get-ChildItem -Path ".github/skills" -Recurse -Filter "SKILL.md" | ForEach-Object {
      $line = (Get-Content $_.FullName -TotalCount 1)
      Write-Host "$($_.FullName): $line"
  }
  ```
- **Expected output:** All files show `---` as first line.

---

## Validation and Acceptance

- All 7 SKILL.md files begin with plain `---` YAML frontmatter
- No non-standard frontmatter fields (`argument-hint`, `user-invokable`, `disable-model-invocation`)
- Skills with >5-row tables or >5-line scripts have content in Layer 3 `reference/` or `scripts/` directories
- Layer 3 files are referenced from Layer 2 SKILL.md bodies (no orphans)
- `validate-agents.instructions.md` exists and targets correct glob pattern
- "Skill Authoring Standard" section exists in agents/README.md
- "Context-load heuristic" is documented in copilot-instructions.md
- `source-tracking.json` dates are `2026-03-30`

---

## Idempotence and Recovery

- All steps are file edits — re-running produces the same result.
- If a Layer 3 extraction is wrong, the SKILL.md pointer can be reverted and content re-inlined.
- No destructive operations — original content is moved, not deleted.

---

## Artifacts and Notes

- Branch: `main` (governance files, no code changes)
- No scratch files needed.

---

## Interfaces and Dependencies

| Component | Type | Impact |
|-----------|------|--------|
| `.github/skills/*/SKILL.md` | Governance | Frontmatter + structure refactoring |
| `.github/skills/*/reference/` | Governance | New Layer 3 reference files |
| `.github/skills/*/scripts/` | Governance | New Layer 3 scripts |
| `.github/instructions/validate-agents.instructions.md` | Governance | New instruction file |
| `.github/agents/README.md` | Documentation | New section added |
| `.github/copilot-instructions.md` | Documentation | New subsection added |
| `.github/skills/review-upstream-sources/source-tracking.json` | Tracking | Date correction |
