---
name: Microsoft Medius
status: working
hostPatterns:
  - medius.studios.ms
  - medius.microsoft.com
  - "*.event.microsoft.com"
urlPatterns:
  - https://medius.studios.ms/Embed/*
  - https://medius.microsoft.com/Embed/*
  - https://medius*.event.microsoft.com/Embed/*
underlyingPlayer: Shaka MSE (HLS via inline player config)
authNeeded: none (public events; some Microsoft-internal events may require sign-in via the dedicated Edge profile)
lastVerified: 2026-06-04
zakiraReplayVersion: 0.10.1+
---

# Microsoft Medius

The Microsoft Events streaming platform that hosts Microsoft Build, Ignite, and other event session recordings. The player is Shaka over MSE, fed via inline JS configuration. Most users encounter Medius transparently via wrapper pages (e.g. [`build.microsoft.com/sessions/<CODE>`](microsoft-build.md)); this profile applies whenever you hand a direct Medius embed URL to Zakira.Replay.

## What works

- **Transcript:** yes via `MediusTranscriptInterceptor` — the embed page inlines `captionsConfiguration` with SAS-signed `Caption_<lang>.vtt` URLs that the interceptor parses and downloads directly. No `--stt`, no playback engagement, no audio download required.
- **Frames:** yes via the automatic sidestep fallback OR `--prefer-inline-media`. The embed page also inlines `coreConfiguration.manifests.main[]` carrying the HLS master playlist URL; the interceptor surfaces it as `BrowserCaptureResult.InlineMediaUrl` and ffmpeg seeks into it.
- **Session metadata** (`manifest.sessionMetadata`): partial — `coreConfiguration.videoTitle` and friends are inlined alongside the player config but Medius doesn't put them in JSON-LD/OpenGraph form. The deterministic `SessionMetadataExtractor` will fill `title` from the page `<title>` element; `speakers`, `track`, `sessionCode` typically end up null.
- **Deep links:** generic W3C Media Fragments (`#t=<seconds>`).
- **Captions languages observed:** up to 36 on first-tier events (Build keynotes); regional events may have fewer.
- **Auth:** none for public events. Microsoft-internal Medius events require sign-in — use the dedicated Edge profile (`zakira-replay auth init-edge-profile`).

## Recommended commands

### Single session — CLI

```pwsh
zakira-replay analyze "https://medius.studios.ms/Embed/video-nc/<id>" `
  --capture-mode browser --frames 5 --frame-strategy interval `
  --caption-languages en --prefer-inline-media
```

Transcript-only:

```pwsh
zakira-replay transcribe "https://medius.studios.ms/Embed/video-nc/<id>" `
  --capture-mode browser --caption-languages en
```

### Single session — MCP

```json
{
  "tool": "analyze.start",
  "arguments": {
    "source": "https://medius.studios.ms/Embed/video-nc/<id>",
    "captureMode": "browser",
    "frames": 5,
    "frameStrategy": "interval",
    "captionLanguages": "en",
    "preferInlineMedia": true
  }
}
```

### Conference / batch

Same shape as Build — see [`microsoft-build.md`](microsoft-build.md) for the full queue + `index build-conference` workflow. The only difference is the URL pattern in `queue enqueue`.

### Spot frames

```pwsh
zakira-replay frames "https://medius.studios.ms/Embed/video-nc/<id>" --at "<MM:SS>"
```

## Known limitations

- Same as [Microsoft Build](microsoft-build.md):
  - `--frame-strategy scene` pulls the entire HLS stream.
  - `analyze --capture-mode browser` without `--prefer-inline-media` emits `CAPTURE_DURATION_UNRESOLVED`; sidestep still works.
  - Frames require `--capture-mode browser` explicitly (`ytdlp` cannot resolve Medius).
- **`asl`/`isl`/`bsl` sign-language video tracks are deliberately ignored.** The interceptor picks `coreConfiguration.manifests.main[0].manifest` so spot frames reflect the speaker's slide content, not the sign-language overlay.
- **The interceptor's HLS URL is host-direct, not SAS-signed.** Public Build/Ignite sessions accept it without cookies. Sign-in-gated Medius events may add per-request auth headers that the inline URL strips; if frames fail with HTTP 403 after the interceptor reported the URL, the source needs auth via the dedicated Edge profile (the captions still work because each `Caption_<lang>.vtt` carries its own SAS token).

## Source-specific warning codes

Same as [Microsoft Build](microsoft-build.md):

- `CAPTURE_MEDIUS_TRANSCRIPT_DISCOVERED` (info)
- `CAPTURE_MEDIUS_TRANSCRIPT_DOWNLOADED` (info)
- `CAPTURE_MEDIUS_TRANSCRIPT_FAILED` (warning)
- `CAPTURE_BROWSER_FALLBACK` (info, identifies sidestep path)

## Gotchas

- **`CAPTURE_DURATION_UNRESOLVED` (error severity) is expected and harmless** when using the sidestep — see Build profile for the explanation.
- **Wrapper URLs** (`build.microsoft.com/sessions/<CODE>`, `myignite.microsoft.com/.../sessions/<CODE>`) also activate this interceptor because the Medius embed page is loaded in an iframe and the interceptor watches the iframe response. You don't need to extract the Medius URL manually; pass the wrapper URL to Zakira.Replay.
