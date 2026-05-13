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

## Validation & normalization

All three transports run the entry through:

1. **Schema validation** — required fields (`type`, `source`, `title`) checked. Missing → entry rejected.
2. **Template normalization** (if a template is registered for `entry.type`) — applies defaults for `severity`/`icon`/`tags`, aliases content keys, validates expected content blocks.

See [templates.md](templates.md) for how to register a template.

## Updating an existing entry

Supply the same `id` you used the first time. ActionView upserts on `id`. Without an `id`, every publish creates a new entry — fine for most one-shot notifications, problematic if your tool re-runs (e.g., re-analyzing the same PR every commit).

For partial updates of an already-ingested entry, use `PUT /api/entries/{id}` with `EntryUpdateRequest` (title/subtitle/severity/tags/content/actions/priority).

## Real-time push

Once an entry is ingested, ActionView broadcasts it to all connected dashboards via SignalR (`/hubs/entries`). No further action needed — clients receive `entriesAdded` immediately.

## Errors

- **400 Bad Request** — required field missing, invalid JSON.
- **Inbox**: file moved to `data/errors/` with a `.error.txt` sibling explaining the failure.

If you're an AI agent and your `add_entry` call fails, read the error message and retry with corrections — don't loop blindly.
