---
name: zakira-replay-cli
description: Use the Zakira.Replay command-line tool to extract durable, timestamped, fact-shaped evidence from video URLs or local media. Zakira.Replay produces facts only; you synthesize summaries, work items, and other insights from those artifacts.
---

# Zakira.Replay CLI Skill

Use this skill when you can run shell commands and the user asks you to analyze, summarize, inspect, search, quote, clip, or extract work items from a video.

Zakira.Replay is an evidence producer. It writes transcripts, frames, OCR, vision notes, chapters, search indexes, manifests, and queue artifacts to disk. **It does not synthesize summaries, work items, decisions, or any other inferences.** Your job is to run the CLI, read the artifacts, and produce the user's requested answer from that evidence.

## Core Rule

Never claim you watched a video directly. Base every answer on `manifest.json`, `evidence.json`, `transcript.md`, frame images, `ocr/combined.md`, `vision/combined.md`, or `chapters/chapters.md`.

## When To Use

Use this skill for:

- YouTube, Vimeo, webinar, course, lecture, demo, meeting, or local media analysis.
- Requests that require transcript evidence, timestamps, visual inspection, OCR, clips, chapters, search, summaries (synthesized from evidence), or work-item extraction.
- Batch or queue processing where a human or agent can run local commands.
- Cases where durable disk artifacts are useful for later review or another agent.

Do not use this skill for:

- Text-only pages without video.
- Unauthorized downloads or bypassing access controls.
- Making claims before artifacts have been generated and inspected.

## Preflight

Run these before the first analysis in an environment or when dependency failures occur:

```powershell
zakira-replay doctor
zakira-replay deps status
```

If dependencies are missing and the user permits local downloads:

```powershell
zakira-replay deps install media
zakira-replay deps install onnx
zakira-replay deps install ocr [--language latin|chinese|english|korean|cyrillic|arabic|devanagari|greek|telugu|tamil]
zakira-replay deps install vision --mode clip    # CLIP ViT-B/32 ONNX from Xenova; ~150 MB
zakira-replay vision generate-clip-embeddings     # writes clip-kind-embeddings.bin (14336 bytes)
zakira-replay deps install whisper-model    # default small; use --whisper-model <size> to pick
zakira-replay deps install diarization      # pyannote-segmentation + 3D-Speaker ONNX (~32 MB)
```

`media` installs portable `yt-dlp`, `ffmpeg`, and `ffprobe` where supported. `onnx` installs the default semantic-search model files. `ocr` installs the RapidOCR PP-OCRv5 latin models that the local (non-LLM) OCR provider needs (~30 MB across four files). Automatic downloads only happen when configured with `dependencies.autoDownload=true`, `search.onnx.autoDownload=true`, or `ocr.local.autoDownload=true`.

For SSO-gated sources (SharePoint Stream, Microsoft Stream, internal corporate portals, Microsoft event playbacks behind Microsoft accounts) prefer the **dedicated Edge profile** path over the legacy `auth login` (StorageState JSON) path \u2014 the dedicated profile keeps cookies in Edge's native DPAPI-encrypted SQLite, whereas StorageState writes a portable plaintext JSON. One-time setup per machine:

```powershell
zakira-replay auth init-edge-profile --url https://microsofteur-my.sharepoint.com/
# Sign in interactively in the Edge window that opens (MFA, etc.); close Edge when done.
zakira-replay doctor    # confirm edge-profile: found via config
```

Default profile path: `%LOCALAPPDATA%\Zakira.Replay\edge-profile` (resolved per-machine). Override with `capture.browser.edgeUserDataDir` (env-var-literal preserved across config sync) or env var `ZAKIRA_REPLAY_EDGE_USER_DATA_DIR`. Sub-profile (Chromium `--profile-directory`) defaults to `Default`; override with `capture.browser.edgeProfileDirectory`. After the one-time sign-in, persistent-context mode auto-activates on every browser-capture run \u2014 no per-run CLI flags needed.

Dependency path overrides, if needed:

- `ZAKIRA_REPLAY_YTDLP_PATH`
- `ZAKIRA_REPLAY_FFMPEG_PATH`
- `ZAKIRA_REPLAY_FFPROBE_PATH`
- `ZAKIRA_REPLAY_ONNX_MODEL` (0.10.0+: search-embedding model id — `bge-small-en-v1.5`, `snowflake-arctic-embed-s`, `multilingual-e5-small`)
- `ZAKIRA_REPLAY_ONNX_MODEL_KIND` (0.10.0+: embedding scheme override — `bert`, `bge`, or `e5`)
- `ZAKIRA_REPLAY_ONNX_MODEL_PATH`
- `ZAKIRA_REPLAY_ONNX_TOKENIZER_PATH` (0.10.0+: tokenizer file — `vocab.txt` for BERT, `sentencepiece.bpe.model` for XLM-R)
- `ZAKIRA_REPLAY_ONNX_VOCAB_PATH` (legacy alias for `ZAKIRA_REPLAY_ONNX_TOKENIZER_PATH`)
- `ZAKIRA_REPLAY_OCR_MODEL_DIRECTORY` (plus per-file `*_DETECTION_MODEL_PATH`, `*_CLASSIFICATION_MODEL_PATH`, `*_RECOGNITION_MODEL_PATH`, `*_DICTIONARY_PATH`)
- `ZAKIRA_REPLAY_EDGE_USER_DATA_DIR` (overrides `capture.browser.edgeUserDataDir`)
- `ZAKIRA_REPLAY_RUNS_DIRECTORY` (overrides `runs.directory`; pins where every `runs/<run-id>/` artifact tree lands instead of inheriting `<cwd>/runs`)
- Config keys: `yt-dlp.path`, `ffmpeg.path`, `ffprobe.path`, `search.onnx.*` (including the 0.10.0 `search.onnx.model`, `search.onnx.modelKind`, `search.onnx.tokenizerPath`), `ocr.local.*`, `capture.browser.edge{UserDataDir,ProfileDirectory}`, `dependencies.portableDirectory` (where models / yt-dlp / ffmpeg land), `runs.directory` (where analysis artifacts land; env-var literals like `%LOCALAPPDATA%\Zakira.Replay\runs` are preserved verbatim and expanded at read time)

