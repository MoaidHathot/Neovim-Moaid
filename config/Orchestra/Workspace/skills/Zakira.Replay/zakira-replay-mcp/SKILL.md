---
name: zakira-replay-mcp
description: Use Zakira.Replay's MCP server tools to run non-blocking video analysis jobs, retrieve timestamped evidence artifacts, build chapters/search indexes, and extract clips. Zakira.Replay produces facts only; you synthesize summaries, work items, and other insights from those artifacts.
---

# Zakira.Replay MCP Skill

Use this skill when Zakira.Replay is available as an MCP server and the user asks you to analyze, summarize, inspect, search, quote, clip, or extract work items from a video.

Zakira.Replay is an evidence producer. It writes durable, fact-shaped artifacts to disk and returns artifact paths through MCP. **It does not synthesize summaries, work items, decisions, or any other inferences.** Your job is to call MCP tools, read the produced artifacts, and synthesize the user's requested answer from those files.

## Core Rule

Never claim you watched a video directly. Base every answer on artifacts returned by MCP: `manifest.json`, `evidence.json`, `transcript.md`, frame images, `ocr/combined.md`, `vision/combined.md`, or `chapters/chapters.md`.

## MCP Server

The server command is:

```bash
zakira-replay mcp serve [--transport stdio|http|sse] [--port 8765]
```

`--transport stdio` (the default) is what Claude Desktop, Cursor, VS Code Copilot, and any subprocess-style MCP client use. `--transport http` hosts a Streamable HTTP MCP endpoint at `http://127.0.0.1:<port>/` for hosted-agent platforms that connect over the network instead of spawning a subprocess. `--transport sse` is an alias for the same Streamable HTTP endpoint (the SSE transport was folded into Streamable HTTP in the MCP spec) and is kept for legacy clients.

If `zakira-replay` is not on `PATH`, configure the MCP client to use the full executable path or a development `dotnet run` command.

The MCP server reads + writes artifacts under the configured **runs directory**: `ZAKIRA_REPLAY_RUNS_DIRECTORY` env var > `runs.directory` user-config key > legacy `<cwd>/runs`. Job snapshots persist under `<runs>/.mcp/jobs/`, the persistent queue lives under `<runs>/.queue/`. When deploying the MCP server as a long-running service (HTTP transport), set `runs.directory` to a stable location (`%LOCALAPPDATA%\Zakira.Replay\runs` on Windows, `~/Library/Application Support/Zakira.Replay/runs` on macOS, `$XDG_DATA_HOME/Zakira.Replay/runs` on Linux) so runs survive cwd changes.

Use `doctor` as the first tool when dependency or provider readiness is unknown, then `deps-install` to download anything it reports missing.

## Source-specific profiles

When the `source` is a URL (not a local file), open `skills/zakira-replay/sources/README.md` and match the URL's host against the index. If a profile matches, read **that profile only** — it names the recommended capture mode, argument combinations, expected artifacts, known limitations, and warning codes specific to that source. Lookup is advisory: hosts not in the index use the defaults documented here. Adding a new source profile is one file + one row in the index — see the directory's README for the contribution shape.

## Tool Selection

Prefer these tools:

- `analyze-start`: start non-blocking analysis and get a `jobId`.
- `analyze-status`: poll logs and status.
- `analyze-result`: fetch completed manifest and artifact directory.
- `chapters-build`: build `chapters/chapters.json` and `chapters/chapters.md` for a completed run.
- `index-build`: build JSON, SQLite, or SQLite+ONNX search over a completed run.
- `index-build-conference`: aggregate `evidence.json` from multiple completed runs into one cross-run / conference index at `<runs-root>/.indexes/<conferenceId>/index.json`. Each document carries its origin `runId` and `sourceUrl` so query results stay attributable per session.
- `index-query`: retrieve relevant evidence chunks. `target` is polymorphic — accepts a file path, a run directory, or a conference id from `index-build-conference`. Each `SearchMatch` carries `deepLink` (time-anchored URL the agent can hand to the user), plus `runId` and `sourceUrl`.
- `clip`: create a timestamped clip when start/end are known.
- `frames`: ad-hoc frame capture at specific timestamps or inside a time window, without paying for the full analyze pipeline (no slides/OCR/vision/alignment). Use after a full `analyze` run when an agent needs additional stills for a downstream artifact (e.g. illustrating a recipe step, attaching a thumbnail to a chapter, or grabbing a screenshot at a transcript moment). For Microsoft Build / Medius sources, the tool automatically runs a fast browser metadata probe to recover the inline HLS URL — `frames --at "00:22:30"` against a Build session works without explicit `--allow-media-download`.
- `align`: build cross-modal alignment views (`by-chapter`, `by-slide`) over a completed run. Pure rearrangement; no model calls.
- `doctor`: diagnose dependencies and provider setup (binaries, local models, Ollama daemon, Edge profile).
- `info`: resolved configuration + capability summary (config path, runs directory, LLM provider/model, portable + per-feature model directories, and which optional features are ready).
- `deps-install`: download missing portable dependencies on demand — `yt-dlp`, `ffmpeg`, `copilot-cli`, and the local `onnx`/`ocr`/`vision`/`whisper-model`/`diarization` models (or `media` / `all`). Use right after `doctor` reports something missing to self-provision without a CLI shell-out.
- `queue-enqueue`, `queue-run`, `queue-status`: persistent queue workflow for many videos.

Use `analyze` only for short, low-risk jobs where blocking is acceptable. For long videos, visual analysis, OCR, or STT work, use `analyze-start`.

## Job Workflow

1. Call `analyze-start` with source and analysis options.
2. Poll `analyze-status` every few seconds until status is `succeeded`, `failed`, or `cancelled`.
3. If `succeeded`, call `analyze-result`.
4. Extract `artifactDirectory` from the result.
5. Read `manifest.json` first, then the evidence artifacts needed for the user's request.
6. Build chapters/search only after analysis succeeds.

General analysis arguments:

```json
{
  "source": "https://example.com/video",
  "visionInstruction": "Extract transcript, representative frames, OCR, and visual evidence for answering the user's question.",
  "cache": true,
  "ocr": true,
  "vision": true,
  "maxAiFrames": 5
}
```

