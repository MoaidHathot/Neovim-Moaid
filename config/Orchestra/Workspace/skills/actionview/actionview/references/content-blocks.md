# Content blocks

The `entry.content` array is rendered top-to-bottom by the dashboard. Each item is an object with a `type` discriminator. Pick the block type that matches the data; don't shoehorn structured data into a `markdown` block.

See the table at the bottom of this document for the full type list.

## `markdown`

Prose, summaries, AI analysis. GitHub-flavored markdown, plus math (`$inline$` and `$$block$$` via KaTeX) and task lists (`- [ ]`).

```json
{
  "type": "markdown",
  "body": "## Summary\n\nThis PR adds a Redis-backed cache, reducing p95 from 120ms to 15ms.\n\n- [x] Cache key strategy reviewed\n- [ ] Load test in staging"
}
```

Embedded `![alt](url)` images render as click-to-enlarge thumbnails. JSON requires `\n` for line breaks.

## `code`

Code snippets with copy button, line-number / wrap toggles, and per-line annotations.

```json
{
  "type": "code",
  "language": "csharp",
  "filename": "src/Services/UserPreferenceCacheService.cs",
  "highlight": [5, 17],
  "showLineNumbers": true,
  "wordWrap": true,
  "body": "public class UserPreferenceCacheService\n{\n    private static readonly TimeSpan CacheTTL = TimeSpan.FromMinutes(5);\n}",
  "annotations": [
    { "line": 3, "level": "warning", "body": "Hard-coded TTL. Move to appsettings.", "author": "ai-reviewer" }
  ]
}
```

`annotations[].body` is markdown. Use this instead of a separate `alert` block after the code.

## `diff`

Real diff view. **Use this instead of `code` with `language: "diff"`** — it gives you add/remove gutters, per-hunk collapse, and a unified/split toggle.

```json
{
  "type": "diff",
  "oldFilename": "src/Cache.cs",
  "newFilename": "src/Cache.cs",
  "mode": "unified",
  "body": "@@ -10,3 +10,5 @@\n private TimeSpan CacheTTL = TimeSpan.FromMinutes(5);\n+\n+public void Invalidate(string key) => _cache.Remove(key);\n"
}
```

`mode` is `"unified"` (default) or `"split"`. `body` is a unified diff string; the parser accepts both a full patch and a bare hunk body.

## `json`

Foldable, syntax-colored JSON tree with copy.

```json
{
  "type": "json",
  "label": "Webhook payload",
  "body": { "user_id": "u_42", "action": "login_failed", "attempts": 5 }
}
```

## `table`

Tabular data with optional `sortable: true` and `filterable: true`. Cells may be strings or rich-cell objects (see "Rich cells" below).

```json
{
  "type": "table",
  "label": "Test Results",
  "columns": ["Test", "Status", "Duration"],
  "sortable": true,
  "filterable": true,
  "rows": [
    ["AuthHandlerTests.LoginSucceeds", { "type": "status", "level": "success", "label": "Passed" }, "12ms"],
    ["CacheTests.SetAndGet",           { "type": "status", "level": "error",   "label": "Failed" }, "8ms"]
  ]
}
```

## `keyValue`

Header metadata. Values use the rich-cell shape — a Commit SHA can be a `copy` cell, a file path a `link`, status a `status` pill.

```json
{
  "type": "keyValue",
  "label": "Pull Request",
  "pairs": {
    "Repository": { "type": "link", "url": "https://github.com/acme/backend", "label": "acme/backend" },
    "Branch": "feature/cache",
    "Commit": { "type": "copy", "value": "a3f8c2d9e1f0", "display": "a3f8c2d" },
    "Status": { "type": "status", "level": "success", "label": "Approved" }
  }
}
```

## `link`

One link via `url` + optional `body` description, **or** many via `links[]`.

```json
{
  "type": "link",
  "label": "References",
  "links": [
    { "url": "https://github.com/acme/backend/pull/482", "label": "PR #482", "icon": "pr", "body": "Add cache layer" },
    { "url": "https://ci.example.com/jobs/1847", "label": "CI Job #1847", "icon": "dashboard" }
  ]
}
```

Built-in icon names (Lucide): `pr`, `ticket`, `bug`, `runbook`, `docs`, `dashboard`, `file`, `web`. Unknown icon names fall back to a generic link icon; GitHub URLs auto-pick a PR icon.

