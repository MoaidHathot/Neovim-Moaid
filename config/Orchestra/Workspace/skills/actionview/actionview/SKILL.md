---
name: actionview
description: Create review and notification entries (PR reviews, deploy approvals, incidents, alerts) in the user's ActionView review queue, and inspect or modify existing entries via its MCP server. Use when the user has ActionView running and you need to surface something interactive for them to review, when you produce content the user must approve or edit before submitting (e.g., AI-drafted PR comments), or when the user asks you to inspect, update, dismiss, or pin items in the queue.
license: See repository LICENSE
metadata:
  project: ActionView
  schema-version: "1"
---

# ActionView

ActionView is a real-time **review queue** that external tools (and AI agents) push entries into. The user sees them in a dashboard and clicks buttons to act. Use this skill whenever you want the user to:

- Review something you produced (a PR analysis, an incident summary, a deploy diff).
- Approve, dismiss, or take a parameterized action on something (post a comment with editable text, approve with optional message, request changes with required reason).

Pressing buttons on entries is **deliberately** a human-only surface — clicks happen in the dashboard, not via the MCP API. You can read, update, dismiss, and pin entries via MCP, but you cannot execute their actions programmatically.

## Decision tree

| Goal | Use |
|------|-----|
| Push something for the user to review | Publish an entry (see below) |
| Check an entry is well-formed before publishing | MCP `validate_entry` (or `actionview validate` / `POST /api/entries/validate`) |
| User asked you to look at their queue | MCP `list_entries` / `get_entry` |
| User asked you to amend an entry (bump severity, add a tag, append a finding) | MCP `update_entry` |
| User asked you to dismiss / archive an entry | MCP `dismiss_entry` |
| User asked you to delete an entry permanently | MCP `delete_entry` (destructive) |
| User asked you to pin / unpin | MCP `pin_entry` |
| User asked you to **act on** an entry (approve PR, post comment, etc.) | Tell them to click in the dashboard. ActionView keeps action execution human-only. |
| User asked you to add a new template type | MCP `register_template` (or POST `/api/templates`) |

## Publishing an entry — three transports, same payload

Pick whichever the environment supports; the JSON is identical.

1. **Drop a JSON file in `data/inbox/`.** ActionView's file watcher ingests it. Simplest. No server needed beyond the dashboard.
2. **POST `/api/entries`** with the JSON body. Use when the dashboard is reachable over HTTP.
3. **MCP tool `add_entry`.** Use when an MCP connection to ActionView exists.

Full transport details + URLs: see [references/publishing.md](references/publishing.md).

## Minimum entry

```json
{
  "type": "pr-review",
  "source": "your-tool-name",
  "title": "PR #482: Add user preference caching layer"
}
```

Required: `type`, `source`, `title`. Everything else is optional but you almost always want `severity`, `content`, and `actions`.

Full schema: [references/entry-anatomy.md](references/entry-anatomy.md).

## Validate instead of memorizing the schema

Don't burn effort reasoning about the whole schema up front — especially for large entries. **Emit a best-effort entry, validate it, fix the reported errors, resubmit.**

- MCP: `validate_entry(entryJson)` → `{ ok, errors[], warnings[] }`.
- CLI: `actionview validate -f entry.json` (exits non-zero on failure) or `actionview add --wait …` (validate + submit, fail fast).
- HTTP: `POST /api/entries/validate`.

Each diagnostic has a JSON `path` (e.g. `/content/3/type`), a stable `code` (`schema.enum`, `schema.required`, `block.missingRequired`, `tag.notAllowed`, `json.parse`), and a `message`. Fix those exact paths and retry — it's far cheaper and more reliable than trying to emit a perfect entry in one shot. `add_entry` runs the same validation, so a failed create returns the same structured report to retry against.

**Errors** block ingestion; **warnings** (missing required template blocks, disallowed tags) don't, unless the entry type / server is in **strict** mode.

## Body shape

`content` is an ordered array of typed blocks. Built-in types (all also work nested inside `section` and `tabs`):

**Prose & code**
- `markdown` — prose, summaries, AI analysis. GFM + math (`$$ ... $$`) + task lists. Embedded `![alt](url)` images render as click-to-enlarge thumbnails.
- `code` — diffs, file snippets. Copy button, wrap/line-no toggles, per-line `annotations[]` (review-style inline comments).
- `diff` — first-class unified or split diff view with add/remove gutters and per-hunk collapse. Body is a unified-diff string.
- `json` — foldable JSON tree with copy button.

**Tabular & metadata**
- `table` — sortable, filterable. Cells may be plain strings or rich-cell objects (`link`, `status`, `badge`, `code`, `copy`, `markdown`, `image`).
- `keyValue` — header metadata. Values use the same rich-cell shapes (so a Commit SHA can be a `copy` cell, a file path a `link`, status a `status` pill).
- `link` — one URL (`url`) or many (`links[]`) with optional `body` description and `icon`.

**Visual**
- `image` — thumbnail + lightbox. Supports `imageAnnotations[]` (arrows/boxes/text overlays) and `timestampUrl` (open external link instead of lightbox).
- `gallery` — grid of images sharing one lightbox carousel (prev/next + zoom + keyboard arrows).
- `video` — YouTube / Vimeo / file with optional `startTime`/`endTime` clipping and `chapters[]`.
- `file` — downloadable attachment via `/api/files`.
- `beforeAfter` — image slider with `beforeUrl` / `afterUrl`.

