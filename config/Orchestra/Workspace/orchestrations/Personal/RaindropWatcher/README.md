# Raindrop Watcher

A personal orchestration suite that watches a raindrop.io collection,
classifies each new raindrop along two axes (`medium` = video|article,
`intent` = recipe|session|generic), dispatches a specialized child
orchestration per `(medium, intent)`, publishes a rich ActionView entry,
optionally saves recipes to a configured directory, and finally moves the
raindrop into a "Processed" collection.

State per raindrop is persisted in **Zakira.Exchange** under the
`raindrop-watcher-state` category, exactly the same pattern used by the
existing `icm-investigator` orchestrations. Failures are surfaced as a
`raindrop-error` ActionView entry via an orchestration-failure hook.

## Multi-machine story (dotfiles-first)

The suite is designed to live in your dotfiles repo and to require **zero
per-machine setup beyond two secret env vars** (or one, if you use a personal
token):

- The orchestration YAMLs are name-based -- no numeric collection ids
  anywhere. The tracker's `bootstrap-config` step calls
  `raindrop ensure-collection <name>` on every tick (idempotent: returns
  existing or creates) and forwards the resolved id to children as a
  parameter.
- ActionView templates live in
  `$XDG_CONFIG_HOME/actionview/templates/` (your dotfiles). ActionView's
  `TemplateScanner` auto-syncs them into its data directory on every
  startup, so adding/removing files from that folder propagates everywhere.
- OAuth refresh tokens are intentionally **not** part of dotfiles -- they
  live at `%LOCALAPPDATA%\Orchestra\RaindropWatcher\raindrop-tokens.bin`
  (Windows) or `$XDG_DATA_HOME/orchestra/raindrop-watcher/raindrop-tokens.bin`
  (Unix). On Windows the file is DPAPI-encrypted using your Windows user's
  key, so it is unreadable by anyone else (and unreadable even by you if
  copied off the machine).
- **No manual `login` step.** When the OAuth env vars are set and no token
  file is on disk, the CLI auto-launches the interactive browser login on
  first use. The browser pops up, you click "Allow" once, the encrypted
  refresh token persists, and every subsequent call (including the
  scheduled tracker tick) runs silently. Set `RAINDROP_AUTO_LOGIN=0` if
  you want to force an explicit `raindrop login` instead.
- The only per-machine work is setting two env vars (or one personal token).

## Component map

```
RaindropWatcher/
+- raindrop-tracker.yaml                 # scheduler poller + fan-out dispatcher
+- raindrop-processor.yaml               # classifier + router (one run per raindrop)
+- raindrop-video-session-processor.yaml # Zakira lecture preset + chapters
+- raindrop-video-recipe-processor.yaml  # Zakira scene frames + recipe extraction
+- raindrop-video-generic-processor.yaml # Zakira transcript-first summary
+- raindrop-article-recipe-processor.yaml  # HTTP+Playwright + recipe extraction
+- raindrop-article-generic-processor.yaml # HTTP+Playwright + flexible analysis
+- tools/
|   +- raindrop.cs                       # .NET 10 single-file CLI for raindrop.io
|   +- scripts/
|       +- fetch-article.ps1             # cheap HTTP fetch with heuristic "thin" flag
|       +- save-recipe.ps1               # write recipe md to recipes dir
|       +- hook-mark-failed.ps1          # orchestration.failure hook
+- skills/
|   +- raindrop-router/SKILL.md          # classification ruleset
+- tests/
    +- test-raindrop-cli.ps1             # arg-parsing / error-path smoke tests
    +- test-raindrop-cli-integration.ps1 # full CLI exercised against a mock raindrop.io
    +- test-raindrop-cli-tokens.ps1      # DPAPI round-trip + legacy migration tests

# Templates live OUTSIDE this folder, in your dotfiles:
$XDG_CONFIG_HOME/actionview/templates/
    +- raindrop-video-session.json
    +- raindrop-video-generic.json
    +- raindrop-recipe.json              # used by BOTH recipe processors (video + article)
    +- raindrop-article.json
    +- raindrop-error.json
```

## Routing table

Determined by `skills/raindrop-router/SKILL.md`. Tags are sparse: a single
intent tag wins; otherwise URL host + heuristics decide.

