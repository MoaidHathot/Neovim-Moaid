# MCP tool reference

Load this when you need the complete MCP tool surface and parameter shapes. For task-oriented guidance prefer `references/search.md`, `references/research.md`, or `references/fetch.md`.

The server is started with:

```powershell
recall mcp
```

It communicates over stdio. Tools are registered from `RecallMcpTools` in the `Zakira.Recall.Tool` package; tool names are snake_case
(`web_search`, not `WebSearch`). Results are JSON objects with camelCase field names; fields whose value is null are omitted.
The CLI's `--output json` prints the same objects with PascalCase names.

---

## `web_search`

Search the web with the selected provider or the configured default.

**Input**

| Name                | Type        | Required | Default   | Description                                                                |
|---------------------|-------------|----------|-----------|----------------------------------------------------------------------------|
| `query`             | string      | yes      | -         | Raw query (`site:`, `filetype:`, `"exact"` etc. pass through).             |
| `provider`          | string      | no       | profile   | Provider name or alias (`duckduckgo`, `ddg`, `duckduckgo-browser`, `bing`).|
| `profile`           | string      | no       | `default` | Named profile from `profiles.json`.                                        |
| `maxResults`        | int         | no       | `10`      | Cap on returned results.                                                    |
| `page`              | int         | no       | `1`       | 1-indexed page number.                                                      |
| `timeRange`         | string      | no       | -         | `day`, `week`, `month`, `year`.                                            |
| `safeSearch`        | bool        | no       | -         | Override.                                                                   |
| `enableFallback`    | bool        | no       | profile   | Whether to fall back if the primary fails.                                  |
| `fallbackProviders` | string[]    | no       | profile   | Ordered fallback providers.                                                 |

**Output**: `SearchResponse` (see `references/search.md` for the full shape).

---

## `web_fetch`

Fetch readable content from a single URL.

**Input**

| Name             | Type   | Required | Default   | Description           |
|------------------|--------|----------|-----------|-----------------------|
| `url`            | string | yes      | -         | URL to fetch.         |
| `profile`        | string | no       | `default` | Named profile.        |
| `timeoutSeconds` | int    | no       | `30`      | Navigation timeout.   |

**Output**: `FetchResponse` (see `references/fetch.md`):

| Field             | Type            | Notes                                                                       |
|-------------------|-----------------|-----------------------------------------------------------------------------|
| `url`, `finalUrl` | string          | Requested and final (post-redirect) URL.                                    |
| `success`         | bool            | `false` when `error` is set.                                                |
| `statusCode`      | int?            | HTTP status of the main document.                                           |
| `title`           | string?         | `<title>`.                                                                  |
| `text`            | string?         | Readable content with block structure.                                      |
| `excerpt`         | string?         | Single line, first 400 characters.                                          |
| `domain`, `siteName`, `publishedAt` | string? / string? / ISO 8601? | Page metadata (meta tags, then JSON-LD).             |
| `wordCount`       | int             | Words in `text`.                                                            |
| `contentSelector` | string?         | Element the text was taken from (diagnostic).                               |
| `mainImage`       | string?         | Representative image, absolute URL.                                         |
| `structuredData`  | object?         | `{ types: string[], mainEntityType: string?, mainEntity: object? }` from JSON-LD. |
| `error`           | `OperationError`? | `{ code, message, provider?, target, transient }`.                        |

---

## `web_research`

Search, then fetch top pages, return search results + sources + structured citations.

**Input**

| Name                     | Type     | Required | Default   | Description                                                                  |
|--------------------------|----------|----------|-----------|------------------------------------------------------------------------------|
| `query`                  | string   | yes      | -         | Research query.                                                              |
| `provider`               | string   | no       | profile   | Provider override.                                                           |
| `profile`                | string   | no       | `default` | Named profile.                                                               |
| `maxResults`             | int      | no       | `8`       | Cap on the search step.                                                      |
| `topPagesToRead`         | int      | no       | `3`       | Number of result pages to actually fetch.                                    |
| `page`                   | int      | no       | `1`       | Result page number.                                                          |
| `timeRange`              | string   | no       | -         | `day`, `week`, `month`, `year`.                                              |
| `safeSearch`             | bool     | no       | -         | Override.                                                                    |
| `enableFallback`         | bool     | no       | profile   | Whether to fall back if the primary search fails.                            |
| `fallbackProviders`      | string[] | no       | profile   | Ordered fallback providers.                                                  |
| `maxConcurrentFetches`   | int      | no       | profile   | Cap on parallel page fetches (1-16).                                         |
| `enforceDomainDiversity` | bool     | no       | `true`    | Prefer unique domains when selecting top pages.                              |

**Output**: `ResearchResponse` (see `references/research.md`). Each source's `fetch` is a full `FetchResponse`, including `structuredData`.

---

## `web_batch_fetch`

Fetch multiple URLs in one call with bounded concurrency.

**Input**

| Name                   | Type     | Required | Default   | Description                                                            |
|------------------------|----------|----------|-----------|------------------------------------------------------------------------|
| `urls`                 | string[] | yes      | -         | URLs to fetch.                                                         |
| `profile`              | string   | no       | `default` | Named profile.                                                         |
| `timeoutSeconds`       | int      | no       | `30`      | Per-URL timeout.                                                       |
| `maxConcurrentFetches` | int      | no       | profile   | Pages fetched at the same time (1-16); the profile default is 3.       |

