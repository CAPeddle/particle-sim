---
name: validate-agent-tools
description: Validates and updates tool references in VS Code agent files (.agent.md). Identifies invalid tools (yellow underlines in editor), verifies availability in current VS Code/Copilot tooling, and updates agent configurations to use supported tools.
---

# Validate Agent Tools

This skill provides a systematic process for validating and updating tool references in agent frontmatter `tools:` arrays.

## When to Use This Skill

- An agent file has tools marked as invalid (yellow underline)
- Reviewing agent configurations before distribution
- Creating a new agent and confirming tool availability
- Updating agents to newer tool names or capabilities

## Reference Sources

1. [VS Code Agent Tools](https://code.visualstudio.com/docs/copilot/agents/agent-tools)
2. [VS Code Agent Skills](https://code.visualstudio.com/docs/copilot/customization/agent-skills)
3. [Awesome Copilot Learning Hub](https://awesome-copilot.github.com/learning-hub/what-are-agents-skills-instructions/)
4. [Awesome Copilot Skills Repository](https://github.com/github/awesome-copilot/tree/main/skills)

## Validation Workflow

### Step 1 — Identify invalid tools

Open the agent file and inspect frontmatter:

```yaml
tools: ['read', 'search', 'edit', 'execute', 'todo']
```

Any yellow-underlined tool should be validated.

### Step 2 — Check availability

For each invalid tool:
1. Check built-in VS Code tools list
2. Check community skills for equivalent capabilities
3. Check local `.github/skills/` for custom definitions
4. Check MCP server tools (typically prefixed, e.g. `mcp_*`)

### Step 3 — Choose action

| Situation | Action |
|---|---|
| Tool is valid but parser lagged | Keep as-is, reload editor |
| Tool was renamed/deprecated | Replace with current equivalent |
| Tool does not exist | Remove and document why |
| Capability needed but no tool exists | Document gap and suggest workflow fallback via skill/instructions |

### Step 4 — Update the agent file

After editing `tools:` ensure:
- only valid tools remain
- no duplicates
- tools are grouped logically (built-ins first, then MCP/custom)

### Step 5 — Document and verify

- Add a brief note in commit message about tool changes
- Reload editor; confirm yellow underlines are resolved
- Run repository validation/build checks if applicable

## Commit message example

```
docs(agents): validate tools in developer.agent.md

- Removed unavailable tool: <name>
- Updated renamed tool: <old> -> <new>
- Verified against VS Code Agent Tools docs
```

## particle-sim Agent Roster

Full agent list with file paths and reference source check order: see [reference/agent-roster.md](reference/agent-roster.md).

## Common notes

| Tool family | Note |
|---|---|
| Built-in VS Code tools | Usually stable; invalid underline often means typo/version mismatch |
| `mcp_*` tools | Require corresponding MCP server to be configured |
| Custom tool names | Must exist in current runtime; otherwise replace with skills/workflow guidance |