Frame strategy and count default to `interval` / `15`; capture mode defaults to `auto` (yt-dlp → browser fallback, with known Medius/Build hosts going straight to browser + inline-media). Override `frames`, `frameStrategy`, or `captureMode` only when the defaults aren't right for the source.

Transcript-first arguments:

```json
{
  "source": "https://example.com/video",
  "visionInstruction": "Extract a timestamped transcript and key evidence.",
  "frames": 0,
  "cache": true
}
```

Slide, UI, code, or demo-heavy arguments (override the default `interval` strategy with `scene` for slide-cut sampling — safe on direct-URL sources like YouTube, **avoid on long HLS sources** like Microsoft Build keynotes where scene-cut detection pulls the entire stream):

```json
{
  "source": "https://example.com/video",
  "visionInstruction": "Extract timestamped transcript evidence, visible slide/UI text, visual context, and topic boundaries.",
  "frames": 30,
  "frameStrategy": "scene",
  "cache": true,
  "stt": true,
  "ocr": true,
  "vision": true,
  "maxAiFrames": 30
}
```

Authenticated video arguments:

```json
{
  "source": "https://example.com/private-video",
  "visionInstruction": "Extract evidence from this authenticated video.",
  "cache": true,
  "browserAuth": "edge"
}
```

Use `cookies` when the user provides a cookies file path. Use `browserAuth` or `cookiesFromBrowser` only when the local browser session is expected to have legitimate access.

For SSO-gated sources (Microsoft 365 / Azure AD / Okta / SharePoint / Microsoft Stream / Medius portals) where yt-dlp cookie passthrough is insufficient, use a persistent **auth profile**. There are two profile shapes, both interactive CLI-side setup (MCP cannot perform interactive logins because there is no terminal/UI):

1. **Dedicated Edge profile** (`zakira-replay auth init-edge-profile [--url <site>]`) \u2014 **strongly preferred for Microsoft sources**. Stores cookies in Edge's native DPAPI-encrypted SQLite (per-user, per-machine), refreshes them in place during normal use, and activates automatically for every `captureMode: "browser"` (or `"auto"`) run that lands on a Microsoft site. No `authProfile` argument needed once the profile is initialised; the CLI default path is `%LOCALAPPDATA%\Zakira.Replay\edge-profile`. **SharePoint Stream / Microsoft Stream transcripts** \u2014 including speaker attribution (`<v Speaker>` voice spans, downloaded as Teams transcript JSON with the `?isformatjson=true&transcriptkey=<id>` URL variant the player itself uses) \u2014 land in `captions/stream-NNNN-<lang>.{vtt,json}` and populate `transcript.md` automatically.

2. **StorageState JSON profile** (`zakira-replay auth login <name>`, then pass `authProfile`) \u2014 legacy path. Writes plaintext cookies to `<config-dir>/auth/<slug>.json`. Faster to set up but expires within ~1\u20132 hours for Microsoft sources and is portable to any machine (security concern). Use only when the dedicated Edge profile is unavailable, or for non-Microsoft sites where a portable snapshot is preferable.

When both an initialised dedicated Edge profile and `authProfile` are present, persistent-context wins and `CAPTURE_PROFILE_CONFLICT` (info) records the override. Pass `authProfile` and `captureMode: "browser"` (or `"auto"`):

```json
{
  "source": "https://medius.studios.ms/Embed/video-12345",
  "visionInstruction": "Extract evidence from this Microsoft Ignite session.",
  "frames": 10,
  "captureMode": "browser",
  "authProfile": "ignite-2026",
  "ocr": true,
  "ocrProvider": "local",
  "smartCrop": true,
  "cache": true
}
```

Browser capture for sources yt-dlp cannot reach:

```json
{
  "source": "https://corporate.example.com/portal/watch/abc",
  "visionInstruction": "Extract evidence from a custom enterprise video portal.",
  "frames": 7,
  "captureMode": "browser",
  "authProfile": "corp-sso",
  "cache": true
}
```

`captureMode: "auto"` tries yt-dlp + ffmpeg first and falls back to Playwright on failure (emits `CAPTURE_BROWSER_FALLBACK`). Use `auto` when you are unsure which path will work for a given URL; use `browser` when you already know yt-dlp cannot reach the source.

## Option Selection

Use these defaults unless the user says otherwise:

- `cache: true`: default for agent workflows; set `force: true` only when intentionally recomputing.
- `frames`: defaults to `15` — fine for most general analysis. Override down to `5` for cheap exploration, up to `30+` for visually dense videos. Set `frames: 0` for transcript-only.
- `frameStrategy`: defaults to `"interval"` — predictable N-frame sampling, bandwidth-light. Override to `"scene"` for slide/demo-heavy content where scene-cut sampling is preferable. **Avoid `"scene"` on long HLS sources** (Microsoft Build keynotes, Medius wrappers) — ffmpeg decodes every frame, pulling the entire stream (~6–8 GB on a 3-hour keynote).
- `frameStrategy: "every-frame"` or `everyFrame: true`: only when the user explicitly needs capped frame-by-frame inspection.
- `ocr: true`: slides, code, dashboards, diagrams, documents, or burned-in captions may be visible.
- `vision: true`: visual content matters.
- `stt: true`: captions may be absent or poor. Captions/sidecars are tried first; STT runs only when transcript extraction fails.
- `captionLanguages: ["fr", "en"]` (or `"fr,en"`): override subtitle/caption language preferences. Defaults to `["auto"]`, which unions the source's primary language, the languages with **manually uploaded** subtitles (per `info.subtitles`), English (`en`, `en.*`), and YouTube live-chat. YouTube auto-translation languages (those that appear only under `info.automatic_captions`) are intentionally **not** expanded by `auto` because they are inferences from the source, not facts about what was spoken. To opt into a specific auto-translation, pass that language explicitly (e.g. `captionLanguages: ["es"]`). Read `metadata.json -> availableSubtitleLanguages` first to learn which languages exist for the source and whether each has manual (`hasManual`) or auto-only (`hasAuto`) coverage. Frames carry stable `id` values referenced from `ocr[*].frameId` and `vision[*].frameId`.
- `visionInstruction` and `ocrInstruction`: optional focus signals appended to the vision and OCR prompts. Both default to empty; the model already extracts every visible piece of content (vision: slide titles, bullets, code blocks, chart axes, UI controls; OCR: every readable character). Use these only to bias enumeration toward what matters for your question (e.g. `visionInstruction: "Bias toward chart axes and code"`, `ocrInstruction: "Preserve indentation in code-like text"`). Both are persisted into `evidence.json::visionInstruction` and `evidence.json::ocrInstruction` for audit. They never relax the "do not invent" guardrails.
- `framesPerMinute`: optional duration-aware sampling rate for the interval strategy. When set, the effective frame count is `max(framesPerMinute * durationMinutes, frames)`. Ignored for `scene` and `every-frame`. Use this instead of cranking `frames` when sampling a long video.
- `sceneSafetyCap`: per-run override of `frames.sceneSafetyCap` (default 5000). The scene strategy returns up to this many frames; slide grouping deduplicates. The run carries a `FRAMES_SCENE_CAP_REACHED` warning when the cap is hit, and `FRAMES_LIKELY_UNDERSAMPLED` when interval sampling without `framesPerMinute` (and with `frames.perMinute=0` in config) produces fewer than 1 frame per 5 minutes.
- `ocrProvider`: choose the OCR backend. `"local"` (default) runs RapidOCR (PP-OCRv5) entirely on-device via ONNX — no LLM, no network at run-time after the one-time model download, no per-frame agent loop. Defaults to the **latin** language pack; switch packs for non-Latin scripts via `zakira-replay deps install ocr --language <pack>` + `ocr.local.languagePack` config (or `ZAKIRA_REPLAY_OCR_LANGUAGE_PACK`). Supported packs: `latin`, `chinese`, `english`, `korean`, `cyrillic`, `arabic`, `devanagari`, `greek`, `telugu`, `tamil`. `"copilot"` routes the image through the configured LLM (GitHub Copilot / OpenAI / Azure OpenAI / Ollama) using vision-capable chat models — prefer this for complex layouts, mixed scripts not covered by the local packs, or when `tables[]` reconstruction matters (the local provider leaves `tables[]` empty in this release). The first local-OCR run auto-downloads ~30 MB of models (`ocr.local.autoDownload=true` by default; set false to disable, or pre-install with `zakira-replay deps install ocr [--language <pack>]`). The chosen provider is recorded on every `OcrFrameResult.provider`.
- `visionProvider` + `localVisionMode`: choose the vision backend. `"copilot"` (default) routes the image through the configured LLM; `"local"` runs the fully-on-device `LocalOnnxVisionProvider` that never calls an LLM. Under `"local"`, set `localVisionMode` to one of `"heuristic"` (zero models, structure derived from OCR; runs out of the box), `"clip"` (heuristic + CLIP ViT-B/32 zero-shot for `kind`, ~150 MB auto-installable via CLI `zakira-replay deps install vision --mode clip` followed by `zakira-replay vision generate-clip-embeddings`), or `"clip-caption"` (default for the local provider; CLIP + Florence-2-base-ft image captioning — auto-installed by `zakira-replay deps install vision --mode clip-caption`, ~410 MB total). The deprecated `"clip-blip"` string is still accepted as an alias for `"clip-caption"`. When `visionProvider: "local"` is requested without `useOcr: true`, the pipeline auto-enables OCR and records `VISION_LOCAL_OCR_REQUIRED` (info). Missing CLIP/Florence files cause graceful degradation (`clip-caption` → `clip` → `heuristic`) with a `VISION_LOCAL_MODE_DEGRADED` warning. Local-mode `charts[]` is always empty; the LLM path is structurally better for charts, diagrams, and free-form scenes. Florence-2-base captions are smaller-model captions (always paired with literal OCR text in `freeText` for the trustworthy part). **Vision-model install is CLI-side only** (interactive setup; the MCP server does not run downloads). An MCP-orchestrated agent should advise the user to run the two CLI commands above the first time they want `clip-caption` mode.
- `smartCrop` + `smartCropProfile`: enable smart-crop preprocessing that removes meeting-platform UI chrome (Teams/Zoom/WebEx controls bar, participant gallery sidebar, black letterbox bars, bottom navigation) before perceptual hashing, OCR, and vision. Profiles: `"auto"` (default), `"teams"`, `"zoom"`, `"webex"`, `"generic"` (all share the same algorithm in this release; the value is recorded on each `FrameCropBox.source` for audit), or `"off"` to disable. Use this when the source is a meeting recording — it dramatically improves slide-grouping stability (the persistent gallery sidebar otherwise dilutes the dHash) and removes meeting-app vocabulary from OCR text. Cropped frames are written to `frames/<frameId>-cropped.jpg`; the `FrameArtifact` records `width`, `height`, `crop` (the box), and `originalPath` (the pre-crop frame).
- `captureMode`: choose the frame-capture backend. `"auto"` (default in 0.14+) tries yt-dlp + ffmpeg first and falls back to Playwright on failure; for known browser-only hosts (`medius.studios.ms`, `medius.microsoft.com`, `medius*.event.microsoft.com`, `build.microsoft.com`, `mediastream.microsoft.com`) it skips the yt-dlp probe entirely and goes straight to browser. `"ytdlp"` forces yt-dlp + ffmpeg — works for ~1000 sites yt-dlp supports plus local files. `"browser"` forces a Playwright-controlled Chromium pinned to Edge to navigate, click play, JS-seek `video.currentTime`, and screenshot the `<video>` element — required for SharePoint/Medius/Teams recordings and any source yt-dlp can't reach. **Side benefit:** when browser capture runs, a network listener watches for any `.vtt`/`.srt` responses the page fetches, persists them under `captions/browser-NNNN.vtt`, indexes them in `captions/discovered.json` (schema: `captions-discovered.schema.json`), and — if no transcript was found by yt-dlp / sidecar / STT — picks the best-language match (using `captionLanguages` and the source's primary language as hints) and uses it to populate `transcript.md`. This is the easiest way to get transcripts for Medius/Ignite/MVP-Summit sessions and any custom player whose page-side JS fetches a caption file.
- `authProfile`: name of a persistent Playwright storage-state profile to load into the browser context before navigating. Only consulted in `browser` and `auto` capture modes. Created on the user's machine via the CLI `zakira-replay auth login <name>` (interactive — MCP cannot perform the initial login). Required for SSO-gated sources. The pipeline emits `AUTH_PROFILE_NOT_FOUND` (severity error) when the named profile does not exist on disk and `AUTH_PROFILE_STALE` (severity info) when the profile's file mtime is older than `auth.staleThresholdMinutes` (default 60). Staleness is informational — capture proceeds; if downstream extraction looks like it landed on a login page rather than the intended content, suggest the user re-runs `auth login <name>` with the same name.

