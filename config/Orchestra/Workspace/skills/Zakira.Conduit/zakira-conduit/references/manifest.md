# Manifest field reference

Every field accepted by a `conduit.json` manifest. The runtime validator (`ManifestValidator`) and the JSON Schema at `schemas/conduit.schema.json` are the authoritative specs; this document mirrors them in prose.

## File format and discovery

- **File name**: `conduit.json` (preferred) or `conduit.jsonc` (editor-hint alias). Both are probed at every discovery location; `.json` wins when both exist.
- **Format**: JSONC. Line comments (`// ...`), block comments (`/* ... */`), and trailing commas are accepted regardless of file extension.
- **Discovery order** (when `--manifest` is not supplied): `$XDG_CONFIG_HOME/Zakira.Conduit/conduit.{json,jsonc}` -> `$HOME/.config/Zakira.Conduit/conduit.{json,jsonc}` -> `./conduit.{json,jsonc}`.
- **Round-trip trivia**: `conduit pin` / `unpin` / `update` preserve comments and trailing commas when every touched entry has a string-shaped source on disk (URL rewrite). When an object-shaped source needs key insertion/removal (e.g. dropping `branch` on pin), the write falls back to a full reformat that loses trivia.

## Top-level object

```jsonc
{
  "$schema": "https://raw.githubusercontent.com/MoaidHathot/Zakira.Conduit/main/schemas/conduit.schema.json",
  "version": 1,
  "entries": [ /* ... */ ],
  "strategies": { /* optional; manifest-global strategy config */ }
}
```

| Field        | Required | Notes |
|--------------|----------|-------|
| `$schema`    | no       | Editor hint. Ignored at runtime. |
| `version`    | no       | Schema version. Must be `1`. Default is `1`. |
| `entries`    | yes      | Non-empty array of entry objects. |
| `strategies` | no       | Manifest-global strategy configuration. Currently exposes the `skills` sub-section (custom harness registry, default collision policy). See "Strategies section". |

## Entry object

```jsonc
{
  "name": "code-review",
  "description": "Optional human-readable notes.",
  "disabled": false,
  "source": { /* see below */ },
  "targets": [ /* see below */ ],
  "strategy": "wrap",
  "groupBy": "none",
  "onCollision": "error",
  "skills": [ "code-review", "test-writer" ],
  "harness": ["claude", "opencode"]
}
```

| Field         | Required | Notes |
|---------------|----------|-------|
| `name`        | no       | Matches `[A-Za-z0-9._-]+`. Unique within the manifest. **Optional**: when omitted, Conduit derives a default from the source (GitHub/AzDO repo name, single-path local directory basename) or from an explicit alias supplied via the in-string `... -> Name` shorthand or the `{ "source": ..., "as": "Name" }` wrapper. Used as the destination subdirectory name when the chosen `strategy` is `wrap` and the source produces exactly one content unit (and no per-target `as:` override is set). Other strategies compute destination names from their own rules; the name is then metadata only (used by `--entry` filtering and logs). |
| `description` | no       | Free-form documentation; ignored at runtime. |
| `disabled`    | no       | Default `false`. When `true`, `sync` skips the entry. |
| `source`      | yes      | The remote or local source. See "Source object". |
| `targets`     | yes      | Non-empty array. See "Target item". |
| `strategy`    | no       | Selects the destination-layout strategy. One of `wrap` (default, backwards-compatible with pre-0.3 manifests), `flat`, `expand`, `skills`. See "Strategies". |
| `groupBy`     | no       | One of `none` (default) or `source`. When `source`, every planned destination is wrapped in an extra sub-directory named after the source (GitHub/AzDO repo name, local basename, or explicit alias). Composes with every strategy. |
| `onCollision` | no       | Per-entry override for the collision policy: `error` (default), `skip`, `last-wins`. Falls back to `strategies.skills.onCollision` (for the skills strategy) and then to `error`. |
| `skills`      | no       | Skills-strategy only. Filter list: when set, only the named skills (by `SKILL.md` folder basename) are mirrored. Empty / omitted = "every discovered skill". Validator errors if set on a non-skills strategy. |
| `harness`     | no       | Skills-strategy only. Boolean (`true`/`false`) or string array. See "Harness selector". Validator errors if set on a non-skills strategy. |