| medium  | intent  | processor                              | Special handling                                   |
|---------|---------|----------------------------------------|----------------------------------------------------|
| video   | recipe  | `raindrop-video-recipe-processor`      | Zakira scene frames + saves recipe markdown to dir |
| video   | session | `raindrop-video-session-processor`     | Zakira lecture preset + chapters + slide rollups   |
| video   | generic | `raindrop-video-generic-processor`     | Zakira transcript-only (cheap)                     |
| article | recipe  | `raindrop-article-recipe-processor`    | HTTP+Playwright fetch + saves recipe markdown      |
| article | session | `raindrop-article-generic-processor`   | Same as generic article                            |
| article | generic | `raindrop-article-generic-processor`   | HTTP+Playwright fetch + flexible analysis          |

Recognized intent tags (case-insensitive): `recipe`, `cooking`, `food`,
`session`, `talk`, `lecture`, `keynote`, `conference`, `webinar`, `course`.

Notes in raindrops are passed verbatim as the **analysis prompt** to the
synth step. When the note is empty, each processor falls back to a built-in
default ask appropriate for its (medium, intent) slot.

## Setup

### One-time, per account (in your dotfiles)

You only do these once -- they persist across every machine that pulls your
dotfiles.

1. **Register a raindrop.io app** at <https://app.raindrop.io/settings/integrations>.
   - For the OAuth flow, set the redirect URI to
     `http://localhost:53682/raindrop-oauth-callback`.
   - Save the client id and client secret in your secrets manager of choice.

2. **(Optional) Customize defaults** in `raindrop-tracker.yaml` `variables`:
   - `inboxCollectionName` (default: `AI-Inbox`)
   - `processedCollectionName` (default: `AI-Processed`)
   - `recipesDirectory` (default: `$USERPROFILE/OneDrive/Documents/Recipes`)
   - `maxDispatchPerTick` (default: `3`)
   - `maxAttempts` (default: `3`)

3. **(Already done if you have ActionView set up):** confirm
   `actionview.json` declares `"templates": { "externalDirectory": "./templates" }`
   so ActionView picks up the 5 raindrop-* templates already shipped at
   `$XDG_CONFIG_HOME/actionview/templates/`.

### Per machine

1. **Set OAuth env vars** (preferred -- once, user-wide):

   ```powershell
   [Environment]::SetEnvironmentVariable('RAINDROP_OAUTH_CLIENT_ID',     '<your client id>',     'User')
   [Environment]::SetEnvironmentVariable('RAINDROP_OAUTH_CLIENT_SECRET', '<your client secret>', 'User')
   ```

   **OR** use a personal test token (simpler, no login flow needed at all):

   ```powershell
   [Environment]::SetEnvironmentVariable('RAINDROP_TOKEN', '<your personal test token>', 'User')
   ```

   That's it. The very first time anything calls the CLI (manually or via
   the scheduled tracker tick), the OAuth flow kicks off automatically:

   - Browser pops up at `https://raindrop.io/oauth/authorize?...`.
   - You click "Allow".
   - The encrypted refresh token is written to
     `%LOCALAPPDATA%\Orchestra\RaindropWatcher\raindrop-tokens.bin`.
   - Every subsequent call runs silently and refreshes the access token
     automatically.

   To force an explicit login flow instead of the auto path, set
   `RAINDROP_AUTO_LOGIN=0` and run:

   ```powershell
   dotnet run P:/github/Neovim-Moaid/config/Orchestra/Workspace/orchestrations/Personal/RaindropWatcher/tools/raindrop.cs -- login
   ```

   **Backward-compat**: if an old plaintext
   `$XDG_CONFIG_HOME/orchestra/raindrop-tokens.json` exists from a
   previous install, the next CLI call auto-migrates it to the new
   encrypted location and deletes the plaintext.

2. **Register the orchestrations with your Orchestra server**, or let
   directory-scan pick them up if that's how your Orchestra is configured.

That's it. The tracker's first scheduled tick will run `bootstrap-config`,
verify auth via `whoami` (triggering the one-time browser grant if needed),
create the two collections if they don't yet exist, and start dispatching
items from `AI-Inbox` into `AI-Processed`.

## Verifying the install

