# Raindrop Watcher

A personal orchestration suite that watches a raindrop.io collection,
classifies each new raindrop along two axes (`medium` = video|article,
`intent` = recipe|session|generic), dispatches a specialized child
orchestration per `(medium, intent)`, publishes a rich ActionView entry,
optionally saves recipes to a configured directory, and finally moves the
raindrop into a "Processed" collection -- or, after `maxAttempts` failed
attempts, into a "DeadLetter" collection so the failure cannot be silently
lost.

State per raindrop is persisted in **Zakira.Exchange** under the
`raindrop-watcher-state` category, exactly the same pattern used by the
existing `icm-investigator` orchestrations. Failures are surfaced as a
`raindrop-error` ActionView entry via an orchestration-failure hook;
permanent failures (after `maxAttempts`) additionally produce a
`raindrop-dead-letter` entry (severity=critical). Every tracker tick also
refreshes a single rolling `raindrop-watcher-status` entry that summarises
inbox / dispatched / dead-lettered counts so you have a one-glance health
indicator.

## State lifetime (Zakira.Exchange records)

```
                                            +-> completed   (success)
no record -> queued -> processing ---+
                                     +-> failed -- retried (up to maxAttempts)
                                                |
                                                +-> dead-lettered  (terminal)
```

Tracker-tick guarantees, by design:

- **Stuck-in-flight detection.** If `status` stays in `queued` or
  `processing` for longer than `stuckThresholdMinutes` (default 60), the
  next tick reclassifies the item as `failed` (with
  `lastError = "stuck-in-flight: ..."`) and the normal failed rules apply.
  This recovers items that were lost when the Orchestra host crashed mid-
  run or when the orchestration.failure hook itself failed.
- **Dead-letter after maxAttempts.** Items that fail `maxAttempts` times
  (default 3) are *moved* out of `AI-Inbox` into `AI-DeadLetter`, tagged
  `dead-letter`, marked `status=dead-lettered` in Zakira, and surface a
  `raindrop-dead-letter` ActionView entry. They are NEVER skipped silently.
- **Move-then-mark order in raindrop-processor.** `move-to-processed` runs
  *before* `mark-completed`. This guarantees we never have the misleading
  state "Zakira says completed, but the raindrop is still in `AI-Inbox`".
  The trade-off: if `move` succeeds and `mark-completed` then fails, the
  raindrop is in `AI-Processed` but its state record says `failed`. The
  next tick will skip it (no longer in inbox), and the user finds the
  ActionView entry that the analysis already produced.
- **Failure hook throws on internal failure.** When the
  `orchestration.failure` hook can't write to Zakira or can't add the
  ActionView entry, it now throws so the error surfaces in the hook log
  (rather than silently leaving the state inconsistent). The stuck-
  detection rule above is the second line of defense for this case.
