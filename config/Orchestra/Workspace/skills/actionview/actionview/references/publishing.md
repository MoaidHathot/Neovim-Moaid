# Publishing entries

Three transports, identical JSON payload. Pick whichever the environment supports.

## 1. Drop a JSON file in the inbox

Simplest. ActionView's `InboxWatcher` polls `data/inbox/` and ingests any `*.json` file that appears.

```bash
cp my-entry.json /path/to/actionview/data/inbox/
```

After successful ingestion the file is moved out of the inbox automatically. Invalid entries land in `data/errors/` with a `.error.txt` companion explaining why.

**When to use:** local development, scripts that already write files, no network access required.

## 2. POST `/api/entries`

When the dashboard is reachable over HTTP (default `http://localhost:5000`).

```bash
curl -X POST http://localhost:5000/api/entries \
  -H 'Content-Type: application/json' \
  -d @my-entry.json
```

Returns `201 Created` with the ingested entry (including the auto-generated `id`).

For batch ingest, POST an array to `/api/entries/batch/ingest`.

**When to use:** CI/CD systems that already speak HTTP, tools running in different containers, anything cross-network.

## 3. MCP `add_entry` tool

When you have an MCP connection to ActionView's MCP server (`actionview-mcp`).

```
add_entry(entryJson: '{ "type": "alert", "source": "watchdog", "title": "Disk full" }')
```

The argument is a JSON **string** (not an object). Returns `{ success, id, title, type, severity }` or `{ error }`.

**When to use:** AI agents that already have ActionView MCP wired in. See [mcp-tools.md](mcp-tools.md) for the full tool list.

## Validate before you publish

Rather than reasoning about the whole schema up front, **emit → validate → fix**:

- MCP: `validate_entry(entryJson)` — read-only, no side effects.
- CLI: `actionview validate -f entry.json` (exits non-zero on failure), or `actionview add --wait` to validate-then-submit and fail fast.
- HTTP: `POST /api/entries/validate` (add `?strict=true` to also treat warnings as errors).

All return `{ ok, errors[], warnings[] }`, where each diagnostic has a JSON `path`, a stable `code` (`schema.enum`, `schema.required`, `block.missingRequired`, `tag.notAllowed`, …), and a `message`. Fix those paths and retry.

## Validation & normalization at ingest

All three transports run the entry through the same pipeline:

1. **Schema validation** against `entry.v1.schema.json` — required fields (`type`, `source`, `title`, each non-empty), enum values, and structural shape. Failures are reported with precise JSON paths.
2. **Template normalization** (if a template is registered for `entry.type`) — applies defaults for `severity`/`icon`/`tags`, aliases content keys, normalizes tags (case-fold / alias / allow-list), and flags missing required content blocks.

By default this is **non-destructive**: schema failures block (the entry can't be used), but template warnings (e.g. a missing block) are logged and the entry still ships. Turn on **strict** (`--strict`, `?strict=true`, template `strict`, or `ingest.strict` in config) to reject warnings into `errors/` too.

See [templates.md](templates.md) for how to register a template.

## Updating an existing entry

Supply the same `id` you used the first time. ActionView upserts on `id`. Without an `id`, every publish creates a new entry — fine for most one-shot notifications, problematic if your tool re-runs (e.g., re-analyzing the same PR every commit).

For partial updates of an already-ingested entry, use `PUT /api/entries/{id}` with `EntryUpdateRequest` (title/subtitle/severity/tags/content/actions/priority).

## Real-time push

Once an entry is ingested, ActionView broadcasts it to all connected dashboards via SignalR (`/hubs/entries`). No further action needed — clients receive `entriesAdded` immediately.

## Errors

- **400 Bad Request** — invalid/unparseable JSON, a failed required/enum/shape check, or (in strict mode) a template warning. The body is `{ error: "validation_failed", validation: { ok, errors[], warnings[] } }`.
- **Inbox**: an invalid file is moved to `data/errors/` with a `.error.txt` sibling that now contains the same precise, structured reason (e.g. `[schema.enum] /severity: …`).

If you're an AI agent and a publish fails, read the `errors[]` (each has a `path` + `code` + `message`), fix those exact fields, and retry — don't loop blindly. Better yet, call `validate_entry` first.