Synthesis is your job, not Zakira.Replay's. Do not look for a `summary` flag; it does not exist. Read the evidence artifacts and produce the synthesis the user asked for.

Provider notes:

- `github-copilot` is the default LLM provider for STT/OCR/vision when `ocrProvider: "copilot"`.
- `openai` supports chat/image and audio transcription.
- `azure-openai` supports chat/image for OCR/vision, but Zakira.Replay STT is not implemented yet.
- `ollama` talks to a local Ollama daemon (`http://localhost:11434` default) through OllamaSharp's native `Microsoft.Extensions.AI.IChatClient`. **Chat / vision only** — no STT. The orchestrator must have a running daemon and pre-pulled models (`ollama pull qwen2.5:7b`, `ollama pull llama3.2-vision:11b`). Configure via `llm.ollama.*` keys or `ZAKIRA_REPLAY_OLLAMA_*` env vars. Combine with `local-whisper` for STT and `ocrProvider: "local"` for OCR to get an air-gapped run.
- `local-whisper` runs Whisper.net (whisper.cpp bindings) entirely on-device for STT. **STT-only** — has no chat/vision/OCR surface; combine with `ocrProvider: "local"` for a fully-offline run. The orchestrator must pre-install a model with `zakira-replay deps install whisper-model` (default `small`, ~466 MB) or set `llm.localWhisper.modelPath` to an existing ggml file. Surface-specific warnings: `STT_LOCAL_MODEL_MISSING`, `STT_LOCAL_INIT_FAILED`, `STT_LOCAL_INFERENCE_FAILED`.
- `ocrProvider: "local"` bypasses LLM providers entirely — useful when GitHub Copilot is rate-limited or behind an agent-loop session that times out, when the user is offline, or when per-frame OCR cost matters.

Diarization (`useDiarization: true`): runs local sherpa-onnx speaker diarization (pyannote-segmentation-3.0 + 3D-Speaker embedding) over the audio after STT, labelling each transcript segment with a `SPEAKER_NN` cluster. Requires a transcript (set `useSpeechToText: true` or rely on captions). Combine `numSpeakers: <n>` when the number of speakers is known; otherwise `diarizationThreshold: <0.0-1.0>` (default 0.5) controls the cluster cutoff. The pipeline rewrites `transcript.md` with `[SPEAKER_NN]` prefixes and re-populates `evidence.speakers[]` plus `evidence-aligned/by-{slide,chapter}.json` speaker rollups automatically — no extra calls required. Pre-install models with `zakira-replay deps install diarization`. Surface-specific warnings: `DIARIZATION_NO_AUDIO`, `DIARIZATION_NO_TRANSCRIPT`, `DIARIZATION_MODELS_MISSING`, `DIARIZATION_INIT_FAILED`, `DIARIZATION_FAILED`.

Conference / Build / Medius arguments (`analyze`, `analyze-start`, `queue-enqueue`):

- `preferInlineMedia: true` — skip the in-browser play+duration probe. The pipeline runs a fast `MetadataOnly` browser probe (~3-5s vs ~25s for a duration timeout), reads the inline media URL the registered interceptors discovered (e.g. `MediusTranscriptInterceptor` for `medius.studios.ms` / `medius.microsoft.com` / `medius*.event.microsoft.com` / `build.microsoft.com/sessions/<CODE>`), ffmpeg-seeks the requested frames, AND downloads the inline captions in the same pass. Fast path for sources whose JS player won't boot headlessly. Falls through to the regular full-capture path when no inline URL is discovered; emits `CAPTURE_BROWSER_FALLBACK` (info). **Auto-enabled in 0.14+** for the known Medius/Build hosts listed above — you don't need to pass this argument for those sources. **Automatic version** (no arg required, always on for browser mode): when the in-browser play+duration probe yields no frames AND an interceptor recovered an inline URL, the pipeline transparently hands that URL to ffmpeg. Closes the "0 frames captured" gap for Build sessions.
- `secondaryCaptionLanguages: "fr,he"` — opt-in additional-language transcripts written alongside the primary `transcript.md`. Surfaced on `manifest.secondaryTranscripts` as `{ language, markdownPath, sourcePath }[]` so the agent can discover them deterministically. Missing languages emit info warnings and skip — never fail.
- `autoplayPolicy: "no-user-gesture-required"` — Chromium autoplay-policy override. Resolves through three layers (per-run arg > `capture.browser.autoplayPolicyByHost` map > `capture.browser.autoplayPolicy` global default). Per-host map supports exact match + `*.<suffix>` wildcards (longest-match-wins). String-based so future Chromium policies extend cleanly; unknown values silently collapse to `default`.
- `allowMediaDownload: true` — **opt-in for any local download of the source video.** Off by default. Gates four previously-silent download paths: the yt-dlp ffmpeg-failure fallback, the STT fallback when no caption/audio source is reachable, the spot-frames last-resort in `frames`, and clip extraction. When declined, each path emits `MEDIA_DOWNLOAD_DECLINED` (error) with the field name in the message. **`stt: true` no longer implicitly authorises a download** — combine `stt: true` + `allowMediaDownload: true` when no captions / audio source are available. Resolution: per-request arg > `capture.allowMediaDownload` config key > `false`. An agent that catches `MEDIA_DOWNLOAD_DECLINED` can decide whether to prompt the user before retrying with `allowMediaDownload: true`.

## Artifact Reading Order

After `analyze-result`, read artifacts from `artifactDirectory` in this order:

1. `manifest.json`: confirms produced artifacts, structured warnings, frame list, and paths. Each `FrameArtifact` may carry optional `width`, `height`, `crop` (`{x, y, width, height, source}`), and `originalPath` when smart-crop fired — the `path` field then points to the cropped variant and the perceptual hash was computed on the crop, not the original. Two newer fields agents should read: `secondaryTranscripts[]` (`{ language, markdownPath, sourcePath }` for each language requested via `secondaryCaptionLanguages`) and `sessionMetadata` (deterministic page-derived facts: `title`, `description`, `sessionCode`, `track`, `level`, `publishedAt`, `speakers[]`, `products[]`, `tags[]`, `sourceUrl`, with per-strategy provenance under `sources[]`).
2. `evidence.json`: structured transcript segments, frames, slides, OCR, vision, per-speaker registry (`speakers[]`), structured warnings.
3. `slides/slides.json` (also embedded in `evidence.json`): slide grouping facts (`firstSeenSeconds`, `lastSeenSeconds`, `frameIds`, `primaryFrameId`). OCR/vision run once per slide; each `OcrFrameResult` and `VisionFrameResult` carries the corresponding `slideId`. `OcrFrameResult.provider` records whether the result came from `"copilot"` (LLM vision-as-OCR) or `"local"` (RapidOCR via ONNX).
4. `transcript.md`: readable timestamped transcript with `[Speaker Name]` prefixes when captions carried speaker tags. The `TranscriptArtifact.kind` field on the underlying record identifies the source: `"yt-dlp-subtitle"`, `"sidecar"`, `"<provider>-audio-transcription"` (STT), or `"browser-network"` (browser-discovered VTT/SRT picked up by the network interceptor and used to retroactively populate the transcript). Secondary-language transcripts live alongside as `transcript.<lang>.md` when `secondaryCaptionLanguages` was requested.
5. `transcript/normalization.json` and `transcript/raw.*`: audit exact quotes when normalization matters. Speaker changes are hard boundaries.
6. `audio/chunks/chunks.json`: present only when long-audio STT was silence-chunked. Useful for branching on chunk failures (warning code `STT_CHUNK_FAILED`).
7. `ocr/{frameId}.json` and `ocr/combined.md`: structured OCR (`freeText`, `lines[]`, `tables[]`); branch on `OCR_PARSE_FALLBACK` warnings to detect prose responses, on `OCR_LOCAL_MODELS_MISSING` to know `deps install ocr` is needed, and on `OCR_LOCAL_INFERENCE_FAILED` for per-frame local-OCR failures (the run continues with remaining frames).
8. `vision/{frameId}.json` and `vision/combined.md`: structured vision (`kind`, `title`, `bullets[]`, `codeBlocks[]`, `charts[]`, `uiElements[]`, `freeText`); branch on `VISION_PARSE_FALLBACK` warnings.
9. `frames/`: inspect image artifacts when visual details matter. When smart-crop ran, `frames/scene-NNNN.jpg` is the cropped variant and `frames/scene-NNNN-cropped.jpg` is its alias on disk; the original pre-crop frame is preserved at the path recorded in `originalPath`.
10. `captions/discovered.json` (schema: `captions-discovered.schema.json`): present only when browser capture ran and observed at least one `.vtt`/`.srt` response on the wire. Each entry carries the original network URL, the persisted `relativePath` (e.g. `captions/browser-0001.vtt`), an inferred BCP-47 `language` and the heuristic that produced it (`languageSource`: `url-Caption_<lang>` for Medius, `url-filename`, `url-path-segment`, `url-query-lang`/`hl`/`language`/`l`/`tlang`), byte count, content type, and SHA-256 hash. The top-level `originalLanguage` field is the source's primary language as reported by yt-dlp metadata, which serves as the "main"/"original" language hint for orchestrators picking among multiple captured tracks.
11. `metadata.json`: title, URL, duration, uploader metadata, `availableSubtitleLanguages`.
12. `evidence.md`: concise human-readable index of artifact paths.

Speakers in `evidence.speakers[]` carry `id` (slug, stable), optional `displayName`, `segmentCount`, `totalSeconds`, `firstSeenSeconds`, `lastSeenSeconds`. Each `transcript[*]` segment has `id` (`segment-NNNN`) and may have `speakerId` and `speakerDisplayName`. STT-derived transcripts do not carry speakers in this release.

Warnings in `manifest.json` and `evidence.json` are structured records: `{ code, message, source, severity }`. Branch on `code` (for example `TRANSCRIPT_NOT_FOUND`, `STT_NO_LLM_PROVIDER`, `STT_CHUNK_FAILED`, `OCR_PARSE_FALLBACK`, `OCR_LOCAL_MODELS_MISSING`, `OCR_LOCAL_INIT_FAILED`, `OCR_LOCAL_INFERENCE_FAILED`, `OCR_UNKNOWN_PROVIDER`, `VISION_PARSE_FALLBACK`, `PERCEPTUAL_HASH_FAILED`, `FRAMES_REMOTE_FALLBACK`, `FRAMES_LIKELY_UNDERSAMPLED`, `FRAMES_SCENE_CAP_REACHED`, `CROP_BAIL_OUT`, `CROP_PROFILE_UNKNOWN`, `CROP_IMAGE_DECODE_FAILED`, `CROP_OUTPUT_FAILED`, `CAPTURE_BROWSER_FALLBACK`, `CAPTURE_BROWSER_UNAVAILABLE`, `CAPTURE_PLAY_BUTTON_NOT_FOUND`, `CAPTURE_DURATION_UNRESOLVED`, `CAPTURE_SEEK_FAILED`, `CAPTURE_SCREENSHOT_FAILED`, `CAPTURE_UNKNOWN_MODE`, `CAPTIONS_BROWSER_NETWORK_NONE`, `CAPTIONS_BROWSER_NETWORK_DOWNLOAD_FAILED`, `CAPTIONS_BROWSER_NETWORK_PARSE_FAILED`, `CAPTURE_BROWSER_CAPTIONS_ACTIVATED`, `CAPTURE_BROWSER_CAPTIONS_HARVESTED_FROM_DOM`, `CAPTURE_BROWSER_PROFILE_NOT_INITIALIZED`, `CAPTURE_BROWSER_PROFILE_DIR_MISSING`, `CAPTURE_BROWSER_PROFILE_LOCKED`, `CAPTURE_BROWSER_PROFILE_LAUNCH_FAILED`, `CAPTURE_BROWSER_AUTH_REQUIRED`, `CAPTURE_BROWSER_AUTH_MFA_DETECTED`, `CAPTURE_PROFILE_CONFLICT`, `CAPTURE_BROWSER_MEDIA_DOWNLOADED`, `CAPTURE_BROWSER_MEDIA_NO_CANDIDATE`, `CAPTURE_BROWSER_MEDIA_DOWNLOAD_FAILED`, `CAPTURE_STREAM_TRANSCRIPT_DISCOVERED`, `CAPTURE_STREAM_TRANSCRIPT_DOWNLOADED`, `CAPTURE_STREAM_METADATA_PARSE_FAILED`, `CAPTURE_STREAM_TRANSCRIPT_PARSE_FAILED`, `CAPTURE_MEDIUS_TRANSCRIPT_DISCOVERED`, `CAPTURE_MEDIUS_TRANSCRIPT_DOWNLOADED`, `CAPTURE_MEDIUS_TRANSCRIPT_FAILED`, `MEDIA_DOWNLOAD_DECLINED`, `AUTH_PROFILE_NOT_FOUND`, `AUTH_PROFILE_STALE`, `AUTH_PROFILE_LOAD_FAILED`) rather than fuzzy-matching the message.

