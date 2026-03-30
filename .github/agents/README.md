# Agent Workflow Documentation — Index

**Purpose:** Central reference for all agent workflow documentation
**Status:** ✅ Active

---

## File Organisation

### In This Folder (`.github/agents/`)
- Agent definition files: `*.agent.md`
- Index and guidance: this `README.md`
- Agent-wide trigger rules: [`AGENTS.md`](../../AGENTS.md)

### Supporting Documentation
- ExecPlan standard: [`.github/planning/PLANS.md`](../planning/PLANS.md)
- ExecPlan template: [`.github/planning/execplans/_TEMPLATE.md`](../planning/execplans/_TEMPLATE.md)

---

## Core Workflow

```
User request
    │
    ▼
Overlord (orchestrator)
    ├─ determine if ExecPlan required
    ├─ if yes: create + approve ExecPlan first
    │
    ├─ Testing agent  ──►  RED phase tests (written before implementation)
    ├─ Developer agent ──► GREEN implementation
    ├─ Debugger agent  ──► investigate failures (as needed)
    ├─ Code Reviewer   ──► mandatory formal review (cannot be skipped)
    └─ Developer        ──► resolve all ERRORs from review
         │
         ▼
    Overlord — integrate outcomes, report completion
```

**Code review is mandatory.** No work is complete until the code-reviewer agent (or a human reviewer) reports zero ERRORs.

---

## Agent Roster

### Primary Agents

#### [Overlord](./overlord.agent.md)
**Role:** Orchestrator. Enforces standards, coordinates agents, owns quality gate.

#### [Developer](./developer.agent.md)
**Role:** Implementation specialist. TDD, C++23/CUDA 20, project coding standards.

#### [Debugger](./debugger.agent.md)
**Role:** Investigation specialist. Root-cause analysis, diagnostic reports, targeted fixes.

#### [Testing](./testing.agent.md)
**Role:** TDD specialist. Writes failing RED-phase tests before implementation begins.

#### [Code Reviewer](./code-reviewer.agent.md)
**Role:** Quality gatekeeper. Mandatory review against `copilot-instructions.md`.

### Specialist Agents

#### [C++ Expert](./expert-cpp.agent.md)
**Role:** Deep C++23/CUDA 20 guidance. Core Guidelines, RAII, no-exception, sanitizer compliance, SM 89 CUDA patterns.

#### [ADR Generator](./adr-generator.agent.md)
**Role:** Creates Architecture Decision Records in `docs/adr/` with full POS/NEG/ALT/IMP structure.

---

## Skills

Skills are procedural guides invoked by agents. They are not agents — they have no tools and produce no output unless an agent reads and applies them.

| Skill | Purpose |
|-------|---------|
| [`build-and-test`](../skills/build-and-test/SKILL.md) | Step-by-step build, dependency setup, and test execution |
| [`conventional-commit`](../skills/conventional-commit/SKILL.md) | Conventional Commits 1.0.0 workflow with particle-sim scopes |
| [`create-architectural-decision-record`](../skills/create-architectural-decision-record/SKILL.md) | ADR document to `docs/adr/` with full template |
| [`create-technical-spike`](../skills/create-technical-spike/SKILL.md) | Time-boxed research doc to `docs/spikes/` |
| [`validate-agent-tools`](../skills/validate-agent-tools/SKILL.md) | Validate and update tools listed in `.agent.md` frontmatter against current VS Code/Copilot capabilities |
| [`adopt-template-updates`](../skills/adopt-template-updates/SKILL.md) | Safely adopt newer Generic template governance updates into particle-sim |
| [`review-upstream-sources`](../skills/review-upstream-sources/SKILL.md) | Review upstream governance sources for changes, update local governance |

---

## Skill Authoring Standard — "Point Don't Dump"

Skills follow a **layered** structure aligned with VS Code's [progressive loading model](https://code.visualstudio.com/docs/copilot/customization/agent-skills). The principle is **point, don't dump**: give the agent layers of increasing detail, letting it pull what it needs rather than flooding context on every invocation.

### The Three Layers

| Layer | Location | Content | When Loaded |
|-------|----------|---------|-------------|
| **1 — Description** | YAML frontmatter (`name` + `description`) | What the skill does and when to use it | **Always** — drives skill discovery; never consumes conversation context |
| **2 — Process** | SKILL.md body | Decision tree: steps, decision points, and **pointers** to Layer 3 resources | **On invocation** — loaded into context when the skill matches or is `/`-invoked |
| **3 — Reference & Scripts** | Other files in the skill directory (`.md`, `.ps1`, etc.) | Lookup tables, runnable scripts, templates, worked examples | **On demand** — accessed only when the Layer 2 process explicitly references them |

### Layer 2 Guidelines