Tokenization for the `sqlite-onnx` search backend is handled by **`Microsoft.ML.Tokenizers` 2.0** — `BertTokenizer.Create(vocab.txt)` for BGE / arctic / generic-BERT, `SentencePieceTokenizer.Create(stream)` for the XLM-R-based multilingual-e5 family. The right path is picked automatically from the tokenizer-file extension, so swapping `search.onnx.model` between known ids requires no extra config.

Do not put secret values in JSON config. Config stores environment variable names for provider secrets.

## Recommended Analysis Commands

General evidence extraction (relies on the new defaults: `--frame-strategy scene`, `--ocr-provider local`, `--max-ai-frames 50`, `--scene-safety-cap 5000`, deterministic run-id):

```powershell
zakira-replay analyze "<url-or-file>" --ocr --vision --cache
```

Pin a run-id explicitly when you need a stable folder name beyond the auto-generated `<source-slug>-<sha8>`:

```powershell
zakira-replay analyze "<url-or-file>" --run-id <run-id> --ocr --vision --cache
```

Presets — opinionated default bundles for common scenarios. Explicit flags always win, so you can combine `--preset` with overrides:

```powershell
# Meeting recordings: enables --ocr --vision --diarize --stt and --audio in one flag.
zakira-replay analyze "<meeting.mp4>" --preset meeting --cache

# Lecture / course captures: enables --ocr --vision --audio.
zakira-replay analyze "<lecture.mp4>" --preset lecture --cache

# Demo / screencast: --ocr --vision with --frame-strategy scene.
zakira-replay analyze "<demo.mp4>" --preset demo --cache

# Podcast / interview: --diarize --audio --stt, frame count zeroed (audio-first).
zakira-replay analyze "<interview.mp3>" --preset interview --cache

# Raw / no opinion: equivalent to omitting --preset.
zakira-replay analyze "<source>" --preset raw --cache
```

Transcript-first analysis (no frames extracted):

```powershell
zakira-replay analyze "<url-or-file>" --frames 0 --frame-strategy interval --cache
```

Force LLM-backed OCR/vision (when the local OCR provider's accuracy isn't sufficient — typically for slides with tables, complex code blocks, or non-Latin scripts):

```powershell
zakira-replay analyze "<url-or-file>" --ocr --ocr-provider copilot --vision --cache
```

Audio fallback when no captions exist (still opt-in even with the new defaults):

```powershell
zakira-replay analyze "<url-or-file>" --ocr --vision --stt --cache
```

Authenticated videos:

```powershell
zakira-replay analyze "<url>" --browser-auth edge --frames 7 --frame-strategy scene --ocr --vision --cache
zakira-replay analyze "<url>" --cookies "<cookies.txt>" --frames 7 --cache
```

Always quote URLs in PowerShell, especially YouTube URLs containing `&`.

## Global Flags

Every command — including the subcommand groups (`runs`, `index`, `chapters`, `align`, `queue`, …) — accepts these recursive flags from the root command:

- `--output-format text|json|ndjson`: switch the command's stdout format. `text` (default) is the human-readable one-line-per-thing format. `json` emits the same structured payload as the corresponding MCP tool. `ndjson` is reserved for future streaming results. Replaces every per-command `--json` flag from the 0.8.x surface.
- `--log-file <path>`: optional path to write structured log output to. Stderr still receives the human-readable progress lines.
- `--log-level info|debug|trace`: minimum log level. `info` is the default.
- `--correlation-id <string>`: propagated to evidence and logs so agent runs can be cross-referenced with an external workflow. Useful when the CLI is invoked from a larger orchestrator that already has a trace ID.

The 0.8.x per-command `--json` flag no longer exists; use `--output-format json` instead. Example:

```powershell
zakira-replay doctor --output-format json
zakira-replay info --output-format json
zakira-replay queue status --queue-id research --output-format json
```

## Option Selection

Defaults that ship out-of-the-box: `--frame-strategy scene` (no `--frames` cap, bounded by `frames.sceneSafetyCap=5000`), `--ocr-provider local` (offline RapidOCR; first OCR run auto-downloads ~30 MB models from ModelScope unless `ocr.local.autoDownload=false`), `--max-ai-frames 50` (per-slide OCR/vision cap), `--frames 500` (only used when `--frame-strategy interval`), `frames.perMinute=12` (duration-aware floor for interval strategy). The auto-generated run-id is deterministic per source URL: `<slug>-<sha8>` so re-running the same source reuses the same run folder and `--cache` short-circuits cleanly.

Use these defaults unless the user says otherwise:

- `--preset <name>`: opinionated defaults bundles for the most common scenarios. `meeting` enables `--ocr --vision --diarize --stt --audio`. `lecture` enables `--ocr --vision --audio`. `demo` enables `--ocr --vision --frame-strategy scene`. `interview` enables `--diarize --audio --stt --frames 0`. `raw` (or omitting `--preset`) leaves every flag at its individual default. Explicit flags always win, so `--preset meeting --frame-strategy interval` keeps the meeting bundle and overrides the frame strategy.
- `--cache`: include by default for LLM-backed work; use `--force` only when intentionally recomputing.
- `--frames 500` is the new general-analysis default for the `interval` strategy. Override down for cheap exploration (`--frames 30`) or up for very dense sampling (`--frames 5000` paired with `--frame-strategy interval`). When `--frame-strategy scene` is in effect (the default), `--frames` is ignored.
- `--frames 0 --frame-strategy interval`: transcript-only (no frames extracted).
- `--frame-strategy scene` (default): presentations, demos, UI walkthroughs, slide videos, conference talks, anything with discrete visual changes. Returns one frame per detected scene change, slide-grouping deduplicates. Total frame count scales with content, capped at `frames.sceneSafetyCap` (default 5000).
- `--frame-strategy interval`: dense uniform sampling, useful when you need a predictable count or when scene-detection produces too few frames (rare with the new default cap).
- `--frame-strategy every-frame`: only when the user explicitly needs capped frame-by-frame inspection.
- `--ocr`: enable when slides, code, dashboards, diagrams, documents, or burned-in captions may be visible.
- `--ocr-provider <name>`: choose the OCR backend. `local` (default) runs RapidOCR (PP-OCRv5) entirely on-device via ONNX — no LLM, no network at run-time after the one-time model download. Defaults to the **latin** language pack; switch packs for non-Latin scripts via `zakira-replay deps install ocr --language <pack>` + `zakira-replay config set ocr.local.languagePack <pack>` (or `ZAKIRA_REPLAY_OCR_LANGUAGE_PACK`). Supported packs: `latin`, `chinese`, `english`, `korean`, `cyrillic`, `arabic`, `devanagari`, `greek`, `telugu`, `tamil`. `copilot` routes the image through the configured LLM (GitHub Copilot, OpenAI, Azure OpenAI, or Ollama) using vision-capable chat models — prefer this for complex layouts, mixed scripts, or when `tables[]` reconstruction matters (the local provider leaves `tables[]` empty in this release). The first local-OCR run auto-downloads ~30 MB of models (set `ocr.local.autoDownload=false` to disable; pre-install with `zakira-replay deps install ocr [--language <pack>]`).
- `--vision-provider <name>` + `--local-vision-mode <mode>`: choose the vision backend. `copilot` (default) routes per-slide vision through the configured LLM. `local` runs the fully-on-device `LocalOnnxVisionProvider` that never invokes an LLM. Under `local`, pick one of three sub-modes via `--local-vision-mode`: `heuristic` (zero models, structure derived from OCR; works out of the box), `clip` (heuristic + CLIP ViT-B/32 zero-shot for the `kind` field, ~150 MB auto-downloaded via `zakira-replay deps install vision --mode clip` + a one-time `zakira-replay vision generate-clip-embeddings`), or `clip-caption` (default for the local provider; CLIP + Florence-2-base-ft image captioning fills `freeText` — auto-installed by `zakira-replay deps install vision --mode clip-caption`, ~410 MB total). The deprecated string `clip-blip` is still accepted as an alias for `clip-caption`. When `--vision-provider local` is passed without `--ocr`, OCR is auto-enabled and `VISION_LOCAL_OCR_REQUIRED` (info) is emitted. Missing CLIP/Florence files cause graceful degradation (`clip-caption` → `clip` → `heuristic`). Limitations: `charts[]` is always empty in local mode; Florence-2-base captions are smaller-model captions (always paired with literal OCR text in `freeText` for the trustworthy part). The chosen provider is recorded on each `VisionFrameResult.provider`. CLI install path:

