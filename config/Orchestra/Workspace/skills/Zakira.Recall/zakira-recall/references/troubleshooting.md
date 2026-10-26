# Troubleshooting reference

Use this when searches fail, results look empty or wrong, a provider is unhealthy, a consent page or captcha appears, or page fetches come back with an error code or with obviously wrong content (consent walls, login forms, verification pages).

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

If those work but a specific query or URL fails, the issue is the query, the page, the provider, or the profile; keep reading.

## Reading a failed fetch

A `FetchResponse` with `success: false` always has `error.code`, and usually `statusCode`, `text` and `contentSelector` as well. Decide from the code:

| `error.code`           | What happened                                                                | What to do                                                                                      |
|------------------------|------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|
| `fetch_http_error`     | Server answered 4xx/5xx; `statusCode` has the value, `text` has the error page. | 404/410: the URL is gone, search for a replacement. 401/403: try a profile with cookies for that site. 429/5xx (`transient: true`): retry once after a pause. |
| `fetch_bot_challenge`  | A verification or block page (Cloudflare "Just a moment...", "Sorry, you have been blocked", Akamai "Access Denied", PerimeterX "Press & Hold"). | Retry once (`transient: true`). If it persists, fetch through a profile that has visited the site interactively (see 4), or use a different source for the same content. |
| `fetch_login_required` | A login wall.                                                                | Use a profile that is signed in to that site, or a different source. Retrying is pointless.     |
| `fetch_weak_content`   | Fewer than 15 readable words: an empty shell, an app that renders nothing without interaction, or a redirect stub. | Raise `timeoutSeconds` for slow SPAs; otherwise the page has no readable content.               |
| `fetch_failed`         | The browser could not load the page: `net::ERR_NAME_NOT_RESOLVED`, connection refused, navigation timeout, or a browser/driver error. | Check the URL. Timeouts and browser errors are `transient: true`; retry once.                    |

A response with `success: true` but a small `wordCount` (a few dozen words for what should be an article) means the readable content was not
reached: look at `contentSelector` (which element was used) and `statusCode`, and read `text` to see whether it is a consent page.

## Common failure modes and fixes

### 1. Browser not found or browser launch errors

Symptom: `web_search` with `duckduckgo-browser` or `bing`, or any `web_fetch`, fails with a message like
`Browser channel 'msedge' is not installed on this machine` or `The Playwright Chromium browser is not installed`.

The default profile channel is `msedge` (the installed Microsoft Edge). Either install Edge, or switch the profile to Playwright's bundled
Chromium and install it once:

```powershell
recall profile init default --channel chromium --provider duckduckgo --headless true
pwsh "<install-dir>/playwright.ps1" install chromium
```

See `references/setup.md` for where `playwright.ps1` lives depending on how the tool was installed.

### 2. Provider returns 0 results or consent page

Symptom: `web_search` succeeds but `results` is empty, or a `web_fetch` of the provider's domain returns text that says "accept cookies" or "verify you are human".

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

