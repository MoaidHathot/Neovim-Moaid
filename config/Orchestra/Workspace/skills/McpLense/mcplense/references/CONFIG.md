# `McpLense.Config.json` schema

The unified configuration file. Auto-discovered from:

- `$XDG_CONFIG_HOME/McpLense/McpLense.Config.json` (or `McpLense.Profiles.json` — both names load).
- `$XDG_CONFIG_HOME/McpLense/profiles/*.json` (per-profile layout, alphabetised).
- Windows fallback when `XDG_CONFIG_HOME` is unset: `%APPDATA%\McpLense\…`.
- Unix fallback: `~/.config/McpLense/…`.

Override with `--profiles <path>` (repeatable). Set
`MCPLENSE_NO_PROFILE_AUTO_DISCOVERY=1` to disable auto-discovery entirely.

## Top-level shape

```jsonc
{
  "authProfiles":   [...],   // unchanged from earlier releases - see AUTH.md
  "targets":        [...],   // per-URL header / profile / transport / timeout binding
  "targetPatterns": [...],   // URL-glob overlays that apply across many MCPs
  "scan": {
    "checks":       { ... }, // per-check toggle + knobs
    "output":       { ... }, // baseline directory etc.
    "schemaVersion": 1
  }
}
```

The four blocks are independent; only declare what you use.

## `targets[]`

Binds an exact MCP URL to a set of headers + an auth profile + transport / timeout
overrides + a list of checks to skip.

```jsonc
{
  "targets": [
    {
      "name":           "ec-foo",                       // optional; CLI ref via @ec-foo
      "url":            "https://example.ec.com/foo/mcp",
      "headers": {
        "x-mcp-ec-organization": "msazure",
        "x-mcp-ec-project":      "One",
        "x-mcp-ec-repository":   "ZTS",
        "x-some-token":          "${MY_TOKEN}"          // env-expanded
      },
      "scope":          "All",                          // "All" (default) | "Session"
      "profile":        "agent365",                     // optional; binds an authProfile by name
      "transport":      "streamable-http",              // optional
      "timeoutSeconds": 90,                             // optional
      "disabledChecks": ["corsPreflight"]               // optional; union with CLI --disable
    }
  ]
}
```

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | Short identifier. Case-insensitive. Duplicates across files = error. |
| `url` | string | Required. Exact URL match (case-insensitive scheme + host, case-sensitive path, trailing slash ignored). |
| `headers` | `{ string: string }` | Values run through env-expander (`env:VAR`, `${VAR}`, `${VAR:-default}`). |
| `scope` | `"All"` (default) \| `"Session"` | Header coverage. See below. |
| `profile` | string | Auth profile name to bind. CLI `--profile` overrides. |
| `transport` | `"auto"` \| `"streamable-http"` \| `"sse"` | HTTP transport mode. |
| `timeoutSeconds` | number | Per-server handshake timeout. Overrides CLI `--timeout`. |
| `disabledChecks` | string[] | Check ids to skip. Union with CLI `--disable`. |

## `targetPatterns[]`

URL-glob overlays applying to every MCP whose URL matches. Same field shape as
`targets[]` but with `match` instead of `url` / `name`.

```jsonc
{
  "targetPatterns": [
    {
      "match":   "https://*.example.com/**",
      "headers": { "x-mcp-ec-organization": "default-org" },
      "scope":   "All"
    },
    {
      "match":   "https://**bluebird**/**",
      "headers": {
        "x-mcp-ec-organization": "msazure",
        "x-mcp-ec-project":      "One",
        "x-mcp-ec-repository":   "ZTS"
      }
    }
  ]
}
```

Pattern entries are the **least-specific** layer: named `targets[]` entries
override matching patterns; CLI flags override both. Per-header-key last-write-wins.

### Glob syntax

- `*` — single host label OR single path segment (no `/`, no `.` in host).
- `**` — any sequence including `/` (and `.` in host).
- `?` — single character (no `/`, no `.` in host).
- Literal: case-insensitive on host, case-sensitive on path (browser convention).
- Default ports (`:443` for `https`, `:80` for `http`) normalise away.
- The scheme separator `://` is required.
- Query strings and fragments are stripped before matching.

| Pattern | Matches |
| --- | --- |
| `https://api.example.com/mcp` | exact URL only |
| `https://*.example.com/mcp` | any single subdomain |
| `https://*.example.com/**` | any subdomain, any path |
| `https://**.example.com/**` | any depth of subdomain |
| `https://**bluebird**/**` | host containing `bluebird` anywhere |
| `https://example.com/api/*/mcp` | `api/v1/mcp`, `api/v2/mcp`, ... |

Malformed patterns (missing scheme, empty host) get a stderr warning and the
pattern is skipped — other patterns + targets keep working.

## `scope`: `All` vs `Session`

