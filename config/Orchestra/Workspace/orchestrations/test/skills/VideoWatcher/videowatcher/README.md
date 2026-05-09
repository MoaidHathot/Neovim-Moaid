# VideoWatcher Skill Packages

VideoWatcher ships separate reusable agent-facing skills for CLI and MCP use.

## Files

- `../videowatcher-cli/SKILL.md`: CLI workflow for agents that can run shell commands.
- `../videowatcher-mcp/SKILL.md`: MCP workflow for agents connected to `videowatcher mcp serve`.
- `SKILL.md`: compatibility router for older setups that only referenced `skills/videowatcher`.
- `examples/mcp-client-config.json`: generic MCP stdio client configuration.
- `examples/job-flow.jsonl`: JSON-RPC job-flow example.
- `examples/prompts.md`: user prompt patterns and agent execution notes.
- `examples/artifact-checklist.md`: artifact reading and evidence checklist.

## Installation Concept

Copy or reference `../videowatcher-cli/SKILL.md` for CLI use, or `../videowatcher-mcp/SKILL.md` for MCP use, in an agent system that supports custom skills/instructions. Configure the MCP server command as:

```bash
videowatcher mcp serve
```

If the `videowatcher` global tool is not on PATH, use the full path to the executable or run through `dotnet` from the project during development.
