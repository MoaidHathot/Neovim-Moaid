# Research reference

Use this when the user wants a synthesized answer drawn from multiple web sources, with citations. If they just want the result list, use `references/search.md`. If they only need to read a specific URL, use `references/fetch.md`.

`WebResearch` runs a complete pipeline in one call:

1. Search the web with the chosen provider.
2. Deduplicate equivalent result URLs.
3. Pick the top N results, preferring unique domains by default.
4. Fetch those pages in parallel.
5. Extract readable text.
6. Return structured `Citations` and full `Sources` (search result + fetch).

If some fetches fail, the others still succeed and `Errors` reports what was lost. This is intentional — one bad page does not fail the whole research call.

## MCP — `WebResearch`

| Parameter                | Type       | Default | Notes                                                                                |
|--------------------------|------------|---------|--------------------------------------------------------------------------------------|
| `query`                  | string     | —       | Raw research query.                                                                  |
| `provider`               | string?    | profile | `duckduckgo`, `duckduckgo-browser`, `bing`, or alias.                                |
| `profile`                | string?    | `default` | Named profile from `profiles.json`.                                                |
| `maxResults`             | int        | `8`     | Cap on the search step.                                                              |
| `topPagesToRead`         | int        | `3`     | How many of those results to actually fetch and read. Keep small to control latency. |
| `page`                   | int        | `1`     | 1-indexed result page.                                                                |
| `timeRange`              | string?    | —       | `day`, `week`, `month`, `year`. Provider must support it.                            |
| `safeSearch`             | bool?      | —       | Override profile/provider default.                                                    |
| `enableFallback`         | bool?      | profile | Allow falling back to `fallbackProviders` if primary search fails.                   |
| `fallbackProviders`      | string[]?  | profile | Ordered fallback list.                                                                |
| `maxConcurrentFetches`   | int?       | profile | Cap concurrent page fetches. Defaults to the profile's `maxConcurrentFetches`.       |
| `enforceDomainDiversity` | bool       | `true`  | Prefer unique domains when picking top pages. Set `false` to allow many from one site. |

## CLI — `recall research`

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

## Response shape (abridged)

```json
{
  "Query": "best local mcp web search tools",
  "Provider": "duckduckgo",
  "Profile": "default",
  "Success": true,
  "Summary": null,
  "SearchResults": [ /* full SearchResult list, in rank order */ ],
  "Sources": [
    {
      "CitationId": "c1",
      "SearchResult": { "Rank": 1, "Title": "...", "Url": "...", "Snippet": "..." },
      "Fetch": {
        "Url": "...",
        "FinalUrl": "...",
        "Success": true,
        "Title": "...",
        "Text": "...",
        "Excerpt": "...",
        "Domain": "github.com",
        "SiteName": "GitHub",
        "WordCount": 1843
      }
    }
  ],
  "Citations": [
    { "Id": "c1", "Title": "...", "Url": "...", "Domain": "github.com", "Rank": 1 }
  ],
  "Errors": [
    { "Code": "FetchFailed", "Message": "...", "Provider": null, "Target": "https://...", "Transient": false }
  ]
}
```

- `SearchResults` always contains the full search step output.
- `Sources` contains successfully fetched results with their extracted content.
- `Citations` is the lightweight reference list intended for prompts and footnotes.
- `Errors` is non-empty when some pages failed; `Success` is still `true` if at least one page was fetched.

## Tuning the call

- **Faster, cheaper**: `topPagesToRead: 2`, `maxResults: 5`.
- **Broader survey**: `topPagesToRead: 5`, `maxResults: 12`, `enforceDomainDiversity: true`.
- **Single-source deep read**: `enforceDomainDiversity: false` lets multiple results from the same domain through.
- **Fresh content**: add `timeRange: "week"` or `"month"`.

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

Inspect `Errors` to decide whether to retry:

- `FetchFailed` for an individual URL → not fatal; you can ignore or re-attempt that URL via `WebFetch`.
- `SearchFailed` on the entire response with empty `SearchResults` → the search step itself failed. Try a different `provider` or enable fallback. See `references/troubleshooting.md`.
- Many `FetchFailed` errors from the same domain → that site may be blocking automation. Try `duckduckgo-browser` or fetch through a profile that has accepted consent.

## When to use research vs. search+fetch manually

Prefer `WebResearch` when:

- You want one round-trip from query to source-backed content.
- You want domain diversity handled for you.
- You want one consistent partial-error model.

Prefer `WebSearch` + targeted `WebFetch`/`WebSearchThenFetch` when:

- You need to inspect snippets before deciding what to read.
- You want full control over which exact result indexes are fetched.
- You want to fetch many pages without the research step's `topPagesToRead` cap. See `references/fetch.md`.
