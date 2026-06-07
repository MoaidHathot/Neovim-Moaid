# Zakira.Replay Prompt Examples

## Summarize A Video

User prompt:

```text
Summarize this video and include timestamps for the main claims: https://example.com/video
```

Agent behavior:

- Call `analyze-start` with `cache: true`. The 0.14 defaults (`frames: 15`, `frameStrategy: "interval"`, `captureMode: "auto"`) cover most general use; override only when the question demands it.
- Add `ocr: true` and `vision: true` if slides, UI, code, or diagrams matter.
- Poll until succeeded.
- Read `manifest.json`, `evidence.json`, and `transcript.md`.
- If exact transcript fidelity matters, inspect `transcript/normalization.json` and `transcript/raw.md` before quoting.
- Synthesize the timestamped summary yourself from the evidence; Zakira.Replay does not produce summaries. Mention warnings by `code`.

## Answer A Specific Question

User prompt:

```text
In this lecture, what does the speaker say about model evaluation? https://example.com/lecture
```

Agent behavior:

- Prioritize transcript extraction.
- Use `frames: 0` unless visual evidence is relevant.
- Quote or paraphrase only from transcript/evidence artifacts.
- Build/query a search index first for long transcripts, preferably `sqlite-onnx` when the local ONNX model is configured.
- If transcript is missing, rerun with `stt: true`.

MCP search flow:

```json
{"name":"index-build","arguments":{"runDirectory":"<artifact-directory>","backend":"sqlite-onnx"}}
{"name":"index-query","arguments":{"target":"<artifact-directory>","query":"model evaluation","backend":"sqlite-onnx","top":5}}
```

## Analyze Visual Content

User prompt:

```text
Review the dashboard shown in this demo and list the visible metrics: https://example.com/demo
```

Agent behavior:

- Use `frames: 12`, `ocr: true`, `vision: true`, and `cache: true`. Add `frameStrategy: "scene"` if the source is a direct-URL stream (YouTube, local file) — **avoid `"scene"` on HLS sources like Microsoft Build / Medius** since scene-cut detection pulls the entire stream.
- Inspect `ocr/combined.md`, `vision/combined.md`, and frame images.
- Separate visible text from inferred meaning.

## Offline OCR (No LLM Provider)

User prompt:

```text
Extract the slide text from this conference talk. We're offline / our LLM quota is gone.
```

Agent behavior:

- Use `ocrProvider: "local"` to run RapidOCR (PP-OCRv5 latin) entirely on-device via ONNX. No LLM, no network at run-time after the models are installed.
- The user must run `zakira-replay deps install ocr` once before the first local-OCR run; without the models the run emits `OCR_LOCAL_MODELS_MISSING`.
- Bump `frames: 30` for slide-heavy content (default is 15). Add `frameStrategy: "scene"` only when the source isn't an HLS stream.
- Tradeoff to mention: lower fidelity than a frontier vision model on complex layouts; no `tables[]` reconstruction.

```json
{
  "name": "analyze-start",
  "arguments": {
    "source": "https://example.com/conference-talk",
    "visionInstruction": "Extract slide text and code blocks.",
    "frames": 30,
    "ocr": true,
    "ocrProvider": "local",
    "cache": true
  }
}
```

## Teams / Zoom / WebEx Meeting Recording

User prompt:

```text
Analyze this Teams meeting recording and pull out the slide content.
```

Agent behavior:

- Use `smartCrop: true` (with default `smartCropProfile: "auto"`) so the meeting-app UI chrome is removed before perceptual hashing, OCR, and vision. This dramatically improves slide grouping (the gallery sidebar no longer dilutes the dHash) and removes meeting-app vocabulary from OCR text.
- Combine with `frameStrategy: "scene"` so only slide-change frames are kept.
- Local OCR works well for slide text; consider `ocrProvider: "local"`.

```json
{
  "name": "analyze-start",
  "arguments": {
    "source": "C:\\meetings\\team-sync.mp4",
    "visionInstruction": "Extract the slide content.",
    "frames": 12,
    "frameStrategy": "scene",
    "smartCrop": true,
    "ocr": true,
    "ocrProvider": "local",
    "cache": true
  }
}
```

## Sites yt-dlp Cannot Reach

User prompt:

```text
Analyze this video on our internal training portal: https://corp.example.com/training/abc
```

Agent behavior:

- yt-dlp does not know about custom enterprise portals. Set `captureMode: "browser"` to drive Playwright instead.
- For SSO-gated sources, the user must first run `zakira-replay auth login <profile-name>` on their machine (interactive, browser opens visibly). Then pass `authProfile: "<profile-name>"`.
- The browser-network interceptor watches for `.vtt`/`.srt` responses during playback; if the page exposes captions, they're picked up and used to populate `transcript.md` automatically (look for `captions/discovered.json`).
- Smart-crop and local OCR still work in browser-capture mode.

```json
{
  "name": "analyze-start",
  "arguments": {
    "source": "https://corp.example.com/training/abc",
    "visionInstruction": "Extract slide content from this internal training video.",
    "frames": 7,
    "captureMode": "browser",
    "authProfile": "corp-sso",
    "ocr": true,
    "ocrProvider": "local",
    "smartCrop": true,
    "cache": true
  }
}
```

