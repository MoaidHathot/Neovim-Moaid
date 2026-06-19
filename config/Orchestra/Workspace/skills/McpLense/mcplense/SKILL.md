---
name: mcplense
description: Explore, debug, and security-scan Model Context Protocol (MCP) servers - list tools/resources/prompts, call tools (and generate example args), classify auth surface (anonymous / RFC 9728 OAuth / Bearer / custom challenge), capture TLS posture, audit OAuth/RFC 8414 authorization-server metadata, run behavioural probes (server-initiated sampling/elicitation/roots, call-non-existent-tool, malformed-input handling), and produce stable JSON reports with diff/baseline support. The opt-in `analyze` layer turns the facts into severity-rated security findings (prompt-injection signals, anonymous destructive tools, weak CORS, TLS issues, rug-pull / tool-poisoning detection) with a `--fail-on` CI gate and SARIF output. Also: `explain` (plain-language summary), `doctor` (connectivity triage), `--trace` (JSON-RPC wire log), and `serve` (run McpLense itself as an MCP server). Use when the user asks to "inspect / scan / audit / analyze / explain / debug an MCP server", "list or call tools on an MCP", "find prompt injection or insecure tools", "diff two MCP scans", "check OAuth/auth setup of an MCP", "why won't my MCP connect", or works with the `mcplense` CLI / `McpLense.Cli` dotnet tool / `McpLense` NuGet library.
license: Unlicense
compatibility: Requires the .NET 10 runtime. Run without installing via `dnx McpLense.Cli <args>`, or install the tool with `dotnet tool install -g McpLense.Cli` (command: `mcplense`). Network access required for remote MCPs. Optional - Azure CLI / interactive browser for Entra-protected MCPs.
metadata:
  author: Moaid Hathot
  source: https://github.com/MoaidHathot/McpLense
  version: "0.17.0"
---

# mcplense

`mcplense` is a CLI + library for exploring, debugging, and security-scanning **Model Context Protocol (MCP)** servers. It connects, classifies auth, enumerates capabilities, captures TLS facts, runs behavioural probes, and emits a stable structured JSON report. The scan is fact-only (it extracts data, never labels it); the opt-in `analyze` layer is a separate consumer that turns the facts into severity-rated security **findings**.

## When to invoke this skill

Trigger whenever the user wants to:

- **List or audit an MCP server**: tools / resources / prompts / capabilities / instructions.
- **Call a tool** (or generate an example call from its input schema).
- **Security-scan / analyze an MCP**: severity-rated findings, a CI gate, SARIF, rug-pull detection.
- **Explain an MCP** in plain language ("what is this and is it safe?").
- **Classify auth**: anonymous? RFC 9728 OAuth? bearer-without-metadata? custom challenge?
- **Diagnose connectivity** ("why won't my MCP connect?") or **trace** the JSON-RPC wire.
- **Compare two scans** (`diff`) or **detect drift** since an approved baseline.
- **Observe server-initiated traffic**: sampling, elicitation, roots, notifications.
- **Add per-target headers** (organization / project / tenant identifiers) to an MCP fleet.
- **Set up Entra ID / Azure CLI / Bearer auth** for an MCP.
- **Run McpLense as an MCP server** so an agent can audit other MCPs.

## Quickstart

```bash
# Run without installing (.NET 10) - or `dotnet tool install -g McpLense.Cli` then use `mcplense`
dnx McpLense.Cli inspect https://mcp.example.com/ --format json

# Security findings (opt-in analysis layer over the fact-only scan) + CI gate
dnx McpLense.Cli analyze https://mcp.example.com/ --fail-on high
dnx McpLense.Cli analyze https://mcp.example.com/ --format sarif > mcplense.sarif

# Plain-language summary / connectivity triage
dnx McpLense.Cli explain https://mcp.example.com/
dnx McpLense.Cli doctor  https://mcp.example.com/

# Full fact-only audit (every check, JSON report)
dnx McpLense.Cli scan https://mcp.example.com/ --format json

# Call a tool (or generate a ready-to-edit example from its schema)
dnx McpLense.Cli call <tool-name> https://mcp.example.com/ --args '{"arg":"value"}'
dnx McpLense.Cli call <tool-name> https://mcp.example.com/ --example

# Save a baseline + diff later; or rug-pull detection
dnx McpLense.Cli scan https://mcp.example.com/ --baseline ./baselines/
dnx McpLense.Cli analyze https://mcp.example.com/ --approve approved.json
dnx McpLense.Cli analyze https://mcp.example.com/ --since approved.json --fail-on high
```

