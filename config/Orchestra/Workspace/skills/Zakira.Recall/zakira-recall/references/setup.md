# Setup reference

Use this when the user wants to install Zakira.Recall, configure a profile, install the Playwright runtime, or register the `recall mcp` server with an MCP-compatible client.

## 1. Install the global tool

```powershell
dotnet tool install --global Zakira.Recall
```

Verify:

```powershell
recall --help
```

Requires .NET 10 SDK or runtime in `PATH`. Update with `dotnet tool update --global Zakira.Recall`.

## 2. Browser runtime

Every fetch and the Playwright providers (`duckduckgo-browser`, `bing`) run a real browser. The default profile channel is `msedge`,
so on a machine with Microsoft Edge installed nothing else is needed.

Without Edge, switch the profile to Playwright's bundled Chromium and install it once:

```powershell
recall profile init default --channel chromium --provider duckduckgo --headless true
pwsh "<install-dir>/playwright.ps1" install chromium
```

Where `playwright.ps1` lives:

- Global tool: next to the tool's installed files, usually `~/.dotnet/tools/.store/zakira.recall/<version>/zakira.recall/<version>/tools/net10.0/any/playwright.ps1`.
- Build output: `%TEMP%\Zakira.Recall\bin\Debug\net10.0\playwright.ps1` (all projects share that output root).

Headless fetches run in a throw-away copy of the profile (caches excluded, about 2 MB) under `%TEMP%\Zakira.Recall\browser-sessions\`;
the copy is removed after the fetch.

You can confirm the runtime with:

```powershell
recall providers test ddg
recall fetch "https://example.com" --output json
```

A successful test response means the provider can run end-to-end; a successful fetch means the browser channel launches.

## 3. Generate a config file

```powershell
recall config init
```

By default this writes to:

- `$XDG_CONFIG_HOME/Zakira.Recall/profiles.json` if `XDG_CONFIG_HOME` is set
- `%APPDATA%\Zakira.Recall\profiles.json` otherwise on Windows

Override the destination:

```powershell
recall config init --path "C:/temp/recall-profiles.json"
```

Generate with non-default defaults in one shot:

```powershell
recall config init `
  --provider duckduckgo `
  --fallback-provider duckduckgo-browser bing `
  --enable-fallback true `
  --config-log-level Information
```

Inspect the resolved config any time:

```powershell
recall config show
recall config show --output json
```

## 4. Configure a profile

A profile bundles a browser channel, default provider, headless mode, locale, timeout, and per-profile overrides.

Initialize a named profile:

```powershell
recall profile init default --channel msedge --provider duckduckgo --headless true
recall profile init interactive --channel msedge --provider bing --headless false
```

Inspect:

```powershell
recall profile show default --output json
recall profile show interactive --provider bing --output markdown
```

Useful fields:

- `name`, `channel`, `defaultProvider`, `headless`, `userDataDir`, `locale`, `timeoutSeconds`
- `fallbackProviders`, `enableProviderFallback`, `providerHealthCooldownSeconds`
- `maxConcurrentFetches`, `logLevel`, `metadata`

A separate `interactive` profile is useful for browser-backed providers that need a one-time sign-in or consent click — see `references/troubleshooting.md`.

## 5. One-time interactive auth (for `bing`, sometimes `duckduckgo-browser`)

Some providers show consent pages or sign-in flows on first use. Open a real (non-headless) browser using a chosen profile, navigate to the provider's setup URL, and let the user click through:

```powershell
recall profile auth interactive --provider duckduckgo-browser
recall profile auth interactive --provider bing
recall profile auth interactive --provider bing --no-wait true
```

By default the command waits for `Enter` before closing so the user has time to interact. Use `--no-wait true` if you want it to return immediately after opening the page (useful from scripts).

Once consent/cookies are stored in the profile's `userDataDir`, subsequent headless searches will reuse them.

## 6. Register the MCP server with a client

The MCP server runs over stdio:

```powershell
recall mcp
```

Configure your MCP client to launch it. The exact config file differs per product, but the command is the same.

### OpenCode

Add to `.opencode/opencode.json` (project) or `~/.config/opencode/opencode.json` (global):

```json
{
  "mcp": {
    "recall": {
      "type": "local",
      "command": ["recall", "mcp"],
      "enabled": true
    }
  }
}
```

### Claude Code

Add to `~/.claude.json` or your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "recall": {
      "command": "recall",
      "args": ["mcp"]
    }
  }
}
```

Or use the CLI:

```powershell
claude mcp add recall -- recall mcp
```

### Cursor

Add to `~/.cursor/mcp.json` (global) or `.cursor/mcp.json` (project):

```json
{
  "mcpServers": {
    "recall": {
      "command": "recall",
      "args": ["mcp"]
    }
  }
}
```

### Generic MCP stdio client

Any stdio-compatible MCP client takes the same shape: command `recall`, args `["mcp"]`. Optionally pass `--config <path>` or `--default-profile <name>` after `mcp` to bind a specific config or profile.

Without a global install, `dnx` runs the package straight from NuGet: command `dnx`, args `["Zakira.Recall", "--yes", "--", "mcp"]`.

The server exposes `web_search`, `web_fetch`, `web_research`, `web_batch_fetch`, `web_search_then_fetch`, `web_list_providers`,
`web_get_provider_health`, `web_show_config` and `web_show_profile` (see `references/mcp-tools.md`).

## 7. Verify the install end-to-end

```powershell
recall config show --output json
recall providers list --output json
recall providers test ddg
recall search "agent skills" --limit 3 --output json
```

If any step fails, see `references/troubleshooting.md`.

## Storage locations

- Config: `$XDG_CONFIG_HOME/Zakira.Recall/profiles.json` or `%APPDATA%\Zakira.Recall\profiles.json`.
- Profile data (cookies, browser state): `$XDG_DATA_HOME/Zakira.Recall/profiles/` or `%LOCALAPPDATA%\Zakira.Recall\profiles\`.

Override the config path at any command with `--config <path>`. Override the profiles root with `--profiles-root <path>`. Override the default profile with `--default-profile <name>`. Override the default provider with `--default-provider <name>`.

## Global CLI options

These can be passed to any `recall` subcommand:

```
--config <path>
--default-provider <name>
--default-profile <name>
--profiles-root <path>
--log-level <Trace|Debug|Information|Warning|Error|Critical|None>
--verbose          (Debug logging)
--quiet            (errors only)
```

Logs go to stderr, so `--output json` on stdout stays parseable.
