---
name: <Display name>
status: needs-verification
hostPatterns:
  - <bare.host.com>
urlPatterns:
  - <https://example.com/pattern/*>
underlyingPlayer: <Shaka MSE | HLS native | MP4 | YouTube iframe | DASH | other>
authNeeded: <none | cookies | dedicated-edge-profile>
lastVerified: <YYYY-MM-DD>
zakiraReplayVersion: 0.10.1+
---

# <Display name>

One-sentence "what this source is" so an agent that landed here from the index knows it's in the right place.

## What works

- **Transcript:** <yes via captions / yes via STT / no — needs --stt + --allow-media-download>
- **Frames:** <yes via direct URL / requires --prefer-inline-media / requires --allow-media-download>
- **Session metadata** (`manifest.sessionMetadata`): <yes / partial — only title / no>
- **Deep links** (chapters, search matches): <site-specific format used | W3C `#t=` fragments fallback>
- **Captions languages observed:** <e.g. en, fr, es | unknown — single language only>
- **Auth:** <public | sign-in via dedicated Edge profile | cookies-from-browser>

## Recommended commands

### Single session — CLI

```pwsh
zakira-replay analyze "<example URL>" `
  --capture-mode <ytdlp|browser|auto> [other flags]
```

### Single session — MCP

```json
{
  "tool": "analyze.start",
  "arguments": {
    "source": "<example URL>",
    "captureMode": "<ytdlp|browser|auto>"
  }
}
```

### Conference / batch / sweep (when relevant)

```pwsh
zakira-replay queue enqueue "<example URL>" --queue-id <id> [flags]
zakira-replay queue run --queue-id <id> --concurrency <N> --retries 2
```

### Spot frames (when relevant)

```pwsh
zakira-replay frames "<example URL>" --at "<MM:SS,MM:SS>"
```

## Known limitations

- <e.g. "scene strategy downloads the full HLS; use interval">
- <e.g. "DRM-protected content cannot be captured">
- "none known" if everything works.

## Source-specific warning codes

- `<CODE>` (severity): <one-line meaning + what an agent should do about it>

If no source-specific codes exist, say "none — the standard warning codes from the CLI/MCP skill apply".

## Gotchas

Things that look like failures but are actually expected for this source.

- <e.g. "`CAPTURE_DURATION_UNRESOLVED` is expected when using `--prefer-inline-media`; the sidestep still produces frames">

## Measured run (optional, but include when you have it)

- Source: <URL or session code>
- Command: <exact command>
- Run id: <id>
- Elapsed: <Ns>
- Artifacts produced: <e.g. "3 frames, transcript.md 210 KB, en VTT 217 KB">
- Zakira.Replay version: <version>
- Date: <YYYY-MM-DD>

---

> Replace every `<placeholder>` with concrete content, drop sections that don't apply (but **keep the section headers**, marked "none known" — the structure is the contract), and add an index row in [`README.md`](README.md).
