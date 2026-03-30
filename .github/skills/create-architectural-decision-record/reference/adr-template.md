# ADR Template — particle-sim

Use this template when creating a new Architecture Decision Record in `docs/adr/`.

Replace all `[bracketed]` placeholders. File naming: `docs/adr/NNNN-[title-slug].md`

---

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

## particle-sim Notes

- Reference CUDA constraints (SM 89 / Ada Lovelace) when relevant
- Reference `docs/fluid-sim-comparison.md` for predecessor decisions
- Reference `COMPARISON_RESEARCH.md` for library selection research
- Confirm error handling decisions use `std::expected<T, E>` (not exceptions)
- Link to the `adr-generator` agent for automated ADR creation