## MCP Resources (`replay://`)

In addition to tools (verbs), Zakira.Replay exposes its on-disk artifacts as MCP **resources** at stable URIs under the `replay://` scheme. Clients that support resources (Claude Desktop, Cursor, VS Code Copilot, MCP Inspector) can list them via `resources/templates/list` and read them via `resources/read` without firing a tool call. Prefer resources when the user only needs to look at an existing artifact — no compute cost, no job lifecycle, no polling.

Available templates:

- `replay://runs` — JSON index of every run under the configured `runs/` directory (id, directory path, manifest-exists flag, last-write timestamp; most-recent-first).
- `replay://runs/{id}/manifest` — `manifest.json` for a run.
- `replay://runs/{id}/evidence` — `evidence.json` for a run (the canonical fact stream).
- `replay://runs/{id}/transcript` — `transcript.md` (speaker-attributed markdown).
- `replay://runs/{id}/chapters` — `chapters/chapters.json` (when chapters were built).
- `replay://runs/{id}/aligned/by-chapter` — `evidence-aligned/by-chapter.json` (cross-modal rollup by chapter).
- `replay://runs/{id}/aligned/by-slide` — `evidence-aligned/by-slide.json` (cross-modal rollup by slide).
- `replay://runs/{id}/frames/{frameId}/ocr` — per-frame OCR JSON.
- `replay://runs/{id}/frames/{frameId}/vision` — per-frame structured vision JSON.
- `replay://jobs/{jobId}/logs` — the live in-memory log buffer of an MCP analyze job; subscribe to follow progress without polling `analyze-status`.

When `analyze-result` returns an `artifactDirectory`, the `runId` is the last path segment — use it as `{id}` in the resource URIs above. Reading a resource that does not exist on disk returns an MCP error with the missing path in the message; treat it the same way as a missing artifact in the artifact-reading workflow.

## Search Workflow

Build search when the transcript is long, repeated Q&A is expected, or the user asks about specific topics:

```json
{
  "runDirectory": "<artifactDirectory>",
  "backend": "sqlite-onnx"
}
```

Then query:

```json
{
  "target": "<artifactDirectory>",
  "query": "important topic or action item",
  "backend": "auto",
  "top": 10
}
```

Backend choice:

- `json`: portable sparse TF-IDF fallback.
- `sqlite`: SQLite FTS5 keyword search.
- `sqlite-onnx`: semantic search via local ONNX embedding model, best for natural-language retrieval.

Search-embedding model choice (0.10.0+): three models ship in the known-model registry.
Pass `onnxModel` to `index-build` / `index-query` to select one; the default is
`bge-small-en-v1.5`. Each model auto-downloads on first `index-build` when
`search.onnx.autoDownload=true`.

| Model id | Language | Footprint | Notes |
|---|---|---|---|
| `bge-small-en-v1.5` (default) | English | ~33 MB ONNX | Top of the 384-dim retrieval tier. |
| `snowflake-arctic-embed-s` | English | ~33 MB ONNX | Same family as BGE; slight quality difference; pick when BGE underperforms. |
| `multilingual-e5-small` | 100+ languages | ~118 MB ONNX | Use for non-English transcripts. |

```json
{
  "runDirectory": "<artifactDirectory>",
  "backend": "sqlite-onnx",
  "onnxModel": "multilingual-e5-small"
}
```

For custom local models, set `onnxModelPath` + `onnxTokenizerPath` and pass
`onnxModelKind` as `bert`, `bge`, or `e5` to apply the right prefix and pooling.

**Important**: indexes built with one model cannot be queried with another. If `onnxModel`
differs from what the index was built with, the tool returns
`SEARCH_INDEX_EMBEDDING_MISMATCH` and the recommended fix is to call `index-build` again
with `force=true` (per-run rebuild) or pass `onnxModel: "<original-id>"` to pin the
indexed model.

The `index-build` tool result now includes `embeddingModel`, `embeddingModelKind`, and
`embeddingDimensions` so orchestrators can persist the index identity alongside the
`indexPath`.

Treat search results as evidence pointers. Open the referenced artifacts before making final claims.

## Chapters Workflow

Build chapters after transcript evidence exists:

```json
{
  "runDirectory": "<artifactDirectory>",
  "minDuration": 60,
  "maxDuration": 600
}
```

Read `chapters/chapters.md` for the topic outline and `chapters/chapters.json` for structured timestamps. Chapters are pure time spans plus per-chapter evidence references; titles and prose summaries are not produced by Zakira.Replay. Generate any labels you need from the chapter's evidence yourself.

## Evidence Alignment Workflow

After chapters and slides exist, call `align` to materialise cross-modal views:

```json
{
  "runDirectory": "<artifactDirectory>"
}
```

The tool writes two files under `evidence-aligned/`:

- `by-chapter.json`: per-chapter join of `slideIds`, `transcriptSegmentIds`, `ocrFrameIds`, `visionFrameIds`, and per-speaker statistics within each chapter window.
- `by-slide.json`: per-slide join of `frameIds`, `ocr`, `vision`, `transcriptSegmentIds` spoken while the slide was visible, per-speaker statistics, and the chapters the slide overlaps.

