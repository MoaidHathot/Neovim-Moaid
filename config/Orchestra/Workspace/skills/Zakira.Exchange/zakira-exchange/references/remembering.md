# Remembering: when and how to save

Memory you don't write down might as well not exist. But noisy memory is
worse than no memory - it pollutes future search results and confuses
the next agent. Write deliberately.

## When to save

Save when **all** of these are true:

- The fact, decision, or preference is **non-obvious from the codebase
  or the immediate conversation**.
- It will plausibly matter in **a future session**, not just this one.
- A future agent searching for it would benefit from finding it.

Strong candidates:

- **Decisions with rationale.** "We use JWT with 15-minute access
  tokens because [reason]."
- **User or team preferences.** "User prefers Rust over Go for
  CPU-bound services."
- **Stable facts about the project or environment.** "The staging
  database lives at `<host>` and rotates credentials weekly."
- **Things learned the hard way.** "Migration X requires running Y
  first or it deadlocks."
- **Recurring answers.** Questions the user has asked before, or that
  another agent has already worked through.

Weak candidates (don't save unless asked):

- Anything trivially re-derivable from the code with one tool call.
- Transient state: today's plan, the next test to run, scratch math.
- Anything sensitive the user hasn't explicitly consented to persist.

If you're unsure, ask the user: "Want me to save this to Zakira so it
sticks around for next session?"

## How to write a good entry

### `data`

- **Self-contained.** A reader who hasn't seen the conversation should
  understand it.
- **Concise.** One short paragraph or a short bullet list. Long entries
  get scanned, not read.
- **Present tense for facts.** "Uses X" beats "We decided to use X."
- **Include the *why*** if the entry is a decision. Future agents will
  challenge it otherwise.

Bad:

> switched it

Good:

> Auth uses JWT with 15-minute access tokens and a 7-day refresh token
> rotated on each use. Chosen over sessions for stateless horizontal
> scaling; reviewed by the security team on 2026-04-12.

### `reason`

One sentence describing **why this entry exists**, not what it says.
Future agents use this to decide whether to keep, update, or retire it.

> Captured during architecture review so service-level decisions
> persist across agent sessions.

### `author`

Your agent identity. Useful values:

- A stable role name (`backend-architect`, `pr-reviewer`, `docs-bot`).
- A model + session identifier
  (`claude-opus-2026-06-07-abc123`) if you need traceability.
- A human handle if the user dictated the entry (`alice`).

`author` shows up in `list_memories` and `search_memories` filters and
is part of the embedding, so consistent author strings improve both
recall and audit.

### `tags`

See `conventions.md`. Prefer **faceted** tags (`topic:auth`,
`scope:web`, `status:active`) over ad-hoc keywords.

### `custom`

Free-form string-to-string JSON. Good for structured metadata you'll
never search on but want to keep alongside the entry:

```json
{ "reviewed_by": "team-lead", "sprint": "14", "ticket": "BACK-942" }
```

## Choosing `(category, key)`

`(category, key)` is the **primary identifier** - pick it as if you'll
need to type it from memory later.

- `category`: lowercase plural noun (`decisions`, `preferences`,
  `architecture`, `runbooks`).
- `key`: lowercase kebab-case noun phrase that names the concept
  (`auth-strategy`, `prefer-rust-for-perf`, `staging-db-rotation`).

Full naming guidance: `conventions.md`.

If you might already have an entry on this topic, **search first**
before assuming you need to create. Two near-duplicates is the failure
mode that ruins recall.

## Update vs create

- The key exists? `edit_memory` - only the fields you pass change.
- Replacing a wrong entry? `edit_memory`, not delete + create. Keeps
  the same key and the history of `modified` timestamps.
- The fact is truly obsolete and the new fact lives at a different key?
  `delete_memory` (if allowed) then `create_memory` with the right key.

## Editing carefully

`tags` and `custom` are **full replacements**, not merges. To add a tag:

1. `get_memory` to read the current entry.
2. Append your new tag to the existing comma-separated list.
3. `edit_memory` with the merged `tags` value.

Same pattern for `custom` - read, merge in your new keys, then edit. If
you skip the read, you will silently overwrite work the user or another
agent did.

## Multi-author hygiene

The store may be shared between agents and humans. Before overwriting
`data` on an existing entry:

1. `get_memory` to see the current value.
2. If you'd be discarding meaningful content, **append or merge**
   instead of overwriting.
3. Update `reason` to reflect the new state if the rationale changed.
4. Update `author` so the audit trail reflects who last touched it.

## Worked example: capturing an architecture decision

User says: "Let's standardise on Postgres for new services going forward
instead of MySQL. It's about the JSONB support and the team's
familiarity."

1. **Search first** to avoid duplicates:
   `search_memories(query="database choice for new services")`
2. If nothing relevant, create:

   ```
   create_memory(
     category = "decisions",
     key      = "default-rdbms-postgres",
     data     = "New services default to PostgreSQL. Chosen over MySQL for native JSONB support and existing team expertise. Existing MySQL services stay as-is until they need migration for other reasons.",
     author   = "backend-architect",
     reason   = "Standardising the default database keeps new services consistent and reduces operational surface area.",
     tags     = "topic:database,topic:standards,scope:backend,status:active",
     custom   = "{\"decided_on\":\"2026-06-07\",\"supersedes\":\"none\"}"
   )
   ```
3. Cite it back: "Saved as `decisions/default-rdbms-postgres`."
