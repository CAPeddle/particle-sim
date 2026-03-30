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

Full template with all sections (frontmatter, Summary, Research Questions, Investigation Plan, Technical Context, Research Findings, Decision, Status History): see [reference/spike-template.md](reference/spike-template.md).

Key constraints to always include:
- C++23 (CPU), CUDA 20 (GPU)
- No exceptions — `std::expected<T, E>` only
- FetchContent-compatible (no system installs)
- SM 89 (RTX 4050 Laptop) target

---

## Best Practices

1. **One question per spike** — do not mix unrelated decisions
2. **Time-box strictly** — if the timebox expires without a recommendation, escalate
3. **Evidence required** — "I think X is better" is not a recommendation; show data
4. **Link to outcomes** — completed spikes should produce an ADR or ExecPlan
5. **particle-sim fit** — always check CUDA compatibility and FetchContent availability for libraries
