---
name: YouTube
status: working
hostPatterns:
  - youtube.com
  - "*.youtube.com"
  - youtu.be
urlPatterns:
  - https://www.youtube.com/watch?v=*
  - https://youtu.be/*
  - https://*.youtube.com/embed/*
underlyingPlayer: YouTube iframe player (yt-dlp resolves direct URLs; no browser needed)
authNeeded: none for public videos; cookies-from-browser for age-gated / members-only
lastVerified: 2026-06-04
zakiraReplayVersion: 0.10.1+
---

# YouTube

The happy path. yt-dlp resolves YouTube URLs directly to a media URL ffmpeg can seek into. The default `--capture-mode auto` (0.14+) tries yt-dlp first and falls back to browser on failure; for YouTube that means yt-dlp wins immediately, so no flags are needed. Captions are auto-discovered from the watch page; the default `--caption-languages auto` unions the source's primary language with English and any manually-uploaded sidecars.

## What works

- **Transcript:** yes via yt-dlp subtitles (manual + auto-generated). For very long videos with no captions, fall back to `--stt --allow-media-download`.
- **Frames:** yes via ffmpeg seek against the direct media URL. No browser, no download.
- **Session metadata** (`manifest.sessionMetadata`): only when `--capture-mode browser` is used (the deterministic extractor runs in the browser path). For ytdlp mode, the existing `metadata.json` (yt-dlp's output) carries title, uploader, duration, available subtitle languages.
- **Deep links:** site-specific `?t=Ns` format (replaces any existing `t=` query param). Both `youtube.com/watch?v=…` and `youtu.be/…` URL shapes accepted.
- **Captions languages observed:** depends on the upload. `metadata.json::availableSubtitleLanguages` lists what's actually available (`hasManual` / `hasAuto` per language).
- **Auth:** none for public videos. Age-gated / members-only / private-unlisted: pass `--cookies-from-browser edge` (or `firefox`, `chrome`) so yt-dlp picks up your browser session.

## Recommended commands

### Single video — CLI

Default (works for public videos; uses the 0.14 defaults — `auto` capture mode picks yt-dlp for YouTube, `--frames 15 --frame-strategy interval`):

```pwsh
dnx Zakira.Replay analyze "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

Slide-heavy talks (one frame per scene cut works well on YouTube; safe here because yt-dlp gives a direct media URL, not HLS):

```pwsh
dnx Zakira.Replay analyze "https://www.youtube.com/watch?v=dQw4w9WgXcQ" --frame-strategy scene
```

Transcript-only:

```pwsh
zakira-replay transcribe "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

Age-gated / members-only:

```pwsh
dnx Zakira.Replay analyze "https://www.youtube.com/watch?v=<id>" `
  --cookies-from-browser edge
```

Auto-generated captions are excluded from `--caption-languages auto` by design (they're inferences, not facts). To opt in to a specific auto-translation:

```pwsh
zakira-replay transcribe "https://www.youtube.com/watch?v=<id>" --caption-languages es
```

Spot frames:

```pwsh
zakira-replay frames "https://youtu.be/<id>" --at "00:01:23,00:04:56"
```

### Single video — MCP

```json
{
  "tool": "analyze-start",
  "arguments": {
    "source": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    "frames": 7,
    "frameStrategy": "scene"
  }
}
```

### Playlists

**Not supported as a single source.** yt-dlp is invoked with `--no-playlist` everywhere in the pipeline; passing a playlist URL captures only the entry-point video. To process a playlist, expand it yourself (e.g. `yt-dlp --flat-playlist --print "%(webpage_url)s"`) and enqueue each video separately.

## Known limitations

- **Auto-generated captions are not in `--caption-languages auto`.** This is deliberate — they're machine inferences, not transcriptions of what was actually spoken. Read `metadata.json::availableSubtitleLanguages` to see which languages have `hasManual: true` vs `hasAuto: true` only, and pass the language explicitly when you want auto.
- **DRM-protected / pay-per-view content cannot be captured.** yt-dlp returns no media URL.
- **Region-locked content needs a cookie/proxy.** `--cookies-from-browser` for a logged-in session; pipeline-level proxy is not exposed (set `HTTP_PROXY` env vars yt-dlp reads).
- **Live streams**: not first-class. The pipeline treats them as VOD; if the stream is still active, capture will time out or grab whatever's been DVR-buffered.

## Source-specific warning codes

None — YouTube uses only the standard pipeline warning codes:

- `TRANSCRIPT_NOT_FOUND_NO_STT` (warning): no captions for this video. Retry with `--stt --allow-media-download`.
- `MEDIA_URL_UNRESOLVED` (info): yt-dlp couldn't resolve (age-gated, private, removed). Retry with `--cookies-from-browser`.

## Gotchas

- **`?t=Ns` is preserved on output deep links.** If you pass a URL like `https://youtu.be/<id>?t=120s`, the deep links in `chapters/chapters.json` and `search/index.json` will have **their own** computed `t=` values appended, replacing the input's. The `DeepLink.For` builder deduplicates so you don't end up with two `t=` parameters.
- **`--frame-strategy scene` is safe on YouTube** (yt-dlp resolves a direct progressive media URL so ffmpeg only decodes the frames it needs). On HLS-only sources like Microsoft Build, scene mode pulls the entire stream — that's why the post-0.14 default is `interval`. For long-form livestream archives or podcasts with a static talking head, switch to `--frame-strategy interval --frames-per-minute 1`.
- **No browser capture needed.** `--capture-mode browser` works but is slower and unnecessary; only reach for it when yt-dlp returns nothing (private content + the dedicated Edge profile is already initialised).
