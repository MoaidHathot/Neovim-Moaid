# MCP tools

The `actionview-mcp` server exposes ActionView's queue to AI agents over the Model Context Protocol (stdio transport). Tools split into read-only and write categories — pass `--read-only` on the command line to disable the write set.

**Note on scope.** The MCP server intentionally does **not** expose an `execute_entry_action` tool. Pressing buttons on entries is a human-only surface — the dashboard is the system of record for "what was done." MCP can read, create, update, dismiss, and pin entries; the user clicks to act.

## Read tools (always available)

### `list_entries`
List active (non-archived) entries.

**Args (all optional):** `type`, `severity`, `source`, `tags` (comma-separated), `tagMode` (`any`/`all` — how multiple tags combine; defaults to the server config), `search`, `view` (apply a saved view by id or name, which supplies its `type` + `tags`), `sort` (`created`/`priority`/`severity`/`title`), `dir` (`asc`/`desc`).

**Returns:** `{ count, entries[] }`. Each entry includes its full `content` and `actions`.

Use this first when the user says "what's in my queue" or before deciding what to act on. With no `sort`, entries come back in the dashboard's canonical order (pinned → priority → severity → createdAt). `tagMode=all` is handy for narrowing (e.g. `tags="work,urgent"` + `tagMode=all`).

### `get_entry`
Fetch one entry by ID. Supports prefix matching — `get_entry("a3f")` works if there's exactly one entry whose ID starts with `a3f`. Returns `{ error: "Ambiguous ID", matches: [...] }` if multiple match.

Use this to inspect content, see what actions exist on the entry (and what parameters they declare), or confirm an `update_entry` change took effect.

### `get_stats`
Dashboard counters: total pending, total viewed, counts by type and severity. Cheap; safe to call before/after work.

### `get_schema`
Returns the full `entry.v1.schema.json`. Read this if you're unsure of the entry shape — it's the source of truth.

### `list_templates` / `get_template`
Inspect registered entry-type templates. See [templates.md](templates.md).

## Write tools (omitted with `--read-only`)

### `add_entry`
Create a new entry.

**Args:** `entryJson` (a JSON string, not an object).

**Returns:** `{ success, id, title, type, severity }` or `{ error }`.

Build the JSON string from a real entry object, e.g. `JSON.stringify(entry)` — never hand-concatenate.

### `update_entry` (Idempotent)
Modify fields of an existing **active** entry in place. The dashboard receives the change via SignalR when both processes share the data directory.

**Args:**
- `id` — entry ID.
- `updateJson` — JSON **object string** with the fields you want to change. Any field that is omitted **or set to null** is left untouched. Updatable fields: `title`, `subtitle`, `severity`, `tags`, `content`, `actions`, `priority`.

**Identity fields** (`id`, `type`, `source`, `createdAt`) cannot be changed. Use `add_entry` if you actually need a different entry.

**Cannot update archived entries** — `update_entry` operates on the active queue only. Returns `{ error: "Entry not found or not active: ..." }` otherwise.

**Returns:** `{ success, id, title, type, severity, fieldsUpdated: [...] }` listing exactly which fields were applied (so you can confirm to the user that, say, severity changed but their omitted title didn't).

#### Example: bump severity + add a tag

```
update_entry(
  id="a3f",
  updateJson='{"severity":"high","tags":["urgent","prod","backend"]}'
)
```

Response:
```json
{
  "success": true,
  "id": "a3f...",
  "title": "PR #482: Add user preference caching layer",
  "type": "pr-review",
  "severity": "high",
  "fieldsUpdated": ["severity", "tags"]
}
```

#### Example: append a new finding to a section-driven entry

Fetch the entry first, build the new `content` array (existing blocks + appended findings), then push:

```
1. existing = get_entry("a3f")
2. newContent = existing.content + [{ "type": "alert", "level": "warning", "body": "..." }]
3. update_entry(id="a3f", updateJson=JSON.stringify({ content: newContent }))
```

`update_entry` replaces the field wholesale — there's no patch/merge for arrays. If you only want to add a block, you must read, append, and write back.

#### Example: clear the subtitle

Set it to an empty string. (Null in the payload means "leave alone".)

```
update_entry(id="a3f", updateJson='{"subtitle":""}')
```

#### Common gotchas

- The `updateJson` arg is a **JSON object string**, not a JSON-encoded string. Pass `'{"severity":"high"}'`, not `'"{\"severity\":\"high\"}"'`.
- Don't send `id`, `type`, `source`, or `createdAt` — they're ignored.
- Array fields (`tags`, `content`, `actions`) are wholesale replacements. Read-modify-write if you only want to add or remove one entry.

### `dismiss_entry`
Archive an entry without executing any action.

**Args:** `id`, `reason?`.

### `delete_entry` (Destructive)
Permanently delete an active entry. Cannot be undone. Prefer `dismiss_entry`.

### `pin_entry` (Idempotent)
Toggle the entry's `pinned` flag.

### `register_template` / `remove_template`
See [templates.md](templates.md).

## When to use which

| User says... | Tool(s) |
|--------------|---------|
| "What's pending?" / "Show my queue" | `list_entries` |
| "Show only my work items" / "What's in the Personal view?" | `list_entries` (`view="work"` / `view="personal"`) |
| "Tell me about the PR review for #482" | `list_entries` (filter `type=pr-review`) → `get_entry` |
| "Bump that PR review to high severity" | `get_entry` → `update_entry` |
| "Add an `urgent` tag to all critical alerts" | `list_entries` (filter `severity=critical`) → loop `update_entry` |
| "Which backend items are also urgent?" | `list_entries` (`tags="backend,urgent"`, `tagMode=all`) |
| "Append this finding to the deploy entry" | `get_entry` → `update_entry` with the appended `content` array |
| "Approve PR #482" / "Post that comment" | Not an MCP operation. Direct the user to click the button in the dashboard. |
| "Dismiss the disk-usage alert" | `list_entries` → `dismiss_entry` |
| "What's the entry format?" | `get_schema` |
| "Add a notification for X" | `add_entry` |

## Read-only mode

Run with `actionview-mcp --read-only` to expose only the read tools. Useful when you want an AI agent to **observe** the queue but never modify it.
