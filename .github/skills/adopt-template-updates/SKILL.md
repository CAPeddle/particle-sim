---
name: adopt-template-updates
description: Step-by-step process for evaluating and adopting updates from the Generic governance template into particle-sim. Use this when the upstream template has evolved and you want to pull improvements without overwriting local CUDA/particle-sim customizations.
---

# Adopt Generic Template Updates

particle-sim governance files derive from the Generic C++ governance template. As the template
evolves, this skill provides a safe process to pull improvements while preserving intentional
local customizations.

---

## Inputs Required

- Path to latest Generic template: `C:\projects\zoom_copilot_config\Generic` (or updated location)
- Optional list of files to evaluate first (recommended)

---

## Step 1 — Identify candidate files

Start with governance artifacts:
- `.github/copilot-instructions.md`
- `.github/agents/*.agent.md`
- `.github/skills/**/SKILL.md`
- `.github/hooks/**`
- `.github/instructions/*.instructions.md`
- `.github/planning/PLANS.md`
- `.github/planning/execplans/_TEMPLATE.md`
- `.clang-format`, `.clang-tidy`, `AGENTS.md`

---

## Step 2 — Compare template vs project

Use hash check first (fast), then content diff for differences.

Comparison scripts (hash check + content diff): see [reference/comparison-scripts.md](reference/comparison-scripts.md).

Interpretation:
- `TEMPLATE` — line exists only in template (potential adoption)
- `PROJECT` — line exists only in project (local customization)

---

## Step 3 — Classify each delta

| Classification | Criteria | Action |
|---|---|---|
| **Adopt** | Template improvement applies cleanly | Bring into project |
| **Discard** | Template change conflicts with intentional project customizations | Keep project version |
| **Refine-then-adopt** | Useful idea but requires adaptation to particle-sim conventions/toolchain | Adapt then merge |

### particle-sim Customizations to Preserve

These are intentional local differences — do NOT overwrite during adoption.

Full table (9 rows): see [../review-upstream-sources/reference/particle-sim-adaptations.md](../review-upstream-sources/reference/particle-sim-adaptations.md).

---

## Step 4 — Apply updates safely

Preferred: update files selectively, section-by-section.

For wholesale replacement (only when project file has minimal local customization):

```powershell
Copy-Item "C:\projects\zoom_copilot_config\Generic\<file>" ".github\<file>" -Force
```

After each update, validate:
- Placeholders replaced with particle-sim values (`psim::`, `PS-`, etc.)
- Project paths/commands still correct
- CUDA-specific sections preserved
- No references to template-only files remain

---

## Step 5 — Validate

Run repository checks relevant to changed files:

- formatting checks (`clang-format --dry-run --Werror`)
- lint/static checks (`clang-tidy -p build/`)
- build test (`cmake --build build --parallel`)
- test suite (`ctest --test-dir build --output-on-failure`)

If changing agent files, ensure frontmatter parses and tools are recognized.

---

## Step 6 — Commit

Use a descriptive commit message that references template adoption.

Example:

```
docs(governance): adopt Generic template updates

- Updated copilot-instructions.md with anonymous namespace guidance
- Added review-upstream-sources and adopt-template-updates skills
- Synced PLANS.md investigation-first trigger from template
```

---

## Completion checklist

- [ ] Candidate files identified
- [ ] File hashes compared
- [ ] Deltas classified (adopt/discard/refine)
- [ ] Updates applied with particle-sim adaptation
- [ ] CUDA-specific sections preserved
- [ ] Validation checks run
- [ ] Commit created with clear rationale