```powershell
# 1. CLI sanity check.
dotnet run tools/raindrop.cs -- whoami

# 2. Verify token storage state.
dotnet run tools/raindrop.cs -- tokens-show
# -> { "exists": true|false, "path": "...", "encrypted": true, ... }

# 3. Verify the collections (will create them if missing).
dotnet run tools/raindrop.cs -- ensure-collection "AI-Inbox"
dotnet run tools/raindrop.cs -- ensure-collection "AI-Processed"

# 4. Try a one-off run of raindrop-processor with a known raindrop id.
orchestra run raindrop-processor `
    --param raindropId=<id> `
    --param url=https://example.com `
    --param title="Example" `
    --param note="" `
    --param processedCollectionId=<id-from-ensure-collection> `
    --param recipesDirectory="$env:USERPROFILE/OneDrive/Documents/Recipes"

# 5. Run the self-tests.
pwsh -File tests/test-raindrop-cli.ps1
pwsh -File tests/test-raindrop-cli-integration.ps1
pwsh -File tests/test-raindrop-cli-tokens.ps1
```

## Operational notes

- **Concurrency**: the tracker caps dispatch at `maxDispatchPerTick` (default
  3). Excess items defer to the next 5-minute tick. Each child orchestration
  runs end-to-end as its own root run -- you'll see them in the Orchestra UI.

- **Re-processing**: when a raindrop's `note` text changes (detected via
  SHA-256 hash), the tracker re-dispatches it on the next tick.

- **Retries**: failures bump an attempt counter in Zakira.Exchange. The
  tracker retries failed items up to `maxAttempts` (default 3); afterwards
  the item is left as `failed` and surfaces only via the `raindrop-error`
  ActionView entry.

- **Manual retry of a permanently-failed raindrop**: edit (or delete) the
  Zakira.Exchange record under category `raindrop-watcher-state` with key
  `<raindropId>`. Easiest:
  ```powershell
  dnx Zakira.Exchange --yes -- --db $env:XDG_CONFIG_HOME/orchestra/zakira.db `
      delete --category raindrop-watcher-state --key <id>
  ```

- **Adding a new content type**: write a new processor orchestration, add
  a routing row to `skills/raindrop-router/SKILL.md`, and (optionally) add
  a new template JSON to `$XDG_CONFIG_HOME/actionview/templates/`.

## Auth + token storage details

`tools/raindrop.cs` is the only place that speaks raindrop.io's REST API.
Per-invocation auth resolution:

1. `RAINDROP_TOKEN` env var -> long-lived test/personal token.
2. `RAINDROP_OAUTH_CLIENT_ID` + `RAINDROP_OAUTH_CLIENT_SECRET` + persisted
   refresh token -> OAuth with auto-refresh on every call (one extra retry
   on HTTP 401). If no token file exists yet, the CLI auto-launches the
   interactive browser login flow. Disable with `RAINDROP_AUTO_LOGIN=0`.
3. Otherwise the call exits non-zero with a helpful diagnostic.

Token file path resolution (intentionally non-synced):

1. `RAINDROP_STATE_DIR` env var (explicit override; useful for tests).
2. Windows: `%LOCALAPPDATA%\Orchestra\RaindropWatcher\raindrop-tokens.bin`
3. Unix: `$XDG_DATA_HOME/orchestra/raindrop-watcher/raindrop-tokens.bin`
4. Unix fallback: `$HOME/.local/share/orchestra/raindrop-watcher/raindrop-tokens.bin`

On Windows the file is encrypted with DPAPI (`CurrentUser` scope) using
`System.Security.Cryptography.ProtectedData`. On Unix the file is plaintext
JSON with `chmod 600`. The legacy plaintext file at
`$XDG_CONFIG_HOME/orchestra/raindrop-tokens.json` is auto-migrated and
deleted on first invocation of the new CLI.

You can override the raindrop API base URL with `RAINDROP_API_BASE` -- the
integration tests use this to point at a local mock server.

## Testing

Three suites in `tests/`:

- **`test-raindrop-cli.ps1`** -- 11 smoke tests covering arg parsing,
  missing-flag handling, and auth-missing error paths. No network, no
  side effects.

- **`test-raindrop-cli-integration.ps1`** -- 10 tests that spin up an
  in-process `HttpListener` mimicking the subset of raindrop.io's REST API
  the helper touches, then exercise every command (whoami, list, get,
  list-collections, ensure-collection both paths, move, add-tag, remove-tag,
  401-retry).

- **`test-raindrop-cli-tokens.ps1`** -- 10 tests covering the new DPAPI
  storage + legacy migration: pre-seeds a plaintext token file at the old
  XDG location, runs `tokens-show`, and asserts the file is migrated,
  encrypted at the new location, deleted from the old location, and
  readable on a second invocation.