**Dashboards & flow**
- `timeline` — chronological events (RCA bread and butter).
- `tabs` — group nested content into tabs.
- `stat` — big-number with optional `delta`, `trend`, `unit`, `sparkline`.
- `chart` — line / bar / area / pie via `series` + `xAxis`.
- `diagram` — Mermaid diagram (body is Mermaid source).

**Layout**
- `section` — collapsible group with `defaultCollapsed` + `badge` and own nested `content[]` + `actions[]`.
- `alert` — info/warning/error/success callout. Markdown body, optional `dismissible`, can carry its own `actions[]`.
- `divider` — horizontal rule.

Examples for each: [references/content-blocks.md](references/content-blocks.md).

## Actions — buttons the user clicks

Each action declares a `command` (HTTP or CLI) and a post-execution behavior (`archive`, `keep`, or `delete`). Place actions at the entry level (`entry.actions[]`) or inside a `section` block (`block.actions[]`).

**When the user should edit something before submitting** (e.g., an AI-drafted comment, an approval message, a reason for requesting changes), declare `parameters`. The UI renders an inline form (textarea / select / number / checkbox) and substitutes the user's input into the command via `{{param.NAME}}` placeholders.

```json
{
  "label": "Post Comment",
  "style": "primary",
  "parameters": [
    {
      "name": "body",
      "label": "Comment",
      "type": "multiline",
      "default": "Consider making CacheTTL configurable via appsettings.",
      "required": true,
      "helpText": "Edit before posting."
    }
  ],
  "command": {
    "type": "http",
    "method": "POST",
    "url": "https://api.github.com/repos/acme/backend/pulls/482/comments",
    "headers": { "Authorization": "Bearer {{GITHUB_TOKEN}}" },
    "body": { "body": "{{param.body}}" }
  },
  "onSuccess": "keep"
}
```

The two placeholder namespaces are **separate**:

- `{{param.NAME}}` — runtime user input. Resolved first.
- `{{SECRET}}` — value from `actionview.json` `secrets` map or environment variables. Resolved after.

Full action reference (parameter types, validation rules, JSON-leaf substitution, undo): [references/actions.md](references/actions.md).

## Reading and modifying the queue (MCP)

If the ActionView MCP server is connected, you can:

- `list_entries`, `get_entry`, `get_stats`, `get_schema` — discovery (read-only).
- `validate_entry` — check candidate entry JSON against the schema + type template **without** adding it (read-only). Returns `{ ok, errors[], warnings[] }` with JSON paths.
- `add_entry` — create a new entry (validates first; on failure returns `{ success:false, error:"validation_failed", validation:{…} }`).
- `update_entry` — modify fields of an existing active entry (title, subtitle, severity, tags, content, actions, priority). Omitted or null fields are left alone.
- `dismiss_entry` — archive without executing an action.
- `delete_entry` (destructive), `pin_entry`.
- `list_templates`, `get_template`, `register_template`, `remove_template`.

**There is no `execute_entry_action` tool.** Pressing buttons on entries is a deliberate human-in-the-loop surface — if the user wants an action executed, ask them to click in the dashboard. The MCP server's job is to read, create, and curate; the dashboard's job is to act.

Full reference: [references/mcp-tools.md](references/mcp-tools.md).

## Templates

If you produce many entries of the same type, register a template once. ActionView will normalize incoming entries against it (apply defaults, alias content keys, normalize tags — case-fold / alias / allow-list, and flag missing required content blocks). A template can opt into `strict` so its entries are rejected on any validation warning. Templates **do not** define commands — the producer always supplies those.

See [references/templates.md](references/templates.md).

## Concrete examples (read these when authoring)

- `assets/pr-review.json` — full PR review with editable AI comment + approve/request-changes (parameterized).
- `assets/deploy-approval.json` — minimal HTTP action with secret + parameter.
- `assets/alert.json` — minimum-viable alert entry.

## Common pitfalls

- **Required fields are case-sensitive**: `type`, `source`, `title`. Missing any → entry is rejected.
- **Newlines in markdown** must be JSON-escaped as `\n`. Don't paste raw newlines into a JSON string.
- **`{{param.X}}` vs `{{X}}`** — different namespaces. Don't put a secret in `parameters` and don't expect a parameter to fall back to env.
- **HTTP body**: prefer a JSON object (not a stringified one). Substitution walks string leaves and JSON-escapes user input automatically — quotes/newlines in a comment body cannot break the payload.
- **OnSuccess defaults to `archive`.** If the user should keep seeing the entry after acting (e.g., the section's "Post Comment" doesn't end the review), set `"onSuccess": "keep"`.
- **Don't bake user-editable content into command args.** If the user needs to edit a value, declare a `parameter` with `default` set to your draft — never hard-code the draft into `args`/`body` strings.
- **Pick a meaningful `source`.** It appears in the UI and is filterable. Use the producing tool's name (e.g., `"github-pr-bot"`, `"datadog-alerts"`).
- **Tags and `type` power saved views.** The dashboard can split the queue into lanes (e.g. Work vs Personal) by tag and/or type, with Any/All tag matching. Consistent `tags`/`type` make those views useful and let the user — or you, via `list_entries` (`view=`, `tags=`, `tagMode=`) — filter to one lane in a click.
- **Local images need a consumer-side allowlist.** `file://` URLs in `image` blocks or markdown bodies only render if the directory holding the file is listed in the user's `actionview.json` under `fileAccess.allowedRoots`. If you're publishing entries that point at host-local files, either (a) write the images into a directory you know is already allowlisted, (b) document the path the user needs to add, or (c) prefer `http(s)://` / `data:` URLs to avoid the coordination entirely. See [references/content-blocks.md](references/content-blocks.md#image).
