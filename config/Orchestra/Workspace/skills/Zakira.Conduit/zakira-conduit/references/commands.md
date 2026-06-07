# Command reference

Every `conduit` subcommand with its full surface area.

## Global options

These work on every subcommand:

| Option | Description |
|---|---|
| `-m, --manifest <path>` | Override manifest discovery. Path is absolute or relative to the current directory. |
| `-o, --output text\|json` | Output format. `text` is human-friendly (default). `json` emits machine-readable JSON on stdout; logs are still routed to stderr so `... \| jq` works. |
| `--verbosity q\|m\|n\|d\|diag` | Verbosity level. Default `minimal` (warnings + errors only). Use `n[ormal]` to see per-entry operational logs, `d[etailed]` for wire-level debug. |
| `-v, --verbose` | Shortcut for `--verbosity detailed`. |
| `-q, --quiet` | Shortcut for `--verbosity quiet` (errors only). |

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success. |
| `1` | One or more entries failed during `sync`/`pin`/`unpin`/`update`, or `clean` failed to delete an orphan directory. |
| `2` | Manifest could not be located, parsed, or validated. |

## `conduit init`

Create a starter `conduit.json` at the discovered location (or at `--manifest`).

| Option | Description |
|---|---|
| `-f, --force` | Overwrite an existing manifest if one is present at the target path. |
| `-i, --interactive` | Walk through prompts to populate the first entry. Requires an attached TTY (refuses to run when stdin / stdout are redirected). |

JSON output on success: `{ "ok": true, "manifest": "...", "created": true, "forced": false, "interactive": false }`.
JSON output on failure: `{ "ok": false, "manifest": "...", "error": "..." }`.

## `conduit validate`

Parse and validate the manifest. No network IO. Useful as a CI step.

JSON output on success: `{ "ok": true, "manifest": "...", "version": 1, "entries": <count>, "errors": [] }`.
JSON output on failure: `{ "ok": false, "manifest": "...", "error": "...", "details": ["..."] }`.

## `conduit list`

Print every entry in the manifest with its source summary and targets.

JSON output shape: `{ "manifest": "...", "version": 1, "entries": [ /* full ConduitEntry objects */ ] }`.

## `conduit status`

Read the manifest and its sibling `.conduit-state.json` and report, per entry: the last resolved ref, the last sync timestamp, ETag, source content hash, and target presence on disk. No network IO.

A label is printed per entry:

- `synced` &mdash; state present and every recorded target still exists
- `targets drifted` &mdash; state present but at least one recorded target is missing
- `never synced` &mdash; no state recorded for this entry yet
- `disabled` &mdash; the entry's `disabled: true` flag is set

## `conduit sync`

Fetch every selected source and atomically mirror it into each target.

| Option | Description |
|---|---|
| `--entry <name>` | Restrict the run to specific entries. Repeatable, **and** comma-separated values are accepted (`--entry a,b -e c`). |
| `--dry-run` | Fetch + report what would change. No targets are written, no state is updated. |
| `--stop-on-first-error` | Abort on the first failure (otherwise the remaining entries are still attempted). |
| `-f, --force` | Ignore the state cache and re-fetch + re-mirror every entry. |
| `-p, --parallel <N>` | Maximum entries processed concurrently. Default `4`. Use `1` to force sequential execution. |
| `--prune` | After a successful sync, run the orphan cleaner (same as `conduit clean`). Pair with `--prune-yes` (or `--yes`) for non-interactive sessions. |
| `--prune-yes` | Skip the cleanup confirmation prompt that `--prune` would otherwise show. Required for `--prune` in non-interactive sessions. |

### How sync decides to skip an entry

Before fetching, the synchronizer asks the state store whether the entry is provably up-to-date:

- **Commit-pinned GitHub / AzDO entries:** state's recorded ref equals the entry's `commit` AND every recorded target directory still exists -> skip without any network call.
- **Local sources:** a fingerprint of `(relative path, size, last-write-time)` of every file under the source matches the recorded hash AND every recorded target directory still exists -> skip without copying anything.
- **Branch-tracked GitHub entries:** can't skip without consulting GitHub, so the fetcher sends `If-None-Match` against the state's ETag. A 304 short-circuits the mirror.

`--force` bypasses all of these. Removing `.conduit-state.json` also achieves this.

### Include/exclude filtering