## Source object

The `source` field accepts a polymorphic shape. The discriminator `type` selects the concrete kind, but several **shorthand forms** also work:

- **Bare URI string**: `"source": "https://github.com/owner/repo/path"`. The URI inferrer picks the right kind from the shape (`github`, `azdo`, `local`).
- **Bare URI string with alias suffix**: `"source": "https://github.com/owner/repo -> MyName"`. The trailing ` -> Name` overrides the entry's `name`.
- **Wrapper object**: `{ "source": <any other source shape>, "as": "Name" }`. Equivalent to the in-string alias but works around any inner source shape (including concrete objects).
- **Array**: `"source": [ ... ]`. Each element becomes its own sub-entry sharing the parent entry's `targets` / `description` / `disabled`. Per-target `as:` aliases are forbidden on arrays.
- **`type: "uri"` object**: `{ "type": "uri", "uri": "...", "path"?: ..., "branch"?: ..., "auth"?: ..., ... }`. The inferrer rewrites it into the equivalent concrete kind at load time; useful when you need overrides on a pasted browse URL.

Concrete kinds (`type` value):

### `type: "github"`

```jsonc
{
  "type": "github",
  "repo": "owner/repo",
  "path": "sub/path",
  "paths": [ "skills/a", { "path": "skills/b", "as": "renamed" } ],
  "branch": "main",
  "commit": "abc123def...",
  "include": ["**/*.md", "scripts/**"],
  "exclude": ["**/*.test.*", "bin/**"],
  "auth": ["env", "gh", "anonymous"],
  "patEnv": "MY_GH_TOKEN"
}
```

| Field    | Required | Notes |
|----------|----------|-------|
| `repo`   | yes      | Repository identifier. Accepts `owner/repo`, `github.com/owner/repo`, `https://github.com/owner/repo[.git]`, or `git@github.com:owner/repo[.git]`. |
| `path`   | no       | Single sub-path inside the repo. Mutually exclusive with `paths`. Must not begin with `/` or contain `..`. |
| `paths`  | no       | Array of sub-paths. Mutually exclusive with `path`. Each element is either a string or an object `{ path, as? }`. Duplicate destination basenames across the array are a validation error. |
| `branch` | no       | Branch or tag name. May coexist with `commit`: when both are set, `branch` is the tracking intent and `commit` is the snapshot fetched. `conduit pin` removes `branch` when locking to a commit; `conduit unpin` restores it. |
| `commit` | no       | Commit SHA. Wins over `branch` for fetching. |
| `include`| no       | Optional glob list (Microsoft.Extensions.FileSystemGlobbing dialect: `*`, `**`, `?`, character classes). When omitted / empty, all files are mirrored. |
| `exclude`| no       | Optional glob list applied after `include`. |
| `auth`   | no       | Auth chain. Single mode name or an ordered array. Modes: `env`, `gh`, `pat`, `anonymous`. Default `[env, gh, anonymous]`. |
| `patEnv` | no       | For the `pat` mode: the env var name to read the PAT from. Defaults to `CONDUIT_GITHUB_TOKEN`. |

If neither `branch` nor `commit` is set, the repository's default branch is used. If neither `path` nor `paths` is set, the entire repository is mirrored.

URL-embedded shorthands accepted by the inferrer when `source` is a string or `type: "uri"`:

- `https://github.com/owner/repo`
- `https://github.com/owner/repo/<sub-path>`                  (sub-path harvested; default branch)
- `https://github.com/owner/repo/tree/<branch>/<sub-path>`    (branch harvested)
- `https://github.com/owner/repo/tree/<sha>/<sub-path>`       (40-hex SHA -> routed to `commit` instead of `branch`)

### `type: "azdo"`

