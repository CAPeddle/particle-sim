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
