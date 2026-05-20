# Zakira.Replay Skill Packages

Zakira.Replay ships separate reusable agent-facing skills for CLI and MCP use.

## Files

- `../zakira-replay-cli/SKILL.md`: CLI workflow for agents that can run shell commands.
- `../zakira-replay-mcp/SKILL.md`: MCP workflow for agents connected to `zakira-replay mcp serve`.
- `SKILL.md`: compatibility router for older setups that only referenced `skills/zakira-replay`.
- `examples/mcp-client-config.json`: generic MCP stdio client configuration.
- `examples/job-flow.jsonl`: JSON-RPC job-flow example.
- `examples/prompts.md`: user prompt patterns and agent execution notes.
- `examples/artifact-checklist.md`: artifact reading and evidence checklist.

## Installation Concept

Copy or reference `../zakira-replay-cli/SKILL.md` for CLI use, or `../zakira-replay-mcp/SKILL.md` for MCP use, in an agent system that supports custom skills/instructions. Configure the MCP server command as:

```bash
zakira-replay mcp serve                                  # stdio (default)
zakira-replay mcp serve --transport http --port 8765     # Streamable HTTP for hosted agent platforms
zakira-replay mcp serve --transport sse  --port 8765     # alias for Streamable HTTP (legacy SSE clients)
```

If the `zakira-replay` global tool is not on PATH, use the full path to the executable or run through `dotnet` from the project during development.