Every source kind accepts optional `include` and `exclude` glob lists. Patterns use `Microsoft.Extensions.FileSystemGlobbing` syntax (`*`, `**`, `?`, character classes). A path is mirrored when it matches at least one `include` (or `include` is empty/omitted) and zero `exclude` patterns. Filtering happens at mirror time; dirs that end up empty are not created.

## `conduit pin` / `conduit update`

Lock each GitHub or AzDO entry to a specific commit SHA by rewriting its source to the URL-native pinned form:

- GitHub: `…/repo` (or `…/repo/tree/<branch>/…`) becomes `…/repo/tree/<sha>/…`.
- AzDO: `?version=GBmain` becomes `?version=GC<sha>` (or `?version=GC<sha>` is appended when no `version` was set).
- Object form: `commit` is set, `branch` (and `tag`) are removed.

For entries without an explicit branch, pin discovers the repo's default branch via the GitHub/AzDO API (one extra request per repo, cached per run). Already-pinned entries are skipped with a pointer at `conduit unpin`; pin is intentionally one-way so the user's branch choice is never silently lost.

`pin` and `update` are functional aliases; pick whichever reads better in context.

| Option | Description |
|---|---|
| `--entry <name>` | Limit to specific entries. Repeatable, comma-separated values accepted. |
| `--dry-run` | Report what would change without rewriting the manifest. |

The pre-update manifest is backed up at `<manifest>.bak`. JSONC trivia (comments, trailing commas) is preserved when every touched entry has a string-shaped source on disk (URL rewrite, leaf-level edit only); falls back to a full reformat that loses trivia when at least one entry needs object-key insertion/removal.

## `conduit unpin`

Inverse of `pin`. Restores branch tracking by rewriting `tree/<sha>/<path>` back to `tree/<branch>/<path>` (GitHub) or `?version=GC<sha>` back to `?version=GB<branch>` (AzDO). Object-form sources have their `commit` removed and `branch` set.

| Option | Description |
|---|---|
| `--entry <name>` | Limit to specific entries. Repeatable, comma-separated values accepted. |
| `--to <branch>` | Branch name to thaw the pinned entry to. Skips the default-branch API call. |
| `--to-default` | Explicitly opt into default-branch API discovery (the same as supplying no `--to` flag), but surface any discovery failure as an error rather than silently falling back to `main`. |
| `--dry-run` | Report what would change without rewriting the manifest. |

When neither `--to` nor `--to-default` is supplied, Conduit queries the repo's default branch via the API and falls back to the literal `main` if discovery fails (offline, 404, etc.).

## `conduit clean`

Remove destination directories whose owning entry has been deleted from the manifest. Live entries' targets are never touched (cross-checked before deletion).

| Option | Description |
|---|---|
| `--dry-run` | Report which directories would be removed without touching the filesystem or state. |
| `-y, --yes` | Skip the interactive confirmation prompt. Required when stdin is not a TTY or when `-o json` is set. |

The cleaner reads `.conduit-state.json` to find orphan entries, then for each recorded target directory verifies (a) it exists on disk, and (b) no live entry currently claims it, before removing. Hard failures (I/O errors, permission denied) are reported per directory; state rows are pruned only when their target was actually removed or already gone.

## `conduit watch`

Run an initial sync, then re-sync whenever the manifest file changes on disk. Ctrl+C exits.

| Option | Description |
|---|---|
| `--debounce <ms>` | Coalesce burst writes from editors that save via temp + rename. Default `250`. |
| `-p, --parallel <N>` | Forwarded to each re-run. Default `4`. |

## `conduit copy <source> <target>`

One-shot copy that bypasses the manifest entirely. Synthesises a one-entry
manifest from the supplied source URI (same shorthand syntax as a manifest
`source` string &mdash; bare URL, `URL -> Alias`, `./local/path`, etc.) and
runs the standard synchronizer against the supplied target directory.

Useful for scripting, ad-hoc installs, and previewing strategies before
adding them to your manifest.

| Option | Description |
|---|---|
| `-s, --strategy <name>` | Which strategy controls destination layout. One of `wrap` (default), `flat`, `expand`, `skills`. |
| `--group-by source` | Wrap each source's planned output in a source-named sub-directory under the target. |
| `--on-collision <mode>` | Conflict policy when two destinations resolve to the same path. One of `error` (default), `skip`, `last-wins`. |
| `--skills name1,name2` | Skills-strategy only: restrict to the named skills. Repeatable and comma-separated. |
| `--harness name\|true\|false` | Skills-strategy only: enable / disable harness discovery, or restrict to named harnesses (`opencode`, `claude`, `codex`, `agents`). Repeatable and comma-separated. |
| `--add-harness name=path` | Add a custom harness to the registry for this run only. Repeatable. Example: `--add-harness .my-tool=skills/`. |
| `--dry-run` | Plan and report what would change without writing to the target. |

