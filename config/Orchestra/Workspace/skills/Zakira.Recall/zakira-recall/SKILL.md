---
name: zakira-recall
description: Search the web, fetch pages, and run multi-source research with citations using Zakira.Recall, a local CLI and MCP server that uses Playwright-driven providers (DuckDuckGo, Bing) without API keys. Use this when the user wants web search results, wants to read or extract content from a URL (including recipes, articles and products with schema.org structured data), wants deep research with sources, when configuring profiles or browser authentication for blocked providers, or when troubleshooting failed searches, consent pages, captchas, verification pages, or provider fallback. Works both through the `recall` CLI and through the `recall mcp` stdio server (tools `web_search`, `web_fetch`, `web_research`, `web_batch_fetch`, `web_search_then_fetch`, `web_list_providers`, `web_get_provider_health`, `web_show_config`, `web_show_profile`).
license: MIT
compatibility: Requires the `recall` global tool (`dotnet tool install --global Zakira.Recall`) and Microsoft Edge (default channel) or a Playwright chromium install. Works on Windows, macOS, and Linux. CLI and MCP stdio server.
metadata:
  project: Zakira.Recall
  homepage: https://github.com/MoaidHathot/Zakira.Recall
  version: "0.6.1"
---

# Zakira.Recall

Zakira.Recall is a local web search, page fetch, and research toolkit for AI agents. It exposes the same capabilities through two surfaces:

- **CLI**: the `recall` global tool. Use this in shell scripts and one-off commands.
- **MCP server**: `recall mcp` runs an MCP stdio server that exposes typed tools to MCP-compatible clients (Claude Code, OpenCode, Cursor, etc.).

Providers are Playwright-backed (`duckduckgo`, `duckduckgo-browser`, `bing`) and require **no API keys**. The tool keeps cookies and consent state in named browser profiles, so a one-time interactive sign-in unblocks providers that show consent pages or captchas.

Fetched pages are rendered in a real browser and reduced to readable text with block structure (paragraphs, headings, bullets), plus metadata and any schema.org JSON-LD the page declares (`structuredData.mainEntity`: a `Recipe`, `Article`, `Product`, ...). Recipes therefore arrive with ingredients, steps and times already structured; no HTML parsing is needed on the caller's side.

## When to use this skill

Load this skill when the user asks for any of:

- web search ("search for...", "find pages about...", "google this", "look up...")
- reading a URL ("fetch this page", "read https://...", "extract text from...", "get the recipe from...")
- multi-source research with citations ("research...", "what does the web say about...", "summarize sources on...")
- setting up or installing `recall`, `Zakira.Recall`, or the MCP server
- diagnosing failed searches, consent prompts, captchas, "Just a moment..." verification pages, provider fallback, or health issues

## How to navigate this skill

`SKILL.md` is intentionally small. Load the reference file for the specific task. Each reference is self-contained and < 300 lines so it stays cheap to load.

| If the task is...                                              | Load this file                                | Covers                                                                                   |
|----------------------------------------------------------------|-----------------------------------------------|------------------------------------------------------------------------------------------|
| Search the web for results (titles, URLs, snippets)            | `references/search.md`                        | `web_search` / `recall search`, operators, providers, pagination, time range, fallback   |
| Deep research with citations and extracted page content        | `references/research.md`                      | `web_research` / `recall research`, top-pages selection, domain diversity, partial errors |
| Read or extract text or structured data from known URLs        | `references/fetch.md`                         | `web_fetch`, `web_batch_fetch`, `web_search_then_fetch` / `recall fetch`, response fields |
| Install, configure, or register the MCP server with a client   | `references/setup.md`                         | `dotnet tool install`, browser runtime, `recall config init`, MCP registration           |
| Fetch or search fails, provider unhealthy, consent or captcha  | `references/troubleshooting.md`               | Error codes, verification pages, driver restarts, `recall profile auth interactive`      |
| Need full MCP tool surface and parameter reference             | `references/mcp-tools.md`                     | All MCP tools with full parameter tables and return shapes                               |

## Decision rules

Pick the right tool the first time:

- **One query, one SERP** → `web_search` / `recall search`. See `references/search.md`.
- **One known URL** → `web_fetch` / `recall fetch <url>`. See `references/fetch.md`.
- **Multiple known URLs** → `web_batch_fetch` (one call; concurrency is bounded for you). See `references/fetch.md`.
- **Search and then fetch specific result indexes** → `web_search_then_fetch`. See `references/fetch.md`.
- **"Research this topic"** (auto: search + fetch top N + citations) → `web_research` / `recall research`. See `references/research.md`.

Use **research** when the user wants synthesis from multiple sources. Use **search** when the user wants the result list itself. Use **fetch** when the user already has the URL.

When a fetch result has `structuredData.mainEntity`, prefer it over parsing `text` for recipes (`recipeIngredient`, `recipeInstructions`, `prepTime`, ...), articles (`headline`, `datePublished`, `author`) and products. Use `text` for the prose.

## Reading fetch results

Every fetch result carries `success`, `statusCode` and, on failure, `error.code` with `error.transient`:

- `success: true` → `text` is the page's readable content.
- `fetch_http_error` (4xx/5xx), `fetch_bot_challenge` (verification/block page), `fetch_login_required`, `fetch_weak_content` → the page is not usable; `text` still holds what was served so you can see why.
- `error.transient: true` → a retry may succeed (rate limit, 5xx, timeout, browser restart); `false` → do not retry blindly, change the approach (different URL, profile, or provider).

MCP results use camelCase field names with null fields omitted; CLI `--output json` uses PascalCase. Details in `references/fetch.md`.

## Output mode (CLI only)

CLI commands default to human-readable `text` output. When you call the CLI from a script or pipe its output back to an agent, prefer `--output json` for machine-parseable structured output. `--output markdown` prints the readable text and, for pages that declare one, a "Structured data" section with the schema.org main entity. Other mode: `dump`.

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

# Fetch one URL (text plus structured data when the page declares it)
recall fetch "https://example.com" --output markdown

# Research a topic with citations
recall research "best local mcp web search tools" --top-pages 3 --output json

# Run the MCP stdio server
recall mcp
```

For complete examples and parameter tables, load the appropriate reference file from the table above.
