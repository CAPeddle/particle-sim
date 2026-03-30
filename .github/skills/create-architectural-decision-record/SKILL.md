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

Full template with all sections (frontmatter, Status, Context, Decision, Consequences, Alternatives, Implementation Notes, References): see [reference/adr-template.md](reference/adr-template.md).

Key sections to fill:
- At least 1 positive and 1 negative consequence (coded POS-001, NEG-001)
- At least 2 alternatives with rejection reasons (coded ALT-001)
- Implementation notes (coded IMP-001)
- References to related ADRs via relative paths

---

## Quality Checklist

- [ ] File saved in `docs/adr/` with correct sequential number
- [ ] All sections filled — no placeholders remaining
- [ ] Status is "Proposed" unless otherwise specified
- [ ] At least 1 positive and 1 negative consequence
- [ ] At least 2 alternatives with rejection reasons
- [ ] Coded items use correct format (POS-001, NEG-001, etc.)
- [ ] References link to related ADRs via relative paths
