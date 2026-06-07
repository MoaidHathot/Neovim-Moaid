# MCP tool reference

Load this when you need the complete MCP tool surface and parameter shapes. For task-oriented guidance prefer `references/search.md`, `references/research.md`, or `references/fetch.md`.

The server is started with:

```powershell
recall mcp
```

It communicates over stdio. Tools are registered from `RecallMcpTools` in the `Zakira.Recall.Tool` package.

---

## `WebSearch`

Search the web with the selected provider or the configured default.

**Input**

| Name                | Type        | Required | Default   | Description                                                                |
|---------------------|-------------|----------|-----------|----------------------------------------------------------------------------|
| `query`             | string      | yes      | —         | Raw query (`site:`, `filetype:`, `"exact"` etc. pass through).             |
| `provider`          | string      | no       | profile   | Provider name or alias (`duckduckgo`, `ddg`, `duckduckgo-browser`, `bing`).|
| `profile`           | string      | no       | `default` | Named profile from `profiles.json`.                                        |
| `maxResults`        | int         | no       | `10`      | Cap on returned results.                                                    |
| `page`              | int         | no       | `1`       | 1-indexed page number.                                                      |
| `timeRange`         | string      | no       | —         | `day`, `week`, `month`, `year`.                                            |
| `safeSearch`        | bool        | no       | —         | Override.                                                                   |
| `enableFallback`    | bool        | no       | profile   | Whether to fall back if the primary fails.                                  |
| `fallbackProviders` | string[]    | no       | profile   | Ordered fallback providers.                                                 |

**Output**: `SearchResponse` (see `references/search.md` for full shape).

---

## `WebFetch`

Fetch readable content from a single URL.

**Input**

| Name             | Type   | Required | Default   | Description           |
|------------------|--------|----------|-----------|-----------------------|
| `url`            | string | yes      | —         | URL to fetch.         |
| `profile`        | string | no       | `default` | Named profile.        |
| `timeoutSeconds` | int    | no       | `30`      | Per-fetch timeout.    |

**Output**: `FetchResponse` (see `references/fetch.md`).

---

## `WebResearch`

Search, then fetch top pages, return search results + sources + structured citations.

**Input**

| Name                     | Type     | Required | Default   | Description                                                                  |
|--------------------------|----------|----------|-----------|------------------------------------------------------------------------------|
| `query`                  | string   | yes      | —         | Research query.                                                              |
| `provider`               | string   | no       | profile   | Provider override.                                                           |
| `profile`                | string   | no       | `default` | Named profile.                                                               |
| `maxResults`             | int      | no       | `8`       | Cap on the search step.                                                      |
| `topPagesToRead`         | int      | no       | `3`       | Number of result pages to actually fetch.                                    |
| `page`                   | int      | no       | `1`       | Result page number.                                                          |
| `timeRange`              | string   | no       | —         | `day`, `week`, `month`, `year`.                                              |
| `safeSearch`             | bool     | no       | —         | Override.                                                                    |
| `enableFallback`         | bool     | no       | profile   | Whether to fall back if the primary search fails.                            |
| `fallbackProviders`      | string[] | no       | profile   | Ordered fallback providers.                                                  |
| `maxConcurrentFetches`   | int      | no       | profile   | Cap on parallel page fetches.                                                |
| `enforceDomainDiversity` | bool     | no       | `true`    | Prefer unique domains when selecting top pages.                              |

**Output**: `ResearchResponse` (see `references/research.md`).

---

## `WebBatchFetch`

Fetch multiple URLs in parallel.

**Input**

| Name             | Type     | Required | Default   | Description              |
|------------------|----------|----------|-----------|--------------------------|
| `urls`           | string[] | yes      | —         | URLs to fetch.           |
| `profile`        | string   | no       | `default` | Named profile.           |
| `timeoutSeconds` | int      | no       | `30`      | Per-URL timeout.         |

**Output**: `FetchResponse[]`, one per URL, in input order. Each has its own `Success` and `Error` fields.

---

## `WebSearchThenFetch`

Run a search, then fetch the chosen result indexes in one call.

**Input**

