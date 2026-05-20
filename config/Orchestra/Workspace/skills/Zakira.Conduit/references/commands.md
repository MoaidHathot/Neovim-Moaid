# Command reference

Every `conduit` subcommand with its full surface area.

## Global options

These work on every subcommand:

| Option | Description |
|---|---|
| `-m, --manifest <path>` | Override manifest discovery. Path is absolute or relative to the current directory. |
| `-o, --output text\|json` | Output format. `text` is human-friendly (default). `json` emits machine-readable JSON on stdout; logs are still routed to stderr so `... | jq` works. |
| `--verbosity q\|m\|n\|d\|diag` | Verbosity level. Default `normal`. |
| `-v, --verbose` | Shortcut for `--verbosity detailed`. |
| `-q, --quiet` | Shortcut for `--verbosity quiet`. |

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success. |
| `1` | One or more entries failed during `sync`, or one or more refs failed to resolve during `pin`/`update`. |
| `2` | Manifest could not be located, parsed, or validated. |

## `conduit init`

Create a starter `conduit.json` at the discovered location (or at `--manifest`).

| Option | Description |
|---|---|
| `-f, --force` | Overwrite an existing manifest if one is present at the target path. |
| `-i, --interactive` | Walk through prompts to populate the first entry. Requires an attached TTY (refuses to run when stdin / stdout are redirected). |

## `conduit validate`

Parse and validate the manifest. No network IO. Useful as a CI step.

JSON output shape on success: `{ "ok": true, "manifest": "..." }`.
JSON output shape on failure: `{ "ok": false, "manifest": "...", "error": "...", "details": ["..."] }`.

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
| `--entry <name>` | Restrict the run to specific entries. Repeatable. |
| `--dry-run` | Fetch + report what would change. No targets are written, no state is updated. |
| `--stop-on-first-error` | Abort on the first failure (otherwise the remaining entries are still attempted). |
| `-f, --force` | Ignore the state cache and re-fetch + re-mirror every entry. |
| `-p, --parallel <N>` | Maximum entries processed concurrently. Default `4`. Use `1` to force sequential execution. |

### How sync decides to skip an entry

Before fetching, the synchronizer asks the state store whether the entry is provably up-to-date:

- **Commit-pinned GitHub entries:** state's recorded ref equals the entry's `commit` AND every recorded target directory still exists -> skip without any network call.
- **Local sources:** a fingerprint of `(relative path, size, last-write-time)` of every file under the source matches the recorded hash AND every recorded target directory still exists -> skip without copying anything.
- **Branch-tracked GitHub entries:** can't skip without consulting GitHub, so the fetcher sends `If-None-Match` against the state's ETag. A 304 short-circuits the mirror.

`--force` bypasses all of these. Removing `.conduit-state.json` also achieves this.

## `conduit pin` / `conduit update`

For every GitHub entry that has a `branch`, resolve the branch's current tip via the GitHub commits API and write the SHA into the entry's `commit` field. The `branch` is retained as the tracking intent so a future `update` knows what to bump. The two verbs are functional aliases; pick whichever reads better in context.

| Option | Description |
|---|---|
| `--entry <name>` | Limit to specific entries. Repeatable. |
| `--dry-run` | Report what would change without rewriting the manifest. |

The pre-update manifest is backed up at `<manifest>.bak` next to the original. Comments and trailing commas in the source manifest are lost on rewrite &mdash; warn the user before suggesting these commands on a hand-formatted file.

## `conduit watch`

Run an initial sync, then re-sync whenever the manifest file changes on disk. Ctrl+C exits.

| Option | Description |
|---|---|
| `--debounce <ms>` | Coalesce burst writes from editors that save via temp + rename. Default `250`. |
| `-p, --parallel <N>` | Forwarded to each re-run. Default `4`. |

## Environment variables

| Name | Effect |
|---|---|
| `CONDUIT_GITHUB_TOKEN` | OAuth / PAT used for the `Authorization: Bearer ...` header on GitHub API requests. Lifts the anonymous rate limit and unlocks private repos. |
| `GITHUB_TOKEN` | Used when `CONDUIT_GITHUB_TOKEN` is unset. |
| `CONDUIT_GITHUB_API_BASE` | Override the GitHub API base URL (default `https://api.github.com`). Mainly for tests; rarely needed in production. |
| `XDG_CONFIG_HOME` | When set, conduit looks for the manifest under `$XDG_CONFIG_HOME/Zakira.Conduit/conduit.json`. Otherwise the home-dir `.config` fallback is used. |
| `NO_COLOR` | When set (any value), disables ANSI colour output. Colour is also disabled automatically when stdout is redirected. |
