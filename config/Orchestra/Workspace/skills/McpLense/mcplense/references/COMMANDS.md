# `mcplense` commands reference

Every command, every flag, what it does, and how to use it. The agent loads this
on-demand when the main `SKILL.md` says to consult it.

## Conventions

- `<url>` is an absolute http/https URL pointing at an MCP server's endpoint.
- `@<name>` is a positional alternative: looks up a named entry under `targets[]`
  in `McpLense.Config.json` and resolves to that entry's URL + headers + profile.
- `<command>` (without a `<>`) refers to an MCP tool / resource / prompt name.
- `--format json` is the recommended output for any tool-pipeline use.

## Inspection commands

### `mcplense inspect <url|@target>`

Open a session and emit a one-shot snapshot: capability bits, tools, resources,
resource templates, prompts. Best general-purpose "what's on this MCP" command.

```bash
mcplense inspect https://mcp.example.com/ --format json
mcplense inspect @ec-foo --format json
```

### `mcplense tools <url|@target>`

Just the tools list. Each entry: `name`, `description`, `inputSchema`.

### `mcplense resources <url|@target>`

Just the resources list. Each entry: `uri`, `name`, `mimeType`, `description`.

### `mcplense prompts <url|@target>`

Just the prompts list. Each entry: `name`, `description`, `arguments`.

## Action commands

### `mcplense call <tool-name> <url|@target> --args '<json>'`

Invoke a tool. `--args` is a JSON object whose keys map to the tool's input schema.
Captures the tool result envelope (`content[]`, `structuredContent`, `_meta`,
`isError`).

```bash
mcplense call resolve-library-id https://mcp.context7.com/mcp \
  --args '{"libraryName":"spectre.console"}'
```

### `mcplense read <uri> <url|@target> [--args '<json>']`

Read a resource by URI. `--args` may carry template-substitution variables when
the URI references a `uriTemplate` (RFC 6570).

### `mcplense prompt <prompt-name> <url|@target> --args '<json>'`

Render a server-side prompt with the supplied arguments. Returns the rendered
message list.

### `mcplense fetch-resource <uri> <url|@target> [--args '<json>']`

Drill-down equivalent of `read`. Same wire shape.

## Scanning / auditing

### `mcplense scan <url|@target>`

The big one. Runs every enabled `IScanCheck` and emits a stable JSON report.
Builds the report shape documented in
[CHECKS.md](CHECKS.md). Use `--format json` for downstream automation.

Common flags:

- `--baseline <dir>` — after the scan, write the report under
  `<dir>/<host>/<UTC-timestamp>.json`. When `<dir>` is a file, write there
  directly.
- `--diff <baseline.json>` — after the scan, emit a structural diff vs the
  baseline instead of the report.
- `--enable <check-id>` / `--disable <check-id>` — toggle a check per run.
- `--parallel-servers <N>` — concurrency across servers (default 1).
- `--quiet` / `--verbose` — silence / expand stderr observability.
- `--check-authorization-servers` — opt in to fetching RFC 8414 / OIDC
  discovery metadata for advertised authorization servers (outbound to a
  different host, off by default).
- `--classify-only` — skip profile attempts AND skip enumeration that
  depends on them. Only the `auth` block is emitted.

### `mcplense auth-scan <url|@target>`

Lightweight classification-only path: probe + classify + (optionally) profile
attempts. Skips the full check pipeline. Useful as a fast "what is this MCP's
auth model?" command.

Adds:

- `--classify-only` — same as the `scan` flag.

### `mcplense observe <url|@target>`

Hold a session open and observe inbound server-initiated traffic
(`sampling/createMessage`, `elicitation/create`, `roots/list`, and the six
standard notifications). Output is the `behavior.serverInitiated` check entry.

- `--timeout <seconds>` — observation window (default 30).
- `--enable` / `--disable` — same toggles as `scan`.

### `mcplense diff <baseline-before> <baseline-after>`

Pure file-to-file structural diff: takes two baseline JSON files written by
previous `scan` runs and emits the per-section delta. No network. Stable wire
shape so you can pipe into automation that highlights `added`, `removed`,
`changed`.

## Auth-management commands

### `mcplense login {--all | --profile <name> | <url>}`

Forces an interactive login flow for a profile, every profile, or the profile
that auto-picks for `<url>`. After this, subsequent runs use the cached token
silently.

### `mcplense logout {--all | --profile <name> | <url>}`

Mirror of `login`: revokes cached credentials for the named profile / all
profiles / the auto-picked profile for `<url>`.

## Helper / meta

### `mcplense help` / `mcplense version`

Self-explanatory.

### `mcplense tui`

Interactive Spectre.Console UI. Not useful for agents — never invoke from
automation.

## Target options (apply to every command above)

| Flag | Effect |
| --- | --- |
| `--url <url>` | Long form of the positional URL. Cannot combine with positional URL. |
| `--config <path>` | Load stdio MCP servers from a JSON file. Stdio-only; HTTP belongs to positional URLs. |
| `--server <name>` | Filter `--config` servers by name. Repeatable. |
| `--profiles <path>` | Auth-profile file path; overrides XDG/APPDATA auto-discovery. Repeatable. |
| `--profile <name>` | Force a specific loaded profile. |
| `--header NAME=VALUE` | HTTP header. Repeatable. Most-specific overlay layer (wins over config). |
| `--transport <auto\|streamable-http\|sse>` | Force HTTP transport mode. Default `auto`. |
| `--timeout <seconds>` | Per-server handshake timeout (default 30). |
| `--no-auth` | Suppress all authentication (HTTP and stdio). |
| `--auth bearer --auth-token <value>` | Ad-hoc static Bearer token. Use a profile for OAuth. |
| `--name <value>` | Display name for direct targets. |
| `--command <command>` | Launch a stdio MCP server. |
| `--command-arg <value>` | Argument for `--command`. Repeatable. |
| `-- <command...>` | Alternative stdio form (everything after `--` becomes the command line). |
| `--cwd <path>` | Working directory for stdio targets. |
| `--env NAME=VALUE` | Environment variable for stdio targets. |
| `--format <text\|json\|dumpify>` | Output format (default `text`). |

## Picking flags by user intent

| User intent | Flag combo |
| --- | --- |
| Just want JSON I can pipe | `--format json` |
| Don't show the auth/matched/AuthProbe lines | `--quiet --format json` |
| Show me everything (headers, auth picks, probe reasoning) | `--verbose` |
| I want to test the bare unauthenticated surface | `--no-auth` |
| I only want the auth classification, no enumeration | `mcplense auth-scan ... --classify-only` |
| I want to also see RFC 8414 metadata | `mcplense scan ... --check-authorization-servers` |
| Save and compare scans over time | `--baseline ./baselines/` then `--diff <path>` |
| Fleet of MCPs in one go | One `mcplense scan` per URL, or wrap in a loop / xargs |