```powershell
zakira-replay deps install vision --mode clip
zakira-replay vision generate-clip-embeddings
zakira-replay doctor    # confirm vision-models: found
```
- `--vision`: enable when visual content matters.
- `--smart-crop` / `--smart-crop-profile <profile>`: enable smart-crop preprocessing that removes meeting-platform UI chrome (Teams/Zoom/WebEx controls bar, participant gallery sidebar, black letterbox bars, bottom navigation) before perceptual hashing, OCR, and vision. Profiles: `auto` (default), `teams`, `zoom`, `webex`, `generic` (all share the same algorithm in this release), or `off` to disable. Use this when the source is a meeting recording — it dramatically improves slide-grouping stability (the persistent gallery sidebar otherwise dilutes the dHash) and removes meeting-app vocabulary from OCR text. Set `crop.enabled=true` in config to make it the default for all runs.
- `--capture-mode {auto|ytdlp|browser}`: choose the frame-capture backend. `ytdlp` (default) uses yt-dlp + ffmpeg — works for ~1000 sites yt-dlp supports plus local files. `browser` drives Playwright-controlled Chromium (pinned to Edge) to navigate, click play, JS-seek, and screenshot — required for SharePoint/Medius/Teams recordings and any source yt-dlp can't reach. `auto` tries yt-dlp first and falls back to `browser` on failure, emitting `CAPTURE_BROWSER_FALLBACK` so orchestrators can branch on which path was used. For authenticated sources, combine with `--cookies-from-browser edge` (yt-dlp-side) or rely on the dedicated Edge profile (browser side). **Browser-mode silent capabilities:** (1) network listener watches for any `.vtt`/`.srt` responses the page fetches, persists them under `captions/browser-NNNN.vtt`, indexes them in `captions/discovered.json`, and uses the best-language match to populate `transcript.md`; (2) `track.mode = "showing"` is set on all `<video>.textTracks` so players that gate cue loading on CC-activation actually fetch their cues — emits `CAPTURE_BROWSER_CAPTIONS_ACTIVATED` (info); (3) when the network interceptor sees no `.vtt`/`.srt` responses, cues are harvested directly from `videoElement.textTracks[i].cues` and serialised to synthetic VTT — emits `CAPTURE_BROWSER_CAPTIONS_HARVESTED_FROM_DOM` (info); (4) **SharePoint Stream-specific path**: when the Stream player exposes its `_api/v2.X/.../media/transcripts` metadata, Zakira follows each `temporaryDownloadUrl` via the authenticated context, tries multiple URL variants (`?isformatjson=true&transcriptkey=<id>` first to coax out the rich Teams transcript JSON with `speakerDisplayName`), converts to VTT with `<v Speaker>` voice spans, and persists under `captions/stream-NNNN-<lang>.{vtt,json}`. Activates automatically for `*.sharepoint.com/.../stream.aspx?id=...` URLs; emits `CAPTURE_STREAM_TRANSCRIPT_DISCOVERED` and `CAPTURE_STREAM_TRANSCRIPT_DOWNLOADED` (info); (5) when `--stt` is requested but no captions are obtained AND no audio source exists, the browser observes media responses during playback and re-downloads the best single-file candidate via the authenticated context for ffmpeg + Whisper — DASH/HLS fragmented streams emit `CAPTURE_BROWSER_MEDIA_NO_CANDIDATE` and STT is skipped with a clear reason.
- `--capture-debug` (or `capture.browser.debug=true` in config): opt-in diagnostic dump under `runs/<run-id>/debug/`. Writes `network.log` (JSONL of every browser response with URL, status, content-type, size, headers, timestamp), `metadata-responses/<seq>-<sha8>.<ext>` (full bodies for JSON/XML/text/JavaScript responses under `capture.browser.debugMaxBodyBytes`, default 1 MB), `metadata-responses/index.json` (URL → body map), `texttracks-state.json` (post-activation snapshot of `<video>.textTracks`), and `network.har` (industry-standard HAR via Playwright). Strictly side-channel \u2014 doesn't affect capture behaviour. Use when reverse-engineering a new player or diagnosing why a transcript is missing for a Stream-shaped URL.
- `--auth-profile <name>`: load a previously-saved Playwright **StorageState JSON** profile into the browser context. **Legacy path \u2014 prefer the dedicated Edge profile (`auth init-edge-profile`)** for SharePoint Stream, Microsoft Stream, and any Microsoft SSO source. Reasons: persistent-context Edge keeps cookies DPAPI-encrypted (per-user, per-machine) while StorageState writes plaintext JSON that is portable to any attacker machine; persistent-context cookies refresh in place during use while StorageState files expire fast (1\u20132 hours typical for Microsoft). When both `--auth-profile` and an initialised `edgeUserDataDir` are set, persistent-context wins and `CAPTURE_PROFILE_CONFLICT` (info) records the override. Use `--auth-profile` only when persistent-context is impossible (no dedicated Edge profile, locked-down environment) or for non-Microsoft sites where you already have a StorageState snapshot. Pipeline emits `AUTH_PROFILE_NOT_FOUND` (error) when the named profile does not exist on disk and `AUTH_PROFILE_STALE` (info) when the profile's file mtime is older than `auth.staleThresholdMinutes` (default 60). Staleness is informational \u2014 capture proceeds; if downstream extraction looks like it landed on a login page, suggest the user re-run `auth login <name>` or migrate to `auth init-edge-profile`.
- `--stt`: enable when captions may be absent or poor. Captions/sidecars are tried first; STT only runs if transcript extraction fails.
- `--diarize` / `--num-speakers <n>` / `--diarize-threshold <0.0-1.0>`: run local sherpa-onnx speaker diarization (pyannote-segmentation-3.0 + 3D-Speaker embedding + agglomerative clustering) on top of the transcript. Requires a transcript (`--stt` or captions). Diarization rewrites `transcript.md` in place with `[SPEAKER_NN]` prefixes; the per-speaker registry in `evidence.json` and the per-slide / per-chapter speaker rollups in `evidence-aligned/` are then populated automatically. Pass `--num-speakers` when you know how many speakers are present; otherwise `--diarize-threshold` (default 0.5) controls the cluster cutoff (lower → more speakers). Pre-install models with `zakira-replay deps install diarization` (~32 MB). Speaker IDs are anonymous within a run (`SPEAKER_00`, `SPEAKER_01`, …) and have no cross-run meaning. Explicit caption-side attribution (VTT `<v>` tags / SRT prefixes) is preserved — diarization never overwrites a known speaker name. Warning codes: `DIARIZATION_NO_AUDIO`, `DIARIZATION_NO_TRANSCRIPT`, `DIARIZATION_MODELS_MISSING`, `DIARIZATION_INIT_FAILED`, `DIARIZATION_FAILED`, `DIARIZATION_UNKNOWN_PROVIDER`.
- `--caption-languages`: comma-separated language preferences for yt-dlp subtitles (e.g. `--caption-languages fr,en`). Defaults to `auto`, which unions the source's primary language, the languages with **manually uploaded** subtitles (per `info.subtitles`), English (`en`, `en.*`), and YouTube live-chat. YouTube auto-translation languages (those that appear only under `info.automatic_captions`) are intentionally **not** expanded by `auto` because they are inferences from the source, not facts about what was spoken. To opt into a specific auto-translation, pass that language explicitly (`--caption-languages es`); read `metadata.json -> availableSubtitleLanguages` first to see which languages exist (`hasManual` / `hasAuto`) for the source. Stable IDs for any frames that get extracted are written to both `frames[*].id` and `ocr[*].frameId` / `vision[*].frameId` for cross-reference.
- `--vision-instruction`: optional focus signal appended to the vision prompt. The default is empty; the model already extracts every visible piece of content (slide titles, bullets, code blocks, chart axes, UI controls). Use this only to bias enumeration order toward what matters for the orchestrator's question (e.g. `"Bias toward chart axes and code"`).
- `--ocr-instruction`: optional focus signal appended to the OCR prompt. The default is empty; the model already extracts every readable character. Use this for hints like `"Preserve indentation in code-like text"`. Both instructions are persisted into `evidence.json::visionInstruction` and `evidence.json::ocrInstruction` for audit. They never relax the "do not invent" guardrails. The local OCR provider ignores `--ocr-instruction` entirely (it always extracts every visible character) but still persists the value for audit.
- `--frames-per-minute <n>`: per-request override of the duration-aware sampling rate for the interval strategy. The config default is `frames.perMinute=12` (one frame every 5 seconds). When set (or non-zero in config), the effective frame count is `max(framesPerMinute * durationMinutes, --frames)`. Pass `--frames-per-minute 0` to disable duration-aware scaling for one run. Ignored for `scene` and `every-frame`.
- `--max-ai-frames <n>`: cap on the number of unique slides sent to OCR/vision. Default `50`. Slide grouping deduplicates extracted frames first; this then bounds the AI cost. Lower for cheap runs, higher when slide-deck content is dense.
- `--scene-safety-cap <n>`: per-run override of `frames.sceneSafetyCap` (default 5000). The scene strategy returns up to this many frames; slide grouping deduplicates. When the cap is hit the run carries a `FRAMES_SCENE_CAP_REACHED` warning. The pipeline also emits `FRAMES_LIKELY_UNDERSAMPLED` if interval sampling without `--frames-per-minute` (and with `frames.perMinute=0` in config) produces fewer than 1 frame per 5 minutes.

