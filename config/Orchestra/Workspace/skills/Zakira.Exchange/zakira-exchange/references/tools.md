# Zakira.Exchange MCP tools - full reference

The server registers up to 6 stdio MCP tools. Which tools appear depends
on the configured access mode (see `setup.md`). All tools operate on
"memory entries" - rows in SQLite with the shape:

| Field      | Type                | Notes                                       |
| ---------- | ------------------- | ------------------------------------------- |
| `category` | string              | Required. Namespace; also a scoping key.    |
| `key`      | string              | Required. Unique within `category`.         |
| `data`     | string              | The content. Plain text; markdown is fine.  |
| `author`   | string or null      | Who/what created or last edited the entry.  |
| `reason`   | string or null      | Why this entry exists; one short sentence.  |
| `tags`     | comma-separated     | Faceted, lowercase, hyphen-separated.       |
| `custom`   | JSON object         | Arbitrary string-to-string metadata.        |
| `created`  | ISO 8601 timestamp  | Set by the server.                          |
| `modified` | ISO 8601 timestamp  | Updated by the server on every edit.        |

If the server is in const-category mode (`--category <name>`), the
`category` parameter is **not on any tool's schema**. Just omit it.

---

## `search_memories` *(all access modes)*

Hybrid semantic + keyword search across all entries (or one category),
ordered by Reciprocal Rank Fusion score. Triggers a lazy model load on
first call.

| Parameter  | Required | Notes                                                |
| ---------- | -------- | ---------------------------------------------------- |
| `query`    | yes      | Natural-language query. No exact-match required.     |
| `category` | no\*     | Restrict to one category.                            |
| `top`      | no       | Max results. Default 10.                             |
| `author`   | no       | Filter by author (applied after fusion).             |
| `tags`     | no       | Comma-separated; matches any (applied after fusion). |

\* Hidden in const-category mode.

Returns an ordered list of entries with their fused score. Higher first.
Each entry is embedded as a single unit (`key | data | tags | reason`)
so all of those fields contribute to recall.

---

## `get_memory` *(all access modes)*

Fetch a single entry by `(category, key)`. Cheap; no model load.

| Parameter  | Required | Notes                  |
| ---------- | -------- | ---------------------- |
| `category` | yes\*    | The entry's category.  |
| `key`      | yes      | The entry's key.       |

\* Hidden in const-category mode.

Returns the full entry, or a "not found" result.

---

## `list_memories` *(all access modes)*

Browse entries with filters, ordered by `modified` descending. No model
load.

| Parameter  | Required | Notes                                                |
| ---------- | -------- | ---------------------------------------------------- |
| `category` | no\*     | Filter by category.                                  |
| `top`      | no       | Max results. Default 50.                             |
| `author`   | no       | Filter by author.                                    |
| `tags`     | no       | Comma-separated; matches any.                        |
| `before`   | no       | ISO 8601; only entries with `modified < before`.     |
| `after`    | no       | ISO 8601; only entries with `modified > after`.      |

\* Hidden in const-category mode.

Returns a list of matching entries.

---

## `create_memory` *(modes: full, append-only, no-delete)*

Insert a new entry. Fails if `(category, key)` already exists - use
`edit_memory` to update instead.

| Parameter  | Required | Notes                                                       |
| ---------- | -------- | ----------------------------------------------------------- |
| `category` | yes\*    | Namespace.                                                  |
| `key`      | yes      | Unique within category. See `conventions.md` for naming.    |
| `data`     | yes      | The content.                                                |
| `author`   | no       | Your agent identity (e.g., a role name or model + run id).  |
| `reason`   | no       | One sentence: why this entry exists.                        |
| `tags`     | no       | Comma-separated; faceted; lowercase. See `conventions.md`.  |
| `custom`   | no       | JSON object of additional metadata.                         |

\* Hidden in const-category mode.

Triggers an embedding pass on the joined `(key, data, tags, reason)`
text.

---

## `edit_memory` *(modes: full, no-delete)*

Update an existing entry. **Only the fields you pass are changed.**
Omitting a field keeps its current value.

| Parameter  | Required | Notes                              |
| ---------- | -------- | ---------------------------------- |
| `category` | yes\*    | The entry's category.              |
| `key`      | yes      | The entry's key.                   |
| `data`     | no       | New content (replaces).            |
| `author`   | no       | Last editor.                       |
| `reason`   | no       | Updated rationale.                 |
| `tags`     | no       | **Replaces** the full tag list.    |
| `custom`   | no       | **Replaces** the full custom object. |

\* Hidden in const-category mode.

Re-embeds the entry whenever any embedded field changes.

> `tags` and `custom` are full replacements, not deltas. To add a single
> tag or custom key without losing the others, fetch with `get_memory`
> first, merge in your changes, then call `edit_memory` with the merged
> value.

---

## `delete_memory` *(mode: full only)*

Permanently remove an entry. Not reversible.

| Parameter  | Required | Notes                  |
| ---------- | -------- | ---------------------- |
| `category` | yes\*    | The entry's category.  |
| `key`      | yes      | The entry's key.       |

\* Hidden in const-category mode.

Returns success or "not found".

---

## Access mode availability matrix

| Tool              | full | read-only | append-only | no-delete |
| ----------------- | ---- | --------- | ----------- | --------- |
| `search_memories` | yes  | yes       | yes         | yes       |
| `get_memory`      | yes  | yes       | yes         | yes       |
| `list_memories`   | yes  | yes       | yes         | yes       |
| `create_memory`   | yes  | --        | yes         | yes       |
| `edit_memory`     | yes  | --        | --          | yes       |
| `delete_memory`   | yes  | --        | --          | --        |

Tools the mode disallows are not registered at all - they simply do not
appear in the agent's tool list. Discover the active mode by inspecting
which tools are available, not by asking the server.

---

## Error and edge cases

- **Duplicate key on `create_memory`.** Treat as a signal that
  `(category, key)` is already taken; switch to `edit_memory` or pick a
  different key.
- **`not found` on `get_memory` / `edit_memory` / `delete_memory`.** The
  entry may have been removed by another agent or the user. Re-search
  before assuming it never existed.
- **Const-category mode + `category` parameter.** Passing `category`
  when the server is in const-category mode is a schema violation - the
  parameter simply isn't there, so passing it will fail validation.
- **Missing ONNX model.** `create_memory`, `edit_memory`, and
  `search_memories` will fail if the model file isn't installed.
  `get_memory`, `list_memories`, and `delete_memory` keep working
  without it.
