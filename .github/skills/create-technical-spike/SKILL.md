---
name: create-technical-spike
description: >
  Create a time-boxed technical spike document for particle-sim.
  Saves to docs/spikes/ and formalises research questions, investigation plans,
  and evidence-based recommendations. Use before committing to a library,
  architecture pattern, or performance approach.
---

# Create Technical Spike — particle-sim

Create a time-boxed spike document in `docs/spikes/` to research a critical technical
question before implementation begins. Each spike produces a concrete recommendation.

---

## When to Use

- Evaluating a library (e.g., comparing TOML parsers, spatial index implementations)
- Investigating a CUDA performance approach before committing to it
- Researching an architecture pattern with unclear trade-offs
- Any question that must be answered before an ExecPlan can be written

---

## Steps

1. Identify the primary technical question.
2. Create the file: `docs/spikes/[category]-[short-description]-spike.md`
3. Fill all sections; set status to 🔴 Not Started.
4. Conduct research and update findings in-place.
5. Mark complete (🟢) with a clear recommendation when done.

---

## File Naming

Pattern: `[category]-[short-description]-spike.md`

**particle-sim categories:**
- `cuda-` — GPU kernel approach, memory layout, occupancy
- `perf-` — Performance measurement, bottleneck analysis
- `lib-` — Library selection (e.g., `lib-toml-parser-spike.md`)
- `arch-` — Architecture or design pattern
- `render-` — OpenGL / CUDA-GL interop decision
- `algo-` — Algorithm selection (spatial index, SPH kernel, etc.)

---

## Spike Template

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

---

## Best Practices

1. **One question per spike** — do not mix unrelated decisions
2. **Time-box strictly** — if the timebox expires without a recommendation, escalate
3. **Evidence required** — "I think X is better" is not a recommendation; show data
4. **Link to outcomes** — completed spikes should produce an ADR or ExecPlan
5. **particle-sim fit** — always check CUDA compatibility and FetchContent availability for libraries
