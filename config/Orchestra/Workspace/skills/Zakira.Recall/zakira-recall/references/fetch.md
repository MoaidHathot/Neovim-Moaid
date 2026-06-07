# Fetch reference

Use this when the user has one or more known URLs and wants the readable content (text, title, metadata) extracted. If the user only has a topic or query, use `references/search.md` or `references/research.md` first.

There are three related tools. Pick the one that matches the situation:

| Tool                  | Use when                                                                                       |
|-----------------------|------------------------------------------------------------------------------------------------|
| `WebFetch`            | You have exactly one URL.                                                                      |
| `WebBatchFetch`       | You already have N URLs and want all of them in parallel in one call.                          |
| `WebSearchThenFetch`  | You want to search first, then fetch a specific subset of result indexes in the same call.     |
| `WebResearch`         | You want the full search + pick top-N + fetch + citations pipeline. See `references/research.md`. |

## MCP — `WebFetch`

Fetch one URL and extract readable content.

| Parameter        | Type     | Default | Notes                                          |
|------------------|----------|---------|------------------------------------------------|
| `url`            | string   | —       | The URL to fetch.                              |
| `profile`        | string?  | `default` | Named profile from `profiles.json`.          |
| `timeoutSeconds` | int      | `30`    | Per-page navigation/timeout budget.            |

Returns a `FetchResponse`:

```json
{
  "Url": "https://example.com",
  "FinalUrl": "https://example.com/",
  "Success": true,
  "Title": "Example Domain",
  "Text": "...readable extracted text...",
  "Excerpt": "...first paragraph...",
  "Domain": "example.com",
  "SiteName": "Example",
  "PublishedAt": null,
  "WordCount": 142,
  "Error": null
}
```

`FinalUrl` reflects redirects. `Success` is `false` and `Error` is populated when the fetch fails.

## MCP — `WebBatchFetch`

Fetch many URLs in parallel. Returns an array of `FetchResponse`, one per URL, in input order.

| Parameter        | Type        | Default   | Notes                                  |
|------------------|-------------|-----------|----------------------------------------|
| `urls`           | string[]    | —         | URLs to fetch.                         |
| `profile`        | string?     | `default` | Named profile.                         |
| `timeoutSeconds` | int         | `30`      | Per-URL timeout.                       |

A failed URL does not abort the batch. Each result has its own `Success` and `Error` fields.

## MCP — `WebSearchThenFetch`

Run a search, then fetch a chosen subset of result indexes.

| Parameter               | Type      | Default   | Notes                                                        |
|-------------------------|-----------|-----------|--------------------------------------------------------------|
| `query`                 | string    | —         | Search query.                                                |
| `selectedResultIndexes` | int[]     | —         | Zero-based indexes into the search response's `Results`.     |
| `provider`              | string?   | profile   | Provider override.                                           |
| `profile`               | string?   | `default` | Named profile.                                               |
| `maxResults`            | int       | `8`       | Cap on the search step.                                      |
| `page`                  | int       | `1`       | Result page.                                                 |
| `timeoutSeconds`        | int       | `30`      | Per-URL fetch timeout.                                       |

Indexes out of range are silently dropped. URLs are deduplicated before fetching. Returns the same shape as `WebBatchFetch`.

Use this when you want surgical control over which results to read. Compared to `WebResearch`:

- `WebResearch` picks the top N for you and returns search + sources + citations.
- `WebSearchThenFetch` returns only the fetched pages, and you choose the indexes yourself.

## CLI — `recall fetch`

```powershell
recall fetch <url> `
  [--profile <name>] `
  [--timeout <seconds>] `
  [--output <json|text|markdown|dump>]
```

There is no built-in CLI for batch fetching or search-then-fetch yet — for those, use the MCP server (`recall mcp`) or call `recall search` and `recall fetch` from a script.

## Common patterns

**1. Read a single URL (markdown out, good for prompts):**

```powershell
recall fetch "https://example.com" --output markdown
```

**2. Fetch the top 3 results of a search (MCP):**

```json
{
  "tool": "WebSearchThenFetch",
  "input": {
    "query": "site:github.com agent skills spec",
    "selectedResultIndexes": [0, 1, 2],
    "maxResults": 8
  }
}
```

**3. Batch-fetch a known list (MCP):**

```json
{
  "tool": "WebBatchFetch",
  "input": {
    "urls": [
      "https://agentskills.io/specification",
      "https://opencode.ai/docs/skills/",
      "https://modelcontextprotocol.io/introduction"
    ],
    "timeoutSeconds": 45
  }
}
```

**4. Use a profile with cookies (e.g. for sites that need consent):**

```powershell
recall fetch "https://www.bing.com/search?q=site:github.com+mcp" `
  --profile interactive --output json
```

See `references/troubleshooting.md` for how to prepare an interactive profile.

## Tuning

- **Slow page or JS-heavy SPA** → raise `timeoutSeconds` (e.g. `60`).
- **Many URLs** → use `WebBatchFetch` instead of N separate `WebFetch` calls; the tool fetches in parallel internally.
- **Need extracted text + provenance for a synthesis** → prefer `WebResearch` so you get `Citations` for free.

## When NOT to use fetch

- No URL yet, only a topic → search first. See `references/search.md`.
- Multi-source synthesis with citations → use `WebResearch`. See `references/research.md`.
- Site shows consent/captcha → fetch alone will return text but may be a consent page. Run `recall profile auth interactive --provider <name>` first. See `references/troubleshooting.md`.