## `alert`

Colored callout. Markdown body, optional `dismissible` (persists in localStorage), can carry its own `actions[]`.

```json
{
  "type": "alert",
  "level": "warning",
  "label": "Heads up",
  "body": "Hard-coded TTL on line 5. See the [runbook](https://wiki.example.com/cache-ttl) for the standard value.",
  "dismissible": true
}
```

## `image`

Single image with click-to-enlarge lightbox, optional annotations, optional `timestampUrl` (overrides the lightbox - useful for video-frame images that should jump back to the source).

```json
{
  "type": "image",
  "url": "https://example.com/frames/00-45.jpg",
  "alt": "Speaker introducing the chip specs",
  "caption": "00:45 - intro",
  "maxWidth": 400,
  "imageAnnotations": [
    { "shape": "arrow", "x": 60, "y": 30, "label": "look here", "level": "warning" },
    { "shape": "box",   "x": 10, "y": 50, "width": 30, "height": 25, "label": "broken", "level": "error" }
  ]
}
```

## `gallery`

Many images sharing one lightbox carousel (prev/next + zoom + keyboard arrows). Replaces stacks of separate markdown images.

```json
{
  "type": "gallery",
  "label": "Frames",
  "images": [
    { "url": "...frame-001.jpg", "alt": "intro",   "caption": "00:10", "timestampUrl": "https://youtu.be/...?t=10" },
    { "url": "...frame-002.jpg", "alt": "spec",    "caption": "01:15", "timestampUrl": "https://youtu.be/...?t=75" },
    { "url": "...frame-003.jpg", "alt": "lineup",  "caption": "02:45", "timestampUrl": "https://youtu.be/...?t=165" }
  ]
}
```

If `timestampUrl` is set, clicking the thumbnail opens that URL in a new tab instead of the lightbox.

## `video`

YouTube / Vimeo / direct file. Optional `startTime` / `endTime` clipping and `chapters[]`.

```json
{
  "type": "video",
  "url": "https://www.youtube.com/watch?v=0-VG9QBm8S8",
  "startTime": 165,
  "chapters": [
    { "at": 0,   "label": "Intro" },
    { "at": 165, "label": "Spec sheet" },
    { "at": 245, "label": "The real pitch is agents" }
  ]
}
```

`provider` is auto-detected from the URL. For local MP4s, point `url` at a `file://` path under `fileAccess.allowedRoots`.

## `file`

Downloadable attachment. Served via `/api/files` for `file://` URLs (gated by allowlist), or directly for `http(s)://`.

```json
{
  "type": "file",
  "url": "file:///C:/temp/incident/logs.zip",
  "filename": "incident-2024-0891-logs.zip",
  "fileSize": 4823100,
  "mimeType": "application/zip"
}
```

## `timeline`

Chronological events. Bread and butter for incident RCAs.

```json
{
  "type": "timeline",
  "label": "Incident Timeline",
  "events": [
    { "at": "12:00", "label": "Alert fired", "level": "warning", "body": "Error rate spiked from 0.1% to 4.7%." },
    { "at": "12:05", "label": "Rollback initiated", "level": "info" },
    { "at": "12:30", "label": "Resolved", "level": "success", "body": "Error rate returned to baseline." }
  ]
}
```

`at` is a free-form string; `body` is markdown; `level` is one of `info` (default), `warning`, `error`, `success`.

## `tabs`

Group nested content into tabs. Use to reduce wall-of-text on long entries (incident RCAs, AI research with many sections).

```json
{
  "type": "tabs",
  "tabs": [
    { "label": "Summary",  "content": [{ "type": "markdown", "body": "..." }] },
    { "label": "Timeline", "badge": "12", "content": [{ "type": "timeline", "events": [] }] },
    { "label": "Logs",     "content": [{ "type": "json", "body": {} }] }
  ]
}
```

## `stat`

Big-number metric with optional delta, trend, unit, and sparkline. Common in monitoring summaries.

```json
{
  "type": "stat",
  "label": "Error rate",
  "value": "2.3",
  "unit": "%",
  "delta": "+0.5%",
  "trend": "up",
  "sparkline": [1.6, 1.7, 1.8, 1.9, 2.0, 2.1, 2.3],
  "caption": "Last 24h"
}
```

## `chart`

