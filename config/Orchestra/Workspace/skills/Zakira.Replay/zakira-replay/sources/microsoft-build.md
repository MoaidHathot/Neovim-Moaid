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
zakiraReplayVersion: 0.10.1+
---

# Microsoft Build (sessions)

Public Microsoft Build session pages (`build.microsoft.com/en-US/sessions/<CODE>?source=sessions`). The outer page is a Next.js wrapper; the actual player is a [Microsoft Medius](microsoft-medius.md) iframe inside it. Captions and HLS playlist URLs are inlined as JavaScript constants in the Medius embed HTML, so transcripts and frames are recoverable **without** the Shaka MSE player ever booting — which it won't, in headless Edge.

## What works

- **Transcript:** yes via `MediusTranscriptInterceptor` (inline `captionsConfiguration` manifest, typically 36 languages). No `--stt`, no audio download.
- **Frames:** yes via the automatic sidestep fallback OR `--prefer-inline-media`. Browser navigates → interceptor reads inline HLS URL → ffmpeg seeks → JPEGs.
- **Session metadata** (`manifest.sessionMetadata`): partial — JSON-LD + OpenGraph on the `build.microsoft.com` wrapper page give title + description + sometimes the session code; richer fields (speakers, track) live inside the Medius iframe and are inconsistently exposed.
- **Deep links:** generic W3C Media Fragments (`#t=<seconds>`). Build's player accepts the URL as-is; the fragment is preserved.
- **Captions languages observed:** ar-EG, bd-BD, bg-BG, br-BR, cs-CZ, da-DK, de-DE, dl-NL, el-GR, en-US, es-ES, fi-FI, fr-FR, hi-IN, hu-HU, it-IT, ja-JP, ko-KR, nb-NO, pl-PL, pt-PT, ro-RO, ru-RU, sk-SK, sl-SI, sv-SE, th-TH, tr-TR, uk-UA, ur-PK, vi-VN, zh-Hans, zh-Hant, fr-CA, he-IL, id-ID (36 total on KEY01).
- **Auth:** none. Public sessions accept HLS segments and caption blobs unauthenticated.

## Recommended commands

### Single session — CLI

Frames + transcript + caption in one pass (~71 s on KEY01):

```pwsh
zakira-replay analyze "https://build.microsoft.com/en-US/sessions/KEY01?source=sessions" `
  --capture-mode browser --frames 5 --frame-strategy interval `
  --caption-languages en --prefer-inline-media
```

Transcript-only (fastest, ~10–15 s):

```pwsh
zakira-replay transcribe "https://build.microsoft.com/en-US/sessions/KEY01?source=sessions" `
  --capture-mode browser --caption-languages en
```

Spot frames at known transcript moments (~20 s per frame batch, one browser probe amortised across all `--at` timestamps):

```pwsh
zakira-replay frames "https://build.microsoft.com/en-US/sessions/KEY01?source=sessions" `
  --at "00:22:30,00:35:10,01:11:50"
```

### Single session — MCP

```json
{
  "tool": "analyze.start",
  "arguments": {
    "source": "https://build.microsoft.com/en-US/sessions/KEY01?source=sessions",
    "captureMode": "browser",
    "frames": 5,
    "frameStrategy": "interval",
    "captionLanguages": "en",
    "preferInlineMedia": true
  }
}
```

### Conference / batch — recommended workflow

For an "agent builds a book of the whole conference" pattern:

```pwsh
# 1) Enqueue every session — captions + frames via the sidestep, no downloads, 4 in parallel.
foreach ($code in @("KEY01","BRK101","BRK205","BRK220")) {
    zakira-replay queue enqueue "https://build.microsoft.com/en-US/sessions/$code`?source=sessions" `
        --queue-id build-2026 --capture-mode browser --frames 5 --frame-strategy interval `
        --caption-languages en --prefer-inline-media
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

- **`--frame-strategy scene` is a foot-gun on long keynotes.** Scene-cut detection inspects every decoded frame, so ffmpeg pulls the entire HLS stream — 6–8 GB for a 3-hour keynote, ~9.5 minutes of wall time (observed 836 scene cuts on KEY01). Use `--frame-strategy interval` with `--frames N` for spot sampling instead.
- **`analyze --capture-mode browser` without `--prefer-inline-media` always emits `CAPTURE_DURATION_UNRESOLVED`.** Expected: the Shaka MSE player doesn't boot headlessly. The automatic sidestep fallback still produces frames from the inline HLS URL; the warning is informational, not a failure.
- **Frames require a browser context.** `--capture-mode ytdlp` (the default) cannot resolve `build.microsoft.com` URLs; you must pass `--capture-mode browser` explicitly. The pipeline emits `MEDIA_URL_UNRESOLVED` (info) noting the fall-through.
- **No frames without playback engagement on `--frames 0 --frame-strategy scene`.** Just don't combine those.
- **Conference catalog crawling is not built in.** You supply the session URLs; `discover` only scrapes one page's embedded video, not a list of session links.

## Source-specific warning codes

- `CAPTURE_MEDIUS_TRANSCRIPT_DISCOVERED` (info): caption manifest parsed; message lists the languages advertised on the page.
- `CAPTURE_MEDIUS_TRANSCRIPT_DOWNLOADED` (info): preferred-language VTT saved to `captions/medius-NNNN-<lang>.vtt`.
- `CAPTURE_MEDIUS_TRANSCRIPT_FAILED` (warning): a discovered caption could not be downloaded (HTTP error, empty body). Other languages can still succeed.
- `CAPTURE_BROWSER_FALLBACK` (info, message contains `duration-unresolved-fallback` or `prefer-inline-media`): the sidestep ran. Identifies which path produced the frames.

## Gotchas

- **`CAPTURE_DURATION_UNRESOLVED` (error severity) is normal for this source** when using the sidestep. The Shaka player never booting is the whole reason the sidestep exists. The error severity is from the pipeline's perspective ("we couldn't determine duration from the in-browser `<video>` element"), not the user's. Agents should not treat this as a failure if `CAPTURE_BROWSER_FALLBACK` is also present.
- **No `--allow-media-download` needed** for transcripts or frames. The HLS segments are streamed, not downloaded as a full file; the sidestep avoids the silent-download path entirely.
- **`session-source=sessions` query string is part of the canonical URL** — Build pages link to themselves this way. Removing it doesn't break anything but keeps the URL pattern recognisable.

## Measured runs

| Run | Command | Elapsed | Artifacts |
|---|---|---|---|
| KEY01 spot frame | `frames --at "00:02:00"` | 45.6 s | 1 real JPEG (~96 KB), Medius transcript also downloaded |
| KEY01 analyze 3 frames | `analyze --capture-mode browser --frames 3 --frame-strategy interval --prefer-inline-media` | 71.4 s | 3 JPEGs at 35:55 / 01:11:50 / 01:47:45, `transcript.md` 210 KB, English VTT 217 KB |
| KEY01 spot frames batch | `frames --at "00:02:00,00:22:30,01:00:00"` | 64.5 s | 3 JPEGs (browser probe amortised; ~20 s per frame after the first) |
| KEY01 analyze with `--frame-strategy scene` | (do not do this) | 9.5 min | 836 frames, ~6–8 GB of HLS pulled |

Verified on `zakira-replay 0.10.1+` (post-commit `5cf6a8a`).
