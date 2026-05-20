---
name: zakira-conduit
description: Use, configure, and troubleshoot Zakira.Conduit - the .NET 10 global CLI tool that mirrors agent skills from GitHub repositories or local directories into one or more target folders via a conduit.json manifest. Activate when the user mentions conduit, conduit.json, .conduit-state.json, syncing or mirroring agent skills, pinning a commit / branch, or runs commands such as `conduit sync`, `conduit list`, `conduit status`, `conduit pin`, `conduit update`, `conduit watch`, `conduit init`, or `conduit validate`.
license: MIT
metadata:
  project: Zakira.Conduit
  repository: https://github.com/MoaidHathot/Zakira.Conduit
  version: "0.1"
---

# Using Zakira.Conduit

`conduit` is a .NET 10 global tool that **mirrors agent skills** from remote (GitHub) or local sources into one or more target directories on disk, driven by a single declarative `conduit.json` manifest.

Use this skill whenever the user:

- mentions `conduit`, `conduit.json`, `.conduit-state.json`, or "mirror skills"
- asks to add, remove, or modify a skill source
- wants to pin a branch to a commit SHA, refresh a pinned commit, or otherwise reproduce a sync
- runs any `conduit ...` subcommand and asks for help interpreting the output
- describes the goal "I want X skill in folder Y" where X is hosted on GitHub or lives in a directory

If none of those apply, this skill is probably not the right context &mdash; don't read further.

## Mental model

A **manifest** (`conduit.json`) contains a list of **entries**. Each entry has:

- a `name` &mdash; an identifier; usually becomes the destination subdirectory name
- one `source` &mdash; either `type: "github"` (download a zipball over HTTPS) or `type: "local"` (mirror a directory on disk)
- one or more `targets` &mdash; directories on disk to mirror into

`conduit sync` walks every enabled entry, fetches the source, and atomically mirrors it into each target's `<entry-name>/` subdirectory. A sibling `.conduit-state.json` records what was synced so the next run can skip unchanged entries (commit-pinned GitHub entries skip without network; branch-tracked use HTTP `If-None-Match`; local sources use a content fingerprint).

## Discovery: where is the manifest?

If the user doesn't pass `--manifest`, conduit searches these locations in order and uses the first that exists:

1. `$XDG_CONFIG_HOME/Zakira.Conduit/conduit.json`
2. `$HOME/.config/Zakira.Conduit/conduit.json`
3. `./conduit.json` in the current directory

The same XDG-style resolution is used on every OS, including Windows. When asked "where is my manifest?", run `conduit validate` &mdash; it prints the resolved path on success and the candidates it searched on failure.

## Commands at a glance

| Verb | What it does | When to use |
|---|---|---|
| `conduit init [-i]` | Write a starter `conduit.json`. `-i` walks through prompts. | First-time setup. |
| `conduit validate` | Parse + validate the manifest. No network. | Anywhere there's doubt. |
| `conduit list` | Print the configured entries (text or JSON). | "What's currently configured?" |
| `conduit status` | Per-entry: last SHA, last sync time, target presence (no network). | "What is currently synced?" |
| `conduit sync` | Fetch + mirror. Default parallel, default cached. | The main action. |
| `conduit pin` | Resolve every branch-tracked entry to its current SHA and rewrite `commit`. | "Lock to today's tip." |
| `conduit update` | Alias for `pin` (refresh-flavoured verb). | "Bump the pinned versions." |
| `conduit watch` | Initial sync + re-sync on every manifest change. Ctrl+C to stop. | While editing the manifest iteratively. |

Every command accepts:
- `-m, --manifest <path>` &mdash; override discovery
- `-o, --output text|json` &mdash; JSON is stdout-clean for piping into `jq`
- `--verbose` / `--quiet`

`conduit sync` additionally accepts:
- `--entry <name>` (repeatable) &mdash; restrict to specific entries
- `--dry-run` &mdash; preview without writing
- `--stop-on-first-error`
- `--force` &mdash; ignore the cached state, refetch everything
- `--parallel N` &mdash; default 4

## Step-by-step workflows

### A. "Add a new GitHub skill source"

1. Ask whether they want to mirror the **whole repo** or a **sub-path**.
2. Ask which target directories (their agent reads from).
3. Ask whether to pin (`branch:` only = tracks; add `commit:` = locked).
4. Open the manifest at the discovered location (run `conduit validate` to find it).
5. Add a new entry of the form:

   ```jsonc
   {
     "name": "the-skill-name",
     "source": {
       "type": "github",
       "repo": "owner/repo",              // also accepts the full https://github.com/... URL
       "path": "sub/path",                // optional; omit to mirror the whole repo
       "branch": "main"                   // optional; the default branch is used otherwise
     },
     "targets": ["~/.config/agents/skills"]
   }
   ```