There is no `--summary` flag. Synthesis is your job, not Zakira.Replay's.

Provider notes:

- `github-copilot` is the default LLM provider for STT (and for OCR/vision when `--ocr-provider copilot`).
- `openai` supports chat/image and audio transcription via `/audio/transcriptions`.
- `azure-openai` supports chat/image for OCR/vision, but Zakira.Replay STT is not implemented yet.
- `ollama` talks to a local Ollama daemon (`http://localhost:11434` by default) through OllamaSharp's native `Microsoft.Extensions.AI.IChatClient` implementation. **Chat / vision only** — no STT. Configure with `llm.ollama.model` (chat), `llm.ollama.visionModel` (image attachments), and `llm.ollama.endpoint` (or env vars `ZAKIRA_REPLAY_OLLAMA_*`, `OLLAMA_HOST`). Pre-pull models with `ollama pull qwen2.5:7b` / `ollama pull llama3.2-vision:11b`. Combine with `--llm-provider local-whisper` for STT and `--ocr-provider local` for OCR to get an air-gapped run.
- `local-whisper` runs Whisper.net (whisper.cpp bindings) entirely on-device for STT. **STT-only** — has no chat/vision/OCR surface; combine with `--ocr-provider local` for a fully-offline run. Pre-install the model with `zakira-replay deps install whisper-model [--whisper-model tiny|base|small|medium|large-v3|large-v3-turbo]` (default: `small`, ~466 MB). Configure via `llm.localWhisper.*` keys or `ZAKIRA_REPLAY_WHISPER_*` env vars. Surface-specific warnings: `STT_LOCAL_MODEL_MISSING`, `STT_LOCAL_INIT_FAILED`, `STT_LOCAL_INFERENCE_FAILED`.
- The default OCR provider is `local` (RapidOCR via ONNX) which needs no LLM at all.

## Read Command Output

After `analyze`, capture:

- `Completed run:` or `Reused run:`
- `Artifacts:` directory
- `Manifest:` path
- Any `Warnings:` lines (formatted as `[severity] CODE: message`)

If the command reports `Reused run`, inspect existing artifacts before deciding whether `--force` is needed.

## Artifact Reading Order

Read artifacts in this order:

1. `manifest.json`: produced paths, structured warnings, run ID, frame list.
2. `evidence.json`: structured transcript, frames, slides, OCR, vision, per-speaker registry (`speakers[]`), structured warnings.
3. `slides/slides.json` (also embedded in `evidence.json`): slide grouping facts (`firstSeenSeconds`, `lastSeenSeconds`, `frameIds`, `primaryFrameId`). OCR/vision run once per slide; each result carries `slideId`.
4. `transcript.md`: human-readable timestamped transcript with `[Speaker Name]` prefixes when captions carried speaker tags.
5. `transcript/normalization.json` and `transcript/raw.*`: audit exact quotes when normalization matters. Speaker changes are hard merge boundaries.
6. `audio/chunks/chunks.json`: present only when long-audio STT was silence-chunked. Branch on `STT_CHUNK_FAILED` warnings if any chunk failed.
7. `ocr/{frameId}.json` and `ocr/combined.md`: structured OCR (`freeText`, `lines[]`, `tables[]`); branch on `OCR_PARSE_FALLBACK` for prose responses.
8. `vision/{frameId}.json` and `vision/combined.md`: structured vision (`kind`, `title`, `bullets[]`, `codeBlocks[]`, `charts[]`, `uiElements[]`, `freeText`); branch on `VISION_PARSE_FALLBACK`.
9. `frames/`: inspect images when layout, UI, charts, code, slides, or visual details matter.
10. `metadata.json`: title, source URL, duration, uploader metadata, `availableSubtitleLanguages`.
11. `evidence.md`: concise human-readable index of artifact paths.

Speakers in `evidence.speakers[]` carry `id` (slug, stable), optional `displayName`, plus `segmentCount`, `totalSeconds`, `firstSeenSeconds`, `lastSeenSeconds`. Each `transcript[*]` segment has `id` (`segment-NNNN`) and may have `speakerId`/`speakerDisplayName`. STT-derived transcripts do not carry speakers in this release.

