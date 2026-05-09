# VideoWatcher Prompt Examples

## Summarize A Video

User prompt:

```text
Summarize this video and include timestamps for the main claims: https://example.com/video
```

Agent behavior:

- Start `create_analysis_job` with `frames: 7`, `frameStrategy: "scene"`, `cache: true`, and `summary: true`.
- Add `ocr: true` and `vision: true` if slides, UI, code, or diagrams matter.
- Poll until succeeded.
- Read `manifest.json`, `evidence.json`, and `transcript.md`.
- If exact transcript fidelity matters, inspect `transcript/normalization.json` and `transcript/raw.md` before quoting.
- Produce a timestamped summary and mention warnings.

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
{"name":"build_search_index","arguments":{"runDirectory":"<artifact-directory>","backend":"sqlite-onnx"}}
{"name":"query_search_index","arguments":{"target":"<artifact-directory>","query":"model evaluation","backend":"sqlite-onnx","top":5}}
```

## Analyze Visual Content

User prompt:

```text
Review the dashboard shown in this demo and list the visible metrics: https://example.com/demo
```

Agent behavior:

- Use `frames: 12`, `frameStrategy: "scene"`, `ocr: true`, `vision: true`, and `cache: true`.
- Inspect `ocr/combined.md`, `vision/combined.md`, and frame images.
- Separate visible text from inferred meaning.

## Protected Video

User prompt:

```text
Analyze this course video. I am logged into it in Edge: https://example.com/course/video
```

Agent behavior:

- Use `browserAuth: "edge"`.
- If access fails, ask the user for a cookies file or confirm browser/session access.

## Batch Orchestration

User prompt:

```text
Analyze all videos in this manifest and make study notes from the evidence.
```

Agent behavior:

- Use `videowatcher batch run <manifest.json>` if working through CLI.
- Use MCP jobs one-by-one if the orchestrator needs progress control.
- After artifacts are ready, synthesize study notes from each `evidence.json` and `transcript.md`.

## Build Chapters

User prompt:

```text
Create chapter markers for this video and include supporting evidence.
```

Agent behavior:

- Analyze the video with transcript extraction.
- Call `build_chapters` with the completed run directory.
- Read `chapters/chapters.json` and cite chapter evidence timestamps.