6. Run `conduit validate` to confirm.
7. Run `conduit sync --dry-run --entry the-skill-name` to preview.
8. Run `conduit sync --entry the-skill-name` to commit.

### B. "Mirror a local directory into my agent folders"

```jsonc
{
  "name": "house-style",
  "source": { "type": "local", "path": "./vendor/skills/house-style" },
  "targets": [
    "~/.config/claude/skills",
    "~/projects/foo/.agents/skills"
  ]
}
```

Local paths can be absolute or relative to the manifest's directory, and accept `~`, `$VAR`, `${VAR}`, and `%VAR%` (Windows). A subsequent `conduit sync` for an unchanged local source is a no-op &mdash; conduit fingerprints the source contents and skips when nothing changed.

### C. "Pull several skills out of one repo with one fetch"

Use the plural `paths` array. With two or more elements, each path becomes its own destination subdirectory (`<target>/<basename>/`) and the entry's `name` becomes metadata only:

```jsonc
{
  "name": "anthropic-bundle",
  "source": {
    "type": "github",
    "repo": "anthropics/skills",
    "paths": ["code-review", "test-writer", "refactor"],
    "branch": "main"
  },
  "targets": ["~/.config/claude/skills"]
}
```

Result: `~/.config/claude/skills/{code-review, test-writer, refactor}/`.

### D. "Lock today's versions and bump them later"

```bash
# Lock every branch-tracked entry to its current SHA.
conduit pin

# Preview before commit:
conduit pin --dry-run

# Later, bump every pin to the new tip on its tracked branch:
conduit update
```

Both commands keep `branch` in the manifest as the tracking intent, and they back up the original file as `<manifest>.bak` before writing. Comments and trailing commas in the source manifest are lost on rewrite &mdash; warn the user before running these on a hand-formatted file.

### E. "Why didn't sync do anything?"

Almost always the cache. Check, in order:

1. `conduit status` &mdash; shows the recorded SHA / last sync time per entry, and whether targets are still on disk.
2. If `status` reports `synced` and `allTargetsPresent` is true, that entry is up-to-date and will skip.
3. To force a full re-fetch: `conduit sync --force` (or limit to one entry with `--force --entry NAME`).
4. To wipe the cache entirely, delete `.conduit-state.json` next to the manifest.

If `status` reports `targets drifted`, a target directory was removed manually &mdash; the next normal `conduit sync` will re-mirror it.

## Editing the manifest safely

- The CLI's `pin`, `update`, `init --force` write `<manifest>.bak` next to the file before mutating. If a rewrite goes wrong, `cp conduit.json.bak conduit.json` restores.
- The manifest accepts JSON comments (`//`, `/* */`) and trailing commas at load time. They are **not** preserved across `pin`/`update`. Suggest the user version-control the manifest if they care about formatting.
- `commit:` and `branch:` may coexist. When both are set, `commit` wins for fetching; `branch` is the refresh intent that `update` reads.
- `targets` and `paths` items can each be either a bare string or an object with `path` and optional `as:` rename. Per-target aliases are rejected when an entry produces multiple content units (the per-path basename mapping would silently override).

## Privacy & auth

- Private repos and higher rate limits need a token. Read from `CONDUIT_GITHUB_TOKEN`, falling back to `GITHUB_TOKEN`. Set it in the user's shell before suggesting `conduit sync`. Never paste or log the token.
- The token is only sent to the configured GitHub API base (default `api.github.com`) and is not persisted by conduit.

## Reference material

This skill ships extra files. Load them when the question requires more detail:

- `references/manifest.md` &mdash; full field-by-field reference for `conduit.json` (every property, validation rule, and accepted shape).
- `references/commands.md` &mdash; full reference for every CLI command, flag, and exit code.
- `assets/minimal-conduit.json` &mdash; smallest valid manifest, ready to copy.
- `assets/multi-source-conduit.json` &mdash; manifest demonstrating GitHub + local + multi-path + per-target alias.

## Hard rules

- **Never** invent commands that don't exist. The canonical command set is exactly the rows in the table above.
- **Never** suggest manually editing `.conduit-state.json`. Use `--force` or delete it instead.
- **Never** instruct the user to push the API token into the manifest. Tokens live in the environment only.
- When in doubt about the resolved manifest path or what an entry will do, run `conduit validate` and `conduit list` first &mdash; both are read-only and fast.
