---
name: mcplense
description: Inspect and scan Model Context Protocol (MCP) servers - list tools/resources/prompts, classify auth surface (anonymous / RFC 9728 OAuth / Bearer / custom challenge), capture TLS posture, audit OAuth/RFC 8414 authorization-server metadata, run behavioural probes (server-initiated sampling/elicitation/roots, call-non-existent-tool), and produce structured JSON reports with diff/baseline support. Use when the user asks to "inspect / scan / audit / list / test / observe an MCP server", "list tools/resources/prompts on an MCP", "diff two MCP scans", "find leaky tool descriptions", "check OAuth/auth setup of an MCP", "fetch a resource from an MCP", "set per-target headers on an MCP", or works with the `mcplense` CLI / `McpLense.Cli` dotnet tool / `McpLense` NuGet library.
license: Unlicense
compatibility: Requires the `mcplense` dotnet tool (`dotnet tool install -g McpLense.Cli`) and the .NET 10 runtime. Network access required for remote MCPs. Optional - Azure CLI / interactive browser for Entra-protected MCPs.
metadata:
  author: Moaid Hathot
  source: https://github.com/MoaidHathot/McpLense
  version: "0.4.0"
---

# mcplense

`mcplense` is a CLI + library for inspecting and scanning **Model Context Protocol (MCP)** servers. It connects, classifies auth, enumerates capabilities, captures TLS facts, runs behavioural probes, and emits a stable structured JSON report. Fact-only: the tool extracts data, consumers classify.

## When to invoke this skill

Trigger whenever the user wants to:

- **List or audit an MCP server**: tools / resources / prompts / capabilities / instructions.
- **Classify auth**: anonymous? RFC 9728 OAuth? bearer-without-metadata? custom challenge?
- **Run a full audit**: `scan` produces a structured per-check JSON report.
- **Compare two scans**: `diff` produces a structural delta between baselines.
- **Observe server-initiated traffic**: sampling, elicitation, roots, notifications.
- **Fetch a resource verbatim** from an MCP.
- **Call a tool** with arguments and capture the response.
- **Add per-target headers** (organization / project / tenant identifiers) to an MCP fleet.
- **Set up Entra ID / Azure CLI / Bearer auth** for an MCP.

## Quickstart

```bash
# Install once
dotnet tool install -g McpLense.Cli

# Inspect what an MCP exposes
mcplense inspect https://mcp.example.com/ --format json

# Full audit (every check, JSON report)
mcplense scan https://mcp.example.com/ --format json

# List capability subset
mcplense tools     https://mcp.example.com/ --format json
mcplense resources https://mcp.example.com/ --format json
mcplense prompts   https://mcp.example.com/ --format json

# Call a tool
mcplense call <tool-name> https://mcp.example.com/ --args '{"arg":"value"}'

# Save a baseline + diff later
mcplense scan https://mcp.example.com/ --baseline ./baselines/
mcplense scan https://mcp.example.com/ --diff ./baselines/mcp.example.com/<ts>.json
```

The `--format text|json|dumpify` flag controls output. **Default to `json`** when piping into other tools or when you want stable wire shape. Use the bare command + `text` for human reading.

## Choosing the right command

| User says... | Command |
| --- | --- |
| "What tools does this MCP have?" | `mcplense tools <url> --format json` |
| "Inspect this MCP" | `mcplense inspect <url> --format json` |
| "Audit / scan / security-check this MCP" | `mcplense scan <url> --format json` |
| "Is this MCP authed? what kind?" | `mcplense auth-scan <url> --format json` OR `mcplense scan <url> --classify-only` |
| "Diff two scans" | `mcplense diff <before>.json <after>.json` |
| "Call this tool" | `mcplense call <tool> <url> --args '<json>'` |
| "Read this resource" | `mcplense read <uri> <url>` OR `mcplense fetch-resource <uri> <url>` |
| "Send a prompt" | `mcplense prompt <name> <url> --args '<json>'` |
| "Watch server-initiated traffic" | `mcplense observe <url> --timeout 30` |
| "Log in / out to my MCP profile" | `mcplense login --profile <name>` / `mcplense logout` |

See [`references/COMMANDS.md`](references/COMMANDS.md) for every command + flag.

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
        "behavior.serverInitiated":     { ... },   // opt-in observation
        "metrics":              { ... },   // per-text-field char/line/url counts
        "hashing":              { ... }    // per-item contentHash + serverFingerprint
      },
      "timings": { "<check-id>": <milliseconds> }
    }
  ]
}
```

Every field is a fact, not a label. Downstream classification = jq filters; see [`references/CLASSIFICATION.md`](references/CLASSIFICATION.md) for ready-made recipes and [`scripts/`](scripts/) for handy one-liners.

## Frequently useful flags

| Flag | Effect |
| --- | --- |
| `--format json` | Stable JSON wire shape (recommended for piping). |
| `--quiet` | Suppress all stderr chatter. |
| `--verbose` | Show overlay header values + auth-resolution trace + per-probe diagnostics. |
| `--no-auth` | Skip every auth path; useful for diff'ing the bare unauthenticated surface. |
| `--profile <name>` | Force a specific profile, bypass auto-pick. |
| `--header NAME=VALUE` | Override / add a header for this run only. |
| `--enable <id>` / `--disable <id>` | Force a scan check on / off. |
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
- [`references/CONFIG.md`](references/CONFIG.md) — full `McpLense.Config.json` schema (`targets[]`, `targetPatterns[]`, `scan.checks.*`, `output`).
- [`references/AUTH.md`](references/AUTH.md) — auth profiles, scope substitution, MSAL cache, Azure CLI flow.
- [`references/CHECKS.md`](references/CHECKS.md) — per-`IScanCheck` reference: what each check emits and how it's enabled.
- [`references/CLASSIFICATION.md`](references/CLASSIFICATION.md) — jq recipes for downstream policy / risk classification.
- [`scripts/`](scripts/) — copy-paste-ready jq one-liners (top scopes, tools without annotations, expired TLS certs, etc.).
