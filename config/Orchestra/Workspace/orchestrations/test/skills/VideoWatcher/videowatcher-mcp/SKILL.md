---
name: videowatcher-mcp
description: Use VideoWatcher's MCP server tools to run non-blocking video analysis jobs, retrieve timestamped evidence artifacts, build chapters/search indexes, extract clips, and answer user questions from the produced evidence.
---

# VideoWatcher MCP Skill

Use this skill when VideoWatcher is available as an MCP server and the user asks you to analyze, summarize, inspect, search, quote, clip, or extract work items from a video.

VideoWatcher is an evidence producer. It writes durable artifacts to disk and returns artifact paths through MCP. It does not directly generate final reports. Your job is to call MCP tools, read the produced artifacts, and synthesize the user's requested answer from those files.

## Core Rule

Never claim you watched a video directly. Base every answer on artifacts returned by MCP: `manifest.json`, `evidence.json`, `transcript.md`, frame images, `ocr/combined.md`, `vision/combined.md`, `summary.md`, or `chapters/chapters.md`.

## MCP Server

The server command is:

```bash
videowatcher mcp serve
```

If `videowatcher` is not on `PATH`, configure the MCP client to use the full executable path or a development `dotnet run` command.

Use `doctor` as the first tool when dependency or provider readiness is unknown.

## Tool Selection

Prefer these tools:

- `create_analysis_job`: start non-blocking analysis and get a `jobId`.
- `get_job_status`: poll logs and status.
- `get_job_result`: fetch completed manifest and artifact directory.
- `build_chapters`: build `chapters/chapters.json` and `chapters/chapters.md` for a completed run.
- `build_search_index`: build JSON, SQLite, or SQLite+ONNX search over a completed run.
- `query_search_index`: retrieve relevant evidence chunks.
- `extract_clip`: create a timestamped clip when start/end are known.
- `doctor`: diagnose dependencies and provider setup.
- `enqueue_analysis_queue_job`, `run_analysis_queue`, `get_analysis_queue_status`: persistent queue workflow for many videos.

Use `analyze_video` only for short, low-risk jobs where blocking is acceptable. For long videos, visual analysis, OCR, STT, or summary work, use `create_analysis_job`.

## Job Workflow

1. Call `create_analysis_job` with source and analysis options.
2. Poll `get_job_status` every few seconds until status is `succeeded`, `failed`, or `cancelled`.
3. If `succeeded`, call `get_job_result`.
4. Extract `artifactDirectory` from the result.
5. Read `manifest.json` first, then the evidence artifacts needed for the user's request.
6. Build chapters/search only after analysis succeeds.

General analysis arguments:

```json
{
  "source": "https://example.com/video",
  "instruction": "Extract transcript, representative frames, OCR, and visual evidence for answering the user's question.",
  "frames": 7,
  "frameStrategy": "scene",
  "cache": true,
  "ocr": true,
  "vision": true,
  "summary": true,
  "maxAiFrames": 5
}
```

Transcript-first arguments:

```json
{
  "source": "https://example.com/video",
  "instruction": "Extract a timestamped transcript and key evidence.",
  "frames": 0,
  "cache": true
}
```

Slide, UI, code, or demo-heavy arguments:

```json
{
  "source": "https://example.com/video",
  "instruction": "Extract timestamped transcript evidence, visible slide/UI text, visual context, topic boundaries, and actionable work items.",
  "frames": 30,
  "frameStrategy": "scene",
  "cache": true,
  "stt": true,
  "ocr": true,
  "vision": true,
  "summary": true,
  "maxAiFrames": 30
}
```

Authenticated video arguments:

```json
{
  "source": "https://example.com/private-video",
  "instruction": "Extract evidence from this authenticated video.",
  "frames": 7,
  "frameStrategy": "scene",
  "cache": true,
  "browserAuth": "edge"
}
```

Use `cookies` when the user provides a cookies file path. Use `browserAuth` or `cookiesFromBrowser` only when the local browser session is expected to have legitimate access.

## Option Selection

Use these defaults unless the user says otherwise:

- `cache: true`: default for agent workflows; set `force: true` only when intentionally recomputing.
- `frames: 7`: general analysis.
- `frames: 0`: transcript-only tasks.
- `frames: 12` or more: visually dense videos.
- `frames: 30`, `frameStrategy: "scene"`: slide/demo-heavy videos.
- `frameStrategy: "scene"`: presentations, demos, UI walkthroughs, slide videos, or visually rich content.
- `frameStrategy: "every-frame"` or `everyFrame: true`: only when the user explicitly needs capped frame-by-frame inspection.
- `ocr: true`: slides, code, dashboards, diagrams, documents, or burned-in captions may be visible.
- `vision: true`: visual content matters.
- `summary: true`: user wants high-level synthesis or downstream report generation.
- `stt: true`: captions may be absent or poor. Captions/sidecars are tried first; STT runs only when transcript extraction fails.

