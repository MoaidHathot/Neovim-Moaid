---
name: zakira-conduit
description: Use, configure, and troubleshoot Zakira.Conduit - the .NET 10 global CLI tool that mirrors agent skills from GitHub, Azure DevOps, or local directories into one or more target folders via a conduit.json (or conduit.jsonc) manifest. Activate when the user mentions conduit, conduit.json, conduit.jsonc, .conduit-state.json, syncing or mirroring agent skills, pinning a commit, unpinning to restore branch tracking, the in-string `-> Name` alias or `{source, as}` wrapper, include/exclude globs, the orphan cleaner, or runs commands such as `conduit sync`, `conduit list`, `conduit status`, `conduit pin`, `conduit update`, `conduit unpin`, `conduit clean`, `conduit watch`, `conduit init`, or `conduit validate`.
license: MIT
metadata:
  project: Zakira.Conduit
  repository: https://github.com/MoaidHathot/Zakira.Conduit
  version: "0.2"
---

# Using Zakira.Conduit

`conduit` is a .NET 10 global tool that **mirrors agent skills** (and any other vendored folder content) from remote sources &mdash; **GitHub**, **Azure DevOps**, or **local directories** &mdash; into one or more target directories on disk, driven by a single declarative `conduit.json` (or `conduit.jsonc`) manifest.

Use this skill whenever the user:

- mentions `conduit`, `conduit.json`, `conduit.jsonc`, `.conduit-state.json`, or "mirror skills"
- asks to add, remove, rename, or modify a skill source
- wants to **pin** an entry to a specific commit, **unpin** back to branch tracking, or refresh a pinned commit (`update`)
- asks about the in-string `-> Name` alias or the `{source, as}` wrapper
- asks about include/exclude globs that filter what gets mirrored
- wants to clean up orphan destination directories (`conduit clean`, `sync --prune`)
- runs any `conduit ...` subcommand and asks for help interpreting the output

If none of those apply, this skill is probably not the right context &mdash; don't read further.

## Mental model

A **manifest** (`conduit.json` or `conduit.jsonc`) contains a list of **entries**. Each entry has:

- an optional `name` &mdash; identifier and destination subdirectory name (for the default `wrap` strategy). When omitted, Conduit derives one from the source (GitHub/AzDO repo name, local dir basename).
- one `source` &mdash; either a discriminator-shaped object (`{type: "github" | "azdo" | "local" | "uri", ...}`), a **bare URL string** (which is inferred to the right kind), or an **array** of any of the above (each element becomes its own sub-entry sharing the parent's targets).
- one or more `targets` &mdash; directories on disk to mirror into.
- an optional `strategy` &mdash; one of `wrap` (default, places content under `<target>/<name>/`), `flat` (merges content into `<target>/`), `expand` (lifts each top-level child of the source to its own sub-directory), or `skills` (discovers `SKILL.md` folders and fans them out across detected agent harnesses under each target). See `references/manifest.md` "Strategies".
- optional `groupBy: "source"` &mdash; composes with every strategy to wrap each source's output in a source-named sub-directory.
- optional `onCollision: error|skip|last-wins` &mdash; controls behaviour when two destinations resolve to the same path.

`conduit sync` walks every enabled entry, fetches the source, dispatches to the entry's strategy to plan one or more `(source, target)` mirror operations, then atomically writes each one. A sibling `.conduit-state.json` records what was synced so the next run can skip unchanged entries (commit-pinned entries skip without network when the strategy is the default `wrap`; branch-tracked entries use HTTP `If-None-Match`; local sources use a content fingerprint).

## Discovery: where is the manifest?

If the user doesn't pass `--manifest`, conduit probes these locations in order and uses the first existing file. At each location both extensions are tried, `.json` first:

1. `$XDG_CONFIG_HOME/Zakira.Conduit/conduit.{json,jsonc}`
2. `$HOME/.config/Zakira.Conduit/conduit.{json,jsonc}`
3. `./conduit.{json,jsonc}` (current working directory)

The same XDG-style resolution is used on every OS, including Windows. To find the resolved path, run `conduit validate`; it prints the path on success and the candidates it searched on failure.

The manifest is parsed as JSONC: line comments (`// ...`), block comments (`/* ... */`), and trailing commas are accepted regardless of file extension.

## Commands at a glance

| Verb | What it does | When to use |
|---|---|---|
| `conduit init [-i]` | Write a starter manifest. `-i` walks through prompts. | First-time setup. |
| `conduit validate` | Parse + validate the manifest. No network. | Anywhere there's doubt. |
| `conduit list` | Print the configured entries (text or JSON). | "What's currently configured?" |
| `conduit status` | Per-entry: last SHA, last sync time, target presence (no network). | "What is currently synced?" |
| `conduit sync` | Fetch + mirror. Default parallel, default cached. | The main action. |
| `conduit pin` | Lock each entry to a specific commit by rewriting its source URL to the pinned form. | "Lock to today's tip." |
| `conduit update` | Alias of `pin`. | "Bump the pinned versions." |
| `conduit unpin` | Restore branch tracking on pinned entries. Inverse of `pin`. | "Thaw so I can re-sync against current HEAD." |
| `conduit clean` | Remove destination directories whose owning entry has been deleted from the manifest. | "Tidy up after I removed entries." |
| `conduit watch` | Initial sync + re-sync on every manifest change. Ctrl+C to stop. | While editing the manifest iteratively. |
| `conduit copy <src> <dst>` | One-shot mirror with optional `--strategy`. Bypasses the manifest. | Scripting, ad-hoc installs, strategy previews. |
| `conduit skills probe <target>` | Scan a target for known agent harness layouts. | "Where would skills go if I targeted this dir?" |

Every command accepts:
- `-m, --manifest <path>` &mdash; override discovery
- `-o, --output text|json` &mdash; JSON is stdout-clean for piping into `jq`
- `--verbose` / `--quiet`

`conduit sync` additionally accepts:
- `--entry <name>` &mdash; restrict to specific entries. Repeatable, **and** comma-separated (`--entry a,b -e c`).
- `--dry-run` &mdash; preview without writing
- `--stop-on-first-error`
- `--force` &mdash; ignore the cached state, refetch everything
- `--parallel N` &mdash; default 4
- `--prune` &mdash; after a successful sync, run the orphan cleaner. Pair with `--prune-yes` (or `--yes`) in non-interactive sessions.

## Step-by-step workflows

### A. "Add a new GitHub skill source"

1. Ask whether they want to mirror the **whole repo** or a **sub-path**, and which target directories the agent reads from.
2. Open the manifest at the discovered location (run `conduit validate` to find it).
3. Add a new entry. The simplest form is a bare URL (Conduit derives the entry name from the repo):

   ```jsonc
   {
     "source": "https://github.com/owner/repo/sub/path",
     "targets": ["~/.config/agents/skills"]
   }
   ```

   The `/sub/path` is optional &mdash; omit it to mirror the whole repo. To track a specific branch, append `/tree/<branch>` before the sub-path: `https://github.com/owner/repo/tree/develop/sub/path`. To override the auto-derived name, append ` -> MyName` or use the wrapper form `{ "source": "...", "as": "MyName" }`.

   The explicit object form is also fine, especially when you need to pin or set include/exclude:

   ```jsonc
   {
     "name": "the-skill-name",
     "source": {
       "type": "github",
       "repo": "owner/repo",
       "path": "sub/path",
       "branch": "main",
       "include": ["**/*.md", "scripts/**"],
       "exclude": ["**/*.test.*"]
     },
     "targets": ["~/.config/agents/skills"]
   }
   ```

4. Run `conduit validate` to confirm.
5. Run `conduit sync --dry-run --entry the-skill-name` to preview.
6. Run `conduit sync --entry the-skill-name` to commit.

### B. "Mirror an Azure DevOps repository"

```jsonc
{
  "name": "internal-runbooks",
  "source": {
    "type": "azdo",
    "url": "https://dev.azure.com/contoso/Conduit/_git/agent-skills",
    "branch": "main",
    "path": "skills"
  },
  "targets": ["~/.config/agents/skills"]
}
```

Or, equivalently, the URL form (Conduit infers the kind):

```jsonc
{
  "source": "https://dev.azure.com/contoso/Conduit/_git/agent-skills?path=/skills&version=GBmain",
  "targets": ["~/.config/agents/skills"]
}
```

AzDO auth uses an ordered chain (default `[env, az]`): the `env` provider reads `CONDUIT_AZDO_TOKEN` -> `AZURE_DEVOPS_EXT_PAT` -> `SYSTEM_ACCESSTOKEN`; the `az` provider shells out to the Azure CLI. Override with `"auth": ["pat", "anonymous"]` etc.

### C. "Mirror a local directory into my agent folders"

```jsonc
{
  "source": "./vendor/skills/house-style",
  "targets": [
    "~/.config/claude/skills",
    "~/projects/foo/.agents/skills"
  ]
}
```

Local paths can be absolute or relative to the manifest's directory, and accept `~`, `$VAR`, `${VAR}`, and `%VAR%` (Windows). A subsequent `conduit sync` for an unchanged local source is a no-op &mdash; conduit fingerprints the source contents and skips when nothing changed.

### D. "Pull several skills out of one repo with one fetch"

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

### E. "Mirror several different repos in one entry"

Give the entry an **array** source. Each element becomes its own sub-entry sharing the parent's targets; if you omit the entry-level `name`, the destination folder is derived from each element's repo name:

```jsonc
{
  "source": [
    "https://github.com/MoaidHathot/ActionView/skills",
    "https://github.com/MoaidHathot/PowerReview/skills",
    "./vendor/house-style -> HouseStyle"
  ],
  "targets": ["~/.config/claude/skills"]
}
```

Result: `~/.config/claude/skills/{ActionView, PowerReview, HouseStyle}/`.

### F. "Lock today's versions; bump them later"

```bash
# Lock every entry to its current SHA. URL-native: GitHub becomes
# /tree/<sha>/<path>, AzDO becomes ?version=GC<sha>.
conduit pin

# Preview before commit:
conduit pin --dry-run

# Later, restore branch tracking on every pinned entry first, then re-pin:
conduit unpin            # default behavior queries the repo's default branch
                         # (falls back to 'main' if discovery fails)
conduit unpin --to main  # skip discovery; use a literal branch name
conduit pin              # re-lock to current tips
```

`pin` is one-way; an already-pinned entry is skipped by `pin`/`update` with a pointer at `unpin`. This is deliberate so the user's branch choice is never silently lost on a refresh.

Comments and trailing commas in the manifest are **preserved** by `pin`/`unpin`/`update` when every touched entry has a string-shaped source on disk (URL rewrite, leaf-level edit only). They are **not** preserved when an entry needs an object-key insertion/removal (e.g. dropping `branch` on an object-form pin); the write falls back to a full reformat in that case.

### G. "Filter what gets mirrored from a source"

Use `include` / `exclude` glob lists on any source kind:

```jsonc
{
  "source": {
    "type": "github",
    "repo": "owner/repo",
    "include": ["**/*.md", "scripts/**"],
    "exclude": ["**/*.test.*", "bin/**"]
  },
  "targets": ["./out"]
}
```

Patterns use `Microsoft.Extensions.FileSystemGlobbing` syntax (`*`, `**`, `?`, character classes). A path is mirrored when it matches at least one `include` (or `include` is empty/omitted) and zero `exclude` patterns.

### H. "Clean up after I removed an entry"

```bash
# Show what would be removed (dry-run is the default behavior preview).
conduit clean --dry-run

# Actually remove. Prompts for confirmation when stdin is a TTY; pass --yes to
# skip the prompt (required for JSON output or CI sessions).
conduit clean --yes

# Or combine cleanup with sync:
conduit sync --prune --prune-yes
```

Orphan = a destination directory recorded in state whose owning entry no longer exists in the manifest. Live entries' targets are never touched (cross-checked before deletion).

### I. "Why didn't sync do anything?"

Almost always the cache. Check, in order:

1. `conduit status` &mdash; shows the recorded SHA / last sync time per entry, and whether targets are still on disk.
2. If `status` reports `synced` and `allTargetsPresent` is true, that entry is up-to-date and will skip.
3. To force a full re-fetch: `conduit sync --force` (or limit to one entry with `--force --entry NAME`).
4. To wipe the cache entirely, delete `.conduit-state.json` next to the manifest.

If `status` reports `targets drifted`, a target directory was removed manually &mdash; the next normal `conduit sync` will re-mirror it.

## Editing the manifest safely

- `pin`, `unpin`, `update`, and `init --force` write `<manifest>.bak` next to the file before mutating. If a rewrite goes wrong, `cp conduit.json.bak conduit.json` restores.
- JSONC trivia (comments, trailing commas) survives `pin`/`unpin`/`update` when every touched entry has a string-shaped source; otherwise the full-reformat path strips comments.
- Object form `branch` and `commit` no longer coexist after `pin`. Pin sets `commit` and removes `branch`; `unpin` does the opposite. To track a branch AND record its current SHA simultaneously, write both fields manually (the loader still accepts the duality, but `pin`/`unpin` enforce the URL-native model on write).
- `targets` and `paths` items can each be either a bare string or an object with `path` and optional `as:` rename. Per-target aliases are rejected when an entry produces multiple content units (the per-path basename mapping would silently override).
- **Cross-entry destination uniqueness** is enforced at validation time: two entries can't both write into the same `<target>/<destName>/` directory. Rename one (set `name` or per-target `as:`) to disambiguate.

## Privacy & auth

- **GitHub**: auth uses an ordered chain (default `[env, gh, anonymous]`):
  - `env` reads `CONDUIT_GITHUB_TOKEN` -> `GITHUB_TOKEN` -> `GH_TOKEN`, first non-empty.
  - `gh` shells out to `gh auth token` (`gh` CLI) and caches the token in-process for ~10 minutes.
  - `pat` reads from the env var named by `patEnv` on the source (default `CONDUIT_GITHUB_TOKEN`).
  - `anonymous` proceeds without an `Authorization` header.
  Override per-entry with `"auth": ["env", "anonymous"]` or `"auth": "pat"`.
- **AzDO**: see workflow B above. Default chain `[env, az]`.
- Tokens are sent only to their respective API hosts. Conduit never persists them.

## Reference material

This skill ships extra files. Load them when the question requires more detail:

- `references/manifest.md` &mdash; full field-by-field reference for the manifest (every property, validation rule, accepted shape).
- `references/commands.md` &mdash; full reference for every CLI command, flag, and exit code.
- `assets/minimal-conduit.json` &mdash; smallest valid manifest, ready to copy.
- `assets/multi-source-conduit.json` &mdash; manifest demonstrating multiple source kinds, an array source, aliases, include/exclude, and per-target rename.

## Hard rules

- **Never** invent commands that don't exist. The canonical command set is exactly the rows in the table above.
- **Never** suggest manually editing `.conduit-state.json`. Use `--force` or delete it instead.
- **Never** instruct the user to push the API token into the manifest. Tokens live in the environment only.
- **Never** suggest a custom in-string suffix beyond ` -> Name` (alias). Pin uses GitHub-native `/tree/<sha>/<path>` URLs and AzDO-native `?version=GC<sha>` query strings; there is no conduit-specific pin syntax.
- When in doubt about the resolved manifest path or what an entry will do, run `conduit validate` and `conduit list` first &mdash; both are read-only and fast.
