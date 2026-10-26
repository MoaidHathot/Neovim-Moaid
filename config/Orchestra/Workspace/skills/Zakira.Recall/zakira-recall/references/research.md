# Research reference

Use this when the user wants a synthesized answer drawn from multiple web sources, with citations. If they just want the result list, use `references/search.md`. If they only need to read a specific URL, use `references/fetch.md`.

`web_research` runs a complete pipeline in one call:

1. Search the web with the chosen provider.
2. Deduplicate equivalent result URLs.
3. Pick the top N results, preferring unique domains by default.
4. Fetch those pages with bounded concurrency.
5. Extract readable text and structured data from each page.
6. Return structured `citations` and full `sources` (search result + fetch).

If some fetches fail, the others still succeed and `errors` reports what was lost. This is intentional: one bad page does not fail the whole research call.

## MCP - `web_research`

| Parameter                | Type       | Default   | Notes                                                                                |
|--------------------------|------------|-----------|--------------------------------------------------------------------------------------|
| `query`                  | string     | -         | Raw research query.                                                                  |
| `provider`               | string?    | profile   | `duckduckgo`, `duckduckgo-browser`, `bing`, or alias.                                |
| `profile`                | string?    | `default` | Named profile from `profiles.json`.                                                  |
| `maxResults`             | int        | `8`       | Cap on the search step.                                                              |
| `topPagesToRead`         | int        | `3`       | How many of those results to actually fetch and read. Keep small to control latency. |
| `page`                   | int        | `1`       | 1-indexed result page.                                                               |
| `timeRange`              | string?    | -         | `day`, `week`, `month`, `year`. Provider must support it.                            |
| `safeSearch`             | bool?      | -         | Override profile/provider default.                                                   |
| `enableFallback`         | bool?      | profile   | Allow falling back to `fallbackProviders` if primary search fails.                   |
| `fallbackProviders`      | string[]?  | profile   | Ordered fallback list.                                                               |
| `maxConcurrentFetches`   | int?       | profile   | Cap concurrent page fetches (1-16). Defaults to the profile's `maxConcurrentFetches` (3). |
| `enforceDomainDiversity` | bool       | `true`    | Prefer unique domains when picking top pages. Set `false` to allow many from one site. |

## CLI - `recall research`

```powershell
recall research <query> `
  [--provider <name>] `
  [--profile <name>] `
  [--limit <n>] `
  [--top-pages <n>] `
  [--page <n>] `
  [--time-range <day|week|month|year>] `
  [--safe-search <true|false>] `
  [--fallback <true|false>] `
  [--fallback-provider <name> ...] `
  [--max-concurrent-fetches <n>] `
  [--domain-diversity <true|false>] `
  [--output <json|text|markdown|dump>]
```

## Response shape (abridged, MCP camelCase; CLI `--output json` uses PascalCase)

```json
{
  "query": "best local mcp web search tools",
  "provider": "duckduckgo",
  "profile": "default",
  "success": true,
  "summary": "One or two sentences per strong source, joined; a quick extractive overview of what was read.",
  "searchResults": [ /* full SearchResult list, in rank order */ ],
  "sources": [
    {
      "citationId": "c1",
      "searchResult": { "rank": 1, "title": "...", "url": "...", "snippet": "..." },
      "fetch": {
        "url": "...",
        "finalUrl": "...",
        "success": true,
        "statusCode": 200,
        "title": "...",
        "text": "...",
        "excerpt": "...",
        "domain": "github.com",
        "siteName": "GitHub",
        "publishedAt": "2026-05-01T10:00:00+00:00",
        "wordCount": 1843,
        "contentSelector": "article",
        "mainImage": "https://...",
        "structuredData": { "types": ["Article"], "mainEntityType": "Article", "mainEntity": { "...": "..." } }
      }
    }
  ],
  "citations": [
    { "id": "c1", "title": "...", "url": "...", "domain": "github.com", "provider": "duckduckgo", "rank": 1, "quote": "...first 400 characters of the page...", "publishedAt": "2026-05-01T10:00:00+00:00" }
  ],
  "errors": [
    { "code": "fetch_http_error", "message": "Server returned HTTP 404 (NotFound).", "target": "https://...", "transient": false }
  ]
}
```

- `summary` is an extractive overview built from the strongest sources (no model involved); it is a starting point, not the answer.
- `searchResults` always contains the full search step output.
- `sources` contains successfully fetched results with their extracted content; each `fetch` is a complete `FetchResponse`
  (see `references/fetch.md`), so `structuredData.mainEntity` is available for recipes, articles and products.
- `citations` is the lightweight reference list intended for prompts and footnotes; `quote` is the page excerpt.
- `errors` is non-empty when some pages failed; `success` is still `true` if at least one page was fetched.

## Tuning the call

- **Faster, cheaper**: `topPagesToRead: 2`, `maxResults: 5`.
- **Broader survey**: `topPagesToRead: 5`, `maxResults: 12`, `enforceDomainDiversity: true`.
- **Single-source deep read**: `enforceDomainDiversity: false` lets multiple results from the same domain through.
- **Fresh content**: add `timeRange: "week"` or `"month"`.
- **Small machine**: lower `maxConcurrentFetches` (each concurrent fetch is a browser instance).

## Common patterns

**1. General-purpose deep research:**

```powershell
recall research "best local mcp web search tools" `
  --top-pages 3 --limit 8 --output json
```

**2. Survey across many domains:**

```powershell
recall research "playwright search providers" `
  --limit 12 --top-pages 5 --domain-diversity true --output json
```

**3. Constrain to recent content:**

```powershell
recall research "Zakira.Recall release notes" `
  --time-range month --top-pages 4 --output markdown
```

**4. Resilient research with provider fallback:**

```powershell
recall research "playwright search providers" `
  --provider duckduckgo `
  --fallback true `
  --fallback-provider duckduckgo-browser bing `
  --max-concurrent-fetches 4
```

## Handling partial failures

Inspect `errors` to decide whether to retry:

- `fetch_http_error`, `fetch_bot_challenge`, `fetch_login_required`, `fetch_weak_content`, `fetch_failed` for an individual URL → not fatal;
  ignore it or re-attempt that URL via `web_fetch` (only when `transient: true`). Meanings in `references/fetch.md`.
- `search_failed` with empty `searchResults` → the search step itself failed. Try a different `provider` or enable fallback. See `references/troubleshooting.md`.
- Many failures from the same domain → that site may be blocking automation. Try `duckduckgo-browser` or fetch through a profile that has visited the site interactively.

## When to use research vs. search+fetch manually

Prefer `web_research` when:

- You want one round-trip from query to source-backed content.
- You want domain diversity handled for you.
- You want one consistent partial-error model.

Prefer `web_search` + targeted `web_fetch`/`web_search_then_fetch` when:

- You need to inspect snippets before deciding what to read.
- You want full control over which exact result indexes are fetched.
- You want to fetch many pages without the research step's `topPagesToRead` cap. See `references/fetch.md`.
