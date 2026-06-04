# Artifact Checklist

Use this checklist after a Zakira.Replay job succeeds.

Zakira.Replay produces facts only. Summaries, work items, decisions, and other insights are the orchestrating agent's responsibility.

## Required First Reads

- `manifest.json`: confirm paths, produced artifacts, structured warnings, and run ID.
- `evidence.json`: load structured evidence and structured warnings.

## Transcript Evidence

- Read `transcript.md` when present.
- Use `transcript/raw.md`, `transcript/raw.json`, and `transcript/normalization.json` when you need to audit whether caption normalization merged or removed repeated fragments.
- Prefer timestamped transcript segments for claims and quotes.
- When captions carried speaker tags, segments include `speakerId` (slug) and `speakerDisplayName`. A per-speaker registry under `evidence.speakers[]` summarises segment counts and total speaking time. STT-derived transcripts do not carry speakers in this release.
- The transcript can come from **five** sources: yt-dlp captions, a local sidecar `.vtt`/`.srt`, STT (when `stt: true` was set), the browser-network interceptor (when `captureMode: "browser"` or `"auto"` was used and the page fetched a caption file), or the **SharePoint Stream metadata interceptor** (when the source is `*.sharepoint.com/.../stream.aspx?id=...` and the dedicated Edge profile is initialised \u2014 Zakira queries the `_api/v2.X/.../media/transcripts` endpoint, follows each transcript's `temporaryDownloadUrl` with `?isformatjson=true&transcriptkey=<id>` to coax out the rich Teams JSON, and converts to WebVTT with `<v Speaker>` voice spans). Check the underlying `TranscriptArtifact.kind` to know which (`"yt-dlp-subtitle"`, `"sidecar"`, `"<provider>-audio-transcription"`, `"browser-network"`, or the Stream layer's emitted captions land under `captions/stream-NNNN-<lang>.vtt`).
- If transcript is absent and audio matters, rerun with `stt: true`. Long audio is silence-chunked automatically; chunk metadata lands under `audio/chunks/chunks.json` when chunking actually fired, and per-chunk failures appear as `STT_CHUNK_FAILED` warnings.
- If transcript is absent and the source is a JS-rendered player (custom enterprise portal, Microsoft Medius, etc.), rerun with `captureMode: "browser"`. The Playwright network listener captures any `.vtt`/`.srt` the page fetches, persists them to `captions/browser-NNNN.vtt`, indexes them in `captions/discovered.json`, and uses the best-language match (per `captionLanguages` and the source's primary language) to populate `transcript.md`.
- For SharePoint Stream / Microsoft Stream specifically, transcripts include rich speaker attribution (Liad Shiran / Boris Forzun / etc., not anonymous `SPEAKER_NN`) when the Teams transcript JSON shape is downloaded. The raw JSON is preserved alongside the VTT at `captions/stream-NNNN-<lang>.json` for audit (carries `speakerId`, `confidence`, `roomId`, `spokenLanguageTag`, ISO 8601 `startOffset`/`endOffset` per entry).

## Browser-Discovered Captions (`captures/discovered.json`)

Present only when browser capture ran and observed at least one caption response on the wire. Schema: `captions-discovered.schema.json`. Each entry has:

- `url` — original network URL with all query params intact (SAS tokens preserved for audit).
- `relativePath` — persisted file path under the run (e.g. `captions/browser-0001.vtt`).
- `inferredLanguage` — best-effort BCP-47 code from one of: `url-Caption_<lang>` (Microsoft Medius style), `url-filename` (`subtitle_es-ES.vtt`), `url-path-segment` (`/captions/en/`), `url-query-{lang|hl|language|l|tlang}`. May be `null` when no signal is present.
- `languageSource` — identifier of the heuristic that produced `inferredLanguage`; useful for triaging false positives.
- `byteCount`, `contentType`, `contentSha256` — per-file accounting (the SHA dedupes across runs).
- The top-level `originalLanguage` field is the source's primary language as reported by yt-dlp metadata, useful for picking the "main" track when several languages are captured.

## Visual Evidence

- Read `ocr/combined.md` for visible text from frames.
- Read `vision/combined.md` for visual descriptions.
- Inspect frame files when the user asks about layout, diagrams, UI, code, charts, or visual details.
- Each `OcrFrameResult.provider` records whether the result came from `"copilot"` (LLM vision-as-OCR) or `"local"` (RapidOCR via ONNX). Local-OCR results are typically lower fidelity on complex layouts and leave `tables[]` empty (no layout-analysis-based table reconstruction in this release); prefer `"copilot"` when `tables[]` matters.
- Each `VisionFrameResult.provider` records whether vision came from `"copilot"` (LLM-backed) or `"local"` (LocalOnnxVisionProvider — never calls an LLM). Local-mode `charts[]` is always empty; the `freeText` includes a BLIP caption ("Frame appears to show: ...") followed by the literal OCR text when `clip-blip` mode is active. Local-mode degradation is recorded via `VISION_LOCAL_MODE_DEGRADED` warnings listing which CLIP/BLIP files were missing.
- Each `FrameArtifact` may carry optional `width`, `height`, `crop` (the rectangle), and `originalPath` (the pre-crop frame) when smart-crop ran. The frame's `path` then points to the cropped variant; the perceptual hash and downstream OCR/vision were computed on the crop, not the original.
- If frames are sparse, rerun with more `frames` or `frameStrategy: "scene"`.
- For meeting recordings (Teams/Zoom/WebEx), enable `smartCrop: true` (CLI: `--smart-crop`) so the persistent UI chrome is removed before slide grouping. This dramatically improves slide stability and removes meeting-app vocabulary ("Take control", "Raise", "Mute all", etc.) from OCR text.

## Search Evidence

- Build `search/index.json` for repeated Q&A over a run.
- Query the index before reading the full transcript when the user asks about a specific topic.
- Treat search matches as pointers into evidence, not final answers by themselves.

## Clips

- Use clip extraction only when start/end timestamps are known or can be justified from artifacts.
- Save clip paths from `clip.json` and report them with the timestamp range.

## Ad-hoc Frame Capture

- A `frame-capture.json` file (schema: `frame-capture.schema.json`, `kind: "frame-capture"`) at the root of a run means the run came from `frames` / `zakira-replay frames --at|--from`, not the full analyze pipeline. There is no `manifest.json`, no `evidence.json`, no slides/OCR/vision/chapters in that directory.
- `frame-capture.json` carries the request summary (`mode: "timestamps" | "range"`, the original timestamps or range bounds, requested options) plus the resulting `frames[]` array (same shape as `FrameArtifact`) and `warnings[]`.
- Use ad-hoc capture to grab additional stills after a full analyze run (recipe-card photos at known timestamps, transcript-aligned thumbnails, screenshots at evidence-cited moments) without re-running the expensive pipeline.
- Range-mode frames carry timestamps in absolute source-timeline seconds even when the underlying ffmpeg call was scoped to a window.

## Auth Profiles (SSO-Gated Sources)

Two shapes, both created interactively via the CLI (cannot be created from MCP):

1. **Dedicated Edge profile** (`zakira-replay auth init-edge-profile [--url <site>]`) \u2014 recommended for SharePoint / Microsoft Stream / Microsoft 365 sources. Stores cookies in Edge's native DPAPI-encrypted SQLite at `%LOCALAPPDATA%\Zakira.Replay\edge-profile` (override via `capture.browser.edgeUserDataDir` or `ZAKIRA_REPLAY_EDGE_USER_DATA_DIR`). Persistent-context mode auto-activates for every `captureMode: "browser"` (or `"auto"`) run \u2014 no `authProfile` argument needed. `doctor` reports `edge-profile: found`. Re-run `auth init-edge-profile` when Conditional Access expires the session (`CAPTURE_BROWSER_AUTH_REQUIRED` / `CAPTURE_BROWSER_AUTH_MFA_DETECTED`).

2. **StorageState JSON profile** (`zakira-replay auth login <profile-name>`) \u2014 legacy path. Stored under `<config-dir>/auth/<slug>.json` as plaintext cookies. List with `auth list`, inspect with `auth show <name>`, delete with `auth clear <name>`. Pass `authProfile: "<name>"` along with `captureMode: "browser"` (or `"auto"`) to load the saved cookies. Use only when persistent-context isn't viable; Microsoft cookies typically expire in 1\u20132 hours so `AUTH_PROFILE_STALE` (info) fires often. When both an initialised dedicated Edge profile AND a StorageState profile are configured, persistent-context wins and `CAPTURE_PROFILE_CONFLICT` (info) records the override.

- The pipeline emits `AUTH_PROFILE_NOT_FOUND` (error) when the named StorageState profile is absent and `AUTH_PROFILE_STALE` (info) when its mtime is older than `auth.staleThresholdMinutes` (default 60). Staleness does not block the run; if downstream extraction looks like it landed on a login page, suggest the user re-run `auth login <name>` (StorageState) or `auth init-edge-profile` (preferred) to refresh cookies.
- `CAPTURE_BROWSER_PROFILE_NOT_INITIALIZED` (info): the configured Edge user-data-dir has no Cookies file yet; capture falls back to StorageState/anonymous. Run `auth init-edge-profile` once.
- `CAPTURE_BROWSER_PROFILE_DIR_MISSING` (error): explicit `edgeUserDataDir` points at a non-existent directory; capture aborts.
- `CAPTURE_BROWSER_PROFILE_LOCKED` (error): `SingletonLock` present \u2014 a running Edge instance is using the dir. Close it.
- `CAPTURE_BROWSER_PROFILE_LAUNCH_FAILED` (error): `LaunchPersistentContextAsync` threw (corrupt profile, DPAPI failure). Re-init.

## Warnings

- Warnings are structured records: `{ code, message, source, severity }`.
- Branch on `code`, not on the message text.
- Known codes (one line per code, severity in parentheses):
  - `TRANSCRIPT_NOT_FOUND` (warning) / `TRANSCRIPT_NOT_FOUND_NO_STT` (warning) — captions missing; the `_NO_STT` variant fires when `stt` was not set so STT fallback was skipped.
  - `MEDIA_URL_UNRESOLVED` (error) — yt-dlp could not extract a direct media URL.
  - `AUDIO_REMOTE_FALLBACK` (info) / `AUDIO_DOWNLOAD_FAILED` (error) — direct audio extract failed; pipeline tried local-download fallback.
  - `STT_NO_AUDIO` / `STT_NO_LLM_PROVIDER` (error) / `STT_CHUNK_FAILED` (warning) — speech-to-text failures.
  - `FRAMES_NO_MEDIA` / `FRAMES_REMOTE_FALLBACK` (info) / `FRAMES_DOWNLOAD_FAILED` (error) / `FRAMES_SCENE_CAP_REACHED` (warning) / `FRAMES_LIKELY_UNDERSAMPLED` (warning) — frame-extraction issues.
  - `OCR_NO_LLM_PROVIDER` (error) / `OCR_PARSE_FALLBACK` (warning) / `OCR_LOCAL_MODELS_MISSING` (error) / `OCR_LOCAL_INIT_FAILED` (error) / `OCR_LOCAL_INFERENCE_FAILED` (warning) / `OCR_UNKNOWN_PROVIDER` (error) — OCR-side issues. The `OCR_LOCAL_*` codes only fire under `ocrProvider: "local"`.
  - `VISION_NO_LLM_PROVIDER` (error) / `VISION_PARSE_FALLBACK` (warning) — vision-side issues.
  - `VISION_LOCAL_MODELS_MISSING` (warning) / `VISION_LOCAL_INIT_FAILED` (error) / `VISION_LOCAL_INFERENCE_FAILED` (warning, per-frame) / `VISION_LOCAL_MODE_DEGRADED` (warning) / `VISION_LOCAL_OCR_REQUIRED` (info) / `VISION_UNKNOWN_PROVIDER` (error) — local vision provider diagnostics. The first four indicate model availability or runtime issues; the fifth records that OCR was auto-enabled because the local provider needs it; the sixth means an invalid `--vision-provider` value was passed.
  - `PERCEPTUAL_HASH_FAILED` (warning) — slide grouping may be coarse for at least one frame.
  - `CROP_IMAGE_DECODE_FAILED` (warning) / `CROP_BAIL_OUT` (info) / `CROP_PROFILE_UNKNOWN` (warning) / `CROP_OUTPUT_FAILED` (warning) — smart-crop issues. `CROP_BAIL_OUT` is informational — the algorithm proposed a too-aggressive crop and used the original frame instead.
  - `CAPTURE_BROWSER_UNAVAILABLE` (error) / `CAPTURE_BROWSER_FALLBACK` (info) / `CAPTURE_PLAY_BUTTON_NOT_FOUND` (info-or-warning) / `CAPTURE_DURATION_UNRESOLVED` (error) / `CAPTURE_SEEK_FAILED` (warning) / `CAPTURE_SCREENSHOT_FAILED` (warning) / `CAPTURE_UNKNOWN_MODE` (warning) — Playwright capture issues.
  - `CAPTIONS_BROWSER_NETWORK_NONE` (info) / `CAPTIONS_BROWSER_NETWORK_DOWNLOAD_FAILED` (warning) / `CAPTIONS_BROWSER_NETWORK_PARSE_FAILED` (warning) — browser caption interceptor results.
  - `CAPTURE_BROWSER_CAPTIONS_ACTIVATED` (info) / `CAPTURE_BROWSER_CAPTIONS_HARVESTED_FROM_DOM` (info) — caption-track activation and direct cue harvest from the `<video>.textTracks` API. The harvest path is the fallback for players that build cues via `track.addCue()` and never fetch a `.vtt`/`.srt` over the wire.
  - `CAPTURE_BROWSER_PROFILE_NOT_INITIALIZED` (info) / `CAPTURE_BROWSER_PROFILE_DIR_MISSING` (error) / `CAPTURE_BROWSER_PROFILE_LOCKED` (error) / `CAPTURE_BROWSER_PROFILE_LAUNCH_FAILED` (error) / `CAPTURE_BROWSER_AUTH_REQUIRED` (error) / `CAPTURE_BROWSER_AUTH_MFA_DETECTED` (error) / `CAPTURE_PROFILE_CONFLICT` (info) — dedicated Edge profile (persistent-context) issues. The first three are setup problems; the next two are runtime auth problems (post-navigation URL landed on a sign-in page, or the page rendered a Microsoft MFA challenge that headless capture cannot satisfy). `CAPTURE_PROFILE_CONFLICT` records that both an initialised Edge profile AND a StorageState `authProfile` were configured \u2014 persistent-context won.
  - `CAPTURE_BROWSER_MEDIA_DOWNLOADED` (info) / `CAPTURE_BROWSER_MEDIA_NO_CANDIDATE` (info) / `CAPTURE_BROWSER_MEDIA_DOWNLOAD_FAILED` (warning) — STT-fallback media download via the authenticated browser context. Triggered only when `stt: true` AND `allowMediaDownload: true` are both set AND no captions came out of the other layers AND no audio source exists. DASH / HLS chunked streams (typical SharePoint Stream pattern) emit `CAPTURE_BROWSER_MEDIA_NO_CANDIDATE` and skip STT cleanly.
  - `CAPTURE_STREAM_TRANSCRIPT_DISCOVERED` (info) / `CAPTURE_STREAM_TRANSCRIPT_DOWNLOADED` (info) / `CAPTURE_STREAM_METADATA_PARSE_FAILED` (warning) / `CAPTURE_STREAM_TRANSCRIPT_PARSE_FAILED` (warning) — SharePoint Stream / Microsoft Stream native transcript layer. The "DISCOVERED" warning lists languages and sources; the "DOWNLOADED" warning records the per-transcript output path. Parse-failure warnings keep the raw response body in `captions/` for manual inspection.
  - `CAPTURE_MEDIUS_TRANSCRIPT_DISCOVERED` (info) / `CAPTURE_MEDIUS_TRANSCRIPT_DOWNLOADED` (info) / `CAPTURE_MEDIUS_TRANSCRIPT_FAILED` (warning) — Medius / Microsoft Build / Ignite native transcript layer. The interceptor parses the embed page's inline `captionsConfiguration` and `coreConfiguration` blocks. Per-language VTT lands at `captions/medius-NNNN-<lang>.vtt`. Captions arrive even when `CAPTURE_DURATION_UNRESOLVED` fires (Shaka MSE player not booting headlessly is expected for these sources).
  - `MEDIA_DOWNLOAD_DECLINED` (error) — the run reached a local-download path (yt-dlp ffmpeg-failure fallback, STT fallback, spot-frames last-resort, or clip extraction) but `allowMediaDownload: true` was not set. The message names the field so the agent can decide whether to prompt the user before retrying with the opt-in.
  - `AUTH_PROFILE_NOT_FOUND` (error) / `AUTH_PROFILE_STALE` (info) / `AUTH_PROFILE_LOAD_FAILED` (error) — StorageState (legacy) auth profile resolution issues.
  - `CLIP_MEDIA_URL_UNRESOLVED` (error) — clip extraction couldn't resolve the source.
  - `FRAME_CAPTURE_MEDIA_URL_UNRESOLVED` (info-or-error) / `FRAME_CAPTURE_TIMESTAMP_OUT_OF_RANGE` (warning) / `FRAME_CAPTURE_RANGE_OUT_OF_BOUNDS` (warning) / `FRAME_CAPTURE_TOO_MANY_TIMESTAMPS` (warning) / `FRAME_CAPTURE_NO_FRAMES` (warning) / `FRAME_CAPTURE_SCENE_CAP_REACHED` (warning) — ad-hoc frame-capture issues. All live on `frame-capture.json::warnings`, not `manifest.json`, because they are emitted by the lean capture path. For Microsoft Build / Medius sources, the `frames` tool automatically falls back to the browser inline-media probe before declining — no `allowMediaDownload` needed for those sources because we never actually download, just stream-seek the inline HLS URL.
- Two newer top-level `manifest.json` fields agents should read alongside the warnings:
  - `manifest.secondaryTranscripts[]` — when `secondaryCaptionLanguages` was requested, each entry is `{ language, markdownPath, sourcePath }` for an additional-language transcript persisted as `transcript.<lang>.md`.
  - `manifest.sessionMetadata` — deterministic page-derived metadata for sources captured via the browser path (Microsoft Build, Medius, Stream, any page with JSON-LD / OpenGraph). Carries `title`, `description`, `sessionCode`, `track`, `level`, `publishedAt`, `speakers[]`, `products[]`, `tags[]`, `sourceUrl`, plus per-strategy provenance under `sources[]`. Use this in lieu of inventing speaker names or session ids when summarising.
- After `chapters.build`, each `Chapter` and `ChapterEvidence` carries a `deepLink` (time-anchored URL — `?t=Ns` for YouTube, `?nav=t=…` for SharePoint Stream, `#t=N` for everything else). Include these in answers when the user might want to jump back into the source.
- After `index.query` (including against a cross-run conference index built with `index.build-conference`), each `SearchMatch` carries `deepLink`, `runId`, and `sourceUrl` so the agent can attribute hits and hand the user a link they can open.
- Treat missing captions, missing media URL, failed OCR, failed vision, fallback downloads, undersampled frame coverage, and stale auth profiles as confidence modifiers — none of them prevent the run from completing, but all of them affect what claims the orchestrator can make.

## Response Quality

- Cite timestamps where possible.
- Keep raw transcript excerpts short unless the user asks for extensive quotes.
- Do not invent speaker names, slides, charts, or numbers not present in artifacts.
- Mention by `code` any warnings that affect confidence in the answer.
- If evidence is insufficient, say so and recommend a concrete rerun option (e.g. "rerun with `stt: true`" / "rerun with `captureMode: \"browser\"`" / "rerun with `smartCrop: true` for this Teams recording" / "ask the user to re-run `auth login <name>` and try again").