**Output**: `FetchResponse[]`, one per URL, in input order. Each has its own `success` and `error` fields.

---

## `web_search_then_fetch`

Run a search, then fetch the chosen result indexes in one call.

**Input**

| Name                    | Type   | Required | Default   | Description                                                |
|-------------------------|--------|----------|-----------|------------------------------------------------------------|
| `query`                 | string | yes      | -         | Search query.                                              |
| `selectedResultIndexes` | int[]  | yes      | -         | Zero-based indexes into the search response's `results`.   |
| `provider`              | string | no       | profile   | Provider override.                                         |
| `profile`               | string | no       | `default` | Named profile.                                             |
| `maxResults`            | int    | no       | `8`       | Cap on the search step.                                    |
| `page`                  | int    | no       | `1`       | Result page.                                               |
| `timeoutSeconds`        | int    | no       | `30`      | Per-URL fetch timeout.                                     |

**Output**: `FetchResponse[]`. Out-of-range indexes are dropped; URLs are deduplicated. Fetch concurrency follows the profile's `maxConcurrentFetches`.

---

## `web_list_providers`

List registered providers with capabilities and current health.

**Input**

| Name      | Type   | Required | Default   | Description    |
|-----------|--------|----------|-----------|----------------|
| `profile` | string | no       | `default` | Named profile. |

**Output**: `SearchProviderDescriptor[]`.

```json
[
  {
    "name": "duckduckgo",
    "aliases": ["ddg"],
    "capabilities": {
      "supportsPagination": true,
      "supportsTimeRange": true,
      "supportsSafeSearch": true,
      "requiresBrowser": false,
      "supportsInteractiveSetup": false
    },
    "health": {
      "provider": "duckduckgo",
      "isHealthy": true,
      "consecutiveFailures": 0,
      "lastSuccessUtc": "2026-06-06T08:14:22Z"
    }
  }
]
```

---

## `web_show_config`

Show the resolved configuration (`RecallConfig`) used by Zakira.Recall.

**Input**: none.

**Output**: `RecallConfig`. Use this when you want to know the current defaults, profile root, fallback list, etc.

---

## `web_show_profile`

Show the resolved profile after applying config defaults and provider overrides.

**Input**

| Name       | Type   | Required | Default   | Description                                                                  |
|------------|--------|----------|-----------|------------------------------------------------------------------------------|
| `profile`  | string | no       | `default` | Named profile to resolve.                                                    |
| `provider` | string | no       | -         | Provider override to apply during resolution.                                |

**Output**: `ProfileDescriptor`.

```json
{
  "name": "default",
  "userDataDir": "C:/.../profiles/default",
  "channel": "msedge",
  "headless": true,
  "defaultProvider": "duckduckgo",
  "locale": "en-US",
  "timeoutSeconds": 30,
  "fallbackProviders": ["duckduckgo-browser", "bing"],
  "enableProviderFallback": true,
  "providerHealthCooldownSeconds": 300,
  "maxConcurrentFetches": 3
}
```

---

## `web_get_provider_health`

Show the current health snapshot for one provider.

**Input**

| Name       | Type   | Required | Default   | Description                          |
|------------|--------|----------|-----------|--------------------------------------|
| `provider` | string | yes      | -         | Provider name or alias.              |
| `profile`  | string | no       | `default` | Named profile (used for cooldown).   |

**Output**: `ProviderHealthSnapshot`.

```json
{
  "provider": "bing",
  "isHealthy": true,
  "consecutiveFailures": 0,
  "lastSuccessUtc": "2026-06-06T08:14:22Z"
}
```

---

## `OperationError`

Returned as `error` on fetch responses, `error` on search responses, and in the `errors` array of research responses.

| Field       | Notes                                                                                                   |
|-------------|---------------------------------------------------------------------------------------------------------|
| `code`      | `fetch_http_error`, `fetch_bot_challenge`, `fetch_login_required`, `fetch_weak_content`, `fetch_failed`, `search_failed`. |
| `message`   | Human-readable description (for HTTP errors includes the status, e.g. `Server returned HTTP 404 (NotFound).`). |
| `provider`  | Provider that produced the error, if applicable (search errors).                                        |
| `target`    | The URL or query the error pertains to.                                                                 |
| `transient` | `true` if a retry might succeed: timeouts, 408/425/429/5xx, challenge pages, browser or driver restarts.|

---

## Tool-selection cheat sheet

| Situation                                                    | Tool                        |
|--------------------------------------------------------------|-----------------------------|
| One query, return result list                                | `web_search`                |
| One known URL                                                | `web_fetch`                 |
| N known URLs                                                 | `web_batch_fetch`           |
| Search and then fetch a chosen subset of result indexes      | `web_search_then_fetch`     |
| Search + auto-fetch top N + citations + extracted content    | `web_research`              |
| What providers exist and are they healthy?                   | `web_list_providers`        |
| Health of one provider                                       | `web_get_provider_health`   |
| What config is the server actually using?                    | `web_show_config`           |
| What does my profile resolve to right now?                   | `web_show_profile`          |
