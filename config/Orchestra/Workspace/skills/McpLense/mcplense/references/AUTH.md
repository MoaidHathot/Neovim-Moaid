# `mcplense` authentication reference

`mcplense` uses **auth profiles**: named, reusable authentication recipes that
describe HOW to authenticate, decoupled from any specific URL. The same profile
can service every MCP it can authenticate to.

## Supported auth kinds

| Kind | How it works | Best for |
| --- | --- | --- |
| `bearer` | Static token from the profile or `--auth-token`. | Token-based services (GitHub, custom APIs). |
| `oauth` | MCP-spec OAuth 2.1 with RFC 9728 / 8414 / 7591 / 7636 (PKCE). | Generic MCP-spec OAuth flow. |
| `interactive-browser` | Microsoft Entra ID via MSAL + `Azure.Identity.InteractiveBrowserCredential`. | Microsoft 365 / Agent365 / Entra-protected MCPs with an interactive user. |
| `azure-cli` | Microsoft Entra ID via `az account get-access-token --resource <scope>`. | Headless / CI / SSH where `az login` is already done. |

Stdio (process) targets never carry authentication.

## Profile file shape (`authProfiles[]`)

```jsonc
{
  "authProfiles": [
    {
      "name": "agent365",
      "auth": {
        "type":     "interactive-browser",
        "clientId": "env:VSCODE_CLIENT_ID",
        "tenantId": "env:CORP_TENANT_ID",
        "scopes":   ["${VSCODE_AUDIENCE}/.default"]
      },
      "priority": 500
    },
    {
      "name": "agent365-cli",
      "auth": {
        "type":     "azure-cli",
        "tenantId": "env:CORP_TENANT_ID",
        "scopes":   ["${VSCODE_AUDIENCE}/.default"]
      }
    },
    {
      "name": "github",
      "auth": { "type": "bearer", "token": "env:GITHUB_TOKEN" }
    },
    {
      "name": "self-hosted-mcp",
      "auth": {
        "type":   "oauth",
        "scopes": ["mcp.read", "mcp.write"]
      }
    }
  ]
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `name` | yes | Globally unique across all loaded files. Case-insensitive. |
| `auth.type` | yes | One of `bearer`, `oauth`, `interactive-browser`, `azure-cli`. |
| `auth.token` | when `bearer` | Static token. Env-expandable. |
| `auth.clientId` | when `interactive-browser` | Pre-registered Entra public client id. |
| `auth.tenantId` | usually | Entra tenant (GUID / domain / `common` / `organizations`). |
| `auth.scopes` | usually | Array of scope strings. `.default` form is supported. |
| `auth.cacheName` | no | MSAL cache key override (default: profile name). |
| `auth.issuer` / `authorizationEndpoint` / `tokenEndpoint` / `registrationEndpoint` / `resourceMetadataUrl` / `resourceUri` | no | Bypass discovery; useful when a server doesn't advertise standard metadata. |
| `priority` | no | Higher = preferred in the tiebreaker. Defaults by kind: `azure-cli`=400, `interactive-browser`=300, `oauth`=200, `bearer`=100. |

## Profile auto-pick (when `--profile` is omitted)

For each MCP being scanned, the resolver:

1. **Probes the URL** for RFC 9728 metadata. Advertised scopes narrow the
   candidate set.
2. **Cache check** — for each candidate, does `MsalCacheInspector` report a
   cached account? Profiles with cached credentials are preferred over those
   without ("the credentials you already have" beats "the priority you set").
3. **Precedence tiebreaker** — among the cached set (or all candidates when no
   cache hits), the highest `EffectivePriority` wins. Ties surface as an
   actionable error asking the user to disambiguate with `--profile`.

Inspect the decision in stderr with `--verbose`:

```
auth: 2 profile(s) loaded ...: agent365(InteractiveBrowser), agent365-cli(AzureCli)
auth: ... - probe classification=inconclusive.
auth: ... - cached profiles: agent365-cli.
auth: ... - profile picked by cache-hit + precedence: 'agent365-cli' (priority=400).
auth: ... -> profile='agent365-cli' kind=AzureCli (auto-picked), scopes=[...]
```

## Scope substitution (`.default` -> advertised scopes)

When a profile's scopes are ALL of the `<resource>/.default` form, the resolver
substitutes them with what the server's RFC 9728 protected-resource-metadata
document advertises. This is what lets one Entra profile work against multiple
namespaced MCP servers (e.g. every Agent365 MCP under a tenant) without
per-server duplication.

Substitution preference (first non-empty wins):

1. **Specific advertised scopes** (non-`.default`, non-OIDC-standard). Bare
   names get fully-qualified using the metadata's `resource` field.
2. **Advertised `.default` forms** (when the server only publishes `.default`).
3. **The profile's original scopes** (no substitution).

Standard OIDC scopes (`openid`, `profile`, `offline_access`, `email`) are
excluded from the "specific" set.

## Login / logout commands

```bash
# Force interactive login for one profile (e.g. clear MSAL cache and re-auth)
mcplense login --profile agent365

# Log in to every loaded profile (skips ones already cached)
mcplense login --all

# Auto-pick a profile for a URL, then log in
mcplense login https://mcp.example.com/

# Logout: mirror semantics
mcplense logout --profile agent365
mcplense logout --all
mcplense logout https://mcp.example.com/
```

## Ad-hoc CLI auth (Bearer only)

```bash
mcplense inspect https://api.example.com/mcp \
  --auth bearer --auth-token env:API_TOKEN
```

`--auth bearer` is the only ad-hoc form. Anything more sophisticated (OAuth,
Entra) must come from a profile.

`--no-auth` strips authentication on every command (HTTP and stdio).

## Disabling auto-discovery

Set `MCPLENSE_NO_PROFILE_AUTO_DISCOVERY=1` (or `true`/`yes`/`on`) to skip the
XDG/APPDATA fallback. `--profiles <path>` flags still work. Useful for CI
runners + integration test suites that must never trigger surprise interactive
flows.

## Verifying auth headers reach the server

`mcplense` prints `auth: …` lines on every non-quiet run that exercises auth.
Combine with the overlay's `matched: …` line for full visibility:

```
matched: patterns=1 target=ec-foo -> 3 headers, scope=all
matched headers for https://example.com/mcp:
  x-mcp-ec-organization: msazure
  x-mcp-ec-project: One
  x-mcp-ec-repository: ZTS
matched pattern(s): https://*.example.com/**
auth: 1 profile(s) loaded from ...: agent365(InteractiveBrowser)
auth: ... -> profile='agent365' kind=InteractiveBrowser (auto-picked), scopes=[...]
```

Sensitive header values (`Authorization`, `Cookie`, `x-api-key`, anything
ending in `-token` / `-secret` / `-password`, anything containing `apikey`)
print as `<redacted, length=N>` even under `--verbose`.
