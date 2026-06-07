# Content blocks

The `entry.content` array is rendered top-to-bottom by the dashboard. Each item is an object with a `type` discriminator. Pick the block type that matches the data; don't shoehorn structured data into a `markdown` block.

## `markdown`

Prose, summaries, AI analysis. The `body` is rendered with GitHub-flavored markdown.

```json
{
  "type": "markdown",
  "body": "## Summary\n\nThis PR adds a Redis-backed cache, reducing p95 from 120ms to 15ms.\n\n### Risk\n\nLow-medium. Watch for race conditions in `Update()`."
}
```

JSON requires `\n` for line breaks — never paste raw newlines.

## `code`

Code snippets and diffs.

```json
{
  "type": "code",
  "language": "csharp",
  "filename": "src/Services/UserPreferenceCacheService.cs",
  "highlight": [5, 17],
  "body": "public class UserPreferenceCacheService\n{\n    private static readonly TimeSpan CacheTTL = TimeSpan.FromMinutes(5);\n    // ...\n}"
}
```

Fields: `language` (highlighter hint), `filename` (header above the block), `highlight` (1-based line numbers to mark).

## `table`

Tabular data. Always use this for changed-files lists, test results, etc. — never a markdown table.

```json
{
  "type": "table",
  "label": "Changed Files",
  "columns": ["File", "Changes", "Status"],
  "rows": [
    ["src/Services/UserPreferenceCacheService.cs", "+98", "Added"],
    ["src/Services/UserPreferenceService.cs", "+12 / -8", "Modified"]
  ]
}
```

All cells are strings.

## `keyValue`

Header-style metadata. Renders as a two-column grid.

```json
{
  "type": "keyValue",
  "label": "Pull Request Details",
  "pairs": {
    "Repository": "acme/backend",
    "Branch": "feature/cache → main",
    "Author": "@danielk",
    "Files Changed": "7"
  }
}
```

Values are strings.

## `link`

External link rendered as a button or link element.

```json
{
  "type": "link",
  "label": "View on GitHub",
  "url": "https://github.com/acme/backend/pull/482",
  "body": "Open pull request in browser"
}
```

`body` is the link's display description; `label` is the heading.

## `image`

Embeds an image as a medium thumbnail. Clicking opens a full-size lightbox modal (close with X, backdrop click, or Esc).

```json
{
  "type": "image",
  "label": "Frame at 02:45",
  "url": "https://example.com/frames/frame-02-45.jpg",
  "alt": "Speaker discussing the 128 GB unified memory advantage",
  "caption": "RTX Spark presentation, ~02:45 mark"
}
```

| Field | Description |
|-------|-------------|
| `url` | Image source. Accepts `http(s)://`, `data:`, and `file://` URLs. |
| `alt` | Alt text. Shown if the image fails to load, used by assistive tech, and shown as the lightbox's accessible label. |
| `caption` | Optional caption rendered beneath the thumbnail and inside the lightbox. |
| `label` | Optional heading above the image (same as other blocks). |
| `maxWidth` | Optional thumbnail max width in CSS pixels. Lightbox always uses the full viewport. |

### Embedding images inside markdown

Standard markdown image syntax inside a `markdown` block also renders as a clickable thumbnail with the same lightbox behavior:

```json
{ "type": "markdown", "body": "![Lineup](https://example.com/lineup.jpg)" }
```

### Local files (`file://`)

Browsers refuse to load `file://` URLs from an `http://` origin, so ActionView serves local files through `/api/files` instead. This is **off by default**: the dashboard user must opt the file's directory in via `fileAccess.allowedRoots` in their `actionview.json`.

```json
{
  "fileAccess": {
    "allowedRoots": ["C:/temp/Zakira.Replay", "/var/lib/myapp/frames"],
    "maxFileSizeBytes": 20971520
  }
}
```

The client rewrites `file:///C:/temp/Zakira.Replay/runs/.../frame.jpg` to `/api/files?path=C:%2Ftemp%2F...%2Fframe.jpg` automatically. Anything outside the allowlist is refused with HTTP 403. Symlinks whose targets escape the allowlist are also rejected.

### Producer / consumer split

`fileAccess.allowedRoots` lives on the **consumer** (the user running ActionView), not the producer. As a producer of entries you have three honest options:

1. **Use `http(s)://` URLs** — zero coordination. The image is fetched directly by the browser. Best when the image is already on a web server (CDN, blob storage, GitHub raw).
2. **Use `data:` URIs** — embed the bytes directly in the entry JSON (`data:image/jpeg;base64,...`). Zero coordination, but inflates entry size; keep to small thumbnails.
3. **Use `file://` URLs** — only works if the producer and consumer share a filesystem, and the directory is in the consumer's `allowedRoots`. Document the path your tool writes to (e.g., "this orchestrator writes frames under `C:/temp/ActionView/runs/...`; add it to your `fileAccess.allowedRoots`") so users can opt in once and stop thinking about it.

Producers should not assume any specific allowlist is configured. If a `file://` image fails to load the consumer sees a broken thumbnail and a 403 in the network log — fail-gracefully by always including an `alt` so the meaning is preserved.

## `alert`

Callout box with a level.

```json
{
  "type": "alert",
  "level": "warning",
  "body": "Hard-coded TTL on line 5. Consider moving to appsettings."
}
```

`level`: `info` | `warning` | `error` | `success`.

## `section`

Collapsible group with its own nested `content[]` and optional `actions[]`. Use this for grouping a code snippet + alert + per-section button (e.g., "Post Comment about this finding").

```json
{
  "type": "section",
  "title": "Key Change: Cache Implementation",
  "content": [
    { "type": "code", "language": "csharp", "body": "..." },
    { "type": "alert", "level": "warning", "body": "Hard-coded TTL." }
  ],
  "actions": [
    {
      "label": "Post Comment",
      "style": "primary",
      "parameters": [
        { "name": "body", "label": "Comment", "type": "multiline",
          "default": "Consider moving CacheTTL to appsettings.", "required": true }
      ],
      "command": { "type": "http", "method": "POST", "url": "...", "body": { "body": "{{param.body}}" } },
      "onSuccess": "keep"
    }
  ]
}
```

Section actions are scoped — they target a specific finding rather than the whole entry. They are addressed by `sectionIndex` (0-based among section blocks at the entry's top level).

## `divider`

Horizontal rule. No fields beyond `type`.

```json
{ "type": "divider" }
```

## `json`

Raw JSON pretty-printed for inspection.

```json
{
  "type": "json",
  "label": "Raw event payload",
  "body": { "user_id": "u_42", "action": "login_failed", "attempts": 5 }
}
```

## Plugin / custom block types

Unknown `type` values are delegated to the dashboard's plugin system. Stick to the built-ins listed above unless the user has installed a custom renderer.

## Composition tips

- Put a `keyValue` block first for metadata at a glance.
- Follow with a `markdown` summary.
- Use `section`s to group findings with their own actions (one section per AI suggestion in a PR review, for example — the user can post just that suggestion).
- End with a `link` block to the source system.