If the source might or might not be yt-dlp-reachable, use `captureMode: "auto"` — the pipeline tries yt-dlp first and falls back to browser capture, emitting `CAPTURE_BROWSER_FALLBACK` so you know which path produced the artifacts.

## Microsoft Ignite / MVP Summit / Build Recordings

These are hosted on Microsoft Medius. The page-side player fetches `Caption_en-US.vtt` (and other-language variants) as plain HTTP responses during initialisation, so the browser-network interceptor catches them automatically.

User prompt:

```text
Summarize this Ignite session: https://medius.studios.ms/Embed/video-12345
```

Agent behavior:

- The user must first sign in to Medius interactively via `zakira-replay auth login ignite-2026 --url https://medius.studios.ms/` (or use the dedicated Edge profile via `auth init-edge-profile`).
- Then pass `authProfile: "ignite-2026"`. In 0.14+ `captureMode` defaults to `auto` and Medius hosts auto-route to browser + inline-media sidestep, so neither `captureMode` nor `preferInlineMedia` is required. Captions arrive automatically through `MediusTranscriptInterceptor`.

```json
{
  "name": "analyze-start",
  "arguments": {
    "source": "https://medius.studios.ms/Embed/video-12345",
    "visionInstruction": "Extract slide titles, bullets, code blocks, and demo content.",
    "frames": 30,
    "authProfile": "ignite-2026",
    "ocr": true,
    "vision": true,
    "smartCrop": false,
    "cache": true
  }
}
```

## SharePoint Stream / Microsoft Stream Meeting Recordings

These are hosted on SharePoint-backed Stream (`*-my.sharepoint.com/.../stream.aspx?id=...`). The Stream player does NOT use the HTML5 `textTracks` API or serve captions as plain `.vtt`/`.srt` URLs, so the generic interceptors miss them. Zakira's **Stream-specific layer** is the only reliable path: it observes the `_api/v2.X/.../media/transcripts` metadata response (or, if the player happens not to query it during automation, proactively fetches it using `(drive-id, item-id)` harvested from any other SharePoint REST call), then follows each transcript's `temporaryDownloadUrl` with the `?isformatjson=true&transcriptkey=<id>` URL variant the player itself uses to coax out the Microsoft Teams transcript JSON. The JSON carries `speakerDisplayName` per entry, which lands in `transcript.md` as `<v Speaker>` voice spans and proper `[Speaker Name]` prefixes.

User prompt:

```text
Analyze this Teams meeting recording on SharePoint Stream and tell me who said what:
https://microsofteur-my.sharepoint.com/personal/.../stream.aspx?id=...
```

Agent behavior:

- The user must first run `zakira-replay auth init-edge-profile --url https://microsofteur-my.sharepoint.com/` (or whichever Stream origin they use) on their machine once per machine. This is **preferred over `auth login`** for Microsoft sources: cookies stay DPAPI-encrypted in Edge's native storage, refresh in place during use, and the persistent-context Edge profile auto-activates for every subsequent run \u2014 no `authProfile` argument required from MCP.
- Then pass `captureMode: "browser"` and any combination of `ocr`/`vision`/`stt` flags as the question warrants. The Stream transcript layer runs automatically and produces a speaker-attributed transcript when one exists.

```json
{
  "name": "analyze-start",
  "arguments": {
    "source": "https://microsofteur-my.sharepoint.com/personal/.../stream.aspx?id=...",
    "visionInstruction": "Extract slide content and visual evidence from this Teams meeting.",
    "frames": 30,
    "frameStrategy": "scene",
    "captureMode": "browser",
    "smartCrop": true,
    "smartCropProfile": "teams",
    "ocr": true,
    "ocrProvider": "local",
    "vision": true,
    "visionProvider": "local",
    "cache": true
  }
}
```

After the job succeeds, read `manifest.json` for `CAPTURE_STREAM_TRANSCRIPT_DOWNLOADED` (info) confirming the speaker-attributed transcript was fetched. The raw Teams JSON is preserved alongside the converted VTT at `captions/stream-NNNN-<lang>.json` for audit (carries `speakerId`, `confidence`, `roomId`, ISO 8601 `startOffset`/`endOffset` per entry).

If the Stream player doesn't expose a transcript at all (recording made without auto-captioning), the run will skip the Stream layer (no `CAPTURE_STREAM_TRANSCRIPT_DISCOVERED`) and `CAPTURE_BROWSER_MEDIA_NO_CANDIDATE` will record that the DASH-encrypted audio cannot be re-downloaded for STT. Recommend the user enable auto-captioning for future meetings.

## Authenticated Video (yt-dlp Cookies)

User prompt:

```text
Analyze this course video. I am logged into it in Edge: https://example.com/course/video
```

Agent behavior:

- Try `browserAuth: "edge"` first (yt-dlp pulls cookies from the local Edge profile).
- If yt-dlp still cannot reach the source, escalate to `captureMode: "browser"` with an `authProfile` (the user creates one with `zakira-replay auth login`).

