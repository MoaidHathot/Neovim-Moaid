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

Add `--example` to print a ready-to-edit `--args` template generated from the tool's
input schema (plus the equivalent command) WITHOUT invoking - a first-call aid.

```bash
mcplense call resolve-library-id https://mcp.context7.com/mcp --example
```

### `mcplense explain <url|@target>`

Plain-language summary of a server: identity, auth posture, how many tools/resources/
prompts it exposes, which tools are server-declared destructive/open-world, and a
one-line findings summary. Built for learning/triage. `--format markdown` renders a
shareable write-up; `--format json` gives the structured form.

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
- `--findings` — also run the analysis layer; emits `{ "scan": ..., "findings": ... }`.
- `--fail-on <severity>` — with `--findings`, exit non-zero when a finding ≥ severity.

### `mcplense analyze <url|@target>`

Runs the scan pipeline, then classifies the fact-only output into severity-rated
**findings** using a built-in rule pack (prompt-injection signals, tool poisoning,
open-shape input, weak CORS, TLS posture, error info-leak, ...). The scan itself stays
fact-only — `analyze` is a separate opt-in consumer. Output is a `FindingsReport`
(`servers[].findings[]`, each with `ruleId`, `severity`, `evidencePath`, `remediation`).

- `--fail-on <severity>` — CI gate: exit non-zero if any finding ≥ severity
  (info/low/medium/high/critical). Overrides `analysis.failOn` from config.
- `--approve <file>` / `--since <file>` — rug-pull detection: `--approve` snapshots the
  current tool/prompt/resource hashes; `--since` flags anything that changed since as a
  `rug-pull` finding.
- `--format sarif` — emit SARIF 2.1.0 for GitHub code scanning / CI security tooling.
- Accepts the scan-shaping flags (`--enable`/`--disable`, `--scan-plugin`,
  `--check-authorization-servers`, `--targets-from`, `--parallel-servers`).

Rules and their severities are configured in `McpLense.Config.json` under the top-level
`analysis` block (`analysis.rules.<id>.enabled` / `.severity`, `analysis.failOn`), so a
fleet policy lives in config rather than CLI flags. See `docs/analysis-rules.md`.

### `mcplense doctor <url|@target>`

Staged connectivity triage for "why won't this MCP connect?": walks DNS → TCP → TLS →
MCP initialize → auth classification and reports exactly which stage broke, with a fix-it
hint (auth required, transport mismatch, expired cert, ...). Stdio targets get spawn +
initialize. Exit code is non-zero if any stage failed. Distinct from `scan` (an audit).

### `mcplense serve`

Runs McpLense itself as a stdio MCP server (see Helper / meta below).

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

Note: every live connection (not just `observe`) now RECEIVES this traffic.
One-shot `inspect` / `call` / `read` / `prompt` log what the server tried and
answer with safe defaults (refuse sampling, decline elicitation, no roots); the
`tui` shows it in a `server-initiated` table after each invocation. Pass
`--server-stream` (on `tui`, or interactive `call` / `read` / `prompt`) to also
keep the standalone GET event-stream open so idle server traffic surfaces - off
by default because some Streamable-HTTP servers drop the POST session when a
parallel GET stream is opened.

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

### `mcplense serve`

Runs McpLense itself as an MCP server over stdio, exposing `mcplense_inspect`,
`mcplense_scan`, `mcplense_analyze`, and `mcplense_explain` as tools (each takes a
`url`). Lets an agent introspect/security-scan OTHER MCP servers on demand. Add it to
an MCP host config like any stdio server. (This is for being hosted by an agent, not
for an agent to invoke as a subprocess.)

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
| `--format <text\|json\|markdown\|sarif\|dumpify>` | Output format (default `text`). `sarif`/`markdown` are findings/report oriented. |
| `--trace` | Log every HTTP MCP request/response (method, URL, JSON-RPC body, status, timing) to stderr. |
| `--watch <seconds>` | Re-run a read-only command (inspect/tools/resources/prompts/scan/analyze/explain/auth-scan/doctor) on an interval; flags when the output changed. Ctrl+C stops. |

## Picking flags by user intent

| User intent | Flag combo |
| --- | --- |
| Just want JSON I can pipe | `--format json` |
| Security findings with a CI gate | `mcplense analyze ... --fail-on high` |
| Findings for GitHub code scanning | `mcplense analyze ... --format sarif` |
| Detect tool changes since I trusted it | `analyze --approve f.json` then `analyze --since f.json` |
| Why won't it connect / see the wire | `mcplense doctor ...` / add `--trace` |
| How do I call this tool | `mcplense call <tool> ... --example` |
| Don't show the auth/matched/AuthProbe lines | `--quiet --format json` |
| Show me everything (headers, auth picks, probe reasoning) | `--verbose` |
| I want to test the bare unauthenticated surface | `--no-auth` |
| I only want the auth classification, no enumeration | `mcplense auth-scan ... --classify-only` |
| I want to also see RFC 8414 metadata | `mcplense scan ... --check-authorization-servers` |
| Save and compare scans over time | `--baseline ./baselines/` then `--diff <path>` |
| Fleet of MCPs in one go | `--targets-from fleet.txt --parallel-servers 8` |
