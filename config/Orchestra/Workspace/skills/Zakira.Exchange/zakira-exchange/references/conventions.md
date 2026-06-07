# Naming conventions

Consistent naming makes recall reliable. The store is shared across
sessions and agents - your future self benefits from your present self
being disciplined.

## `category`

Treat categories as **namespaces** for related entries.

- Lowercase, kebab-case (`architecture-notes`, not `Architecture Notes`).
- Plural noun (`decisions`, not `decision`).
- Broad enough to hold many entries; narrow enough to filter usefully.

Suggested baseline categories for a typical engineering project:

| Category         | What goes here                                                    |
| ---------------- | ----------------------------------------------------------------- |
| `decisions`      | Architecture and policy decisions with rationale.                 |
| `preferences`    | User or team preferences (libraries, styles, patterns).           |
| `architecture`   | Stable facts about how the system is organised.                   |
| `runbooks`       | Step-by-step procedures for recurring operational tasks.          |
| `gotchas`        | Non-obvious failure modes and their workarounds.                  |
| `environment`    | Facts about staging/prod hosts, accounts, paths, credentials\*.   |
| `glossary`       | Project-specific terms and acronyms.                              |
| `recent-context` | Short-lived context the next session might want - prune often.    |

\* Only persist credentials the user has explicitly asked you to
remember. Treat anything that looks like a secret as opt-in.

Avoid `general`, `misc`, `notes` - they become tar pits where nothing
is findable.

If the server is in const-category mode (`--category <name>`), the
category is fixed and not part of the tool schema. Just omit it from
your calls.

## `key`

Keys are the **stable identifier** for an entry within its category.

- Lowercase, kebab-case.
- Noun phrase that names the concept, not a sentence.
- Stable: once chosen, don't rename. Update `data` via `edit_memory`.

Good keys:

- `auth-strategy`
- `prefer-rust-for-perf-paths`
- `staging-db-credential-rotation`
- `deploy-flow-blue-green`

Bad keys:

- `note1`, `decision`, `temp` - non-descriptive
- `2026-06-07-auth-notes` - timestamps belong in `created`, not the key
- `auth strategy` - spaces; not kebab-case
- `AuthStrategy` - uppercase

If the same concept gets discussed under different names, that's a
signal to settle on **one** key and `edit_memory` the canonical entry
rather than creating siblings.

## `tags`

Tags enable faceted filtering and improve embeddings.
Comma-separated, no surrounding whitespace.

Prefer **faceted** tags of the form `facet:value`:

- `topic:auth`, `topic:caching`, `topic:deployment`
- `scope:backend`, `scope:web`, `scope:infra`
- `status:active`, `status:deprecated`, `status:experimental`
- `audience:agent`, `audience:human`

You can mix faceted and plain tags, but pick a facet and stick with it
across entries in the same category. `topic:auth` in one entry and
`auth` in another breaks filtered queries.

A useful starter facet set:

| Facet      | Common values                                  |
| ---------- | ---------------------------------------------- |
| `topic:`   | `auth`, `caching`, `database`, `deployment`... |
| `scope:`   | `backend`, `web`, `infra`, `mobile`, `docs`    |
| `status:`  | `active`, `deprecated`, `experimental`, `wip`  |
| `priority:`| `p0`, `p1`, `p2`                               |
| `audience:`| `agent`, `human`, `both`                       |

## `author`

Use a **stable identifier** for whoever wrote the entry:

- Agent role: `backend-architect`, `pr-reviewer`, `docs-bot`.
- Model + run: `claude-opus-<session-id>` if you need traceability.
- Human handle: the user's name when they dictated the entry.

Don't use ephemeral strings (timestamps, random ids) - they break
`author` filtering and waste embedding signal.

## `reason`

One sentence answering "why does this entry exist?", not "what does it
say?".

Good: `"Captured during sprint 14 retrospective so the next on-call
has the deploy rollback steps."`

Bad: `"How to rollback a deploy."` (that's the data, not the reason)

## `custom`

A JSON object of string-to-string metadata. Use it for:

- External identifiers: `{ "jira": "BACK-942", "rfc": "0017" }`
- Provenance: `{ "source": "rfc-doc", "reviewed_by": "alice" }`
- Lifecycle markers:
  `{ "expires": "2026-12-31", "supersedes": "auth-v1" }`

Keep keys lowercase, kebab-case or snake_case (pick one across the
store), and stable - the same field name should mean the same thing
across entries.

## Multi-project setups

If one Zakira database is shared across projects, prefix categories:

- `acme-decisions`, `acme-architecture`, `acme-runbooks`
- `beta-decisions`, `beta-architecture`, ...

Or run a separate database per project (`--database-path
./project-name.db`) - see `setup.md`. The const-category mode
(`--category acme-decisions`) is good for restricting an agent to a
single namespace it can't accidentally escape.

## A quick checklist before saving

- [ ] Is the `category` an existing, plural, lowercase namespace - or
      do you genuinely need a new one?
- [ ] Is the `key` a kebab-case noun phrase that you'll remember?
- [ ] Did you `search_memories` for this concept first to avoid a
      duplicate?
- [ ] Does `data` stand on its own without the surrounding chat?
- [ ] Does `reason` explain why the entry exists (not just what it says)?
- [ ] Are the `tags` faceted (`facet:value`) where appropriate?
- [ ] Is `author` a stable identifier you'd use again?