- **Reprocess on manual move-back.** A raindrop that appears in
  `AI-Inbox` with `status=completed` or `status=dead-lettered` is treated
  as an explicit reprocess intent (the user must have moved it back
  manually, since the processor and the dead-letter mover normally take
  items OUT of `AI-Inbox`). The next tick re-dispatches with
  `priorAttempts=0`. The same outcome is available one-click via the
  **Reprocess** action on every per-raindrop ActionView entry, or from
  the CLI via `tools/scripts/reprocess-raindrop.ps1`.

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
+- raindrop-video-session-processor.yaml # Zakira lecture preset + chapters + targeted frames via Zakira.Replay MCP
+- raindrop-video-recipe-processor.yaml  # Zakira scene frames + targeted frames + recipe extraction
+- raindrop-video-generic-processor.yaml # Zakira transcript-first + light (5-cap) targeted frames
+- raindrop-article-recipe-processor.yaml  # HTTP+Playwright + image extraction + image download
+- raindrop-article-generic-processor.yaml # HTTP+Playwright + image extraction (embed remote URLs)
+- tools/
|   +- raindrop.cs                       # .NET 10 single-file CLI for raindrop.io
|   +- scripts/
|       +- fetch-article.ps1             # cheap HTTP fetch + ad-filtered image candidate extraction
|       +- save-recipe.ps1               # write recipe md to recipes dir
|       +- save-article-images.ps1       # download chosen article images into <recipesDir>/<slug>-images/
|       +- capture-targeted-frames.ps1   # CLI-driven targeted frame capture (replaces MCP approach)
|       +- submit-actionview-upsert.ps1  # delete-then-add ActionView entry by stable id
|       +- reprocess-raindrop.ps1        # one-shot reprocess helper (move back + clear state + dismiss AV entries)
|       +- hook-mark-failed.ps1          # orchestration.failure hook (throws on internal failure)
|       +- dead-letter-process.ps1       # moves dead-letter items, marks Zakira, publishes ActionView entry
|       +- publish-rolling-status.ps1    # tick-end: replaces the single rolling raindrop-watcher-status entry
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
    +- raindrop-error.json               # one per orchestration.failure hook fire
    +- raindrop-dead-letter.json         # one per item that exhausted maxAttempts
    +- raindrop-watcher-status.json      # exactly one entry total; replaced each tick
