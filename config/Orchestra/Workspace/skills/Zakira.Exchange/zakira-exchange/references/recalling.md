# Recalling: when and how to retrieve

The cost of a missed recall is high - you'll re-derive things the
previous session already figured out, or contradict a decision you
weren't aware of. The cost of a search call is low. Err on the side of
searching.

## When to search

Search at the **start** of a task whenever any of these holds:

- The user's request mentions a topic that might already have history
  ("the auth flow", "our caching strategy", "what we decided about X").
- The user uses a definite article ("the staging DB", "the deploy
  script") that implies pre-existing context.
- You're about to make a decision - verify there isn't already one on
  record before contradicting it.
- The user asks "did we...", "have we...", "do we still..." - these
  are direct recall prompts.
- You're entering a topic area you haven't seen this session.

Search again mid-task whenever the topic shifts.

## Which tool to use

| You know...                                | Use                                       |
| ------------------------------------------ | ----------------------------------------- |
| The exact `(category, key)`                | `get_memory`                              |
| A topic or question, not the key           | `search_memories`                         |
| A category and want to browse              | `list_memories`                           |
| What was changed recently                  | `list_memories` with `before` / `after`   |
| Everything an author has written           | `list_memories --author <name>`           |

When in doubt, **start with `search_memories`** - it's the cheapest
path to "is there anything on this topic?"

## Writing good search queries

Zakira's search is hybrid: BM25 keyword + cosine similarity over
sentence-level embeddings (`all-MiniLM-L6-v2`), merged with Reciprocal
Rank Fusion (k=60). Two implications:

1. **Exact keyword matches still help.** If you know a domain term the
   entry likely uses, include it.
2. **Natural-language phrasing also works.** A query like
   `"how do we authenticate users"` will find an entry titled
   `auth-strategy` even without literal overlap.

Write queries as **questions or noun phrases**, not single words:

- Good: `"caching strategy for the product catalog"`
- Good: `"how do we handle token rotation"`
- Good: `"decision about database choice"`
- Weak: `"cache"`
- Weak: `"auth"`

Single words have too many false neighbours in vector space and too
many BM25 hits to be useful.

## If the first search misses

A missed search doesn't mean the memory isn't there. Try in order:

1. **Rephrase** with synonyms or the user's exact wording.
2. **Broaden**: drop tag or category filters; raise `top` to 20-30.
3. **Browse** via `list_memories` (top 50, optionally filtered by
   likely category) to skim recent entries - sometimes the right key
   is obvious as soon as you see it.
4. **Check sibling categories** if you suspect the entry was filed
   somewhere unexpected.

Only conclude "not stored" after at least one rephrasing.

## Reading results well

`search_memories` returns entries ordered by fused score. Higher score
is better but the absolute number isn't comparable across queries.

- **Top 1-3 are usually relevant.** If they obviously aren't, the
  topic probably isn't in the store.
- **Look at `(category, key)` first.** A well-named key tells you more
  than the data snippet.
- **Read `reason`** if present - it tells you whether the entry is
  still authoritative or was captured for historical context.
- **Check `modified`.** A stale-looking entry might have been
  superseded; if in doubt, search for newer entries with overlapping
  terms.

## Citing memories back to the user

When acting on a recalled memory, mention it by `(category, key)`:

> "Per `decisions/auth-strategy`, we use 15-minute JWTs with rotation.
> I'll reuse that pattern for the new admin API."

This lets the user verify what you found and lets future agents follow
your reasoning if they search for the same topic later.

## Filters: scoping vs discovery

Use filters to **scope**, not to discover:

- `author`: when the user asks "what has Alice decided".
- `tags`: when you want a faceted slice ("everything tagged
  `topic:security`").
- `before` / `after` (`list_memories` only): when the user references
  time ("last sprint", "after the migration").

Don't add filters to a discovery search - they hide entries that might
be relevant under a different categorisation. Start broad, narrow only
when results are noisy.

## Worked example: starting a task with possible history

User says: "Add an admin-only endpoint for resetting user passwords."

1. **Search for relevant prior context:**
   - `search_memories(query="how do we authenticate admin users")`
   - `search_memories(query="password reset flow")`
   - `search_memories(query="admin endpoint conventions")`
2. **Browse the obvious category:**
   - `list_memories(category="decisions", top=20)`
3. **Read top hits.** Look at each entry's `key`, `reason`, and
   `modified` timestamp. If you find e.g.
   `decisions/admin-auth-requires-mfa`, that constrains your
   implementation.
4. **Cite what you used** before proposing the implementation.
5. **At the end**, if you made a new decision (e.g. "admin password
   reset issues a one-time link instead of setting a temp password"),
   capture it with `create_memory`. See `remembering.md`.