The `--format text|json|markdown|sarif|dumpify` flag controls output. **Default to `json`** when piping into other tools. Use `text` (the default) for human reading, `markdown` for a shareable write-up, and `sarif` for findings in CI.

## Choosing the right command

| User says... | Command |
| --- | --- |
| "What tools does this MCP have?" | `mcplense tools <url> --format json` |
| "Inspect this MCP" | `mcplense inspect <url> --format json` |
| "Explain / summarize this MCP" | `mcplense explain <url>` |
| "Is this MCP secure / find vulnerabilities" | `mcplense analyze <url>` (add `--fail-on high` for a gate, `--format sarif` for CI) |
| "Audit / scan this MCP (facts only)" | `mcplense scan <url> --format json` |
| "Did this MCP's tools change since I approved it?" | `mcplense analyze <url> --approve f.json` then `--since f.json` |
| "Is this MCP authed? what kind?" | `mcplense auth-scan <url> --format json` OR `mcplense scan <url> --classify-only` |
| "Why won't this MCP connect?" | `mcplense doctor <url>` |
| "Show me the JSON-RPC traffic" | add `--trace` to any command |
| "Re-run as it changes" | add `--watch <seconds>` to a read-only command |
| "How do I call this tool?" | `mcplense call <tool> <url> --example` |
| "Call this tool" | `mcplense call <tool> <url> --args '<json>'` |
| "Read this resource" | `mcplense read <uri> <url>` OR `mcplense fetch-resource <uri> <url>` |
| "Diff two scans" | `mcplense diff <before>.json <after>.json` |
| "Watch server-initiated traffic" | `mcplense observe <url> --timeout 30` |
| "Run McpLense as an MCP server" | `mcplense serve` |
| "Log in / out to my MCP profile" | `mcplense login --profile <name>` / `mcplense logout` |

See [`references/COMMANDS.md`](references/COMMANDS.md) for every command + flag.

## Security findings (`analyze`)

`scan` is fact-only. `mcplense analyze <url>` runs the same scan, then applies a built-in rule pack
and emits a `FindingsReport` (`servers[].findings[]`, each with `ruleId`, `severity` info→critical,
`evidencePath` into the scan facts, and `remediation`). Rules cover prompt-injection signals (hidden
bidi/zero-width chars + instruction-hijacking phrases in tool descriptions), anonymous servers
exposing destructive/open-world tools, open-shape input schemas, weak CORS, mixed content, TLS
posture, error info-leak, and rug-pull (tool changed vs an approved baseline).

- `--fail-on <severity>` exits non-zero at/above the threshold (CI gate).
- `--format sarif` emits SARIF 2.1.0 for GitHub code scanning.
- `--approve <file>` snapshots the current tool hashes; `--since <file>` flags any change as `rug-pull`.
- Rules + severities are config-driven via the top-level `analysis` block in `McpLense.Config.json`
  (`analysis.rules.<id>.enabled` / `.severity`, `analysis.failOn`).

See [`docs/analysis-rules.md`](../../docs/analysis-rules.md) for the rule reference.

## Learning & debugging

- `mcplense explain <url>` - plain-language narrative (identity, auth, what it exposes, notable tools,
  findings summary). `--format markdown` for a shareable write-up.
- `mcplense call <tool> <url> --example` - generate a filled-in `--args` template from the tool's
  input schema (does not invoke).
- `mcplense doctor <url>` - staged connectivity triage (DNS → TCP → TLS → MCP initialize → auth) with
  a fix-it hint per failed stage; non-zero exit on failure.
- `--trace` - log every HTTP MCP request/response (method, URL, JSON-RPC body, status, timing) to stderr.
- `--watch <seconds>` - re-run a read-only command on an interval, flagging when the output changed.
- `mcplense serve` - run McpLense as a stdio MCP server (tools: `mcplense_inspect` / `_scan` /
  `_analyze` / `_explain`) so an agent can audit other MCPs.

## Authentication: pick one strategy

**Default = profiles.** Profiles describe HOW to authenticate, decoupled from URLs. The same profile services every MCP that accepts those credentials.

- **Bearer (static token)**: simplest. Inline ad-hoc with `--auth bearer --auth-token <value>`, or define a profile.
- **Entra ID interactive-browser**: M365 / Agent365 servers. First-time pops a browser; subsequent runs reuse a token from the OS credential store (DPAPI / Keychain / libsecret).
- **Entra ID via Azure CLI** (`azure-cli`): delegates to `az login`. No browser, no MSAL cache — best for CI / headless / SSH.
- **OAuth (MCP spec, RFC 9728 / 8414 / 7591)**: generic MCP-spec OAuth with discovery + DCR.

