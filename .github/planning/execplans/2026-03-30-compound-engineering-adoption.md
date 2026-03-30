# Governance Adoption — Compound Engineering & Strengthened ExecPlan Policy

This ExecPlan is a living document. Keep `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` up to date as work proceeds.

This plan must be maintained according to `.github/planning/PLANS.md` and aligned with `.github/copilot-instructions.md`.

**Date:** 2026-03-30  
**Status:** ✅ Complete  
**Owner:** Copilot agent  
**Refs:** N/A — governance maintenance

---

## Purpose / Big Picture

Adopt two key methodologies from the upstream governance sources (`C:\projects\zoom_copilot_config`) into particle-sim:

1. **Compound Engineering** — After every ExecPlan completes, learnings from `Outcomes & Retrospective` must be actively propagated into governance files (copilot-instructions.md, skills, agents, etc.), closing the feedback loop.
2. **All-requests-via-ExecPlan** — Strengthen the ExecPlan trigger policy so that all non-trivial agent requests go through ExecPlan, not just "multi-file" work.

Additionally, document the influences and sources that shaped particle-sim's governance model, tracking provenance for future reviews.

**Term definitions:**
- *Compound Engineering:* A workflow pattern from [EveryInc's compound-engineering plugin](https://github.com/EveryInc/compound-engineering-plugin) where each Plan→Work→Review cycle ends with a **Compound step** that codifies learnings for future cycles. The key insight: completed work should make the system smarter, not just bigger.
- *Point Don't Dump:* A skill authoring principle (already adopted) where SKILL.md bodies contain decision trees with pointers to reference files, rather than inlining all content.
- *Compound step:* A mandatory ExecPlan phase after code review where `Outcomes & Retrospective` findings are applied to governance files.

---

## Progress

- [x] (2026-03-30) Initial plan drafted.
- [x] (2026-03-30) Step 1 — Compound Engineering adopted in PLANS.md + template.
- [x] (2026-03-30) Step 2 — Overlord agent updated with Compound step.
- [x] (2026-03-30) Step 3 — ExecPlan-for-all policy strengthened in AGENTS.md.
- [x] (2026-03-30) Step 4 — Influences & Sources documented.
- [x] (2026-03-30) Step 5 — Compound step: apply own learnings from this plan.

---

## Surprises & Discoveries

_(Update as work proceeds.)_

---

## Decision Log

- Decision: Point Don't Dump is already adopted — no further work needed.  
  Rationale: The 2026-03-30 governance audit ExecPlan fully implemented the three-layer skill structure. All 7 skills comply. The Skill Authoring Standard is documented in agents/README.md.  
  Date/Author: 2026-03-30, audit

- Decision: Compound Engineering adoption requires changes to 4 files, not just documentation.  
  Rationale: The pattern only works if enforcement exists in the Overlord workflow (mandatory step), PLANS.md (mandatory checkpoint), and the template (concrete step). Documenting the concept without enforcement is insufficient.  
  Date/Author: 2026-03-30, audit

- Decision: "All requests via ExecPlan" means lowering the threshold, not eliminating judgment entirely.  
  Rationale: Truly trivial operations (single-file typo fix, commit-and-push) don't benefit from ExecPlan overhead. The policy should default to ExecPlan and require explicit justification to skip.  
  Date/Author: 2026-03-30, audit

---

## Outcomes & Retrospective

**What was achieved:**
- Compound Engineering pattern fully adopted: mandatory 5th checkpoint in PLANS.md, Step 5 in template, Overlord workflow step 8
- ExecPlan-for-all policy strengthened: default-to-ExecPlan stance in AGENTS.md and PLANS.md
- Influences & Sources documented in agents/README.md with 8 external sources
- Point Don't Dump confirmed already adopted (no further work needed)

**What remains (if anything):**
- None — all acceptance criteria met

**Patterns to promote** (add to `copilot-instructions.md`):
- The Compound step self-referential test validates the pattern works: this plan’s own compound step updated governance files. Future plans should treat compound as non-negotiable.

**Reusable findings** (worth preserving in `.github/planning/investigations/`):
- Aligning AGENTS.md and PLANS.md on ExecPlan trigger wording prevents drift. Both files should express the same policy; update them together.
- Enforcement of a pattern requires presence in at least three places: the standard (PLANS.md), the template (_TEMPLATE.md), and the orchestrator (overlord.agent.md). Missing any one creates a gap.

**New anti-patterns** (failure modes or wrong approaches to document as warnings):
- Documenting a retrospective without acting on it is compliance theater, not compound engineering. The Compound checkpoint exists to prevent this.

---

## Context and Orientation

### Upstream sources reviewed

| Source | Location | Key pattern |
|--------|----------|-------------|
| zoom_copilot_config README.md | `C:\projects\zoom_copilot_config\README.md` | Influences & Sources table; Compound Engineering adoption notes |
| Generic PLANS.md | `C:\projects\zoom_copilot_config\Generic\.github\planning\PLANS.md` | Living document policy with Outcomes & Retrospective |
| Generic overlord.agent.md | `C:\projects\zoom_copilot_config\Generic\.github\agents\overlord.agent.md` | Simple/complex workflow patterns; no explicit compound step |
| zoom_copilot_config AGENTS.md | `C:\projects\zoom_copilot_config\AGENTS.md` | ExecPlan trigger policy |

### Current particle-sim state

- **PLANS.md**: Has `Outcomes & Retrospective` section with "patterns to promote" / "reusable findings" / "new anti-patterns" fields. But no mandatory **Compound checkpoint** requiring these findings to be *applied* to governance files.
- **_TEMPLATE.md**: Has the Outcomes section. No "Step N — Compound" in template Concrete Steps.
- **Overlord**: Workflow ends at "reports done with summary" — no compound step.
- **AGENTS.md**: ExecPlan required for "multi-file feature work or significant refactor." Small single-file fixes are optional. No default-to-ExecPlan stance.
- **Influences**: Not documented anywhere beyond `source-tracking.json`.

### Gap analysis

| Gap | Severity | Fix |
|-----|----------|-----|
| No compound checkpoint in PLANS.md | High — learnings captured but not applied | Add mandatory checkpoint |
| No compound step in ExecPlan template | High — new plans won't include it | Add Step N template |
| No compound step in Overlord workflow | High — enforcement missing | Add step 9 to complex workflow |
| ExecPlan policy too permissive | Medium — user wants stronger default | Strengthen threshold in AGENTS.md |
| No influences documentation | Low — provenance not tracked | Add section to agents/README.md |

---

## Plan of Work

1. Add Compound Engineering checkpoint and enforcement to PLANS.md
2. Add Step N — Compound to ExecPlan template
3. Add compound step to Overlord workflow
4. Strengthen ExecPlan trigger policy in AGENTS.md
5. Document Influences & Sources in agents/README.md
6. Execute compound step for this plan

---

## Concrete Steps

### Step 1 — PLANS.md + Template compound enforcement

- **Files:** `.github/planning/PLANS.md`, `.github/planning/execplans/_TEMPLATE.md`
- **Action:**
  - PLANS.md: Add 5th mandatory progress checkpoint: "Compound — governance files updated with learnings"
  - PLANS.md: Add "Compound Step" subsection after "Living Document Policy" explaining the feedback loop
  - _TEMPLATE.md: Add "Step 5 — Compound" after Code Review in Concrete Steps
  - _TEMPLATE.md: Add compound checkpoint to Progress list
- **Depends on:** None

### Step 2 — Overlord agent compound step

- **Files:** `.github/agents/overlord.agent.md`
- **Action:** Add step 9 "Compound" to complex workflow. After code review passes, review Outcomes & Retrospective and apply learnings to governance files.
- **Depends on:** None

### Step 3 — Strengthen ExecPlan policy

- **Files:** `AGENTS.md`, `.github/planning/PLANS.md`
- **Action:** Change default from "ExecPlan for complex work" to "ExecPlan by default; skip only for truly trivial single-step operations with explicit justification."
- **Depends on:** None

### Step 4 — Influences & Sources

- **Files:** `.github/agents/README.md`
- **Action:** Add "Influences & Sources" section documenting the methodologies adopted and where each pattern came from.
- **Depends on:** None

### Step 5 — Compound (self-referential)

- **Action:** Execute compound step for THIS plan. Review Outcomes & Retrospective findings. Apply any learnings to governance files.
- **Depends on:** Steps 1-4

---

## Validation and Acceptance

- PLANS.md contains "Compound" as 5th mandatory progress checkpoint
- _TEMPLATE.md has Step 5 — Compound in Concrete Steps
- Overlord workflow includes compound step before completion
- AGENTS.md expresses default-to-ExecPlan policy
- agents/README.md has Influences & Sources section
- This plan's Outcomes & Retrospective is completed and any learnings applied

---

## Idempotence and Recovery

All steps are file edits — re-running produces the same result. No destructive operations.

---

## Artifacts and Notes

No branch required — governance files only.

---

## Interfaces and Dependencies

| Component | Type | Impact |
|-----------|------|--------|
| `.github/planning/PLANS.md` | Governance | Compound checkpoint added |
| `.github/planning/execplans/_TEMPLATE.md` | Template | Compound step added |
| `.github/agents/overlord.agent.md` | Agent | Workflow extended |
| `AGENTS.md` | Governance | Policy strengthened |
| `.github/agents/README.md` | Documentation | Influences section added |
