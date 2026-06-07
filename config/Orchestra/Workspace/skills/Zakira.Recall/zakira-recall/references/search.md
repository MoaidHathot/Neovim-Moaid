# Search reference

Use this when the user wants a list of search results (titles, URLs, snippets) for a query. If the user wants synthesis from multiple sources, prefer `references/research.md` instead. If the user already has a URL, prefer `references/fetch.md`.

## MCP — `WebSearch`

Returns a `SearchResponse` with `Results` (title, url, snippet, rank, provider) plus provider `Attempts` and an optional `Error`.

| Parameter           | Type       | Default | Notes                                                                                  |
|---------------------|------------|---------|----------------------------------------------------------------------------------------|
| `query`             | string     | —       | Raw query. Pass operators through unchanged (`site:`, `filetype:`, `"exact"`).         |
| `provider`          | string?    | profile | `duckduckgo`, `duckduckgo-browser`, `bing`, or alias (e.g. `ddg`).                     |
| `profile`           | string?    | `default` | Named profile from `profiles.json`.                                                  |
| `maxResults`        | int        | `10`    | Upper bound on returned results.                                                       |
| `page`              | int        | `1`     | 1-indexed result page.                                                                  |
| `timeRange`         | string?    | —       | `day`, `week`, `month`, `year`. Provider must support it.                              |
| `safeSearch`        | bool?      | —       | Override profile/provider default.                                                      |
| `enableFallback`    | bool?      | profile | Allow falling back to `fallbackProviders` if primary fails.                            |
| `fallbackProviders` | string[]?  | profile | Ordered list of providers to try if the primary fails.                                  |

## CLI — `recall search`

```powershell
recall search <query> `
  [--provider <name>] `
  [--profile <name>] `
  [--limit <n>] `
  [--page <n>] `
  [--time-range <day|week|month|year>] `
  [--safe-search <true|false>] `
  [--fallback <true|false>] `
  [--fallback-provider <name> ...] `
  [--output <json|text|markdown|dump>]
```

Default `--output` is `text`. Use `--output json` when piping to another agent or tool.

## Query operators

`recall` passes the raw query through to the provider. Use the operators each provider supports:

- Exact phrase: `"model context protocol"`
- Site filter: `site:github.com mcp server`
- File type: `filetype:pdf transformer`
- Exclude term: `nodejs -typescript`
- Boolean: `playwright OR puppeteer`
- Title hint (some providers): `intitle:agent skills`

## Provider selection

- `duckduckgo` — default; HTTP-based, fast, low overhead. Best first pick.
- `duckduckgo-browser` — Playwright variant. Use when the HTTP variant is rate-limited or blocked, or when you need the same cookies as an interactive profile.
- `bing` — Playwright. May require a one-time consent click (`recall profile auth interactive --provider bing`). See `references/troubleshooting.md`.

Aliases work everywhere a provider name is accepted. Discover them with:

```powershell
recall providers list --output json
```

## Fallback

If `enableFallback` is `true` (or set in the profile), the search service tries the primary provider, then each provider in `fallbackProviders` in order until one succeeds. The response's `ProviderAttempts` records each attempt with its outcome.

CLI:

```powershell
recall search "playwright mcp" --provider duckduckgo `
  --fallback true `
  --fallback-provider duckduckgo-browser bing
```

MCP:

```json
{
  "query": "playwright mcp",
  "provider": "duckduckgo",
  "enableFallback": true,
  "fallbackProviders": ["duckduckgo-browser", "bing"]
}
```

## Pagination

Use `page` for additional result pages. `maxResults` is the per-page cap.

```powershell
recall search "best local mcp web search tools" --page 2 --limit 10
```

## Time range and safe search

```powershell
recall search "playwright mcp" --time-range month --safe-search false
```

`timeRange` accepts `day`, `week`, `month`, `year`. Providers silently ignore unsupported values.

## Response shape (abridged)

```json
{
  "Query": "site:github.com mcp server",
  "Provider": "duckduckgo",
  "Profile": "default",
  "Success": true,
  "Results": [
    {
      "Title": "...",
      "Url": "https://github.com/...",
      "CanonicalUrl": "https://github.com/...",
      "Host": "github.com",
      "DisplayUrl": "github.com",
      "Snippet": "...",
      "Provider": "duckduckgo",
      "Rank": 1,
      "RawRank": 1,
      "QualityScore": 0,
      "SourceProviders": ["duckduckgo"]
    }
  ],
  "Attempts": [
    { "Provider": "duckduckgo", "Success": true, "Skipped": false, "ResultCount": 10, "Error": null }
  ],
  "Error": null
}
```

## Common patterns

**1. Find GitHub repos for a topic:**

```powershell
recall search "site:github.com mcp server" --limit 20 --output json
```

**2. Fresh news on a topic from the last week:**

```powershell
recall search "playwright release" --time-range week
```

**3. Force a specific provider (skip default):**

MCP:

```json
{ "query": "agent skills spec", "provider": "bing" }
```

**4. Probe provider health before committing:**

Use `WebGetProviderHealth` (MCP) or `recall providers test <name>` (CLI). See `references/troubleshooting.md`.

## When NOT to use search

- The user already gave you a URL → use `WebFetch`. See `references/fetch.md`.
- The user wants a synthesized answer from multiple sources → use `WebResearch`. See `references/research.md`.
- You need to fetch the top N results' content after searching → use `WebSearchThenFetch`, which combines both. See `references/fetch.md`.
