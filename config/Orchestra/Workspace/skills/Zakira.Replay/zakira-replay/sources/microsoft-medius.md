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
zakiraReplayVersion: 0.14.0+
---

# Microsoft Medius

The Microsoft Events streaming platform that hosts Microsoft Build, Ignite, and other event session recordings. The player is Shaka over MSE, fed via inline JS configuration. Most users encounter Medius transparently via wrapper pages (e.g. [`build.microsoft.com/sessions/<CODE>`](microsoft-build.md)); this profile applies whenever you hand a direct Medius embed URL to Zakira.Replay.

`medius.studios.ms`, `medius.microsoft.com`, and `medius*.event.microsoft.com` are in the `KnownHosts` registry, so the default `analyze` command automatically:

- skips the yt-dlp metadata probe;
- routes straight to browser capture;
- enables the inline-media sidestep (no `CAPTURE_DURATION_UNRESOLVED` noise).

No flags are required for a typical run.

## What works

- **Transcript:** yes via `MediusTranscriptInterceptor` — the embed page inlines `captionsConfiguration` with SAS-signed `Caption_<lang>.vtt` URLs that the interceptor parses and downloads directly. No `--stt`, no playback engagement, no audio download required.
- **Frames:** yes via the automatic inline-media sidestep. The embed page also inlines `coreConfiguration.manifests.main[]` carrying the HLS master playlist URL; the interceptor surfaces it as `BrowserCaptureResult.InlineMediaUrl` and ffmpeg seeks into it.
- **Session metadata** (`manifest.sessionMetadata`): partial — `coreConfiguration.videoTitle` and friends are inlined alongside the player config but Medius doesn't put them in JSON-LD/OpenGraph form. The deterministic `SessionMetadataExtractor` will fill `title` from the page `<title>` element; `speakers`, `track`, `sessionCode` typically end up null.
- **Deep links:** generic W3C Media Fragments (`#t=<seconds>`).
- **Captions languages observed:** up to 36 on first-tier events (Build keynotes); regional events may have fewer.
- **Auth:** none for public events. Microsoft-internal Medius events require sign-in — use the dedicated Edge profile (`zakira-replay auth init-edge-profile`).

## Recommended commands

### Single session — CLI

```pwsh
dnx Zakira.Replay analyze "https://medius.studios.ms/Embed/video-nc/<id>"
```

Transcript-only:

```pwsh
dnx Zakira.Replay transcribe "https://medius.studios.ms/Embed/video-nc/<id>"
```

### Single session — MCP

```json
{
  "tool": "analyze-start",
  "arguments": {
    "source": "https://medius.studios.ms/Embed/video-nc/<id>"
  }
}
```

### Conference / batch

Same shape as Build — see [`microsoft-build.md`](microsoft-build.md) for the full queue + `index build-conference` workflow. The only difference is the URL pattern in `queue enqueue`.

### Spot frames

```pwsh
dnx Zakira.Replay frames "https://medius.studios.ms/Embed/video-nc/<id>" --at "<MM:SS>"
```

## Known limitations

- **Don't pass `--frame-strategy scene`.** Scene-cut detection pulls the entire HLS stream. The 0.14 default of `interval` avoids this; only override if you know you need it.
- **`asl`/`isl`/`bsl` sign-language video tracks are deliberately ignored.** The interceptor picks `coreConfiguration.manifests.main[0].manifest` so spot frames reflect the speaker's slide content, not the sign-language overlay.
- **The interceptor's HLS URL is host-direct, not SAS-signed.** Public Build/Ignite sessions accept it without cookies. Sign-in-gated Medius events may add per-request auth headers that the inline URL strips; if frames fail with HTTP 403 after the interceptor reported the URL, the source needs auth via the dedicated Edge profile (the captions still work because each `Caption_<lang>.vtt` carries its own SAS token).

## Source-specific warning codes

Same as [Microsoft Build](microsoft-build.md):

- `CAPTURE_MEDIUS_TRANSCRIPT_DISCOVERED` (info, suppressed in default output)
- `CAPTURE_MEDIUS_TRANSCRIPT_DOWNLOADED` (info, suppressed in default output)
- `CAPTURE_MEDIUS_TRANSCRIPT_FAILED` (warning)
- `CAPTURE_BROWSER_FALLBACK` (info, suppressed in default output; identifies sidestep path under `--verbose`)

## Gotchas

- **`CAPTURE_DURATION_UNRESOLVED` is now `info` severity** (was `error` through 0.13) and is suppressed in default output — see Build profile for the explanation.
- **Wrapper URLs** (`build.microsoft.com/sessions/<CODE>`, `myignite.microsoft.com/.../sessions/<CODE>`) also activate this interceptor because the Medius embed page is loaded in an iframe and the interceptor watches the iframe response. You don't need to extract the Medius URL manually; pass the wrapper URL to Zakira.Replay.
