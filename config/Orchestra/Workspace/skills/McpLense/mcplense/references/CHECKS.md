# `mcplense scan` checks reference

Every check `mcplense scan` runs, what it emits under `checks.<id>`, and how to
enable / disable it. The top-level report shape is:

```json
{
  "generatedAt": "...",
  "schemaVersion": "1",
  "servers": [
    {
      "name": "...", "transport": "http", "target": "https://...",
      "checks":  { "<id>": <data> },
      "timings": { "<id>": <ms> }
    }
  ]
}
```

Default-enabled checks run out of the box. Default-disabled checks require either
the CLI `--enable <id>` flag or `scan.checks.<id>.enabled: true` in
`McpLense.Config.json`.

| Check id | Default | Depends on | What it emits |
| --- | --- | --- | --- |
| `auth` | on | — | RFC 9728 classification (`anonymous`, `oauth-rfc9728`, `oauth-bearer-unannounced`, `auth-required-unspecified`, `unknown`, `stdio`) + verbatim probe signals + per-profile attempts. |
| `transport` | on | — | Unauthenticated GET: status, TLS leaf cert (subject/issuer/notAfter/SANs/protocolVersion), security-relevant response headers, mixed-content flag. |
| `tlsChain` | on | `transport` | Intermediate chain + platform-validation outcome. |
| `authenticatedHeaders` | on | `auth` | Response headers from an authenticated GET (different from anon when servers gate HSTS / CSP behind auth). |
| `corsPreflight` | on | — | OPTIONS preflight against the MCP URL with synthetic Origin; every `Access-Control-*` header captured verbatim. |
| `authorizationServers` | off | `auth` | RFC 8414 / OIDC discovery for every advertised AS issuer. Toggled by CLI `--check-authorization-servers`. |
| `dcrEndpoint` | off | `authorizationServers` | RFC 7591 DCR endpoint probe (OPTIONS + empty POST). |
| `serverInfo` | on | — | `implementation.name` / `version` / `title` / `description` / `icons` / `websiteUrl`. |
| `protocol` | on | — | Negotiated protocol version + full `capabilities` block + verbatim `serverInstructions` + `sessionId`. |
| `tools` | on | — | Per-tool: `name`, `description`, `inputSchema`, annotations, `missingAnnotations`, `schemaFingerprint` (parameter counts, type histogram, format list, `hasAdditionalProperties`, ...). |
| `prompts` | on | — | Per-prompt: `name`, `description`, `arguments[]`, `icons`, `_meta`. |
| `resources` | on | — | Per-resource: `uri` + scheme, `name`, `mimeType`, `description`, `size`, annotations, `icons`. Plus top-level scheme histogram. |
| `stdio` | on (stdio only) | — | Resolved command line / args / cwd / env. |
| `behavior.callNonExistentTool` | on | — | Calls a tool name the server (presumably) doesn't expose; captures verbatim outcome — `tool-result-returned` / `jsonrpc-error` / `transport-error`. Reveals server-side error-handling leaks. |
| `behavior.callMalformed` | off | — | HTTP only. Sends deliberately malformed JSON-RPC (invalid JSON / not-JSON-RPC / missing `method`) and records the status + response per case. Robustness signal; the `analyze` rule `malformed-handling` flags any `5xx`. Opt-in. |
| `behavior.serverInitiated` | off | `auth` | Holds a session open; observes inbound `sampling/createMessage`, `elicitation/create`, `roots/list`, and the six notifications. Opt-in via config. |
| `metrics` | on | `protocol`, `tools`, `prompts` | Per text field (configurable): `charLength`, `lineCount`, `urlCount`, `urls[]`, markdown link / image / code-fence counts, non-ASCII / control / tab counts. |
| `hashing` | on | every visible check | Per-tool / -prompt / -resource `contentHash` (SHA-256 over canonical JSON) + a top-level `serverFingerprint`. Powers `mcplense diff`. |

## Per-check knobs

```jsonc
{
  "scan": {
    "checks": {
      "behavior.serverInitiated": {
        "enabled": true,
        "observationDurationSeconds": 5,
        "advertiseCapabilities": ["sampling", "elicitation", "roots", "listChanged"],
        "refusalPolicy": "silent"
      },
      "metrics": {
        "urlExtractionFields": ["serverInstructions", "toolDescription", "promptDescription"]
      },
      "authorizationServers": { "enabled": true }
    }
  }
}
```

| Check | Knob | Type | Default |
| --- | --- | --- | --- |
| any | `enabled` | bool | per the table above |
| `behavior.serverInitiated` | `observationDurationSeconds` | number | 2 |
| `behavior.serverInitiated` | `advertiseCapabilities` | string[] | `["sampling", "elicitation", "roots", "listChanged"]` |
| `behavior.serverInitiated` | `refusalPolicy` | `"silent"` \| `"error"` | `silent` |
| `metrics` | `urlExtractionFields` | string[] | `["serverInstructions", "toolDescription", "promptDescription"]` |

## Enable / disable precedence

Highest precedence wins:

1. CLI `--disable <id>` (always wins).
2. CLI `--enable <id>`.
3. Per-target `disabledChecks[]` (unioned with `--disable`).
4. `scan.checks.<id>.enabled` from the config file.
5. The check's `IsEnabledByDefault`.

Unknown check ids in config emit a stderr warning and are ignored.

## Custom checks

Custom `IScanCheck` implementations are added via the library's DI integration:

```csharp
using McpLense.Scanning;

var services = new ServiceCollection()
    .AddMcpLense()
    .AddScanCheck<MyCustomCheck>();
```

Each check is a single class implementing `IScanCheck` with `Id`, `DependsOn`,
`IsEnabledByDefault`, and `RunAsync(ScanContext, CancellationToken)`. The
pipeline topo-sorts by dependencies and runs independent checks in parallel.

See the library's `Scanning/Checks/` folder for examples.
