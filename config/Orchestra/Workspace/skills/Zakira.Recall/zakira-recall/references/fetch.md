# Fetch reference

Use this when the user has one or more known URLs and wants the readable content (text, title, metadata, structured data) extracted. If the user only has a topic or query, use `references/search.md` or `references/research.md` first.

There are three related tools. Pick the one that matches the situation:

| Tool                     | Use when                                                                                          |
|--------------------------|---------------------------------------------------------------------------------------------------|
| `web_fetch`              | You have exactly one URL.                                                                         |
| `web_batch_fetch`        | You already have N URLs and want all of them in one call (fetched with bounded concurrency).      |
| `web_search_then_fetch`  | You want to search first, then fetch a specific subset of result indexes in the same call.        |
| `web_research`           | You want the full search + pick top-N + fetch + citations pipeline. See `references/research.md`. |

## How a page is fetched

The URL is opened in a real headless browser (Microsoft Edge by default) using the profile's cookies, the rendered DOM is
serialized after scripts ran, and the readable content is extracted in-process:

- Every plausible container (`article`, `main`, `[role=main]`, SPA roots, common CMS wrappers) is scored by its
  boilerplate-free word count and link density; the body is used when the best container holds only a fragment of the
  page (a related-post card, a comment). `contentSelector` tells you which element won.
- Navigation, headers, footers, hidden elements, comment areas, tables of contents, breadcrumbs and share widgets are
  removed. Text keeps its block structure: paragraphs, headings, `-` / `1.` bullets, `|`-separated table cells.
- schema.org JSON-LD is parsed into `structuredData`; `publishedAt`, `siteName` and `mainImage` fall back to it when
  meta tags are missing.
- The main document's HTTP status is checked and challenge/block pages are recognized (see error codes below).

## MCP - `web_fetch`

Fetch one URL and extract readable content.

| Parameter        | Type     | Default   | Notes                                  |
|------------------|----------|-----------|----------------------------------------|
| `url`            | string   | -         | The URL to fetch.                      |
| `profile`        | string?  | `default` | Named profile from `profiles.json`.    |
| `timeoutSeconds` | int      | `30`      | Navigation timeout budget for the page.|

Returns a `FetchResponse` (MCP output is camelCase; fields that are null are omitted):

```json
{
  "url": "https://www.kingarthurbaking.com/recipes/everyday-french-loaf-recipe",
  "finalUrl": "https://www.kingarthurbaking.com/recipes/everyday-french-loaf-recipe",
  "success": true,
  "statusCode": 200,
  "title": "Everyday French Loaf Recipe | King Arthur Baking",
  "text": "Everyday French Loaf\n\nMade with only four ingredients...\n\nIngredients\n\n- 1 3/4 cups plus 1 1/2 tablespoons (222g) King Arthur Unbleached All-Purpose Flour\n- ...",
  "excerpt": "Everyday French Loaf Made with only four ingredients, this classic French bread has a thin, crisp crust ...",
  "domain": "www.kingarthurbaking.com",
  "siteName": "King Arthur Baking",
  "publishedAt": "2024-07-08T14:48:00+00:00",
  "wordCount": 1448,
  "contentSelector": "main.main",
  "mainImage": "https://www.kingarthurbaking.com/sites/default/files/2024-07/Everyday-French-Loaf_1366.jpg",
  "structuredData": {
    "types": ["Recipe"],
    "mainEntityType": "Recipe",
    "mainEntity": {
      "@type": "Recipe",
      "name": "Everyday French Loaf",
      "recipeYield": ["28 slices", "two loaves"],
      "prepTime": "PT20M",
      "totalTime": "PT20H0M",
      "recipeIngredient": ["1 3/4 cups plus 1 1/2 tablespoons (222g) King Arthur Unbleached All-Purpose Flour", "..."],
      "recipeInstructions": [{ "@type": "HowToStep", "text": "..." }]
    }
  }
}
```

