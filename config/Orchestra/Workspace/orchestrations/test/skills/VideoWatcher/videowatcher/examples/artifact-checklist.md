# Artifact Checklist

Use this checklist after a VideoWatcher job succeeds.

## Required First Reads

- `manifest.json`: confirm paths, produced artifacts, warnings, and run ID.
- `evidence.json`: load structured evidence and warnings.

## Transcript Evidence

- Read `transcript.md` when present.
- Use `transcript/raw.md`, `transcript/raw.json`, and `transcript/normalization.json` when you need to audit whether caption normalization merged or removed repeated fragments.
- Prefer timestamped transcript segments for claims and quotes.
- If transcript is absent and audio matters, rerun with `stt: true`.

## Visual Evidence

- Read `ocr/combined.md` for visible text from frames.
- Read `vision/combined.md` for visual descriptions.
- Inspect frame files when the user asks about layout, diagrams, UI, code, charts, or visual details.
- If frames are sparse, rerun with more `frames` or `frameStrategy: "scene"`.

## Search Evidence

- Build `search/index.json` for repeated Q&A over a run.
- Query the index before reading the full transcript when the user asks about a specific topic.
- Treat search matches as pointers into evidence, not final answers by themselves.

## Clips

- Use clip extraction only when start/end timestamps are known or can be justified from artifacts.
- Save clip paths from `clip.json` and report them with the timestamp range.

## Warnings

- Include relevant warnings in the final response.
- Treat missing captions, missing media URL, failed OCR, failed vision, and fallback downloads as confidence modifiers.

## Response Quality

- Cite timestamps where possible.
- Keep raw transcript excerpts short unless the user asks for extensive quotes.
- Do not invent speaker names, slides, charts, or numbers not present in artifacts.
- If evidence is insufficient, say so and recommend a concrete rerun option.