```jsonc
{
  "type": "azdo",
  // Either 'url' OR the explicit triplet:
  "url": "https://dev.azure.com/contoso/Conduit/_git/agent-skills",
  "organization": "contoso", "project": "Conduit", "repo": "agent-skills",
  "baseUrl": "https://devops.contoso.internal/",   // for self-hosted AzDO Server
  "path": "sub/path",
  "paths": [ "skills/a", "skills/b" ],
  "branch": "main",
  "tag": "v1.2.3",
  "commit": "abc...",
  "include": ["**/*.md"],
  "exclude": ["bin/**"],
  "auth": ["env", "az"],
  "patEnv": "MY_AZDO_TOKEN"
}
```

| Field          | Required | Notes |
|----------------|----------|-------|
| `url`          | one of `url` / triplet | Browser URL or git remote (HTTPS or SSH form). Mutually exclusive with the triplet. |
| `organization` | one of `url` / triplet | Org name (AzDO Cloud) or collection name (AzDO Server). |
| `project`      | one of `url` / triplet | Project name. |
| `repo`         | one of `url` / triplet | Repository name or GUID. |
| `baseUrl`      | no | Override the REST base URL for AzDO Server. Defaults to `https://dev.azure.com/` for the triplet form. |
| `branch`       | no | Branch name. May coexist with `commit` (branch = tracking intent). |
| `tag`          | no | Tag name. Mutually exclusive with `branch`. |
| `commit`       | no | Commit SHA pin. Wins over `branch` / `tag` for fetching. |
| `path`         | no | Single sub-path inside the repo. Mutually exclusive with `paths`. |
| `paths`        | no | Array of sub-paths. Same shape as the GitHub source. |
| `include`      | no | Same as github. |
| `exclude`      | no | Same as github. |
| `auth`         | no | Auth chain. Modes: `env`, `az`, `pat`, `anonymous`. Default `[env, az]`. |
| `patEnv`       | no | Env var name for the `pat` mode. Defaults to `CONDUIT_AZDO_TOKEN`. |

URL-embedded shorthands accepted on string / `type: "uri"`:

- `https://dev.azure.com/{org}/{project}/_git/{repo}`
- `https://dev.azure.com/{org}/{project}/_git/{repo}/<sub-path>`
- `https://dev.azure.com/{org}/{project}/_git/{repo}?path=/{sub-path}&version=GB{branch}`
- `https://dev.azure.com/{org}/{project}/_git/{repo}?version=GC{sha}`   (`GC` = commit, `GB` = branch, `GT` = tag)
- `https://{org}.visualstudio.com/{project}/_git/{repo}` and self-hosted variants

### `type: "local"`

```jsonc
{
  "type": "local",
  "path": "./local-dir",
  "paths": [ "./a", { "path": "./b", "as": "renamed" } ],
  "include": ["**/*.md"],
  "exclude": ["bin/**"]
}
```

| Field    | Required | Notes |
|----------|----------|-------|
| `path`   | one of `path` / `paths` | Single source directory. Mutually exclusive with `paths`. |
| `paths`  | one of `path` / `paths` | Array of source directories. Mutually exclusive with `path`. |
| `include`| no | Same as github. |
| `exclude`| no | Same as github. |

Local paths support `~`, `$VAR`, `${VAR}`, and `%VAR%` (Windows) expansion. Relative paths are anchored at the manifest's directory.

## Target item

Each element of `targets` is either:

- a **bare string** &mdash; the target directory path, or
- an **object** `{ "path": "...", "as": "..." }` &mdash; the same path plus an alias that overrides the entry's `name` for that one destination only.

Per-target `as:` aliases are forbidden on multi-unit entries (where a source produces multiple destinations) because the basename rule would silently override them.

## Path expansion

Both target paths and local source paths support:

- `~` &mdash; expands to the user's home directory.
- `$NAME` and `${NAME}` &mdash; environment variable expansion, on all platforms.
- `%NAME%` &mdash; Windows-style environment variable expansion (Windows only).
- Relative paths &mdash; anchored at the manifest's own directory.