| Field             | Notes                                                                                                          |
|-------------------|----------------------------------------------------------------------------------------------------------------|
| `finalUrl`        | Reflects redirects.                                                                                            |
| `success`         | `false` when the page is not usable; `error` explains why and `text` still holds what the server sent.         |
| `statusCode`      | HTTP status of the main document (absent when the navigation produced no response).                            |
| `text`            | Readable content: headline, description, then the main content with line breaks between blocks.                |
| `excerpt`         | Single line, first 400 characters. Good for listings and citations.                                            |
| `wordCount`       | Words in `text`. A few dozen words on a page that should be an article means the content was not reached.      |
| `contentSelector` | Element the text came from, e.g. `main.main`, `article#post-7`, `body`. Diagnostic.                            |
| `mainImage`       | `og:image`, `twitter:image` or the main entity's image, as an absolute URL.                                    |
| `structuredData`  | Root JSON-LD `types` on the page and the most relevant content entity (see below). Absent when none declared.  |
| `publishedAt`     | From `article:published_time`, JSON-LD `datePublished` or a `<time>` element. ISO 8601.                        |
| `error`           | `{ code, message, target, transient }` when `success` is `false`.                                              |

### `structuredData`

`mainEntity` is the page's content entity as the site declared it, chosen by priority: `Recipe`, `HowTo`, `NewsArticle`/`Article`/`BlogPosting`,
`Product`, `Event`, `JobPosting`, `FAQPage`, `Course`, `VideoObject`, ... Site chrome (`WebSite`, `WebPage`, `BreadcrumbList`) is never the main
entity; `types` lists everything that was declared. Bulky members that carry no content (`review`, `comment`, `potentialAction`, ...) are removed,
and an entity larger than 32 KB is omitted while `mainEntityType` is kept.

Prefer `structuredData.mainEntity` over parsing `text` when it is present:

- Recipes: `recipeIngredient` (array of strings), `recipeInstructions` (array of `HowToStep` or strings), `prepTime`/`cookTime`/`totalTime`
  (ISO 8601 durations such as `PT20M`), `recipeYield`, `nutrition`, `image`, `video`.
- Articles: `headline`, `datePublished`, `dateModified`, `author`, `publisher`, `articleBody` (when the site includes it).
- Products: `name`, `offers`, `brand`, `aggregateRating`.

Not every site declares structured data (for example chainbaker.com declares only an `Article`); `text` is complete on its own for those.

## MCP - `web_batch_fetch`

Fetch many URLs in one call. Returns an array of `FetchResponse`, one per URL, in input order.

| Parameter              | Type      | Default   | Notes                                                                            |
|------------------------|-----------|-----------|----------------------------------------------------------------------------------|
| `urls`                 | string[]  | -         | URLs to fetch.                                                                   |
| `profile`              | string?   | `default` | Named profile.                                                                   |
| `timeoutSeconds`       | int       | `30`      | Per-URL timeout.                                                                 |
| `maxConcurrentFetches` | int?      | profile   | Pages fetched at the same time (1-16). Defaults to the profile's `maxConcurrentFetches` (3). |

Each URL is a separate browser launch, so concurrency is bounded rather than unlimited. A failed URL does not abort the batch: each result has its
own `success` and `error`.

## MCP - `web_search_then_fetch`

Run a search, then fetch a chosen subset of result indexes.

| Parameter               | Type      | Default   | Notes                                                        |
|-------------------------|-----------|-----------|--------------------------------------------------------------|
| `query`                 | string    | -         | Search query.                                                |
| `selectedResultIndexes` | int[]     | -         | Zero-based indexes into the search response's `results`.     |
| `provider`              | string?   | profile   | Provider override.                                           |
| `profile`               | string?   | `default` | Named profile.                                               |
| `maxResults`            | int       | `8`       | Cap on the search step.                                      |
| `page`                  | int       | `1`       | Result page.                                                 |
| `timeoutSeconds`        | int       | `30`      | Per-URL fetch timeout.                                       |

Indexes out of range are silently dropped. URLs are deduplicated before fetching. Returns the same shape as `web_batch_fetch`.

Compared to `web_research`: `web_research` picks the top N for you and returns search + sources + citations; `web_search_then_fetch` returns only
the fetched pages, and you choose the indexes yourself.

