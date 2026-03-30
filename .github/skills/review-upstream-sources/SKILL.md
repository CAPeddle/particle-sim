---
name: review-upstream-sources
description: Reviews upstream AI governance sources for changes, classifies findings (breaking/enhancement/info), updates local governance files when needed, and can bootstrap a new GitHub repository with the governance template.
---

# Review Upstream Sources

This skill keeps governance files aligned with evolving external best practices and specifications.

---

## Seed Source Registry

Two categories of sources are tracked: **canonical** (likely to require adoption) and **pattern** (inspirational, selective adoption).

Full source tables with URLs and contribution descriptions: see [reference/seed-sources.md](reference/seed-sources.md).

Tracking state (last-reviewed dates, content hashes, version markers): see `source-tracking.json` in this skill directory.

---

## Tracking Baseline

Use `.github/skills/review-upstream-sources/source-tracking.json` as the review baseline.

For each source, track:
- `last_reviewed`
- `version_marker`
- `key_sections_at_review`
- `github_release_tag` (when applicable)
- `notes`

---

## Review Procedure

### Step 0 — Load baseline

Read `source-tracking.json` and note previous state for each source.

### Step 1 — Fetch and compare

For each source:
- Fetch current content
- Compare headings/structure with `key_sections_at_review`
- Check release tags/changelog for GitHub repositories

Record findings as:

```
Source: <tracking-key>
Previous state: <version_marker>
Current state: <observed now>
Delta: <specific changes>
```

### Step 2 — Classify findings

| Classification | Criteria | Action |
|---|---|---|
| Breaking | Schema/format/term changed in a way that invalidates local governance artifacts | Must adopt |
| Enhancement | New practice improves quality/safety/maintainability | Evaluate cost-benefit; adopt if net-positive |
| Informational | Interesting but no immediate governance impact | Track in notes |
| Not applicable | Outside project stack/context (e.g., MSan on CUDA, Conan on FetchContent project) | Skip |

### Step 3 — Determine scope

For breaking/enhancement items:
1. Identify affected local files
2. Apply context-load heuristic: reactive diagnostics should live in a skill/knowledge file, not always-on instructions
3. Plan edits (ExecPlan for complex changes)

### Step 4 — Implement and validate

1. Update impacted governance files
2. Validate structure and commands
3. Commit with a message referencing source key + what changed

Example:

```
docs(governance): adopt updates from vscode-agent-skills

Upstream change: new SKILL frontmatter field added.
Local adoption: updated SKILL templates and guidance.
```

### Step 5 — Update tracking

For reviewed sources:
- update `last_reviewed`
- update `version_marker`
- update `key_sections_at_review` if needed
- update `github_release_tag` if changed
- append notes

Commit tracking updates even when no governance changes were adopted.

---

## particle-sim Adaptation Notes

When reviewing upstream Generic template changes, consult the intentional local customizations table before adopting. These differences are deliberate and must be preserved.

Full table: see [reference/particle-sim-adaptations.md](reference/particle-sim-adaptations.md).

This file is shared with the `adopt-template-updates` skill.