```

## Visual evidence pipeline

Two-stage frame capture for **video** processors (recipe / session / generic):

1. **Baseline** -- `Zakira.Replay analyze` with strategy/preset tuned per
   intent (scene + ocr + vision for recipe; lecture preset + ocr + vision
   for session; transcript-only with `--frames 0` for generic).
2. **Targeted** -- a `pick-targeted-frames` Prompt step scans the
   transcript and emits a JSON list of `{timestamp, reason}` picks.
   A `targeted-frame-capture` Script step then calls
   `Zakira.Replay frames --at <ts1,ts2,...> --run-id <baseline-runId>
   --allow-media-download --max-edge 1280 --output-format json` once,
   so the captured frames land alongside the baseline ones inside the
   same artifact directory. Per-intent caps (enforced both in the prompt
   and in the Script): recipe=20, session=12, generic=5. Every pick
   must include a one-sentence justification.

   We deliberately drive this via the CLI (not Zakira.Replay's MCP)
   because Copilot's tool-name validator (`^[a-zA-Z0-9_-]{1,128}$`)
   rejects MCP tool names containing dots, which Zakira.Replay's MCP
   uses. CLI-driven is also deterministic (no LLM-tool-discovery
   uncertainty) and lets the Script step batch all picks into a single
   CLI invocation.

For **article-recipe**: `fetch-article.ps1` extracts ad-filtered `<img>`
candidates from the raw HTML (drops tracking pixels, ad networks,
sidebar/footer images, decorative small images). A `select-images` step
picks the most relevant; `download-images` saves them into
`<recipesDir>/<slug>-images/` next to the recipe markdown so the recipe
remains usable if the source article disappears.

For **article-generic**: same candidate extraction + selection, but the
images are embedded into the ActionView entry **by remote URL** (no
download).

## Multi-machine story (dotfiles-first)

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
   - `deadLetterCollectionName` (default: `AI-DeadLetter`)
   - `recipesDirectory` (default: `$USERPROFILE/OneDrive/Documents/Recipes`)
   - `maxDispatchPerTick` (default: `3`)
   - `maxAttempts` (default: `3`)
   - `stuckThresholdMinutes` (default: `60`)

3. **(Already done if you have ActionView set up):** confirm
   `actionview.json` declares `"templates": { "externalDirectory": "./templates" }`
   so ActionView picks up the 7 raindrop-* templates already shipped at
   `$XDG_CONFIG_HOME/actionview/templates/` (success entries for each
   medium/intent, plus `raindrop-error`, `raindrop-dead-letter`, and
   `raindrop-watcher-status`).

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
  tracker retries failed items up to `maxAttempts` (default 3). After the
  cap is hit the tracker **moves the raindrop** out of `AI-Inbox` into
  `AI-DeadLetter`, marks the Zakira record `status=dead-lettered`, and
  publishes a critical-severity `raindrop-dead-letter` ActionView entry.
  Items are never silently skipped.

- **Stuck-in-flight recovery**: if a state record sits in
  `queued`/`processing` for more than `stuckThresholdMinutes` (default
  60), the next tracker tick reclassifies it as `failed` with
  `lastError="stuck-in-flight: ..."` and the normal failed-rule applies
  (retry or dead-letter). This is the safety net when the Orchestra host
  crashes mid-run, when a child orchestration is killed, or when the
  failure hook itself fails.

- **Visual evidence (videos)**: each video processor runs a baseline
  `Zakira.Replay analyze` pass, then a `pick-targeted-frames` Prompt
  picks important transcript moments, then `targeted-frame-capture`
  (Script) batches them into a single `Zakira.Replay frames` CLI call
  pinned to the baseline runId. Caps: recipe=20, session=12, generic=5
  additional frames per video. Tune via the `targetedFrameCap` variable
  in each processor YAML.

- **Visual evidence (article recipes)**: `fetch-article.ps1` extracts
  ad-filtered `<img>` candidates from the raw HTML. The `select-images`
  step picks up to `maxImagesToKeep` (default 8) and downloads them into
  `<recipesDir>/<recipe-slug>-images/`. Article-generic embeds remote
  URLs only (no download).

- **Rolling watcher health entry**: every tracker tick replaces the single
  `raindrop-watcher-status` ActionView entry with fresh counts. Use it as
  your "is the watcher healthy?" glance. Severity escalates to `medium`
  whenever anything was dead-lettered or stuck-reclassified this tick.

- **Reprocessing a raindrop (completed OR dead-lettered)**: three options,
  pick whichever is convenient.
  1. **One-click**: each per-raindrop success entry, the `raindrop-error`
     entry, and the `raindrop-dead-letter` entry all carry a **Reprocess**
     action. It runs `tools/scripts/reprocess-raindrop.ps1` to move the
     raindrop back to `AI-Inbox`, strip workflow tags, clear the Zakira
     state record, and dismiss stale ActionView entries; the next tracker
     tick treats it as a brand-new item.
  2. **CLI**: the same helper script directly:
     ```powershell
     pwsh -File .\tools\scripts\reprocess-raindrop.ps1 -RaindropId <id>
     ```
     Flags: `-SkipMove`, `-SkipStateDelete`, `-SkipActionViewDismiss` if
     you want to do only part of the cleanup.
  3. **Manual drag-back**: drag the raindrop in raindrop.io's UI from
     `AI-Processed` (or `AI-DeadLetter`) back to `AI-Inbox`. The tracker
     auto-detects this on the next tick. The detection rule: a raindrop
     with `status=completed` or `status=dead-lettered` that is currently
     in `AI-Inbox` can only have gotten there via a manual move (the
     processor itself moves completed items OUT to `AI-Processed`, and
     dead-letter-move puts failed items in `AI-DeadLetter`). The tracker
     treats this as explicit reprocess intent with `priorAttempts=0`
     (fresh start, not a continuation of any previous retry budget).

- **Idempotency on retries**: every per-raindrop ActionView entry is
  assigned a deterministic id (`raindrop-<raindropId>-<short-type>`,
  `raindrop-error-<raindropId>`, `raindrop-dead-letter-<raindropId>`). The
  submit step does a `delete --force` against that id before adding the
  new entry, so re-running a processor (after a transient failure or a
  note edit) **replaces** the old entry rather than accumulating a second
  one. Downloaded article images are named with a SHA1-hash prefix of the
  source URL; re-runs short-circuit as "already downloaded" without
  re-fetching. Recipe markdown files use the existing overwrite-or-
  timestamp semantics in `save-recipe.ps1`.

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
