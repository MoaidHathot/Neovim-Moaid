---
name: SharePoint Stream / Microsoft Stream
status: working
hostPatterns:
  - "*.sharepoint.com"
  - "*.microsoftstream.com"
urlPatterns:
  - https://*.sharepoint.com/*/stream.aspx?id=*
  - https://*-my.sharepoint.com/personal/*/_layouts/15/stream.aspx?id=*
  - https://*.microsoftstream.com/video/*
underlyingPlayer: SharePoint Stream player (HLS / DASH chunked, MP4 single-file for legacy uploads)
authNeeded: dedicated-edge-profile (preferred), or StorageState via `auth login` (legacy)
lastVerified: 2026-06-04
zakiraReplayVersion: 0.10.1+
---

# SharePoint Stream / Microsoft Stream

SharePoint Stream (the current "Stream on SharePoint") and the older Microsoft Stream Classic. Both host enterprise Teams meeting recordings and organisation-uploaded videos. Always behind Microsoft SSO — use a dedicated Edge profile (`zakira-replay auth init-edge-profile`) so cookies stay DPAPI-encrypted and refresh in-place during use.

## What works

- **Transcript:** yes via `SharePointStreamInterceptor` — the Stream player issues an `_api/v2.X/.../media/transcripts` metadata call on load; the interceptor follows each transcript's `temporaryDownloadUrl` via the authenticated browser context, tries the `?isformatjson=true&transcriptkey=<id>` variant first (rich Teams transcript JSON with `speakerDisplayName`), converts to VTT with `<v Speaker>` voice spans, and persists under `captions/stream-NNNN-<lang>.{vtt,json}`. Full speaker attribution is preserved.
- **Frames:** depends on the upload format.
  - Single-file MP4 uploads (legacy / non-meeting content): yes via the browser STT-fallback path when `--stt --allow-media-download` is set, OR via `frames --at` with `--allow-media-download`.
  - DASH / HLS chunked streams (typical Teams meeting recordings): **no** — the browser-capture frame path requires `<video>.duration` to become finite, which happens here, so seek + screenshot does work. But there's no single addressable media URL for the STT-fallback or sidestep path.
- **Session metadata** (`manifest.sessionMetadata`): partial — page title and description are usually filled; JSON-LD is inconsistent.
- **Deep links:** site-specific `?nav=t=HHhMMmSSs` format on the canonical `stream.aspx` URL. The Stream player respects it.
- **Captions languages observed:** whatever languages the meeting host enabled. For Teams meetings, the source language plus any post-meeting translations.
- **Auth:** **dedicated Edge profile is the right answer.** StorageState JSON profiles expire fast (1–2 hours for Microsoft) and travel as portable bearer tokens; the persistent Edge profile keeps cookies DPAPI-encrypted per-machine and refreshes them in place.

## Recommended commands

### Setup (one-time per machine)

```pwsh
# Initialise the dedicated Edge user-data-dir. Launches a real Edge window; sign in once.
zakira-replay auth init-edge-profile
```

After that, browser-capture runs against `*.sharepoint.com` use the DPAPI-encrypted cookies automatically.

### Single session — CLI

Transcript-only (no media download):

```pwsh
zakira-replay transcribe "https://contoso-my.sharepoint.com/personal/me/_layouts/15/stream.aspx?id=/personal/me/Recordings/Meeting.mp4" `
  --capture-mode browser
```

Frames from a single-file MP4 upload (requires opt-in download):

```pwsh
zakira-replay analyze "https://contoso-my.sharepoint.com/.../stream.aspx?id=..." `
  --capture-mode browser --frames 7 --frame-strategy interval `
  --allow-media-download
```

Frames from a chunked-stream meeting recording (in-browser seek + screenshot, no download):

```pwsh
zakira-replay analyze "https://contoso-my.sharepoint.com/.../stream.aspx?id=..." `
  --capture-mode browser --frames 7 --frame-strategy interval `
  --smart-crop  # removes Teams gallery sidebar before hashing/OCR
```

### Single session — MCP

```json
{
  "tool": "analyze.start",
  "arguments": {
    "source": "https://contoso-my.sharepoint.com/.../stream.aspx?id=...",
    "captureMode": "browser",
    "frames": 7,
    "frameStrategy": "interval",
    "smartCrop": true
  }
}
```

### Spot frames

```pwsh
zakira-replay frames "https://contoso-my.sharepoint.com/.../stream.aspx?id=..." `
  --at "00:10:00,00:25:00" --allow-media-download
```

Spot frames need `--allow-media-download` because the Stream player doesn't inline an HLS URL the sidestep can use (unlike Medius).

## Known limitations

- **No inline-media URL exposed.** Unlike Medius/Build, SharePoint Stream doesn't put the HLS playlist in inline JS the interceptor can read. Frame extraction for chunked streams happens via the in-browser play + seek + screenshot path (the Stream player **does** boot headlessly), or via the STT-fallback download for single-file uploads.
- **MFA challenges abort capture cleanly.** `CAPTURE_BROWSER_AUTH_MFA_DETECTED` (error) fires if the page rendered an MFA challenge. Complete MFA interactively in the dedicated Edge profile, then re-run.
- **Stale cookies after re-login.** If the user signed in on another Edge profile, the Zakira-managed profile may be evicted; `CAPTURE_BROWSER_AUTH_REQUIRED` (error) fires. Re-run `auth init-edge-profile`.
- **Teams meeting recordings have noisy backgrounds.** Use `--smart-crop` (Teams profile auto-detected) to strip the participant gallery before perceptual-hash slide grouping.

## Source-specific warning codes

- `CAPTURE_STREAM_TRANSCRIPT_DISCOVERED` (info): Stream metadata endpoint observed; message lists languages.
- `CAPTURE_STREAM_TRANSCRIPT_DOWNLOADED` (info): per-transcript output path.
- `CAPTURE_STREAM_METADATA_PARSE_FAILED` (warning): metadata endpoint observed but body couldn't be parsed (often a Stream API version not yet supported).
- `CAPTURE_STREAM_TRANSCRIPT_PARSE_FAILED` (warning): transcript downloaded but format not recognised; raw body kept in `captions/` for manual inspection.
- `CAPTURE_BROWSER_PROFILE_NOT_INITIALIZED` (info): dedicated Edge profile not set up — run `auth init-edge-profile`.
- `CAPTURE_BROWSER_AUTH_REQUIRED` (error): post-navigation URL landed on a sign-in page. Cookies expired; re-init the profile.
- `CAPTURE_BROWSER_AUTH_MFA_DETECTED` (error): page rendered an MFA challenge headless capture cannot satisfy.
- `CAPTURE_PROFILE_CONFLICT` (info): both `--auth-profile` and an initialised Edge profile are configured; persistent-context (Edge profile) wins.

## Gotchas

- **The transcript interceptor's downloaded files are the source of truth, not the page's visible captions toggle.** The page may show "no captions" while the interceptor pulled the transcript via the metadata API moments earlier.
- **Don't pass `--cookies-from-browser edge` with the dedicated Edge profile.** That's the yt-dlp cookie path; the dedicated Edge profile is a separate mechanism used by the browser-capture path. Mixing them produces `CAPTURE_PROFILE_CONFLICT` (info) and works, but the persistent-context cookies are what actually take effect.
- **Stream Classic (`*.microsoftstream.com`) is being deprecated by Microsoft.** New uploads go to SharePoint Stream. The `microsoftstream.com` URL pattern is here for archived content.
