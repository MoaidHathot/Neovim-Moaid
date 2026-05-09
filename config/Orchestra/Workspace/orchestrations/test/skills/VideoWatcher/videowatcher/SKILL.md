---
name: videowatcher
description: Deprecated combined VideoWatcher skill. Prefer videowatcher-cli when shell commands are available, or videowatcher-mcp when VideoWatcher MCP tools are available.
---

# VideoWatcher Skill Router

This combined skill is retained for compatibility. Prefer the focused skills:

- `videowatcher-cli`: use when the agent can run shell commands.
- `videowatcher-mcp`: use when VideoWatcher MCP tools are available.

If this is the only available VideoWatcher skill, choose the surface you can access:

- Shell available: follow `../videowatcher-cli/SKILL.md`.
- MCP tools available: follow `../videowatcher-mcp/SKILL.md`.

Core rule: never pretend you watched a video directly. Use VideoWatcher to create durable artifacts, then answer from `manifest.json`, `evidence.json`, `transcript.md`, frame images, `ocr/combined.md`, `vision/combined.md`, `summary.md`, and `chapters/chapters.md`.
