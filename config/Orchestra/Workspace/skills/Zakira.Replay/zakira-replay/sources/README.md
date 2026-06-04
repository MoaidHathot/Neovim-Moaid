# Source profiles

Per-source recommendations for `zakira-replay`. Each profile names the recommended capture mode, flag combinations, expected artifacts, known limitations, and warning codes specific to that source — so the main skills stay compact and you only pay the context cost when handling a URL the index recognises.

## How to use this directory

When the source is a URL (not a local file), match the URL's host against the table below and read **only the matching profile file**. The skill defaults documented in [`zakira-replay-cli/SKILL.md`](../../zakira-replay-cli/SKILL.md) and [`zakira-replay-mcp/SKILL.md`](../../zakira-replay-mcp/SKILL.md) apply for hosts not in the table.

The lookup is **advisory**, not gating: an unknown host is fine, just fall back to the skill defaults.

## Index

| Source | URL patterns | Profile | Status | Last verified |
|---|---|---|---|---|
| Microsoft Build | `build.microsoft.com/*/sessions/*` | [microsoft-build.md](microsoft-build.md) | working | 2026-06-04 |
| Microsoft Medius | `medius.studios.ms/Embed/*`, `medius.microsoft.com/Embed/*`, `medius*.event.microsoft.com/Embed/*` | [microsoft-medius.md](microsoft-medius.md) | working | 2026-06-04 |
| SharePoint Stream / Microsoft Stream | `*.sharepoint.com/.../stream.aspx?id=*`, `*.microsoftstream.com/*` | [sharepoint-stream.md](sharepoint-stream.md) | working | 2026-06-04 |
| YouTube (public + age-gated) | `youtube.com/watch?v=*`, `youtu.be/*`, `*.youtube.com/embed/*` | [youtube.md](youtube.md) | working | 2026-06-04 |

`status` values:

- `working` — verified end-to-end on a real session; numbers in the profile are measured.
- `partial` — the basics work; some flag combinations / edge cases unverified.
- `needs-verification` — schema-only profile, contributions welcome.

## How to add a new source

1. Copy [`_TEMPLATE.md`](_TEMPLATE.md) to `<source-slug>.md` in this directory.
2. Fill in every section. Leave a section empty by saying "none known" rather than deleting it — the section structure is the contract.
3. Add a row to the index table above, in alphabetical-ish order, with an honest `status` value.
4. If you measured timings or recipe steps end-to-end, include the run id, version, and date in the profile body so the next maintainer can re-run.
5. Commit with a message like `docs(sources): add <source-name> profile`.

No code changes required. The CLI and MCP skills already point at this directory.

## Frontmatter convention

Every profile starts with YAML frontmatter. No tool currently consumes it, but the shape lets us auto-generate the index later or build per-host runtime hints. Schema:

```yaml
---
name: Display name as humans say it
status: working | partial | needs-verification
hostPatterns:
  - bare.hostname.com               # case-insensitive exact host match
  - "*.suffix.example.com"          # leading *. = suffix wildcard
urlPatterns:
  - https://example.com/path/*      # glob example for humans + future tooling
underlyingPlayer: short label       # Shaka MSE | HLS native | MP4 | YouTube iframe | etc.
authNeeded: none | cookies | dedicated-edge-profile
lastVerified: YYYY-MM-DD
zakiraReplayVersion: 0.10.1+        # earliest version the recipe is known to work on
---
```

Keep frontmatter values terse and machine-friendly; put nuance in the body.
