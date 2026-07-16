# Entry anatomy

Full schema reference for ActionView entries (schema v1). Source of truth: `schemas/entry.v1.schema.json`.

## Top-level fields

| Field | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `schemaVersion` | string | no | `"1"` | Always `"1"` for this version. |
| `id` | string | no | auto | Unique identifier. Auto-generated when omitted. Supply your own if you want stable cross-references. |
| `type` | string | **yes** | — | Category for grouping/filtering (`pr-review`, `incident`, `deploy`, `alert`, etc.). |
| `source` | string | **yes** | — | Name of the producing tool. Visible in the UI; filterable. |
| `createdAt` | string (ISO 8601) | no | now | Display timestamp. |
| `title` | string | **yes** | — | Primary list-view text. Keep concise. |
| `subtitle` | string | no | — | Secondary text. Good for repo/branch/author one-liners. |
| `severity` | enum | no | `medium` | `low` \| `medium` \| `high` \| `critical`. Drives sort order and color. |
| `icon` | string | no | — | Lucide icon name (e.g., `git-pull-request`, `alert-triangle`). |
| `tags` | string[] | no | `[]` | Free-form filter tags. Power the dashboard's filtering and **saved views** (e.g. a "Work" view = entries tagged `work`), so tag consistently. |
| `content` | block[] | no | `[]` | Body — see [content-blocks.md](content-blocks.md). |
| `actions` | action[] | no | `[]` | Entry-level buttons — see [actions.md](actions.md). |
| `groupId` | string | no | — | Group related entries (same CI run, same repo). |
| `groupLabel` | string | no | — | Display label for the group. |
| `pinned` | bool | no | `false` | Pin to top of list. |
| `priority` | int | no | `0` | Higher = appears earlier; ties broken by severity then createdAt. |

## Sort order in the dashboard

Default: pinned → priority (desc) → severity (desc) → createdAt (desc). The user can also re-sort the list by created / priority / severity / title in either direction, and slice it with **saved views** (filter presets by tag and/or type).

## Severity guidance

- `low` — informational, FYI alerts, nightly summaries.
- `medium` — routine review work (most PR reviews, deploy approvals).
- `high` — needs prompt attention (failing build, security finding).
- `critical` — page-worthy (production incident, data loss risk).

## Minimum viable entry

```json
{
  "type": "alert",
  "source": "watchdog",
  "title": "Disk usage > 90% on db-prod-3"
}
```

`type`, `source`, and `title` are required and must be **non-empty**.

## Validate before publishing

Don't try to emit a perfect entry by memorizing this whole schema. Emit a best-effort entry, validate it, fix the reported errors, and resubmit:

- MCP `validate_entry(entryJson)`, CLI `actionview validate -f entry.json`, or `POST /api/entries/validate`.
- Returns `{ ok, errors[], warnings[] }`; each diagnostic has a JSON `path` (e.g. `/severity`), a stable `code` (`schema.enum`, `schema.required`, `block.missingRequired`, …), and a `message`.

See [publishing.md](publishing.md#validate-before-you-publish) for the full loop.

## Recommended baseline

```json
{
  "type": "pr-review",
  "source": "github-pr-bot",
  "title": "PR #482: Add user preference caching layer",
  "subtitle": "acme/backend — opened by @danielk",
  "severity": "medium",
  "icon": "git-pull-request",
  "tags": ["backend", "performance"],
  "content": [ /* ... */ ],
  "actions": [ /* ... */ ]
}
```

## Stable IDs

If you re-publish a logically identical entry (e.g., the same PR, updated), supply the same `id` so the dashboard updates the existing card instead of creating a duplicate. Without an `id`, every publish creates a new entry.

## Grouping

Use `groupId` + `groupLabel` to cluster related entries (e.g., all findings from a single CI run). The dashboard renders them under a shared header.

```json
{ "groupId": "ci-run-1847", "groupLabel": "CI Run #1847", ... }
```