Warnings in `manifest.json` and `evidence.json` are structured records: `{ code, message, source, severity }`. Branch on `code` (for example `TRANSCRIPT_NOT_FOUND`, `STT_NO_LLM_PROVIDER`, `STT_CHUNK_FAILED`, `OCR_PARSE_FALLBACK`, `OCR_LOCAL_MODELS_MISSING`, `OCR_LOCAL_INFERENCE_FAILED`, `OCR_UNKNOWN_PROVIDER`, `VISION_PARSE_FALLBACK`, `PERCEPTUAL_HASH_FAILED`, `FRAMES_REMOTE_FALLBACK`, `CROP_BAIL_OUT`, `CROP_PROFILE_UNKNOWN`, `CROP_IMAGE_DECODE_FAILED`, `CROP_OUTPUT_FAILED`, `CAPTURE_BROWSER_FALLBACK`, `CAPTURE_BROWSER_UNAVAILABLE`, `CAPTURE_PLAY_BUTTON_NOT_FOUND`, `CAPTURE_DURATION_UNRESOLVED`, `CAPTURE_SEEK_FAILED`, `CAPTURE_SCREENSHOT_FAILED`, `CAPTURE_UNKNOWN_MODE`, `CAPTIONS_BROWSER_NETWORK_NONE`, `CAPTIONS_BROWSER_NETWORK_DOWNLOAD_FAILED`, `CAPTIONS_BROWSER_NETWORK_PARSE_FAILED`, `CAPTURE_BROWSER_CAPTIONS_ACTIVATED`, `CAPTURE_BROWSER_CAPTIONS_HARVESTED_FROM_DOM`, `CAPTURE_BROWSER_PROFILE_NOT_INITIALIZED`, `CAPTURE_BROWSER_PROFILE_DIR_MISSING`, `CAPTURE_BROWSER_PROFILE_LOCKED`, `CAPTURE_BROWSER_PROFILE_LAUNCH_FAILED`, `CAPTURE_BROWSER_AUTH_REQUIRED`, `CAPTURE_BROWSER_AUTH_MFA_DETECTED`, `CAPTURE_PROFILE_CONFLICT`, `CAPTURE_BROWSER_MEDIA_DOWNLOADED`, `CAPTURE_BROWSER_MEDIA_NO_CANDIDATE`, `CAPTURE_BROWSER_MEDIA_DOWNLOAD_FAILED`, `CAPTURE_STREAM_TRANSCRIPT_DISCOVERED`, `CAPTURE_STREAM_TRANSCRIPT_DOWNLOADED`, `CAPTURE_STREAM_METADATA_PARSE_FAILED`, `CAPTURE_STREAM_TRANSCRIPT_PARSE_FAILED`, `AUTH_PROFILE_NOT_FOUND`, `AUTH_PROFILE_STALE`, `AUTH_PROFILE_LOAD_FAILED`) rather than fuzzy-matching the message.

## Inspect Existing Runs (`runs` group)

The `runs` group is a first-class way to inspect, export, and clean up analyses that already landed on disk. Prefer these over hand-rolled directory scans.

```powershell
# Most-recent-first listing; `--output-format json` returns a machine-readable index
zakira-replay runs list
zakira-replay runs list --output-format json

# Path summary plus a pointer to each present artifact; JSON output prints the manifest body
zakira-replay runs show <run-id>
zakira-replay runs show <run-id> --output-format json

# Export a run's transcript (Markdown) or transcript segments (one JSON per line, with `runId` baked in)
zakira-replay runs export <run-id> --format md
zakira-replay runs export <run-id> --format jsonl

# Delete a run directory; `--force` is required so accidental rm-rf is impossible
zakira-replay runs delete <run-id> --force
```

The `<run-id>` is the deterministic `<source-slug>-<sha8>` (auto-generated unless you passed `--run-id`). When you only have the source URL, run `runs list --output-format json` and match on the source field, or just rerun `analyze` with `--cache` — the deterministic run id makes it idempotent.

## Chapters And Search

Build chapters after transcript evidence exists:

```powershell
zakira-replay chapters build runs\<run-id> --min-duration 60 --max-duration 600
```

Chapters are pure time spans plus per-chapter evidence references. Generate any titles or prose summaries you need yourself; the tool does not produce them.

Materialise cross-modal alignment views after chapters and slides exist:

```powershell
zakira-replay align build runs\<run-id>
```

This writes `evidence-aligned/by-chapter.json` (per-chapter join of slides, transcript segment IDs, OCR/vision frame IDs, and speaker stats) and `evidence-aligned/by-slide.json` (per-slide join of frames, OCR, vision, transcript segment IDs spoken while the slide was visible, speaker stats, and overlapping chapter indices). Both files share `evidence-aligned.schema.json` and are pure rearrangements with no model calls.

Build a search index for repeated questions or long transcripts:

```powershell
zakira-replay index build runs\<run-id> --backend sqlite-onnx
zakira-replay index query runs\<run-id> "<question or topic>" --top 10 --backend auto
```

Backend choice:

- `json`: portable sparse TF-IDF fallback.
- `sqlite`: SQLite FTS5 keyword search.
- `sqlite-onnx`: semantic search via local ONNX embedding model, best for natural-language retrieval.

Search-embedding model choice (0.10.0+): three models ship in the known-model registry; the
runtime auto-downloads the chosen one on first `index build` when `search.onnx.autoDownload=true`.

| Model id | Language | Footprint | Notes |
|---|---|---|---|
| `bge-small-en-v1.5` (default) | English | ~33 MB ONNX | BERT WordPiece tokenizer; CLS pooling; query-side prefix. Top of the 384-dim retrieval tier. |
| `snowflake-arctic-embed-s` | English | ~33 MB ONNX | Same architecture as BGE (same tokenizer, same pooling); slight quality difference; pick if BGE underperforms on your corpus. |
| `multilingual-e5-small` | 100+ languages | ~118 MB ONNX | XLM-RoBERTa SentencePiece tokenizer; mean pooling; query+passage prefixes. Use for non-English transcripts. |

Pick a model once via config, or per-call via `--onnx-model`:

```powershell
# Persistent default
zakira-replay config set search.onnx.model multilingual-e5-small
zakira-replay deps install onnx                       # downloads the configured model

# Per-call override (no config change)
zakira-replay index build runs\<run-id> --backend sqlite-onnx --onnx-model multilingual-e5-small
zakira-replay index query runs\<run-id> "<question>" --backend sqlite-onnx --onnx-model multilingual-e5-small
```

For custom local models that aren't in the registry, point `--onnx-model-path` and
`--onnx-tokenizer-path` at your files and set `--onnx-model-kind {bert|bge|e5}` so the
provider applies the right prefix and pooling.

**Important**: indexes built with one model cannot be queried with another. If you change
`search.onnx.model` after having built indexes, the next query raises
`SEARCH_INDEX_EMBEDDING_MISMATCH`. Recover with `zakira-replay index build runs\<run-id> --force`
to rebuild against the new model, or pass `--onnx-model <original-id>` to pin the index's
model for this query.