Line / bar / area / pie chart. Reach for `stat` first; use `chart` when you actually need a time series.

```json
{
  "type": "chart",
  "label": "Requests per second",
  "chartType": "line",
  "xAxis": ["00:00", "06:00", "12:00", "18:00", "24:00"],
  "series": [
    { "name": "us-east-1", "data": [120, 180, 320, 280, 140] },
    { "name": "eu-west-1", "data": [80, 90, 210, 230, 110] }
  ]
}
```

## `diagram`

Mermaid diagram. `body` is the Mermaid source.

```json
{
  "type": "diagram",
  "body": "flowchart LR\n  Alert --> Triage --> Rollback --> Resolved"
}
```

The Mermaid library is lazy-loaded the first time a diagram block renders, so the initial bundle isn't paying for it.

## `beforeAfter`

Image slider revealing before/after.

```json
{
  "type": "beforeAfter",
  "label": "Login page redesign",
  "beforeUrl": "https://example.com/before.png",
  "afterUrl":  "https://example.com/after.png",
  "beforeLabel": "v1.4",
  "afterLabel":  "v1.5"
}
```

## `section`

Collapsible group of nested blocks with optional scoped actions. Supports `defaultCollapsed: true` for heavy sections and an optional `badge` shown next to the title. State (expanded/collapsed) is persisted per-user in localStorage.

```json
{
  "type": "section",
  "title": "Sources",
  "badge": "11 sources",
  "defaultCollapsed": true,
  "content": [
    { "type": "table", "columns": ["#", "Source", "Type"], "rows": [["1", "PIR", "Official"]] }
  ]
}
```

## `divider`

Horizontal rule. No fields beyond `type`.

```json
{ "type": "divider" }
```

## Rich cells

A "rich cell" appears in a `table` row or as a value in a `keyValue` block. It can be a plain string, or a typed object:

| Cell type | Shape | Renders as |
|---|---|---|
| string | `"hello"` | Plain text |
| `text` | `{ type:"text", value, mono? }` | Plain text, optionally monospaced |
| `link` | `{ type:"link", url, label?, icon? }` | Clickable link with icon |
| `status` | `{ type:"status", level, label }` | Colored pill (info/warning/error/success) |
| `badge` | `{ type:"badge", label, color? }` | Neutral or custom-colored badge |
| `code` | `{ type:"code", value, language? }` | Inline `<code>` |
| `copy` | `{ type:"copy", value, display? }` | Display + copy-to-clipboard icon |
| `markdown` | `{ type:"markdown", value }` | Inline markdown |
| `image` | `{ type:"image", url, alt? }` | Small inline thumbnail |

Tables and keyValue blocks are the right place for structured data even when the cells need richness - don't fall back to a markdown block just to get `<code>` formatting for IDs.

## Local files (`file://`)

`image`, `video`, `file`, `gallery`, and `beforeAfter` URLs may use `file://` to reference local files. Browsers refuse to load these from an `http://` origin, so ActionView serves them via `/api/files`. This is **off by default**: the dashboard user must opt the file's directory in via `fileAccess.allowedRoots` in their `actionview.json`.

```json
{
  "fileAccess": {
    "allowedRoots": ["C:/temp/Zakira.Replay", "/var/lib/myapp/frames"],
    "maxFileSizeBytes": 20971520
  }
}
```

Producers shouldn't assume any specific allowlist is configured. Either use `http(s)://` URLs (zero coordination), embed small images as `data:` URIs, or document the path your tool writes to so the user can opt in once. Always set an `alt` so the meaning is preserved if the image fails to load.

## Plugin / custom block types

Unknown `type` values are delegated to the dashboard's plugin system. Stick to the built-ins unless the user has installed a custom renderer.

## Composition tips

- Use `keyValue` first for metadata at a glance - with `copy` cells for IDs, `link` cells for paths, `status` cells for state.
- Follow with a `markdown` summary.
- Use real `diff` blocks for code changes, not `code` with `language: "diff"`.
- Use `code` `annotations[]` for per-line review comments instead of placing `alert` blocks adjacent to a code block.
- Group related findings into `section` blocks (each with their own `actions[]`). For long entries with multiple aspects, `tabs` reduces wall-of-text.
- For multiple images, use `gallery` instead of stacked markdown `![]()` syntax.
- End with a `link` block (single or multi) to the source system.