| Name                    | Type   | Required | Default   | Description                                                |
|-------------------------|--------|----------|-----------|------------------------------------------------------------|
| `query`                 | string | yes      | —         | Search query.                                              |
| `selectedResultIndexes` | int[]  | yes      | —         | Zero-based indexes into the search response's `Results`.   |
| `provider`              | string | no       | profile   | Provider override.                                         |
| `profile`               | string | no       | `default` | Named profile.                                             |
| `maxResults`            | int    | no       | `8`       | Cap on the search step.                                    |
| `page`                  | int    | no       | `1`       | Result page.                                               |
| `timeoutSeconds`        | int    | no       | `30`      | Per-URL fetch timeout.                                     |

**Output**: `FetchResponse[]`. Out-of-range indexes are dropped; URLs are deduplicated.

---

## `WebListProviders`

List registered providers with capabilities and current health.

**Input**

| Name      | Type   | Required | Default   | Description    |
|-----------|--------|----------|-----------|----------------|
| `profile` | string | no       | `default` | Named profile. |

**Output**: `SearchProviderDescriptor[]`.

```json
[
  {
    "Name": "duckduckgo",
    "Aliases": ["ddg"],
    "SetupUrl": null,
    "Capabilities": {
      "SupportsPagination": true,
      "SupportsTimeRange": true,
      "SupportsSafeSearch": true,
      "RequiresBrowser": false,
      "SupportsInteractiveSetup": false
    },
    "Health": {
      "Provider": "duckduckgo",
      "IsHealthy": true,
      "ConsecutiveFailures": 0,
      "LastSuccessUtc": "2026-06-06T08:14:22Z",
      "LastFailureUtc": null
    }
  }
]
```

---

## `WebShowConfig`

Show the resolved configuration (`RecallConfig`) used by Zakira.Recall.

**Input**: none.

**Output**: `RecallConfig`. Use this when you want to know the current defaults, profile root, fallback list, etc.

---

## `WebShowProfile`

Show the resolved profile after applying config defaults and provider overrides.

**Input**

| Name       | Type   | Required | Default   | Description                                                                  |
|------------|--------|----------|-----------|------------------------------------------------------------------------------|
| `profile`  | string | no       | `default` | Named profile to resolve.                                                    |
| `provider` | string | no       | —         | Provider override to apply during resolution.                                |

**Output**: `ProfileDescriptor`.

```json
{
  "Name": "default",
  "UserDataDir": "C:/.../profiles/default",
  "Channel": "msedge",
  "Headless": true,
  "DefaultProvider": "duckduckgo",
  "Locale": "en-US",
  "TimeoutSeconds": 30,
  "FallbackProviders": ["duckduckgo-browser", "bing"],
  "EnableProviderFallback": true,
  "ProviderHealthCooldownSeconds": 300,
  "MaxConcurrentFetches": 3,
  "LogLevel": null
}
```

---

## `WebGetProviderHealth`

Show the current health snapshot for one provider.

**Input**

| Name       | Type   | Required | Default   | Description                          |
|------------|--------|----------|-----------|--------------------------------------|
| `provider` | string | yes      | —         | Provider name or alias.              |
| `profile`  | string | no       | `default` | Named profile (used for cooldown).   |

**Output**: `ProviderHealthSnapshot`.

```json
{
  "Provider": "bing",
  "IsHealthy": true,
  "ConsecutiveFailures": 0,
  "LastSuccessUtc": "2026-06-06T08:14:22Z",
  "LastFailureUtc": null
}
```

---

## Tool-selection cheat sheet

| Situation                                                    | Tool                  |
|--------------------------------------------------------------|-----------------------|
| One query, return result list                                | `WebSearch`           |
| One known URL                                                | `WebFetch`            |
| N known URLs                                                 | `WebBatchFetch`       |
| Search and then fetch a chosen subset of result indexes      | `WebSearchThenFetch`  |
| Search + auto-fetch top N + citations + extracted content    | `WebResearch`         |
| What providers exist and are they healthy?                   | `WebListProviders`    |
| Health of one provider                                       | `WebGetProviderHealth`|
| What config is the server actually using?                    | `WebShowConfig`       |
| What does my profile resolve to right now?                   | `WebShowProfile`      |