## Validation summary

- `entries` is non-empty.
- Every `name` matches the allowed character set and is unique.
- Every entry resolves to a non-null `name` (either explicit, alias-supplied, or source-derived).
- Every `targets[]` is non-empty and contains at least one valid path.
- For github sources: `repo` must parse to a valid `owner/name`.
- `path` + `paths` are mutually exclusive on every source.
- For multi-element `paths`: every resolved destination name (alias or basename) is unique.
- For multi-unit sources: no target may carry a per-target `as:` alias.
- A source path may not begin with `/` or contain `..` for github sources.
- **Cross-entry destination uniqueness**: two entries (or two array-expanded sub-entries) must not write into the same `<target>/<destName>/` directory.

Run `conduit validate` to surface every violation. The exit code is `2` when the manifest fails to load or validate.

## Source aliases (`... -> Name` and `{ source, as }`)

Two equivalent shorthand forms attach a destination alias to a source without
having to spell out the full entry-level `name` field. Useful when you want
multiple array elements to land in well-named folders without writing each
one out:

```jsonc
// In-string arrow suffix on a bare URI. The alias after ' -> ' must match
// [A-Za-z0-9._-]+. Reserved exclusively for the bare-string shorthand;
// concrete `{type, ...}` objects use the wrapper form below.
"source": "https://github.com/anthropics/skills/code-review -> CodeReview"

// Object wrapper. Recognised by the absence of a `type` discriminator.
// Works around any inner source shape: a bare URI, a concrete object, etc.
"source": { "source": { "type": "github", "repo": "anthropics/skills", "path": "code-review" }, "as": "CodeReview" }
```

Both set the entry name to `CodeReview`. The wrapper is rejected if it
contains anything other than `source` and `as`, if `source` is another
wrapper (only one alias per source), or if `source` is an array (aliases
apply to single sources only).

## Strategies

The `strategy` field on an entry selects which built-in `IPlanStrategy`
computes the per-target destination layout. Four strategies ship in v1:

| Strategy | Single source unit | Multi source unit | Per-target `as:` | Static destination set? |
|---|---|---|---|---|
| `wrap` (default) | `<target>/<entry-name>/...` (or `<target>/<target.as>/...`) | `<target>/<unit-basename>/...` per fetched unit | Honoured for single-unit entries | Yes |
| `flat` | Source contents written directly into `<target>/` | All units merged into `<target>/` (collision policy applies) | Rejected by validator | Yes |
| `expand` | Each top-level child directory of the source becomes `<target>/<child>/` (root-level files dropped) | Same per unit (collision policy applies) | Rejected by validator | No (content-dependent) |
| `skills` | Each discovered `SKILL.md`-bearing folder becomes `<target>/<skill-name>/` | Same per unit; fan-out across every detected harness under target | Rejected by validator | No (content-dependent) |

"Static destination set" indicates whether the validator and orphan cleaner can
compute the entry's destinations from the manifest alone. Strategies that
say "No" rely on either the just-fetched content (sync) or the previous
sync's state (orphan cleaner).

### `groupBy` composes with every strategy

When `groupBy: "source"` is set, every emitted destination is wrapped in an
extra sub-directory named after the source:

| Strategy | Without `groupBy` | With `groupBy: "source"` |
|---|---|---|
| `wrap` | `<target>/<entry-name>/...` | `<target>/<source>/<entry-name>/...` |
| `flat` | `<target>/...` | `<target>/<source>/...` |
| `expand` | `<target>/<child>/...` | `<target>/<source>/<child>/...` |
| `skills` | `<target>/<skill>/...` | `<target>/<source>/<skill>/...` |

Source name comes from the same default deriver that fills in
`entry.name` when it's omitted: GitHub / AzDO repo name, single-path local
basename, or an explicit alias from `... -> Name` / `{ source, as }`.

### Harness selector

The `harness` field (skills strategy only) is one of three shapes:

```jsonc
"harness": true                    // (default) require at least one harness; error if none detected
"harness": false                   // skip the scan; treat each target literally
"harness": ["claude", "opencode"]  // enable discovery, restricted to the named harnesses
```

The harness scan auto-disables (treats the target literally) when the
target's trailing path segment is `skills` (case-insensitive) or matches
any registered harness search-path suffix. So if your manifest writes
into `$XDG_CONFIG_HOME/Orchestra/workspace/skills`, no scan runs and
you don't need `harness: false`.

When the scan runs and finds nothing, the resolver:

- with an **explicit name filter**: errors out with a message listing the
  expected harness names.
- with `harness: true` and no name filter: falls back to treating the
  target as literal (so the entry still completes; the destinations land
  directly under the target).

### Built-in harness registry

| Name | Search paths |
|---|---|
| `opencode` | `.opencode/skills`, `.config/opencode/skills` |
| `claude`   | `.claude/skills` |
| `codex`    | `.codex/skills` |
| `agents`   | `.agents/skills` |

OpenCode is the only harness with two paths today: the project-local
`.opencode/skills/` convention and the global `.config/opencode/skills/`
layout used when you target `~` (or `$XDG_CONFIG_HOME`). GitHub Copilot
is deliberately absent &mdash; Copilot uses
`.github/copilot-instructions.md` / `.github/instructions/*.instructions.md`
(files, not skill folders), so the skills strategy does not apply.

## Strategies section

The optional `strategies` top-level object exposes manifest-global
configuration. v1 ships one sub-section, `skills`:

```jsonc
"strategies": {
  "skills": {
    "harnessRegistry": {
      ".my-tool": "skills/",                             // string shorthand
      ".other":   ["a/skills", "b/skills"],              // array form for multi-path harnesses
      ".claude":  null                                    // remove a built-in
    },
    "onCollision": "error"
  }
}
```

| Path | Notes |
|------|-------|
| `strategies.skills.harnessRegistry` | Object whose keys are harness names (leading `.` optional). Values are: a string (single search path), an array of strings (multiple search paths), or `null` (remove the built-in entry of that name). Keys merge into the built-in registry: matching keys are replaced; new keys are added. |
| `strategies.skills.onCollision` | Manifest-wide default collision policy for the skills strategy. Per-entry `onCollision` overrides this. |

## Skills examples

### Install a skill repository into every detected harness under your home dir

```jsonc
{
  "strategy": "skills",
  "source": "https://github.com/anthropics/skills",
  "targets": ["~"]
}
```

Result: every discovered `SKILL.md` is fanned out into each matched
harness layout (`~/.claude/skills/<skill>/`, `~/.opencode/skills/<skill>/`,
`~/.config/opencode/skills/<skill>/`, etc.).

### Same, but only the Claude harness

```jsonc
{
  "strategy": "skills",
  "source": "https://github.com/anthropics/skills",
  "harness": ["claude"],
  "targets": ["~"]
}
```

### Pick a specific skill and install it into a literal `skills/` directory

```jsonc
{
  "strategy": "skills",
  "skills": ["code-review"],
  "source": "https://github.com/anthropics/skills",
  "targets": ["$XDG_CONFIG_HOME/Orchestra/workspace/skills"]
}
```

The trailing `skills` segment auto-disables the harness scan: each
selected skill writes to `$XDG_CONFIG_HOME/Orchestra/workspace/skills/<skill-name>/`.

### Many sources into a shared target, grouped by source name

```jsonc
{
  "strategy": "skills",
  "groupBy": "source",
  "source": [
    "https://github.com/MoaidHathot/ActionView",
    "https://github.com/MoaidHathot/PowerReview",
    "https://github.com/MoaidHathot/Zakira.Replay"
  ],
  "targets": ["$XDG_CONFIG_HOME/Orchestra/workspace/skills"]
}
```

Each source's discovered skills land at
`<target>/<source-name>/<skill-name>/SKILL.md` so provenance is preserved.