Slide visibility windows are extended to `[slide[i].firstSeenSeconds, slide[i+1].firstSeenSeconds)`. Use `by-slide.json` to answer "which transcript segments were spoken while slide X was on screen" and `by-chapter.json` to answer "which slides and speakers appeared in chapter N". Both are pure rearrangements; no inference is added beyond the next-slide-boundary visibility heuristic.

## Clip Workflow

Extract a clip only when timestamps are known or justified by evidence:

```json
{
  "source": "https://example.com/video",
  "start": "01:20",
  "end": "02:05",
  "outputName": "key-demo"
}
```

Report the clip path and timestamp range from the returned clip artifact.

## Ad-hoc Frame Capture Workflow

Use `frames` for the "I already analyzed this and just want a few specific stills" case. The tool skips slide grouping, hashing, OCR, vision, and chapter synthesis, so it is cheap to call repeatedly between turns. Output lands in a new `runs/<id>/frames/` folder with a minimal `frame-capture.json` manifest (schema: `frame-capture.schema.json`, `kind: "frame-capture"`).

Two mutually-exclusive modes:

**Mode A — exact timestamps.** Pass `at` as either a JSON array of strings/numbers or a single comma-separated string. Up to 64 timestamps per request; excess are dropped with `FRAME_CAPTURE_TOO_MANY_TIMESTAMPS`.

```json
{
  "source": "./cooking.mp4",
  "at": ["02:34", "03:10", "04:55"],
  "maxLongEdgePixels": 1024,
  "jpegQuality": 85
}
```

**Mode B — window with frame budget.** Required: `from`, `to`. Optional: `count` (defaults to 1 for `interval`), `strategy` (`"interval"` default, or `"scene"`). For `interval`, the captured timestamps are evenly spaced inclusive of both endpoints. For `scene`, ffmpeg's scene-cut filter is scoped to the window; reported timestamps stay in absolute source timeline.

```json
{
  "source": "https://example.com/video",
  "from": "02:00",
  "to": "03:00",
  "count": 5,
  "strategy": "interval"
}
```

Shared optional fields:

- `runId`: pin the artifact folder name (otherwise auto-generated from source).
- `maxLongEdgePixels`: resize so the longest edge is at most N pixels (aspect ratio preserved). Use for thumbnail-sized stills.
- `jpegQuality`: 1-100 (mapped to ffmpeg qscale 31-2). Default high quality.
- `computePerceptualHash`: when true, also computes a 64-bit dHash per frame so you can dedupe near-identical stills downstream.
- `sceneSafetyCap`: upper bound on scene cuts inside the window (defaults to `max(count, 200)`). Emits `FRAME_CAPTURE_SCENE_CAP_REACHED` when reached.
- `cookies` / `cookiesFromBrowser` / `browserAuth`: yt-dlp auth for remote sources, identical semantics to `analyze`.

The tool response includes `runId`, `artifactDirectory`, `manifestPath`, `frameCount`, a `frames` array (absolute and relative paths plus `timestampSeconds` / `timestampLabel`), and `warnings`. When you want to embed the frames into a downstream artifact (recipe Markdown, work-item file, alignment view), prefer the absolute `path` returned for each frame.

Frame-capture-specific warning codes (all under `frames[*].warnings`/`manifest.warnings`):

- `FRAME_CAPTURE_TIMESTAMP_OUT_OF_RANGE` - a requested timestamp was negative or past the source duration; the entry was dropped.
- `FRAME_CAPTURE_RANGE_OUT_OF_BOUNDS` - the requested `to` exceeded source duration and was clamped.
- `FRAME_CAPTURE_TOO_MANY_TIMESTAMPS` - more than 64 timestamps were supplied; only the first 64 were used.
- `FRAME_CAPTURE_NO_FRAMES` - ffmpeg returned zero frames (e.g. scene detection found nothing inside the window).
- `FRAME_CAPTURE_SCENE_CAP_REACHED` - the safety cap was hit during scene detection.
- `FRAME_CAPTURE_MEDIA_URL_UNRESOLVED` - yt-dlp could not resolve a direct media URL; fell back to downloading.

Do not use `frames` as a substitute for `analyze`/`analyze-start` when you actually need transcript, slides, OCR, vision, chapters, or evidence alignment. It is purpose-built for spot frames.

## Queue Workflow

Use the MCP queue tools for many videos or resumable local processing:

1. `queue-enqueue` with `source`, `queueId`, optional `jobId`, and analysis options.
2. `queue-run` with `queueId`, `concurrency`, and `retries`.
3. `queue-status` to report pending/running/succeeded/failed jobs.
4. Read each completed run's artifact directory before synthesizing results.

## Topic Summary And Work Items Pattern

For requests like "watch this and summarize topics and work items":

1. Use `analyze-start` with `stt: true`, `ocr: true`, `vision: true`, `cache: true`, and `maxAiFrames: 30` unless the user requests cheaper settings. Bump `frames` from the default 15 to `30` for slide-heavy content, and add `frameStrategy: "scene"` for slide-cut sampling (only safe on direct-URL sources like YouTube; avoid scene on HLS-only sources like Microsoft Build keynotes).
2. Poll until success and get `artifactDirectory`.
3. Call `chapters-build`.
4. Call `index-build` with `backend: "sqlite-onnx"` when available; use `sqlite` or `json` if ONNX is unavailable.
5. Query for `action item`, `next steps`, `todo`, `follow up`, `decision`, `owner`, `deadline`, and project terms.
6. Read `chapters/chapters.md`, `evidence.json`, `transcript.md`, and `ocr/combined.md`.
7. Synthesize the topic summary and work items yourself from these facts. Write or return the requested Markdown output. If writing a file, place it next to artifacts, usually `<artifactDirectory>/work-items.md`.

Work item format:

```markdown
- [ ] OWNER -- TASK -- DUE (or "unspecified") -- [HH:MM:SS] -- evidence: "short verbatim quote"
```

Do not invent owners or due dates. Use `unspecified` when unclear. Deduplicate repeated commitments and keep the earliest strong timestamp.

## Failure Handling

If a job fails:

