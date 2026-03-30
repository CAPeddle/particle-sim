---
applyTo: "**/.github/agents/*.agent.md,**/.github/skills/*/SKILL.md"
---

# Agent & Skill File Validation

When modifying agent or skill files, validate both **tool references** and **frontmatter conformance** before committing.

## Tool Validation (`.agent.md` files)

Yellow underlines in the `tools:` array indicate invalid tools. For each, check in order:

1. [VS Code Agent Tools](https://code.visualstudio.com/docs/copilot/agents/agent-tools) — built-in tools
2. [Awesome Copilot Skills](https://github.com/github/awesome-copilot/tree/main/skills) — community skills
3. Local `.github/skills/` — custom skill definitions
4. MCP server tools (`mcp_*` prefix) — verify server is configured in `.vscode/mcp.json`

| Situation | Action |
|---|---|
| Valid but parser lagged | Keep, reload editor |
| Renamed/deprecated | Replace with current equivalent |
| Does not exist | Remove and document why |
| Capability needed, no tool | Document gap; consider a skill or instruction |

After editing `tools:`, ensure: no duplicates, logical order (built-ins → MCP → custom), reload editor to confirm.

## SKILL.md Frontmatter Conformance

Skills must use plain `---` YAML frontmatter (not code fences like ` ```skill `).

Required fields per the [Agent Skills specification](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills):

- **`name`** — lowercase, hyphens only, must match parent directory name, 1–64 chars
- **`description`** — 1–1024 chars

Valid optional fields: `license`, `compatibility`, `metadata`, `allowed-tools`.

**Do not use** non-standard fields such as `argument-hint`, `user-invokable`, or `disable-model-invocation`.

## Agent File Frontmatter

Refer to the [Copilot customization cheat sheet](https://docs.github.com/en/copilot/reference/customization-cheat-sheet) for supported frontmatter fields in `.agent.md` and `.instructions.md` files.

## Commit Convention

```
docs(agents): validate <file-name>

- <action taken>: <name> (reason)
```
