---
name: create-architectural-decision-record
description: >
  Create an Architectural Decision Record (ADR) for particle-sim.
  Saves to docs/adr/ using sequential 4-digit numbering.
  Use when a significant technical decision needs structured documentation
  with context, rationale, alternatives, and consequences.
---

# Create Architectural Decision Record — particle-sim

Create a new ADR document in `docs/adr/` following the project's numbering convention.

---

## Inputs

Before starting, determine:
- **Decision Title** — clear, concise name
- **Context** — the problem or opportunity requiring a decision
- **Decision** — the chosen solution
- **Alternatives** — other options considered
- **Stakeholders** — people or teams involved

If any input is missing, ask the user before proceeding.

---

## Steps

1. Check `docs/adr/` for the highest existing ADR number.
2. Increment by 1 to get the next number (zero-padded to 4 digits).
3. Create the file: `docs/adr/NNNN-[title-slug].md`
4. Fill all sections — do not leave placeholders.

---

## ADR Template

```markdown
---
title: "ADR-NNNN: [Decision Title]"
status: "Proposed"
date: "YYYY-MM-DD"
authors: "[Stakeholder Names/Roles]"
tags: ["architecture", "decision"]
supersedes: ""
superseded_by: ""
---

# ADR-NNNN: [Decision Title]

## Status

**Proposed** | Accepted | Rejected | Superseded | Deprecated

## Context

[Problem statement, technical constraints, requirements, and environmental factors
requiring this decision. Explain the forces at play.]

## Decision

[The chosen solution with clear rationale. State unambiguously what was decided and why.]

## Consequences

### Positive

- **POS-001**: [Beneficial outcomes]
- **POS-002**: [Performance, maintainability improvements]
- **POS-003**: [Alignment with architectural principles]

### Negative

- **NEG-001**: [Trade-offs, limitations]
- **NEG-002**: [Technical debt or complexity introduced]
- **NEG-003**: [Risks and future challenges]

## Alternatives Considered

### [Alternative 1 Name]

- **ALT-001**: **Description**: [Brief technical description]
- **ALT-002**: **Rejection Reason**: [Why this was not selected]

### [Alternative 2 Name]

- **ALT-003**: **Description**: [Brief technical description]
- **ALT-004**: **Rejection Reason**: [Why this was not selected]

## Implementation Notes

- **IMP-001**: [Key implementation considerations]
- **IMP-002**: [Migration or rollout strategy if applicable]
- **IMP-003**: [Monitoring and success criteria]

## References

- **REF-001**: [Related ADRs — relative paths, e.g., 0001-spatial-indexing-strategy.md]
- **REF-002**: [External documentation or standards]
- **REF-003**: [Library research — COMPARISON_RESEARCH.md if applicable]
```

---

## particle-sim Specific Notes

- Reference CUDA constraints (SM 89 / Ada Lovelace) when relevant
- Reference `docs/fluid-sim-comparison.md` for predecessor decisions
- Reference `COMPARISON_RESEARCH.md` for library selection research
- Confirm error handling decisions use `std::expected<T, E>` (not exceptions)
- Link to the `adr-generator` agent for automated ADR creation

---

## Quality Checklist

- [ ] File saved in `docs/adr/` with correct sequential number
- [ ] All sections filled — no placeholders remaining
- [ ] Status is "Proposed" unless otherwise specified
- [ ] At least 1 positive and 1 negative consequence
- [ ] At least 2 alternatives with rejection reasons
- [ ] Coded items use correct format (POS-001, NEG-001, etc.)
- [ ] References link to related ADRs via relative paths