## Batch Orchestration

User prompt:

```text
Analyze all videos in this manifest and make study notes from the evidence.
```

Agent behavior:

- Use `zakira-replay batch run <manifest.json>` if working through CLI.
- Use MCP jobs one-by-one if the orchestrator needs progress control.
- After artifacts are ready, synthesize study notes yourself from each `evidence.json` and `transcript.md`.

## Build Chapters

User prompt:

```text
Create chapter markers for this video and include supporting evidence.
```

Agent behavior:

- Analyze the video with transcript extraction.
- Call `chapters-build` with the completed run directory.
- Read `chapters/chapters.json` and cite chapter evidence timestamps. Generate any per-chapter labels yourself; chapters carry pure time spans plus evidence references, no titles or prose summaries.

## When LLM-Backed OCR Hangs

If an `ocr: true` run with the default `ocrProvider: "copilot"` repeatedly times out (the GitHub Copilot stdio session can stall as an SWE agent loop on image attachments), recommend the user retry with `ocrProvider: "local"`. The RapidOCR path has no LLM session, no agent loop, and no per-frame timeout risk.

## Fully Offline Analysis (No LLM Anywhere)

User prompt:

```text
Analyze this internal training video without contacting any cloud service or LLM.
```

Agent behavior:

- Combine four "local" surfaces: STT via `local-whisper`, OCR via `local`, vision via the new `local` provider, and (optionally) speaker diarization via local sherpa-onnx.
- `--ocr-provider local` is already the default. Add `--vision-provider local` to keep vision off the LLM as well.
- The local vision provider auto-enables OCR when omitted; emits `VISION_LOCAL_OCR_REQUIRED` (info) so the orchestrator can see the implicit decision. Pass `--ocr` explicitly to silence.
- `--local-vision-mode heuristic` (zero models) works out of the box. `--local-vision-mode clip` adds CLIP zero-shot kind classification — install with `zakira-replay deps install vision --mode clip` followed by `zakira-replay vision generate-clip-embeddings` (~150 MB one-time). `--local-vision-mode clip-caption` (default for the local provider) additionally captions frames with Florence-2-base-ft — install with `zakira-replay deps install vision --mode clip-caption` (~410 MB total). The deprecated `clip-blip` is still accepted as an alias for `clip-caption`. Missing files cause graceful degradation (`clip-caption` → `clip` → `heuristic`) with `VISION_LOCAL_MODE_DEGRADED` warnings.

```json
{
  "name": "analyze-start",
  "arguments": {
    "source": "C:/corp/training/onboarding.mp4",
    "visionInstruction": "Extract slide content from this internal training video.",
    "frames": 12,
    "frameStrategy": "scene",
    "stt": true,
    "llmProvider": "local-whisper",
    "ocr": true,
    "ocrProvider": "local",
    "vision": true,
    "visionProvider": "local",
    "localVisionMode": "heuristic",
    "cache": true
  }
}
```

Tradeoffs to mention up front:

- `charts[]` is always empty in local vision mode (no chart-aware model ships).
- Florence-2-base captions are smaller-model captions; the `freeText` always includes the literal OCR text after the caption so the trustworthy part is preserved for citation.
- Diagrams without labels and generic photographic frames classify as `other` with empty structured fields.
- For tasks where the LLM path's free-form scene description matters (e.g. "describe what's happening visually"), suggest the user retry with `visionProvider: "copilot"` or `--llm-provider ollama` with a vision-capable local model.

## Ad-hoc Frame Capture After A Full Analyze

User prompt:

```text
Turn this cooking video into a recipe card with photos for each major step:
https://example.com/recipe-video
```

Agent behavior:

- Step 1: full `analyze` (or `analyze-start`) with `frames: 0` to get the transcript and chapter material cheaply, then `chapters-build` so each step in the recipe has a timestamp.
- Step 2: read `transcript.md` + `chapters/chapters.json` and identify a meaningful timestamp for each step (e.g. "deglaze the pan" at 04:12, "add the cream" at 06:35).
- Step 3: call `frames` with the chosen timestamps. The full pipeline does not need to re-run; this captures stills only.

```json
{
  "name": "frames",
  "arguments": {
    "source": "https://example.com/recipe-video",
    "at": ["02:45", "04:12", "06:35", "08:50", "11:20"],
    "maxLongEdgePixels": 1024,
    "jpegQuality": 85
  }
}
```

- Step 4: synthesize the recipe Markdown yourself, embedding the absolute frame paths returned by `frames` (`path` field) as image references next to each step's transcript-derived prose.

When you only know the rough window and want a few frames inside it — for example, "the speaker shows the final plate somewhere around 10:00-12:00" — use the range mode instead:

```json
{
  "name": "frames",
  "arguments": {
    "source": "https://example.com/recipe-video",
    "from": "10:00",
    "to": "12:00",
    "count": 3,
    "strategy": "scene"
  }
}
```

The scene strategy returns ffmpeg's scene-cut frames inside the window; the interval strategy returns evenly spaced timestamps. Neither runs slide grouping / OCR / vision, so the call is fast and repeatable.
