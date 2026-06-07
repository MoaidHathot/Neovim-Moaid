---
name: Microsoft Build (sessions)
status: working
hostPatterns:
  - build.microsoft.com
urlPatterns:
  - https://build.microsoft.com/*/sessions/*
underlyingPlayer: Shaka MSE (Microsoft Medius, iframe-embedded)
authNeeded: none
lastVerified: 2026-06-04
zakiraReplayVersion: 0.14.0+
---

# Microsoft Build (sessions)

Public Microsoft Build session pages (`build.microsoft.com/en-US/sessions/<CODE>?source=sessions`). The outer page is a Next.js wrapper; the actual player is a [Microsoft Medius](microsoft-medius.md) iframe inside it. Captions and HLS playlist URLs are inlined as JavaScript constants in the Medius embed HTML, so transcripts and frames are recoverable **without** the Shaka MSE player ever booting — which it won't, in headless Edge.

`build.microsoft.com` is in the `KnownHosts` registry, so the default `analyze` command automatically:

- skips the yt-dlp metadata probe (saves ~10 s of guaranteed failure);
- routes straight to browser capture;
- enables the inline-media sidestep (no `CAPTURE_DURATION_UNRESOLVED` noise).

No flags are required for a typical run.

## What works

- **Transcript:** yes via `MediusTranscriptInterceptor` (inline `captionsConfiguration` manifest, typically 36 languages). No `--stt`, no audio download.
- **Frames:** yes via the automatic inline-media sidestep. Browser navigates → interceptor reads inline HLS URL → ffmpeg seeks → JPEGs.
- **Session metadata** (`manifest.sessionMetadata`): partial — JSON-LD + OpenGraph on the `build.microsoft.com` wrapper page give title + description + sometimes the session code; richer fields (speakers, track) live inside the Medius iframe and are inconsistently exposed.
- **Deep links:** generic W3C Media Fragments (`#t=<seconds>`). Build's player accepts the URL as-is; the fragment is preserved.
- **Captions languages observed:** ar-EG, bd-BD, bg-BG, br-BR, cs-CZ, da-DK, de-DE, dl-NL, el-GR, en-US, es-ES, fi-FI, fr-FR, hi-IN, hu-HU, it-IT, ja-JP, ko-KR, nb-NO, pl-PL, pt-PT, ro-RO, ru-RU, sk-SK, sl-SI, sv-SE, th-TH, tr-TR, uk-UA, ur-PK, vi-VN, zh-Hans, zh-Hant, fr-CA, he-IL, id-ID (36 total on KEY01).
- **Auth:** none. Public sessions accept HLS segments and caption blobs unauthenticated.

## Recommended commands

### Single session — CLI

Frames + transcript + caption in one pass (uses 0.14 defaults: `--capture-mode auto` short-circuits to browser, `--frames 15 --frame-strategy interval`, inline-media sidestep auto-enabled, English caption auto-picked):

```pwsh
dnx Zakira.Replay analyze "https://build.microsoft.com/en-US/sessions/KEY01?source=sessions"
```

Bump or trim frame count if the default of 15 isn't right:

```pwsh
dnx Zakira.Replay analyze "https://build.microsoft.com/en-US/sessions/KEY01?source=sessions" --frames 30
```

Transcript-only (fastest, ~10–15 s):

```pwsh
dnx Zakira.Replay transcribe "https://build.microsoft.com/en-US/sessions/KEY01?source=sessions"
```

Spot frames at known transcript moments (~20 s per frame batch, one browser probe amortised across all `--at` timestamps):

```pwsh
dnx Zakira.Replay frames "https://build.microsoft.com/en-US/sessions/KEY01?source=sessions" `
  --at "00:22:30,00:35:10,01:11:50"