- Read returned `error` and `logs`.
- For dependency failures, call `doctor` and report missing `yt-dlp`, `ffmpeg`, `ffprobe`, ONNX search model files, or RapidOCR model files.
- If CLI access is available and the user permits local downloads, suggest `zakira-replay deps install media`, `zakira-replay deps install onnx`, or `zakira-replay deps install ocr` (the last for RapidOCR PP-OCRv5 latin models used by `ocrProvider: "local"`).
- For provider auth failures, inspect config keys for environment variable names; never ask users to store secret values in JSON config.
- For LLM-side OCR/vision failures (timeouts, rate limits, agent-loop hangs on `github-copilot`), suggest re-running with `ocrProvider: "local"` to bypass LLM providers entirely. The local provider needs no LLM session, no network at run-time, and no per-frame agent loop. Tradeoff: lower OCR fidelity on complex layouts and no `tables[]` reconstruction.
- For access failures, retry only with legitimate `cookies`, `cookiesFromBrowser`, or `browserAuth`. For sites yt-dlp cannot reach at all (custom enterprise portals, Medius/Teams playback URLs), retry with `captureMode: "browser"`.
- For SSO-gated sources, the **recommended setup** is `zakira-replay auth init-edge-profile [--url <site>]` on the user's machine (CLI-side, interactive, one-time-per-machine). This writes DPAPI-encrypted cookies into Edge's native storage; persistent-context mode then auto-activates on every subsequent `captureMode: "browser"` (or `"auto"`) MCP call against that origin, **no `authProfile` argument required**. If the run emits `CAPTURE_BROWSER_AUTH_REQUIRED` (error) or `CAPTURE_BROWSER_AUTH_MFA_DETECTED` (error), the Edge profile is missing or its session expired \u2014 ask the user to re-run `auth init-edge-profile`. `CAPTURE_BROWSER_PROFILE_LOCKED` (error) means a running Edge window is using the same user-data-dir; close Edge and retry. `CAPTURE_BROWSER_PROFILE_NOT_INITIALIZED` (info) indicates the profile path is configured but empty \u2014 first-time setup is needed. The legacy `auth login <name>` + `authProfile` path also works; `AUTH_PROFILE_STALE` recommends refreshing it, but for Microsoft sources prefer migrating to `auth init-edge-profile`.
- **SharePoint Stream / Microsoft Stream transcripts** are downloaded automatically (with full speaker attribution as `<v Speaker>` voice spans) when the dedicated Edge profile is initialised and `captureMode: "browser"` is used. Look for `CAPTURE_STREAM_TRANSCRIPT_DISCOVERED` and `CAPTURE_STREAM_TRANSCRIPT_DOWNLOADED` (both info) in the manifest. If the page exposes transcripts metadata but Zakira can't parse the body, `CAPTURE_STREAM_METADATA_PARSE_FAILED` (warning) records the URL; if the download succeeded but the format wasn't recognised, `CAPTURE_STREAM_TRANSCRIPT_PARSE_FAILED` (warning) keeps the raw body in `captions/` for manual inspection.
- **Microsoft Medius / Build / Ignite transcripts + frames** — `medius.studios.ms`, `medius.microsoft.com`, `medius*.event.microsoft.com`, and `build.microsoft.com/.../sessions/<CODE>` URLs go through the `MediusTranscriptInterceptor`. The interceptor parses the embed page's inline `captionsConfiguration` (SAS-signed `Caption_<lang>.vtt`) and `coreConfiguration` (HLS master playlist) — neither needs the Shaka MSE player to boot, so transcripts arrive even when `CAPTURE_DURATION_UNRESOLVED` fires. Look for `CAPTURE_MEDIUS_TRANSCRIPT_DISCOVERED` (info; lists language count), `CAPTURE_MEDIUS_TRANSCRIPT_DOWNLOADED` (info; per-language VTT under `captions/medius-NNNN-<lang>.vtt`), `CAPTURE_MEDIUS_TRANSCRIPT_FAILED` (warning) per failed caption download. In 0.14+ these hosts auto-route to browser capture with inline-media sidestep enabled, so no `captureMode` / `preferInlineMedia` argument is required. `CAPTURE_DURATION_UNRESOLVED` is now `info` severity (was `error` through 0.13) and is suppressed in the default warning view.
- **`MEDIA_DOWNLOAD_DECLINED` (error)** — the pipeline reached a local-download path but `allowMediaDownload: true` was not set (and `capture.allowMediaDownload` is `false` in config). The message names the gate. An agent should decide whether to prompt the user before retrying with `allowMediaDownload: true`. Affected paths: yt-dlp ffmpeg-failure fallback (`analyze-start`/`analyze`), STT fallback when no caption / audio source is reachable, spot-frames last-resort (`frames`), clip extraction (`clip`).
- If transcript is missing, the pipeline tries (in order) yt-dlp captions / sidecar `.vtt`/`.srt` / STT (when `stt: true`) / browser-discovered captions (when `captureMode` was `"browser"` or `"auto"` and the page fetched a `.vtt`/`.srt`). When all four return nothing, you'll see `TRANSCRIPT_NOT_FOUND` (or `TRANSCRIPT_NOT_FOUND_NO_STT` if `stt` was not set). Suggest enabling `stt: true` if the audio is good, or `captureMode: "browser"` if the page-side player exposes captions yt-dlp doesn't see.
- If visual evidence is insufficient, rerun with more `frames`, `frameStrategy: "scene"`, `ocr: true`, or `vision: true`.
- If a previous MCP job was interrupted by server restart, create a new job with the same arguments and `cache: true`.
- For meeting-recording sources (Teams/Zoom/WebEx exports) where slide grouping looks unstable or OCR is polluted with meeting-app vocabulary ("Take control", "Raise", "Mute all", etc.), rerun with `smartCrop: true`. The pipeline crops UI chrome before perceptual hashing so slide grouping stabilises and OCR sees only the slide area.

## Evidence Discipline

When answering:

- Lead with the answer, then cite timestamped evidence.
- Separate confirmed evidence from inference.
- Mention warnings (by `code`) that affect confidence.
- Keep transcript excerpts short unless the user asks for extensive quotes.
- Do not fabricate speakers, slide contents, UI text, numbers, decisions, or work items.
- If evidence is insufficient, state what is missing and recommend concrete MCP arguments for a rerun.