Profile files live at `$XDG_CONFIG_HOME/McpLense/McpLense.Profiles.json` (or `%APPDATA%\McpLense\` on Windows) and auto-load. Override with `--profiles <path>`. Pick one profile with `--profile <name>` or let auto-pick decide (cache-hit first, then priority).

See [`references/AUTH.md`](references/AUTH.md) for full profile schema + scope substitution rules.

### Verifying which profile is in use

Every command prints `auth: …` lines on stderr by default. `--verbose` adds the resolution trace (probe classification → cache check → final pick + reason):

```
auth: 2 profile(s) loaded ...: agent365(InteractiveBrowser), agent365-cli(AzureCli)
auth: ... - probe classification=inconclusive.
auth: ... - cached profiles: agent365-cli.
auth: ... - profile picked by cache-hit + precedence: 'agent365-cli' (priority=400).
auth: ... -> profile='agent365-cli' kind=AzureCli (auto-picked), scopes=[...]
```

## Per-target headers (organization / project / tenant identifiers)

Enterprise MCPs often gate access on custom headers (e.g. `x-mcp-ec-organization`). Declare them once in `McpLense.Config.json` (or `McpLense.Profiles.json` — both names auto-load) and they apply uniformly across every command:

```jsonc
{
  "targetPatterns": [
    {
      "match":   "https://*.example.com/**",
      "headers": { "x-mcp-ec-organization": "default-org" },
      "scope":   "All"
    }
  ],
  "targets": [
    {
      "name":   "ec-foo",
      "url":    "https://example.ec.com/foo/mcp",
      "headers": {
        "x-mcp-ec-organization": "msazure",
        "x-mcp-ec-project":      "One",
        "x-mcp-ec-repository":   "ZTS"
      },
      "scope":   "All",
      "profile": "agent365"
    }
  ]
}
```

Reference by name: `mcplense scan @ec-foo`. Override CLI-side: `--header x-mcp-ec-project=other`.

Confirm headers are flowing with `--verbose`:

```
matched: patterns=1 target=ec-foo -> 3 headers, scope=all
matched headers for https://example.ec.com/foo/mcp:
  x-mcp-ec-organization: msazure
  x-mcp-ec-project: One
  x-mcp-ec-repository: ZTS
matched pattern(s): https://*.example.com/**
```

Glob: `*` = single host label OR path segment, `**` = any sequence including `/`. Host case-insensitive, path case-sensitive. `scope: "All"` (default) extends headers to same-origin probes (transport probe, CORS preflight, authenticated-headers, RFC 9728 metadata when same-origin); `scope: "Session"` keeps probes bare. **Cross-origin probes never receive MCP-server headers regardless of scope** — a security guard you cannot disable.

See [`references/CONFIG.md`](references/CONFIG.md) for the full config schema.

## Scan-report shape (stable wire JSON)

`mcplense scan <url> --format json` emits:

```jsonc
{
  "generatedAt": "2026-05-19T04:21:42Z",
  "schemaVersion": "1",
  "servers": [
    {
      "name":     "...",
      "transport": "http",
      "target":   "https://...",
      "checks": {
        "auth":                 { ... },   // RFC 9728 classification + profile attempts
        "transport":            { ... },   // unauthenticated probe: status, TLS, headers
        "tlsChain":             { ... },   // intermediate chain + validation outcome
        "authenticatedHeaders": { ... },   // headers from an authenticated GET
        "corsPreflight":        { ... },   // OPTIONS preflight observation
        "authorizationServers": { ... },   // RFC 8414 fields (opt-in)
        "dcrEndpoint":          { ... },   // RFC 7591 DCR probe (opt-in)
        "serverInfo":           { ... },   // implementation/name/version/title
        "protocol":             { ... },   // negotiated version + capabilities + instructions
        "tools":                { ... },   // per-tool name + description + schemas + annotations
        "prompts":              { ... },
        "resources":            { ... },
        "stdio":                { ... },   // stdio-only
        "behavior.callNonExistentTool": { ... },
        "behavior.callMalformed":       { ... },   // opt-in: malformed-input handling
        "behavior.serverInitiated":     { ... },   // opt-in observation
        "metrics":              { ... },   // per-text-field char/line/url counts
        "hashing":              { ... }    // per-item contentHash + serverFingerprint
      },
      "timings": { "<check-id>": <milliseconds> }
    }
  ]
}
```

Every field is a fact, not a label. To turn facts into severity-rated findings use `mcplense analyze`
(the built-in rule pack); for custom downstream classification, jq filters work too — see
[`references/CLASSIFICATION.md`](references/CLASSIFICATION.md) and [`scripts/`](scripts/).

## Frequently useful flags

| Flag | Effect |
| --- | --- |
| `--format json` | Stable JSON wire shape (recommended for piping). `markdown`, `sarif`, `dumpify` also available. |
| `--findings` (scan) / `analyze` | Run the analysis layer; `analyze` emits a `FindingsReport`. |
| `--fail-on <severity>` | CI gate: exit non-zero if a finding ≥ severity (info/low/medium/high/critical). |
| `--approve <file>` / `--since <file>` | Snapshot tool hashes / detect rug-pull drift since the snapshot. |
| `--example` (call) | Print a generated `--args` template from the tool's input schema (no invocation). |
| `--trace` | Log every HTTP MCP request/response (JSON-RPC body, status, timing) to stderr. |
| `--watch <seconds>` | Re-run a read-only command on an interval; flag when output changed. |
| `--quiet` | Suppress all stderr chatter. |
| `--verbose` | Show overlay header values + auth-resolution trace + per-probe diagnostics. |
| `--no-auth` | Skip every auth path; useful for diff'ing the bare unauthenticated surface. |
| `--profile <name>` | Force a specific profile, bypass auto-pick. |
| `--header NAME=VALUE` | Override / add a header for this run only. |
| `--enable <id>` / `--disable <id>` | Force a scan check on / off (e.g. `--enable behavior.callMalformed`). |
| `--baseline <dir>` | After scan, write the report under `<dir>/<host>/<UTC-timestamp>.json`. |
| `--diff <baseline.json>` | After scan, emit a structural diff vs the baseline instead of the report. |
| `--parallel-servers N` | Fleet scans: how many servers concurrently (default 1). |
| `--check-authorization-servers` | Opt in to fetching RFC 8414 / OIDC discovery metadata. |
| `--classify-only` | Skip profile attempts + enumeration; emit only the auth-classification block. |
| `--timeout <seconds>` | Per-server handshake timeout (default 30). |

## Common errors / how to act

- **405 Method Not Allowed** on `GET <url>`: server only accepts `POST` at that path. Likely wrong URL — try `/mcp`, `/sse`, `/api/mcp`. The 405 is not an auth failure.
- **`AuthProbe: ... inconclusive`**: classification unclear; tool still tries the configured profile.
- **`auth: ... -> no profile resolved; sending unauthenticated`**: no profile matched the URL; use `--profile <name>` or `--no-auth`.
- **`Duplicate target name '...' across config files`**: rename one entry; target names are globally unique.
- **`Target reference '@<name>' was not found`**: no `targets[]` entry with that name; check the config file or fall back to a positional URL.
- **Stdio command target hangs**: use `--timeout 15` to bound; check the command + args.

## Output format guidance

Prefer **`--format json`** when:
- piping into `jq`, `python -m json.tool`, or any consumer that needs structure.
- writing scripts / pipelines.
- comparing across versions or producing baselines for `diff`.

Prefer **default `text`** for one-off human inspection. Use **`dumpify`** when the user explicitly asks for the .NET-style dumped representation.

## See also

- [`references/COMMANDS.md`](references/COMMANDS.md) — every command + flag.
- [`references/CONFIG.md`](references/CONFIG.md) — full `McpLense.Config.json` schema (`targets[]`, `targetPatterns[]`, `scan.checks.*`, `analysis.*`, `output`).
- [`references/AUTH.md`](references/AUTH.md) — auth profiles, scope substitution, MSAL cache, Azure CLI flow.
- [`references/CHECKS.md`](references/CHECKS.md) — per-`IScanCheck` reference: what each check emits and how it's enabled.
- [`references/CLASSIFICATION.md`](references/CLASSIFICATION.md) — jq recipes for downstream policy / risk classification.
- [`docs/analysis-rules.md`](../../docs/analysis-rules.md) — built-in `analyze` findings rules, the `analysis` config block, SARIF, and rug-pull detection.
- [`scripts/`](scripts/) — copy-paste-ready jq one-liners (top scopes, tools without annotations, expired TLS certs, etc.).