Examples:

```bash
# Mirror a public skill repo into a literal skills directory.
conduit copy https://github.com/anthropics/skills ~/.config/agents/skills --strategy skills

# Same, but only the 'code-review' skill, and fanned out across every
# detected agent harness under ~.
conduit copy https://github.com/anthropics/skills ~ --strategy skills --skills code-review --harness true

# Lift each top-level child of a dotfiles repo into a separate
# sub-directory under ~/.config/my-tool/.
conduit copy https://github.com/example-org/dotfiles ~/.config/my-tool --strategy expand
```

JSON output: `{ "name": "<entry>", "strategy": "...", "dryRun": ..., "succeeded": ..., "targets": [ { "path": ..., "succeeded": ..., "filesWritten": ..., "error": ... } ] }`.

## `conduit skills probe <target>`

Scan a target directory one level deep for registered agent-harness skills
folders (`.opencode/skills`, `.claude/skills`, `.codex/skills`,
`.agents/skills`, plus any custom additions from the manifest's
`strategies.skills.harnessRegistry`).

Returns exit `0` when at least one harness matches, exit `1` when none do.
Useful before adding a skills entry to verify the target is where you think
it is.

Examples:

```bash
# What harnesses do I have under my home directory?
conduit skills probe ~

# Same, but using a custom registry from a specific manifest.
conduit skills probe --manifest ./conduit.json ~/projects/my-app
```

JSON output: `{ "requested": "...", "resolved": "...", "registry": { ... }, "matches": [ { "harness": "...", "matched": "...", "directory": "..." } ] }`.

## Environment variables

### GitHub

| Name | Effect |
|---|---|
| `CONDUIT_GITHUB_TOKEN` | OAuth / PAT used for the `Authorization: Bearer ...` header on GitHub API requests. Read first by the `env` auth provider. |
| `GITHUB_TOKEN` | Read by the `env` provider when `CONDUIT_GITHUB_TOKEN` is unset. |
| `GH_TOKEN` | Read by the `env` provider when both of the above are unset (matches `gh` CLI convention). |
| `CONDUIT_GITHUB_API_BASE` | Override the GitHub API base URL (default `https://api.github.com`). Mainly for tests. |

Auth chain (default `[env, gh, anonymous]`):

- `env` &mdash; the three env vars above, first non-empty wins.
- `gh` &mdash; shells out to `gh auth token`; cached for ~10 minutes per process.
- `pat` &mdash; reads from a specific env var named by the source's `patEnv` field (default `CONDUIT_GITHUB_TOKEN`).
- `anonymous` &mdash; sends no `Authorization` header. Reaching this provider in the chain short-circuits subsequent providers.

Override per entry with `"auth": ["env", "anonymous"]` or `"auth": "pat"`.

### Azure DevOps

| Name | Effect |
|---|---|
| `CONDUIT_AZDO_TOKEN` | PAT used for the `Authorization: Basic` header on AzDO REST calls. Read first by the `env` auth provider. |
| `AZURE_DEVOPS_EXT_PAT` | Read by the `env` provider when `CONDUIT_AZDO_TOKEN` is unset. |
| `SYSTEM_ACCESSTOKEN` | Read by the `env` provider as a last resort (works inside AzDO Pipelines automatically). |

Auth chain (default `[env, az]`):

- `env` &mdash; the three env vars above.
- `az` &mdash; shells out to `az account get-access-token --resource <azdo-aad-guid>`; cached in-memory for ~50 minutes.
- `pat` &mdash; reads from a specific env var named by the source's `patEnv` field (default `CONDUIT_AZDO_TOKEN`).
- `anonymous` &mdash; sends no `Authorization` header.

### Discovery / display

| Name | Effect |
|---|---|
| `XDG_CONFIG_HOME` | When set, conduit looks for the manifest under `$XDG_CONFIG_HOME/Zakira.Conduit/conduit.{json,jsonc}`. Otherwise the home-dir `.config` fallback is used. |
| `NO_COLOR` | When set (any value), disables ANSI colour output. Colour is also disabled automatically when stdout is redirected. |