The SKILL.md body should read like a **decision tree**, not a reference manual:

- **Do:** Name each step, state its purpose, describe the decision or action, and point to a Layer 3 file for the details.
- **Don't:** Inline long scripts, reference tables, or templates. Extract to separate files and reference with a relative link.
- **One-liners are fine inline.** Only extract when a code block exceeds ~5 lines or a table exceeds ~5 rows.
- **Slim summaries preferred.** For large Layer 3 files, include a 2–3 line summary of what the file contains and when to read it, then link.

### Layer 3 Guidelines

- **Runnable scripts** (`.ps1`, `.py`) should be parameterised and directly executable.
- **Reference files** (`.md`) should be self-contained — readable without the parent SKILL.md.
- **Avoid duplication.** Point to canonical sources rather than copying. A slim summary in the skill directory is acceptable when the canonical source is large.

### Example Structure

```
.github/skills/my-skill/
├── SKILL.md                  # Layer 2 — decision tree with pointers
├── scripts/
│   └── validate.ps1          # Layer 3 — runnable script
└── reference/
    └── known-issues.md       # Layer 3 — lookup table
```

> **Review gate:** The `review-upstream-sources` skill includes skill-structure compliance as a review criterion.

---

## Model Selection Guidance

*Based on Cursor "Scaling Agents" (Jan 2026) findings.*

| Task type | Recommended model |
|-----------|------------------|
| Planning, architecture, orchestration | Claude Opus / GPT-5.2 — sustained focus, low drift |
| Focused implementation | Claude Sonnet / GPT-5.1-Codex — fast, context-efficient |
| Code review | Claude Sonnet — nuanced reasoning |
| Short targeted edits | Any fast model |

Use the best model for the role, not one universal model. Planner agents (Overlord) benefit most from the highest-quality models.

---

## particle-sim Specific

### Technology Stack
- **C++23** for CPU code
- **CUDA 20** for GPU kernels
- **CMake 3.28** + Ninja build
- **OpenGL 4.6 + CUDA-GL interop** for rendering

### Naming Conventions
- Classes/Structs: `PascalCase`
- Functions/Methods: `camelCase`
- Variables: `camelCase`
- Private members: `camelCase` (no prefix)
- Constants: `UPPER_SNAKE_CASE`
- CUDA kernels: `camelCaseKernel`
- Namespace: `psim::`

### Quality Gates
- clang-format on `.cpp`, `.hpp`, `.cu`, `.cuh`
- clang-tidy on `.cpp`, `.hpp` only (CUDA limited support)
- ASan + UBSan for CPU code (CUDA incompatible with MSan/TSan)

---

## Influences & Sources

The governance model for this repository draws on the following external sources. Each entry documents what was adopted and where it landed.

| Source | Key Contribution | Where It Landed |
|--------|-----------------|-----------------|
| [EveryInc: Compound Engineering](https://github.com/EveryInc/compound-engineering-plugin) | Plan→Work→Review→**Compound** lifecycle; mandatory code review; learning capture | PLANS.md mandatory Compound checkpoint; Overlord workflow step 8; ExecPlan template Step 5 |
| [OpenAI Cookbook: ExecPlans](https://developers.openai.com/cookbook/articles/codex_exec_plans) | Self-contained plans; define every term; observable outcomes; idempotence | PLANS.md quality bar; ExecPlan template structure |
| [Cursor: Scaling Agents](https://cursor.com/blog/scaling-agents) | Planner/worker hierarchy; model selection by role; prompt quality over architecture | Overlord planner/worker pattern; Model Selection Guidance table |
| [GitHub Copilot Docs](https://docs.github.com/en/copilot) | Agent skills spec; YAML frontmatter; path-specific instructions; agentStop hooks | Skills, instructions, hooks, agent file format |
| [Get Shit Done (GSD)](https://github.com/gsd-build/get-shit-done) | Context degradation thresholds; ExecPlan as session-handoff artifact; task atomicity | Overlord context pressure tracking; PLANS.md task sizing section |
| [Jason Turner, CppCon 2025](https://www.youtube.com/watch?v=xCuRUjxT5L8) | C++ LLM failure modes; prompt discipline; output review checklist | copilot-instructions.md AI Tool Usage Guidelines |
| [github/awesome-copilot](https://github.com/github/awesome-copilot) | Agent/skill/hook/instruction taxonomy | Overall governance structure |
| Generic Governance Template | Starter kit for all governance files; Point Don't Dump skill authoring standard | All `.github/` governance files; agents/README Skill Authoring Standard section |

Full source registry and tracking state: see [`review-upstream-sources/reference/seed-sources.md`](../skills/review-upstream-sources/reference/seed-sources.md) and [`source-tracking.json`](../skills/review-upstream-sources/source-tracking.json).