| Scope | MCP session (`initialize` + JSON-RPC) | Same-origin probes (transport, CORS, authenticated-headers, DCR, RFC 9728 metadata) |
| --- | --- | --- |
| `All` (default) | Headers sent | Headers sent |
| `Session` | Headers sent | Headers stripped |

Cross-origin fetches (e.g. authorization-server metadata at
`login.microsoftonline.com`, DCR endpoint on the AS host) **never** receive
MCP-server headers, regardless of scope. This is a security guard and cannot be
disabled.

Use `Session` to inspect a server's bare unauthenticated challenge while the
session still authenticates normally.

## Resolution & precedence (per scanned URL)

The resolver merges (in order, last-write-wins per header key):

1. Every matching `targetPatterns[]` entry, in declaration order.
2. The matching `targets[]` entry, picked by:
   - The `@<name>` positional (if used), OR
   - Exact URL match against `targets[].url` (auto-resolution).
3. CLI flags (`--header`, `--profile`, `--transport`, `--timeout`, `--disable`).

The overlay applies uniformly to every command that opens an MCP connection
(`inspect`, `tools`, `resources`, `prompts`, `call`, `read`, `prompt`,
`fetch-resource`, `auth-scan`, `observe`, `scan`).

Verify what matched on stderr:

```
matched: patterns=1 target=ec-foo -> 3 headers, scope=all
```

Under `--verbose`, each header (and pattern) is also listed by name + value
(sensitive header values redacted to length-only).

## `scan` block

```jsonc
{
  "scan": {
    "checks": {
      "auth":                       { "enabled": true },
      "authorizationServers":       { "enabled": true },
      "behavior.serverInitiated": {
        "enabled": false,
        "observationDurationSeconds": 2,
        "advertiseCapabilities": ["sampling", "elicitation", "roots", "listChanged"],
        "refusalPolicy": "silent"
      },
      "metrics": {
        "enabled": true,
        "urlExtractionFields": ["serverInstructions", "toolDescription", "promptDescription"]
      },
      "dcrEndpoint": { "enabled": false }
    },
    "output": {
      "baselineDir": "./baselines",
      "format":      "json"
    },
    "schemaVersion": 1
  }
}
```

Per-check `enabled` flag wins over the check's default. CLI `--enable` /
`--disable` flags win over both. Unknown check ids emit a stderr warning and are
ignored (typos don't silently degrade).

Per-check knobs:

| Check | Knobs |
| --- | --- |
| `auth` | none beyond `enabled`. |
| `behavior.serverInitiated` | `observationDurationSeconds`, `advertiseCapabilities` (`sampling`, `elicitation`, `roots`, `listChanged`), `refusalPolicy` (`silent`, `error`). |
| `metrics` | `urlExtractionFields` (`serverInstructions`, `toolDescription`, `promptDescription` by default). |
| `authorizationServers` | none beyond `enabled` (toggled by CLI `--check-authorization-servers`). |
| `dcrEndpoint` | none beyond `enabled`. |

See [CHECKS.md](CHECKS.md) for the full per-check reference.

## `analysis` block

Top-level block (peer of `scan` and `authProfiles`) that configures the `analyze` / `scan --findings`
layer. The scan stays fact-only; this only tunes the opinionated findings layer.

```jsonc
{
  "analysis": {
    "failOn": "high",                 // default CI-gate threshold; --fail-on overrides it
    "rules": {
      "description-url":          { "enabled": false },    // turn a rule off
      "missing-destructive-hint": { "severity": "medium" } // re-rate a rule's findings
    }
  }
}
```

| Key | Effect |
| --- | --- |
| `failOn` | `info`/`low`/`medium`/`high`/`critical`. Process exits non-zero when any finding ≥ it. `--fail-on` overrides. |
| `rules.<id>.enabled` | Turn a rule on/off (overrides its built-in default). |
| `rules.<id>.severity` | Override the severity a rule assigns to its findings. |

Rule ids: `prompt-injection`, `anonymous-destructive`, `weak-cors`, `mixed-content`,
`tls-chain-invalid`, `tls-expiry`, `open-shape-input`, `error-info-leak`, `malformed-handling`,
`description-url`, `missing-destructive-hint`, `unannounced-bearer`, `rug-pull`. See
[`docs/analysis-rules.md`](../../../docs/analysis-rules.md) for the full reference.

## Environment-variable expansion

Every string value (in `targets[]`, `targetPatterns[]`, and `authProfiles[]`)
passes through the standard expander:

- `env:VAR` — whole-string form. Errors when `VAR` is unset.
- `${VAR}` — substring form. Errors when `VAR` is unset.
- `${VAR:-default}` — substring form with default fallback (bash `:-` semantics).
- `$$` — literal `$`.

## Worked example

The sample at [`samples/targets.json`](../../../samples/targets.json) in the
repo combines patterns, named targets, `scope: All` vs `Session`, env-expansion,
and a per-target `profile` binding.