Symptom: a previously-working provider suddenly fails repeatedly; `web_get_provider_health` shows `isHealthy: false` and a high `consecutiveFailures`.

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
{ "tool": "web_get_provider_health", "input": { "provider": "bing" } }
```

Response shape (MCP, camelCase):

```json
{
  "provider": "bing",
  "isHealthy": false,
  "consecutiveFailures": 3,
  "lastSuccessUtc": "2026-06-04T12:30:00Z",
  "lastFailureUtc": "2026-06-06T08:14:22Z"
}
```

### 4. Fetch returns a verification page ("Just a moment...", "Checking your browser")

Symptom: `fetch_bot_challenge`, `statusCode: 403`, `title: "Just a moment..."`.

Headless browsers are recognized by some sites. The fetcher already presents the browser's regular user agent (the headless build otherwise
announces itself as `HeadlessChrome/<version>`, which several sites answer with a verification page), so most sites that served the real
page to a desktop browser serve it here as well. When a site still challenges:

1. Retry once; some challenges clear on the second request from the same profile.
2. Open the site once in a real window so the profile gains its cookies, then fetch with that profile:

   ```powershell
   recall profile auth interactive --url "https://blocked.example/article"   # solve the check in the window, then press Enter
   recall fetch "https://blocked.example/article" --profile interactive
   ```

3. Fall back to another source for the same content (a `web_search` for the title usually finds one).

Do not loop on the same URL; a challenge that survives two attempts will keep surviving.

### 5. Fetch returns the wrong page (consent, login, captcha) with `success: true`

Symptom: `text` is a cookie banner or login form although no error code was raised (the page had enough words and no known marker).

Fix: use a profile that has accepted consent for that domain, or pre-warm it with the interactive auth flow.

```powershell
recall profile auth interactive --provider bing
recall fetch "https://www.bing.com/search?q=mcp" --profile interactive
```

For batch fetches (`web_batch_fetch`), the profile is shared across all URLs, so one profile that has accepted consent for the relevant domains is enough.

### 6. Research call returns `success: true` but few `sources`

This is expected when some pages fail to fetch. Inspect `errors`:

```json
{
  "errors": [
    { "code": "fetch_failed", "message": "Timeout 30000ms exceeded.", "target": "https://slow-site.example/", "transient": true },
    { "code": "fetch_http_error", "message": "Server returned HTTP 404 (NotFound).", "target": "https://moved.example/old", "transient": false }
  ]
}
```

Mitigations:

- Raise `timeoutSeconds` per fetch (via `--timeout` for `recall fetch`).
- Lower `maxConcurrentFetches` to reduce contention on a small machine.
- Set `enforceDomainDiversity: false` if you want more chances from the same domain.
- Re-issue specific URLs via `web_fetch` for finer error handling.

### 7. "Process exited" or "Target page, context or browser has been closed"

Symptom: `fetch_failed` with one of these messages and `transient: true`.

The Playwright driver (a `node.exe` child process) or the browser was closed underneath the fetch, typically by a crash or by another
process killing browser/node processes. The fetcher starts a new driver and retries once on its own; you only see the error when the
second attempt failed too. Retry the call. If every fetch in a long-lived MCP host keeps failing this way, restart the host
(`recall mcp`).

### 8. "Provider not found" or unknown provider name

The registry resolves aliases, so `ddg` works for `duckduckgo`. List exact names and aliases:

```powershell
recall providers list --output json
```

Or call `web_list_providers` and pick a `name` from the response.

### 9. Wrong config file is being used

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

### 10. CLI output is hard to parse

Default `--output` is `text`. For machine consumption pipe with `--output json` (PascalCase field names). For LLM-friendly notes use
`--output markdown`. For interactive debugging use `--output dump`.

```powershell
recall providers list --output dump
recall research "agent skills" --output json | ConvertFrom-Json
```

### 11. Disk usage under the temp folder

Headless fetches run in throw-away copies of the profile under `%TEMP%\Zakira.Recall\browser-sessions\<profile>\`. Each copy is about 2 MB
(caches are excluded) and is deleted after the fetch; copies older than an hour are swept the next time the tool starts. If the folder
grows, a process is being killed before it can clean up; the next start removes the leftovers.

## Operation error reference

`OperationError` (returned in `errors` arrays and `FetchResponse.error`) has:

| Field       | Notes                                                                                                   |
|-------------|---------------------------------------------------------------------------------------------------------|
| `code`      | Stable machine-readable code: `fetch_http_error`, `fetch_bot_challenge`, `fetch_login_required`, `fetch_weak_content`, `fetch_failed`, `search_failed`. |
| `message`   | Human-readable description.                                                                             |
| `provider`  | Provider that produced the error, if applicable.                                                        |
| `target`    | The URL or query the error pertains to.                                                                 |
| `transient` | `true` if a retry might succeed (timeouts, rate limits, 5xx, challenge pages, browser/driver restarts). |

When `transient: true`, retry once; if it persists, fall back to a different provider, profile, or source.

## Last resort

If nothing works, gather diagnostics for an issue report:

```powershell
recall config show --output json
recall providers list --output json
recall providers test ddg --output json
recall profile show default --output json
recall fetch "<failing url>" --output json
```

The fetch output's `statusCode`, `contentSelector`, `wordCount`, `title` and `error` describe what the browser actually received.
Then file an issue with those outputs at the project repository.