Provider notes:

- `github-copilot` is the default provider for STT/OCR/vision/summary.
- `openai` supports chat/image and audio transcription.
- `azure-openai` supports chat/image for OCR/vision/summary, but VideoWatcher STT is not implemented yet.

## Artifact Reading Order

After `get_job_result`, read artifacts from `artifactDirectory` in this order:

1. `manifest.json`: confirms produced artifacts, warnings, frame list, and paths.
2. `evidence.json`: structured transcript segments, frames, OCR, vision, summary, warnings.
3. `transcript.md`: readable timestamped transcript.
4. `transcript/normalization.json` and `transcript/raw.*`: audit exact quotes when normalization matters.
5. `summary.md`: high-level model summary if requested.
6. `ocr/combined.md` and `vision/combined.md`: visual evidence if requested.
7. `frames/`: inspect image artifacts when visual details matter.
8. `metadata.json`: title, URL, duration, uploader metadata.
9. `evidence.md`: concise human-readable artifact summary.

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
- `sqlite-onnx`: semantic search, best for natural-language retrieval, requires ONNX model and vocabulary.

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

Read `chapters/chapters.md` for the topic outline and `chapters/chapters.json` for structured timestamps.

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

## Queue Workflow

Use the MCP queue tools for many videos or resumable local processing:

1. `enqueue_analysis_queue_job` with `source`, `queueId`, optional `jobId`, and analysis options.
2. `run_analysis_queue` with `queueId`, `concurrency`, and `retries`.
3. `get_analysis_queue_status` to report pending/running/succeeded/failed jobs.
4. Read each completed run's artifact directory before synthesizing results.

## Topic Summary And Work Items Pattern

For requests like "watch this and summarize topics and work items":

1. Use `create_analysis_job` with `frames: 30`, `frameStrategy: "scene"`, `stt: true`, `ocr: true`, `vision: true`, `summary: true`, `cache: true`, and `maxAiFrames: 30` unless the user requests cheaper settings.
2. Poll until success and get `artifactDirectory`.
3. Call `build_chapters`.
4. Call `build_search_index` with `backend: "sqlite-onnx"` when available; use `sqlite` or `json` if ONNX is unavailable.
5. Query for `action item`, `next steps`, `todo`, `follow up`, `decision`, `owner`, `deadline`, and project terms.
6. Read `chapters/chapters.md`, `summary.md`, `evidence.json`, `transcript.md`, and `ocr/combined.md`.
7. Write or return the requested Markdown output. If writing a file, place it next to artifacts, usually `<artifactDirectory>/work-items.md`.

Work item format:

```markdown
- [ ] OWNER -- TASK -- DUE (or "unspecified") -- [HH:MM:SS] -- evidence: "short verbatim quote"
```

Do not invent owners or due dates. Use `unspecified` when unclear. Deduplicate repeated commitments and keep the earliest strong timestamp.

## Failure Handling

If a job fails:

- Read returned `error` and `logs`.
- For dependency failures, call `doctor` and report missing `yt-dlp`, `ffmpeg`, `ffprobe`, or ONNX model files.
- If CLI access is available and the user permits local downloads, suggest `videowatcher deps install media` or `videowatcher deps install onnx`.
- For provider auth failures, inspect config keys for environment variable names; never ask users to store secret values in JSON config.
- For access failures, retry only with legitimate `cookies`, `cookiesFromBrowser`, or `browserAuth`.
- If transcript is missing, rerun with `stt: true` and ensure the provider supports STT.
- If visual evidence is insufficient, rerun with more `frames`, `frameStrategy: "scene"`, `ocr: true`, or `vision: true`.
- If a previous MCP job was interrupted by server restart, create a new job with the same arguments and `cache: true`.

## Evidence Discipline

When answering:

- Lead with the answer, then cite timestamped evidence.
- Separate confirmed evidence from inference.
- Mention warnings that affect confidence.
- Keep transcript excerpts short unless the user asks for extensive quotes.
- Do not fabricate speakers, slide contents, UI text, numbers, decisions, or work items.
- If evidence is insufficient, state what is missing and recommend concrete MCP arguments for a rerun.