## CLI - `recall fetch`

```powershell
recall fetch <url> `
  [--profile <name>] `
  [--timeout <seconds>] `
  [--output <json|text|markdown|dump>]
```

- `--output json` prints the same `FetchResponse` with PascalCase field names (`Success`, `WordCount`, `StructuredData`).
- `--output markdown` prints `# <title>`, the readable text and, when the page declares one, a `## Structured data (schema.org <type>)` section
  with the main entity as JSON. Best for feeding a page into a prompt or a note.
- `--output text` prints title, final URL and the excerpt only.

There is no CLI for batch fetching or search-then-fetch; use the MCP server (`recall mcp`) or call `recall search` and `recall fetch` from a script.

## Error codes

| `error.code`           | Meaning                                                                                  | `transient`                      |
|------------------------|------------------------------------------------------------------------------------------|----------------------------------|
| `fetch_http_error`     | The server answered 4xx/5xx. `statusCode` has the value; `text` holds the error page.    | `true` for 408/425/429 and 5xx   |
| `fetch_bot_challenge`  | A verification or block page (Cloudflare "Just a moment...", "Sorry, you have been blocked", Akamai, PerimeterX, DuckDuckGo's bot page). | `true` |
| `fetch_login_required` | A login wall (LinkedIn, Facebook, "sign in to continue").                                 | `false`                          |
| `fetch_weak_content`   | Fewer than 15 readable words.                                                            | `false`                          |
| `fetch_failed`         | The browser could not load the page: DNS/connection error, navigation timeout, closed page, driver restart. | `true` for timeouts and browser/driver errors |

`transient: true` means one retry is reasonable. `false` means the same request will fail the same way; change the URL, profile or approach.
See `references/troubleshooting.md` for what to do per code.

## Common patterns

**1. Read a single URL (markdown out, good for prompts):**

```powershell
recall fetch "https://example.com" --output markdown
```

**2. Get a recipe as data (MCP):**

```json
{ "tool": "web_fetch", "input": { "url": "https://www.kingarthurbaking.com/recipes/everyday-french-loaf-recipe" } }
```

Then read `structuredData.mainEntity.recipeIngredient` and `recipeInstructions[*].text`; use `text` for the author's notes and `mainImage` for a picture.

**3. Fetch the top 3 results of a search (MCP):**

```json
{
  "tool": "web_search_then_fetch",
  "input": {
    "query": "site:github.com agent skills spec",
    "selectedResultIndexes": [0, 1, 2],
    "maxResults": 8
  }
}
```

**4. Batch-fetch a known list (MCP):**

```json
{
  "tool": "web_batch_fetch",
  "input": {
    "urls": [
      "https://agentskills.io/specification",
      "https://opencode.ai/docs/skills/",
      "https://modelcontextprotocol.io/introduction"
    ],
    "timeoutSeconds": 45,
    "maxConcurrentFetches": 3
  }
}
```

**5. Use a profile with cookies (e.g. for sites that need consent):**

```powershell
recall fetch "https://www.bing.com/search?q=site:github.com+mcp" `
  --profile interactive --output json
```

See `references/troubleshooting.md` for how to prepare an interactive profile.

## Tuning

- **Slow page or JS-heavy SPA** → raise `timeoutSeconds` (e.g. `60`).
- **Many URLs** → use `web_batch_fetch` instead of N separate `web_fetch` calls; raise `maxConcurrentFetches` only if the machine has the memory for that many browser instances.
- **Need extracted text + provenance for a synthesis** → prefer `web_research` so you get `citations` for free.
- **`wordCount` is tiny but `success` is true** → check `contentSelector` and `statusCode`; if the page is a consent page, fetch through a profile that accepted it.

## When NOT to use fetch

- No URL yet, only a topic → search first. See `references/search.md`.
- Multi-source synthesis with citations → use `web_research`. See `references/research.md`.
- The result is `fetch_bot_challenge` or `fetch_login_required` → fetching again will not help; see `references/troubleshooting.md`.
