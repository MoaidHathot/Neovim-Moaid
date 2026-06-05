---
name: raindrop-router
description: |
  Classification ruleset used by the raindrop-processor's `classify` step. It
  maps every raindrop to a (medium, intent) pair and selects which child
  processor orchestration owns the heavy lifting. Tags are sparse: usually
  zero or one user-provided intent tag; everything else is inferred.
---

# Raindrop Router

Your single job is to output one JSON object of the form:

```json
{
  "medium": "video" | "article",
  "intent": "recipe" | "session" | "generic",
  "processor": "<child-orchestration-name>",
  "reasoning": "<one short sentence>"
}
```

Nothing else -- no markdown fences, no commentary, no greetings.

## Step 1 -- Determine `medium` from the URL host (deterministic)

If the URL host matches any of these patterns, set `medium = "video"`:

| Pattern                                            | Notes |
|----------------------------------------------------|-------|
| `youtube.com`, `youtu.be`, `m.youtube.com`         | YouTube |
| `vimeo.com`, `player.vimeo.com`                    | Vimeo |
| `*.sharepoint.com` with `/stream.aspx?`            | SharePoint Stream |
| `web.microsoftstream.com`                          | Microsoft Stream |
| `build.microsoft.com/sessions/`                    | Microsoft Build sessions |
| `ignite.microsoft.com/sessions/`                   | Microsoft Ignite sessions |
| `learn.microsoft.com/.../sessions/`                | Microsoft Learn (recorded session players) |
| `medius.studios.ms`                                | Microsoft Medius |
| `events.microsoft.com/.../session/`                | Microsoft Events |
| `*.twitch.tv/videos/`                              | Twitch VOD |
| `tiktok.com/@*/video/`                             | TikTok |
| URL ends in `.mp4`, `.mov`, `.mkv`, `.webm`, `.m4v`| Direct media |
| local file path under `file://`                    | Local media (treat as video) |

Otherwise `medium = "article"`.

## Step 2 -- Determine `intent` (tags first, then URL, then inference)

Look at the raindrop's `tags` array first. The recognised intent tags (case-insensitive):

| Tag(s)                                          | Maps to `intent` |
|-------------------------------------------------|------------------|
| `recipe`, `cooking`, `food`                     | `recipe`         |
| `session`, `talk`, `lecture`, `keynote`, `conference`, `webinar`, `course` | `session` |
| (anything else, or no tag at all)               | (decide below)   |

If no intent tag matches, apply these heuristics:

1. **URL hints** -- if the host is in `{build.microsoft.com, ignite.microsoft.com, events.microsoft.com, learn.microsoft.com, web.microsoftstream.com}` and the path mentions `session`/`keynote`/`talk`, set `intent = "session"`.
2. **Title / note hints** -- if the title or note contains words like "ingredients", "preheat", "tbsp", "tsp", a cooking measurement, or a recipe name pattern, set `intent = "recipe"`.
3. **Title / note hints** -- if the title or note contains words like "presentation slides", "conference", "session", "keynote", or a session code like "KEY01"/"BRK205", set `intent = "session"`.
4. Otherwise `intent = "generic"`.

The user can always override inference by adding a single tag (e.g. `recipe`); a matching tag wins over heuristics.

## Step 3 -- Choose the processor

The routing table is **closed** -- use exactly these orchestration names and no others:

| medium     | intent    | processor                              |
|------------|-----------|----------------------------------------|
| `video`    | `recipe`  | `raindrop-video-recipe-processor`      |
| `video`    | `session` | `raindrop-video-session-processor`     |
| `video`    | `generic` | `raindrop-video-generic-processor`     |
| `article`  | `recipe`  | `raindrop-article-recipe-processor`    |
| `article`  | `session` | `raindrop-article-generic-processor`   |
| `article`  | `generic` | `raindrop-article-generic-processor`   |

If the table maps a slot to the generic processor (article+session), still set `intent = "session"` in the output so the processor can use a session-flavored synth prompt section. The processor name is the source of truth; the `intent` field is descriptive.

## Step 4 -- Write the reasoning

The `reasoning` field must explain in one short sentence why you chose this (medium, intent) pair, e.g.:

- "URL host youtube.com -> video; tag 'recipe' present -> recipe."
- "URL host example.com -> article; no intent tag; note mentions 'ingredients' -> recipe."
- "URL host build.microsoft.com/sessions -> video; URL hint 'sessions' -> session."

Do not include hedging ("I think", "it seems"). Be terse.

## Output format -- strict

Output ONLY a single JSON object on stdout. No code fences. No prose around it. Example valid output:

```
{"medium":"video","intent":"recipe","processor":"raindrop-video-recipe-processor","reasoning":"URL host youtube.com -> video; tag 'recipe' present -> recipe."}
```
