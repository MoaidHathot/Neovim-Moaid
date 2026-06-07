---
name: zakira-recall
description: Search the web, fetch pages, and run multi-source research with citations using Zakira.Recall, a local CLI and MCP server that uses Playwright-driven providers (DuckDuckGo, Bing) without API keys. Use this when the user wants web search results, wants to read or extract content from a URL, wants deep research with sources, when configuring profiles or browser authentication for blocked providers, or when troubleshooting failed searches, consent pages, captchas, or provider fallback. Works both through the `recall` CLI and through the `recall mcp` stdio server (tools `WebSearch`, `WebFetch`, `WebResearch`, `WebBatchFetch`, `WebSearchThenFetch`, `WebListProviders`, `WebGetProviderHealth`, `WebShowConfig`, `WebShowProfile`).
license: MIT
compatibility: Requires the `recall` global tool (`dotnet tool install --global Zakira.Recall`) and a Playwright chromium install. Works on Windows, macOS, and Linux. CLI and MCP stdio server.
metadata:
  project: Zakira.Recall
  homepage: https://github.com/MoaidHathot/Zakira.Recall
  version: "0.5.0"
---

# Zakira.Recall

Zakira.Recall is a local web search, page fetch, and research toolkit for AI agents. It exposes the same capabilities through two surfaces:

- **CLI**: the `recall` global tool. Use this in shell scripts and one-off commands.
- **MCP server**: `recall mcp` runs an MCP stdio server that exposes typed tools to MCP-compatible clients (Claude Code, OpenCode, Cursor, etc.).

Providers are Playwright-backed (`duckduckgo`, `duckduckgo-browser`, `bing`) and require **no API keys**. The tool keeps cookies and consent state in named browser profiles, so a one-time interactive sign-in unblocks providers that show consent pages or captchas.

## When to use this skill

Load this skill when the user asks for any of:

- web search ("search for...", "find pages about...", "google this", "look up...")
- reading a URL ("fetch this page", "read https://...", "extract text from...")
- multi-source research with citations ("research...", "what does the web say about...", "summarize sources on...")
- setting up or installing `recall`, `Zakira.Recall`, or the MCP server
- diagnosing failed searches, consent prompts, captchas, provider fallback, or health issues

## How to navigate this skill

`SKILL.md` is intentionally small. Load the reference file for the specific task. Each reference is self-contained and < 300 lines so it stays cheap to load.

| If the task is...                                              | Load this file                                | Covers                                                                                  |
|----------------------------------------------------------------|-----------------------------------------------|-----------------------------------------------------------------------------------------|
| Search the web for results (titles, URLs, snippets)            | `references/search.md`                        | `WebSearch` / `recall search`, operators, providers, pagination, time range, fallback   |
| Deep research with citations and extracted page content        | `references/research.md`                      | `WebResearch` / `recall research`, top-pages selection, domain diversity, partial errors |
| Read or extract text from one or more known URLs               | `references/fetch.md`                         | `WebFetch`, `WebBatchFetch`, `WebSearchThenFetch` / `recall fetch`                       |
| Install, configure, or register the MCP server with a client   | `references/setup.md`                         | `dotnet tool install`, Playwright install, `recall config init`, MCP registration       |
| Searches fail, provider is unhealthy, consent or captcha shown | `references/troubleshooting.md`               | `recall profile auth interactive`, fallback, health, common errors                       |
| Need full MCP tool surface and parameter reference             | `references/mcp-tools.md`                     | All MCP tools with full parameter tables and return shapes                              |

## Decision rules

Pick the right tool the first time:

- **One query, one SERP** → `WebSearch` / `recall search`. See `references/search.md`.
- **One known URL** → `WebFetch` / `recall fetch <url>`. See `references/fetch.md`.
- **Multiple known URLs** → `WebBatchFetch`. See `references/fetch.md`.
- **Search and then fetch specific result indexes** → `WebSearchThenFetch`. See `references/fetch.md`.
- **"Research this topic"** (auto: search + fetch top N + citations) → `WebResearch` / `recall research`. See `references/research.md`.

Use **research** when the user wants synthesis from multiple sources. Use **search** when the user wants the result list itself. Use **fetch** when the user already has the URL.

## Output mode (CLI only)

CLI commands default to human-readable `text` output. When you call the CLI from a script or pipe its output back to an agent, prefer `--output json` for machine-parseable structured output. Other modes: `markdown`, `dump`.

MCP tools always return structured typed objects.

## Provider quick reference

- `duckduckgo` — fastest, no consent in most regions. Default.
- `duckduckgo-browser` — same provider via Playwright, useful when the HTTP variant is blocked or rate-limited.
- `bing` — Playwright-driven. May require a one-time consent click via `recall profile auth interactive --provider bing`.
- Aliases (e.g. `ddg`) are resolved by the registry, so use them anywhere a provider is accepted.

For provider selection rules and fallback, see `references/search.md`.

## Minimal examples

```powershell
# Search
recall search "site:github.com mcp server" --limit 10 --output json

# Fetch one URL
recall fetch "https://example.com" --output markdown

# Research a topic with citations
recall research "best local mcp web search tools" --top-pages 3 --output json

# Run the MCP stdio server
recall mcp
```

For complete examples and parameter tables, load the appropriate reference file from the table above.