Treat search matches as pointers into evidence, not final answers by themselves.

## Clips

Extract clips only when timestamps are known or justified by artifacts:

```powershell
zakira-replay clip "<url-or-file>" --start 01:20 --end 02:05 --output-name key-demo
```

Read `clip.json` and report the clip path plus timestamp range.

## Ad-hoc Frame Capture

`zakira-replay frames` has two modes:

1. **Legacy mode** (no `--at`/`--from`/`--to`): runs a frames-only full-analyze pipeline. Equivalent to `analyze --no-transcript`. Keep using this when you actually want slides/OCR/vision.
2. **Ad-hoc mode** (any of `--at`, `--from`, `--to` present): cheap spot capture via `FrameCaptureService` - no slide grouping, no OCR, no vision, no chapter synthesis. Use this after a full `analyze` run when an agent needs additional stills for a downstream artifact (e.g. recipe step images, transcript-aligned thumbnails, screenshots at known timestamps for a bug report).

Output for ad-hoc mode lands in a new `runs/<id>/frames/` folder alongside a minimal `frame-capture.json` manifest (schema: `frame-capture.schema.json`, `kind: "frame-capture"`).

```powershell
# Exact timestamps (comma-separated; accepts seconds, MM:SS, HH:MM:SS)
zakira-replay frames "./cooking.mp4" --at 02:34,03:10,04:55 --max-edge 1024 --quality 85

# Window with N evenly spaced frames (endpoints inclusive)
zakira-replay frames "https://example.com/video" --from 02:00 --to 03:00 --count 5

# Window with ffmpeg scene-cut detection scoped to the window
zakira-replay frames "./demo.mp4" --from 02:00 --to 03:00 --strategy scene --scene-safety-cap 20

# JSON output (same shape as the frames MCP tool result)
zakira-replay frames "./demo.mp4" --at 02:34 --output-format json
```

Ad-hoc flag cheatsheet:

- `--at <ts1,ts2,...>`: list of exact timestamps. Up to 64 per call; excess are dropped with `FRAME_CAPTURE_TOO_MANY_TIMESTAMPS`. Out-of-range entries are dropped with `FRAME_CAPTURE_TIMESTAMP_OUT_OF_RANGE`.
- `--from <ts>` / `--to <ts>`: time window. Required together. `--to` is clamped to source duration with `FRAME_CAPTURE_RANGE_OUT_OF_BOUNDS`.
- `--count <n>`: number of frames inside the window. For `--strategy interval`, evenly spaced inclusive of both endpoints. For `--strategy scene`, acts as an upper bound on returned scene cuts.
- `--strategy interval|scene`: defaults to `interval`. `scene` runs ffmpeg's scene-cut filter scoped to the window via output-side `-ss`/`-to`; reported timestamps stay in absolute source timeline.
- `--max-edge <px>`: resize so the longest edge is at most N pixels (aspect ratio preserved). Useful for thumbnail-sized stills.
- `--quality <1-100>`: JPEG quality (mapped to ffmpeg qscale 31-2). Default high quality.
- `--phash`: also compute a 64-bit perceptual hash per frame so the agent can dedupe near-identical stills downstream.
- `--scene-safety-cap <n>`: hard cap on scene cuts in the window (defaults to `max(--count, 200)`). Emits `FRAME_CAPTURE_SCENE_CAP_REACHED` when reached.
- `--output-format json`: emit machine-readable output (runId, artifactDirectory, manifestPath, frameCount, frames[], warnings) instead of the human-readable per-frame summary.
- `--cookies` / `--cookies-from-browser` / `--browser-auth`: yt-dlp auth for remote sources, identical semantics to `analyze`.
- `--run-id <id>`: pin the artifact folder name; otherwise auto-generated from the source.

`--at` and `--from`/`--to` are mutually exclusive; passing both raises a CLI error before ffmpeg runs.

Frame-capture-specific warning codes (also written into `manifest.warnings`):

- `FRAME_CAPTURE_TIMESTAMP_OUT_OF_RANGE` - timestamp was negative or past source duration.
- `FRAME_CAPTURE_RANGE_OUT_OF_BOUNDS` - `--to` exceeded source duration and was clamped.
- `FRAME_CAPTURE_TOO_MANY_TIMESTAMPS` - >64 timestamps supplied; only the first 64 were used.
- `FRAME_CAPTURE_NO_FRAMES` - ffmpeg returned zero frames (e.g. scene detection found nothing in the window).
- `FRAME_CAPTURE_SCENE_CAP_REACHED` - safety cap was hit during scene detection.
- `FRAME_CAPTURE_MEDIA_URL_UNRESOLVED` - yt-dlp could not resolve a direct media URL; the pipeline fell back to downloading.

Do not reach for `frames --at`/`--from`/`--to` when you actually need transcript, slides, OCR, vision, chapters, or evidence alignment; use `analyze` for those.

## Queue And Batch

Use queue commands when many videos need local processing:

```powershell
zakira-replay queue enqueue "<url-or-file>" --queue-id research --job-id <job-id> --frames 7 --cache
zakira-replay queue run --queue-id research --concurrency 2 --retries 2
zakira-replay queue status --queue-id research --output-format json
```

Use batch manifests when the user already has a manifest file:

```powershell
zakira-replay batch run <manifest.json>
```

## Topic Summary And Work Items Pattern

For requests like "watch this and summarize topics and work items":

1. Run slide/demo-heavy analysis with `--stt --ocr --vision --frames 30 --frame-strategy scene --cache` unless the user requests cheaper settings.
2. Build chapters with `zakira-replay chapters build`.
3. Build semantic search with `zakira-replay index build --backend sqlite-onnx` when available.
4. Read `chapters/chapters.md`, `evidence.json`, `transcript.md`, and `ocr/combined.md`.
5. Search for `action item`, `next steps`, `todo`, `follow up`, `decision`, `owner`, `deadline`, and relevant project terms.
6. Synthesize the topic summary and work items yourself from these facts. Write the final Markdown alongside the run, usually `runs/<run-id>/work-items.md`, if the user asked for a durable output file.

