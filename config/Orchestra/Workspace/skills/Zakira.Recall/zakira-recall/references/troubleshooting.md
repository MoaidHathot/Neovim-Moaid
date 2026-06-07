# Troubleshooting reference

Use this when searches fail, results look empty or wrong, a provider is unhealthy, a consent page or captcha appears, or page fetches return obviously wrong content (consent walls, login forms).

## Triage in three commands

Run these in order before changing anything else:

```powershell
recall config show --output json
recall providers list --output json
recall providers test ddg
```

- `config show` confirms which config file and profile defaults are in use.
- `providers list` shows every registered provider, its aliases, capabilities, setup URL, and current health snapshot.
- `providers test <name>` runs an end-to-end probe against that provider.

If those work but a specific query fails, the issue is the query, the provider, or the profile — keep reading.

## Common failure modes and fixes

### 1. "Playwright not installed" or browser launch errors

Symptom: `WebSearch` with `duckduckgo-browser` or `bing`, or any `WebFetch`, fails with a chromium-not-found error.

Fix: install the chromium runtime once.

```powershell
pwsh "<install-dir>/playwright.ps1" install chromium
```

See `references/setup.md` for where `playwright.ps1` lives depending on how the tool was installed.

### 2. Provider returns 0 results or consent page

Symptom: `WebSearch` succeeds but `Results` is empty, or a `WebFetch` of the provider's domain returns text that says "accept cookies" or "verify you are human".

Fix: prepare an interactive profile, sign in / accept consent once, then reuse that profile.

```powershell
recall profile auth interactive --provider bing
# Browser opens, click through consent, then press Enter in the terminal.
```

Subsequent calls that pass `--profile <name>` (CLI) or `profile: <name>` (MCP) reuse the saved cookies.

For DuckDuckGo, retry with the browser variant if the HTTP one is blocked or rate-limited:

```powershell
recall search "site:github.com mcp server" --provider duckduckgo-browser
```

### 3. Provider is marked unhealthy

Symptom: a previously-working provider suddenly fails repeatedly; `WebGetProviderHealth` shows `IsHealthy: false` and a high `ConsecutiveFailures`.

The registry tracks failures in-process and avoids retrying a recently failing provider for a cooldown window (`providerHealthCooldownSeconds`, set in the config or profile).

Options:

- Wait out the cooldown. Default is set by the profile.
- Override the cooldown in the profile (`recall profile init <name> --provider-health-cooldown 30`, or edit `profiles.json` and set `providerHealthCooldownSeconds`).
- Enable fallback so search still works while the primary cools off:

```powershell
recall search "playwright mcp" --provider duckduckgo `
  --fallback true `
  --fallback-provider duckduckgo-browser bing
```

In MCP:

```json
{
  "query": "playwright mcp",
  "provider": "duckduckgo",
  "enableFallback": true,
  "fallbackProviders": ["duckduckgo-browser", "bing"]
}
```

Inspect health for a single provider:

```powershell
# CLI
recall providers list --output json
```

```json
// MCP
{ "tool": "WebGetProviderHealth", "input": { "provider": "bing" } }
```

Response shape:

```json
{
  "Provider": "bing",
  "IsHealthy": false,
  "ConsecutiveFailures": 3,
  "LastSuccessUtc": "2026-06-04T12:30:00Z",
  "LastFailureUtc": "2026-06-06T08:14:22Z"
}
```

### 4. Fetch returns the wrong page (consent, login, captcha)

Symptom: `WebFetch` reports `Success: true` but the `Text` is a cookie banner or login form.

Fix: use a profile that has accepted consent for that domain, or pre-warm it with the interactive auth flow.

```powershell
recall profile auth interactive --provider bing
recall fetch "https://www.bing.com/search?q=mcp" --profile interactive
```

For batch fetches (`WebBatchFetch`), the profile is shared across all URLs, so one profile that has accepted consent for the relevant domains is enough.

### 5. Research call returns `Success: true` but few `Sources`

This is expected when some pages fail to fetch. Inspect `Errors`:

```json
{
  "Errors": [
    { "Code": "FetchFailed", "Message": "Timeout", "Target": "https://slow-site.example/", "Transient": true }
  ]
}
```

Mitigations:

- Raise `timeoutSeconds` per fetch (via `--timeout` for `recall fetch`).
- Lower `maxConcurrentFetches` to reduce contention.
- Set `enforceDomainDiversity: false` if you want more chances from the same domain.
- Re-issue specific URLs via `WebFetch` for finer error handling.

### 6. "Provider not found" or unknown provider name

The registry resolves aliases, so `ddg` works for `duckduckgo`. List exact names and aliases:

```powershell
recall providers list --output json
```

Normalize a name yourself in MCP via the registry's `NormalizeProviderName` (used internally) — or just call `WebListProviders` and pick a `Name` from the response.

### 7. Wrong config file is being used

Symptom: settings you edited are not applied.

The CLI resolves the config in this order:

1. `--config <path>` if provided to the command.
2. `$XDG_CONFIG_HOME/Zakira.Recall/profiles.json` if `XDG_CONFIG_HOME` is set.
3. `%APPDATA%\Zakira.Recall\profiles.json` on Windows.

Check what's actually loaded:

```powershell
recall config show --output json
```

If you maintain multiple configs, pass `--config <path>` on each call (or via the MCP launch command).

### 8. CLI output is hard to parse

Default `--output` is `text`. For machine consumption pipe with `--output json`. For LLM-friendly notes use `--output markdown`. For interactive debugging use `--output dump`.

```powershell
recall providers list --output dump
recall research "agent skills" --output json | ConvertFrom-Json
```

## Operation error reference

`OperationError` (returned in `Errors` arrays and `FetchResponse.Error`) has:

| Field       | Notes                                                              |
|-------------|--------------------------------------------------------------------|
| `Code`      | Stable machine-readable code (e.g. `FetchFailed`, `SearchFailed`). |
| `Message`   | Human-readable description.                                        |
| `Provider`  | Provider that produced the error, if applicable.                   |
| `Target`    | The URL or query the error pertains to.                            |
| `Transient` | `true` if a retry might succeed (timeouts, rate limits).           |

When `Transient: true`, retry once; if it persists, fall back to a different provider or profile.

## Last resort

If nothing works, gather diagnostics for an issue report:

```powershell
recall config show --output json
recall providers list --output json
recall providers test ddg --output json
recall profile show default --output json
```

Then file an issue with those outputs at the project repository.
