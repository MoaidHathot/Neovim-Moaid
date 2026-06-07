---
name: zakira-exchange
description: Save, recall, and search durable agent memories via the Zakira.Exchange MCP server. Use when the create_memory, edit_memory, delete_memory, get_memory, list_memories, or search_memories tools are available; when the user mentions Zakira, memory entries, or persistent agent notes; or when a task involves remembering decisions, preferences, learned facts, or prior context that should outlive the session. Covers tool usage, hybrid keyword+semantic search, naming conventions, access modes, and MCP client setup.
license: Unlicense
metadata:
  project: Zakira.Exchange
  homepage: https://moaidhathot.github.io/Zakira.Exchange/
  source: https://github.com/MoaidHathot/Zakira.Exchange
---

# Zakira.Exchange

Zakira.Exchange is a standalone MCP server (and CLI) that gives agents a
durable, searchable memory store. Memories are structured entries -
`(category, key, data)` plus metadata - kept in SQLite with full-text
search (FTS5) and ONNX vector embeddings (`all-MiniLM-L6-v2`), merged via
Reciprocal Rank Fusion for hybrid retrieval.

## When this skill applies

Load this skill when **any** of the following is true:

- The agent has access to one or more of these MCP tools:
  `create_memory`, `edit_memory`, `delete_memory`, `get_memory`,
  `list_memories`, `search_memories`.
- The user mentions Zakira, a memory store, persistent agent notes,
  "remember this", "have we decided...", or similar.
- A task involves capturing or recalling facts, decisions, preferences,
  or prior context that should outlive the current session.

Do **not** load this skill for transient working memory the user does not
ask to persist, or for unrelated note-taking tools that aren't Zakira.

## The tool surface at a glance

| Tool              | Purpose                              | Typical use                                   |
| ----------------- | ------------------------------------ | --------------------------------------------- |
| `search_memories` | Hybrid semantic + BM25 search        | First call when starting a task with context  |
| `get_memory`      | Fetch a known `(category, key)`      | You already know the exact key                |
| `list_memories`   | Browse / filter recent entries       | Discovery, audit, time-bound queries          |
| `create_memory`   | Insert a new entry                   | A new fact, decision, or preference appeared  |
| `edit_memory`     | Update an existing entry             | Existing entry is now stale or incomplete     |
| `delete_memory`   | Permanently remove an entry          | Entry is wrong, obsolete, or no longer wanted |

Tools the access mode disallows are **not registered**. If
`delete_memory` isn't in your tool list, deletion is disabled - don't
tell the user you'll delete and then fail. Treat the registered tool set
as the source of truth.

If the tools don't expose a `category` parameter, the server is running
in const-category mode (`--category`) and the category is fixed
server-side. Just omit it from your calls.

## Core workflow

1. **Recall before acting.** When the user asks about a topic that might
   have prior context, call `search_memories` *first*. See
   `references/recalling.md`.
2. **Act on what you find.** Use the recalled entries as ground truth
   for the current task. Cite them back to the user by
   `(category, key)` so they can verify.
3. **Remember what's worth keeping.** When a new decision, preference,
   or non-trivial fact emerges, call `create_memory` (or `edit_memory`
   if it already exists). See `references/remembering.md`.

Treat the store as a shared notebook between you and future agent
sessions. Optimise for the next session being able to find what you
wrote.

## Reference map

Load these only when relevant - they exist so this `SKILL.md` stays
small and the rest is pulled in on demand.

| File                          | Load when                                                                  |
| ----------------------------- | -------------------------------------------------------------------------- |
| `references/tools.md`         | You need the exact parameters or behaviour of any of the 6 tools.          |
| `references/remembering.md`   | About to save or update a memory and want to do it well.                   |
| `references/recalling.md`     | About to search or list memories, or first search returned nothing useful. |
| `references/conventions.md`   | Choosing a `category`, `key`, or `tags` for a new entry.                   |
| `references/setup.md`         | Helping a user install or configure Zakira in their MCP client.            |

## Quick reminders

- **Stable keys, mutable data.** Once you pick `(category, key)`, keep
  it. Update via `edit_memory`; don't delete-and-recreate.
- **Search is hybrid.** You don't need exact keyword overlap - write
  the query as the user would phrase the question.
- **Categories are namespaces.** Group related entries; don't dump
  everything into `general`.
- **Tags enable filtered recall.** Faceted tags (`topic:auth`,
  `scope:web`, `status:active`) beat ad-hoc free-text tags.
- **The store is shared.** Other agents and humans may also write to
  it. Don't assume entries you wrote yesterday are unchanged today -
  re-fetch with `get_memory` if you need the current value.
- **`tags` and `custom` are full replacements on edit.** To add a
  single tag, `get_memory` first, merge, then `edit_memory`.