Work item format:

```markdown
- [ ] OWNER -- TASK -- DUE (or "unspecified") -- [HH:MM:SS] -- evidence: "short verbatim quote"
```

Do not invent owners or due dates. Use `unspecified` when unclear. Deduplicate repeated commitments and keep the earliest strong timestamp.

## Failure Handling

If dependency-related:

- Run `zakira-replay doctor` and `zakira-replay deps status`.
- Suggest `zakira-replay deps install media` for missing `yt-dlp`/`ffmpeg`/`ffprobe`.
- Suggest `zakira-replay deps install onnx` for semantic search model files.

If access-related:

- Use `--cookies <file>`, `--cookies-from-browser <browser>`, or `--browser-auth <browser>` only when the user has legitimate access.
- For sites yt-dlp cannot reach at all (authenticated SharePoint portals, Medius/Teams playback URLs, custom corporate players), use `--capture-mode browser` so frames are captured by Playwright directly. Combine with `--cookies-from-browser edge` if the page also needs session cookies for the initial load.
- For SSO-gated sources (Microsoft 365 / Azure AD / Okta), **prefer the dedicated Edge profile** (`zakira-replay auth init-edge-profile [--url <site>]`) which writes DPAPI-encrypted cookies into Edge's native storage. Once per machine, then every subsequent `--capture-mode browser` run picks it up automatically \u2014 no `--auth-profile` flag needed. Stale: SSO/Conditional-Access may force re-auth after 1\u201390 days; emit `CAPTURE_BROWSER_AUTH_REQUIRED` (error) when the post-navigation URL lands on a sign-in domain; remediation is to re-run `auth init-edge-profile`. Locked: `CAPTURE_BROWSER_PROFILE_LOCKED` (error) means an Edge instance is already using the user-data-dir; close Edge and retry. MFA: `CAPTURE_BROWSER_AUTH_MFA_DETECTED` (error) means the player rendered an MFA challenge that headless capture cannot satisfy; re-init interactively.
- The legacy `auth login <name>` / `--auth-profile <name>` path (Playwright StorageState JSON) still works, but writes plaintext cookies and expires faster. Use only when persistent-context is unavailable. List existing StorageState profiles with `zakira-replay auth list`; refresh by re-running `auth login` with the same name.
- **SharePoint Stream / Microsoft Stream transcripts**: when the dedicated Edge profile is initialised and `--capture-mode browser` is used, transcripts are downloaded automatically with full speaker attribution (Teams transcript JSON \u2192 WebVTT `<v Speaker>` voice spans). No flag needed. See `CAPTURE_STREAM_TRANSCRIPT_DOWNLOADED` (info) on each run with a Stream URL. If the page exposes transcripts metadata but Zakira can't download the file, `CAPTURE_STREAM_TRANSCRIPT_PARSE_FAILED` (warning) records the URL for manual inspection.

If transcript is missing:

- Rerun with `--stt`.
- Remember Azure OpenAI STT is not implemented; use GitHub Copilot or OpenAI for STT-required runs.

If visual evidence is sparse:

- Rerun with more `--frames`, `--frame-strategy scene`, `--ocr`, or `--vision`.
- Use `--frame-strategy every-frame` only with a tight `--frames` cap.

If AI provider calls fail:

- Preserve warnings in the final answer. Branch on warning `code`.
- Rerun with `--force` only if recomputation is worth the cost.
- For repeated OCR/vision failures, reduce `--frames` or switch provider/model if configured.
- If the LLM-backed OCR is unreliable or unavailable, fall back to `--ocr-provider local` (after `zakira-replay deps install ocr`). The local provider doesn't need any LLM and is unaffected by Copilot/OpenAI/Azure outages. Tradeoff: lower OCR fidelity on complex layouts and no `tables[]` reconstruction.

## MCP Server and Shell Completion

The same binary also hosts a Model Context Protocol server. Use this when you have an MCP-aware agent (Claude Desktop, Cursor, VS Code Copilot, hosted-agent platforms) that should call Zakira.Replay directly as a tool:

```powershell
# Default stdio transport (subprocess MCP clients)
zakira-replay mcp serve

# Streamable HTTP transport for hosted agent platforms / network MCP clients
zakira-replay mcp serve --transport http --port 8765

# SSE alias for legacy clients; same Streamable HTTP endpoint under the hood
zakira-replay mcp serve --transport sse --port 8765
```

The MCP surface mirrors the CLI groups (`analyze`, `analyze.start`, `queue.enqueue`, `index.build`, `chapters.build`, `align`, `frames`, `clip`, `discover`, `doctor`) and additionally exposes `replay://` resources (`replay://runs`, `replay://runs/{id}/{manifest|evidence|transcript|chapters|aligned/by-…|frames/{frameId}/{ocr|vision}}`, `replay://jobs/{jobId}/logs`). See the companion `zakira-replay-mcp` skill for the full agent contract.

For shell-completion scripts (Bash, Zsh, PowerShell, Fish):

```powershell
zakira-replay completion pwsh
zakira-replay completion bash
zakira-replay completion zsh
zakira-replay completion fish
```

The output is the snippet to source from your shell rc file; install it once per environment so `Tab` completes commands, options, and enum values.

## Evidence Discipline

When answering:

- Lead with the answer, then cite timestamped evidence.
- Separate confirmed evidence from inference.
- Mention warnings (by `code`) that affect confidence.
- Keep transcript excerpts short unless the user asks for extensive quotes.
- Do not fabricate speakers, slide contents, UI text, numbers, decisions, or work items.
- If evidence is insufficient, say so and recommend a concrete rerun command.