```

Add `--verbose` to any of the above to see the full progress stream + info-severity warnings; add `--quiet` to suppress everything except errors.

### Single session — MCP

```json
{
  "tool": "analyze-start",
  "arguments": {
    "source": "https://build.microsoft.com/en-US/sessions/KEY01?source=sessions"
  }
}
```

MCP defaults match the CLI: `frames=15`, `frameStrategy=interval`, capture mode auto-resolves to browser, prefer-inline-media auto-enabled, captions auto.

### Conference / batch — recommended workflow

For an "agent builds a book of the whole conference" pattern:

```pwsh
# 1) Enqueue every session — host-aware defaults handle browser/inline-media/captions/strategy.
foreach ($code in @("KEY01","BRK101","BRK205","BRK220")) {
    zakira-replay queue enqueue "https://build.microsoft.com/en-US/sessions/$code`?source=sessions" `
        --queue-id build-2026
}

# 2) Drain.
zakira-replay queue run --queue-id build-2026 --concurrency 4 --retries 2

# 3) Build the cross-conference index (per-document RunId + SourceUrl + DeepLink).
zakira-replay index build-conference build-2026 --runs "runs/*"

# 4) Query across the whole conference.
zakira-replay index query build-2026 "Maia 200 announcement" --top 10 --output-format json
```

Each cross-run hit carries `runId`, `sourceUrl`, and `deepLink` so the agent can attribute and link directly.

## Known limitations

- **Don't pass `--frame-strategy scene` on long keynotes.** Scene-cut detection inspects every decoded frame, so ffmpeg pulls the entire HLS stream — 6–8 GB for a 3-hour keynote, ~9.5 minutes of wall time (observed 836 scene cuts on KEY01). The 0.14 default of `interval` avoids this; only override if you know you need it.
- **Conference catalog crawling is not built in.** You supply the session URLs; `discover` only scrapes one page's embedded video, not a list of session links.

## Source-specific warning codes

- `CAPTURE_MEDIUS_TRANSCRIPT_DISCOVERED` (info, suppressed in default output): caption manifest parsed; message lists the languages advertised on the page. Visible under `--verbose`.
- `CAPTURE_MEDIUS_TRANSCRIPT_DOWNLOADED` (info, suppressed in default output): preferred-language VTT saved to `captions/medius-NNNN-<lang>.vtt`.
- `CAPTURE_MEDIUS_TRANSCRIPT_FAILED` (warning): a discovered caption could not be downloaded (HTTP error, empty body). Other languages can still succeed.
- `CAPTURE_BROWSER_FALLBACK` (info, suppressed in default output): the sidestep ran. Message identifies which path produced the frames (`prefer-inline-media` is the expected one for Build URLs in 0.14+).

## Gotchas

- **`CAPTURE_DURATION_UNRESOLVED` is now `info` severity** (was `error` through 0.13). The Shaka player never booting is the whole reason the inline-media sidestep exists. Default output suppresses it entirely; only `--verbose` surfaces it.
- **No `--allow-media-download` needed** for transcripts or frames. The HLS segments are streamed, not downloaded as a full file; the sidestep avoids the silent-download path entirely.
- **`session-source=sessions` query string is part of the canonical URL** — Build pages link to themselves this way. Removing it doesn't break anything but keeps the URL pattern recognisable.

## Measured runs

| Run | Command | Elapsed | Artifacts |
|---|---|---|---|
| KEY01 spot frame | `frames --at "00:02:00"` | 45.6 s | 1 real JPEG (~96 KB), Medius transcript also downloaded |
| KEY01 analyze 3 frames | `analyze --frames 3` | 71.4 s | 3 JPEGs at 35:55 / 01:11:50 / 01:47:45, `transcript.md` 210 KB, English VTT 217 KB |
| KEY01 spot frames batch | `frames --at "00:02:00,00:22:30,01:00:00"` | 64.5 s | 3 JPEGs (browser probe amortised; ~20 s per frame after the first) |
| KEY01 analyze with `--frame-strategy scene` | (do not do this) | 9.5 min | 836 frames, ~6–8 GB of HLS pulled |

Verified on `zakira-replay 0.10.1+` (post-commit `5cf6a8a`).
