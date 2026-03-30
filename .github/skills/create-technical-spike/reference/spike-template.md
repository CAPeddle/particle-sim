# Spike Template — particle-sim

Use this template when creating a new technical spike in `docs/spikes/`.

Replace all `[bracketed]` placeholders. File naming: `docs/spikes/[category]-[short-description]-spike.md`

**Categories:** `cuda-`, `perf-`, `lib-`, `arch-`, `render-`, `algo-`

---

```markdown
---
title: "[Spike Title]"
category: "[cuda|perf|lib|arch|render|algo]"
status: "🔴 Not Started"
priority: "[High|Medium|Low]"
timebox: "[e.g., 2 hours, 1 day]"
created: YYYY-MM-DD
updated: YYYY-MM-DD
owner: ""
tags: ["technical-spike", "[category]", "research"]
---

# [Spike Title]

## Summary

**Spike Objective:** [Clear, specific question that must be answered]

**Why This Matters:** [Impact on architecture, performance, or development decisions]

**Timebox:** [How much time is allocated]

**Decision Deadline:** [When this must be resolved to unblock development]

## Research Questions

**Primary Question:** [The main question to answer]

**Secondary Questions:**

- [Related question 1]
- [Related question 2]

## Investigation Plan

### Research Tasks

- [ ] [Task 1 — e.g., benchmark library A vs library B]
- [ ] [Task 2 — e.g., build minimal prototype]
- [ ] [Task 3 — e.g., check CUDA compatibility / SM 89 support]
- [ ] [Document findings and recommendation]

### Success Criteria

**This spike is complete when:**

- [ ] [Specific measurable criterion 1]
- [ ] [Specific measurable criterion 2]
- [ ] Clear recommendation documented
- [ ] Prototype or evidence collected (if applicable)

## Technical Context

**Related Components:** [src/ directories or modules affected]

**Dependencies:** [Other spikes or decisions that depend on this]

**Constraints:**
- C++23 (CPU), CUDA 20 (GPU)
- No exceptions — `std::expected<T, E>` only
- FetchContent-compatible (no system installs)
- SM 89 (RTX 4050 Laptop) target
- [Any additional project constraints]

## Research Findings

### Investigation Results

[Document findings, benchmarks, and evidence as research progresses]

### Prototype/Testing Notes

[Results from any prototype or experiment]

### External Resources

- [Link to documentation]
- [Link to benchmark data]
- [Link to related particle-sim issue or ADR]

## Decision

### Recommendation

[Clear, specific recommendation based on evidence]

### Rationale

[Why this was chosen over alternatives]

### Implementation Notes

[Key considerations for the implementing ExecPlan]

### Follow-up Actions

- [ ] Create ADR if a significant architectural decision was made
- [ ] Update COMPARISON_RESEARCH.md with library comparison results
- [ ] Create ExecPlan to implement the chosen approach

## Status History

| Date | Status | Notes |
|------|--------|-------|
| YYYY-MM-DD | 🔴 Not Started | Spike created |
| YYYY-MM-DD | 🟡 In Progress | Research commenced |
| YYYY-MM-DD | 🟢 Complete | [Recommendation summary] |

---

_Last updated: YYYY-MM-DD_
```

## particle-sim Notes

- Always check CUDA compatibility and FetchContent availability for libraries
- One question per spike — do not mix unrelated decisions
- Time-box strictly — escalate if the timebox expires without a recommendation
- Evidence required — "I think X is better" is not acceptable; show data
- Completed spikes should produce an ADR or ExecPlan as a follow-up
