---
name: creating-review-actionview-entry
description: Creates an ActionView entry of type 'pr-review-summary' from PowerReview draft comments and consolidated review data. Produces a structured JSON entry with PR metadata, per-comment details (reviewer name, file, severity, code diff), per-comment approve/delete actions, and entry-level bulk actions (approve all, submit, vote, delete all). Use after all PR reviewers have finished creating their draft comments and the consolidated review is available.
compatibility: Requires the PowerReview MCP server connected via stdio. Requires the ActionView entry schema (fetched at runtime or embedded). Requires a completed review with drafts in the PowerReview session.
---

# Creating a PR Review ActionView Entry

This skill tells you how to build an ActionView entry of type `pr-review-summary` from PowerReview review data. The entry is a structured JSON object that the user views in the ActionView dashboard to review, approve, and submit AI-generated PR comments.

## When to use this skill

Use this skill in the `create-action-view-entry` step of a PR review orchestration, **after**:
1. All reviewer agents have finished creating draft comments via PowerReview
2. The consolidated review summary is available

## Prerequisites

- A PowerReview session is open for the PR
- The PR URL (`prUrl`) is known
- The consolidated review JSON is available (from the consolidation step)
- The ActionView entry schema is available (fetched via `actionview schema` or provided)

## Data collection

Before building the entry, you must collect data from PowerReview. The consolidated review gives you summary-level data, but **you also need the individual drafts** for per-comment sections and action buttons.

### Step 1: Get PR metadata

Call `GetReviewSession(prUrl)` to get:

```json
{
  "pull_request": {
    "id": 42,
    "title": "Add input validation",
    "url": "https://dev.azure.com/org/project/_git/repo/pullrequest/42",
    "source_branch": "feature/validation",
    "target_branch": "main",
    "author": { "name": "John Doe" }
  },
  "files": [
    { "path": "src/main.cs", "change_type": "Edit" }
  ]
}
```

### Step 2: Get all draft comments

Call `ListCommentThreads(prUrl)` to get all threads and drafts. The response includes a `drafts` array:

```json
{
  "drafts": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "draft": {
        "file_path": "src/main.cs",
        "line_start": 42,
        "line_end": 45,
        "body": "bug: Null reference possible here when `user` is not found.",
        "status": "Draft",
        "author": "Ai",
        "author_name": ".NET Expert",
        "created_at": "2026-04-13T10:00:00Z"
      }
    }
  ]
}
```

Key fields for each draft:
- `id` -- the draft UUID, needed for per-comment action commands
- `draft.file_path` -- the file this comment is on
- `draft.line_start` / `draft.line_end` -- line range
- `draft.body` -- the comment text
- `draft.author_name` -- which reviewer agent wrote this (e.g. ".NET Expert", "Security Expert")

### Step 3: Get code diffs for commented files

For each unique file that has comments, call `GetFileDiff(prUrl, filePath)` to get the unified diff. You'll use this to show code context next to each comment.

You don't need the full file diff for every file -- only for files that have draft comments on them.

## Building the entry

### Entry-level fields

```json
{
  "schemaVersion": "1",
  "type": "pr-review-summary",
  "source": "<orchestration name>",
  "title": "PR Review: <PR title>",
  "subtitle": "<overall status> | <total comments> comments",
  "severity": "<mapped from overall status>",
  "icon": "git-pull-request",
  "tags": ["pr-review", "code-review", "ZTS", "<overall status>"]
}
```

Severity mapping:
- `needs-work` or has critical issues -> `"high"`
- `approved-with-suggestions` -> `"medium"`
- `approved` -> `"low"`

### Content blocks (in order)

#### 1. Alert (optional)

Only include if there are critical or blocking issues:

```json
{
  "type": "alert",
  "level": "error",
  "body": "This PR has <N> critical issues that must be addressed before merging."
}
```

#### 2. PR metadata (keyValue)

```json
{
  "type": "keyValue",
  "label": "Pull Request",
  "pairs": {
    "Repository": "<org>/<project>/<repo>",
    "Branch": "<source_branch> -> <target_branch>",
    "Author": "<author name>",
    "Files Changed": "<count>",
    "Lines": "+<added> / -<removed>"
  }
}
```

#### 3. Review Summary table

One row per reviewer agent, from the consolidated review's `reviewerSummaries`:

```json
{
  "type": "table",
  "label": "Review Summary",
  "columns": ["Reviewer", "Status", "Comments", "Critical Issues"],
  "rows": [
    [".NET Expert", "approved-with-suggestions", "3", "0"],
    ["Principal Engineer", "approved", "1", "0"],
    ["Security Expert", "needs-work", "2", "1"],
    ["DTFx Expert", "approved", "0", "0"]
  ]
}
```

#### 4. Review Comments section (required -- one nested section per draft comment)

This is the most important section. Each draft comment becomes a nested section with:

**a) keyValue "Details"** -- comment metadata:

```json
{
  "type": "keyValue",
  "label": "Details",
  "pairs": {
    "Reviewer": "<draft.author_name, e.g. '.NET Expert'>",
    "File": "<draft.file_path>",
    "Lines": "<draft.line_start>-<draft.line_end>",
    "Severity": "<extracted from body prefix: nit/suggestion/bug/critical>",
    "Draft ID": "<draft UUID>"
  }
}
```

To extract severity: check if the comment body starts with `nit:`, `suggestion:`, `bug:`, or `critical:`. If no prefix, use `"info"`.

**b) markdown "Comment"** -- the comment text:

```json
{
  "type": "markdown",
  "label": "Comment",
  "body": "<draft.body>"
}
```

**c) code "Code"** (optional) -- the relevant code diff:

```json
{
  "type": "code",
  "label": "Code",
  "language": "diff",
  "filename": "<draft.file_path>",
  "body": "<relevant portion of the file diff around the commented lines>"
}
```

Extract the relevant hunk from the full file diff that covers the commented line range. If the diff is short enough, you can include the entire file diff. Use `language: "diff"` for unified diff format, or use the file's language (e.g., `"csharp"`) if showing the raw code instead of a diff.

**d) Per-comment actions:**

```json
{
  "actions": [
    {
      "label": "Approve",
      "style": "success",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["comment", "approve", "--pr-url", "<prUrl>", "--draft-id", "<draft UUID>"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Delete",
      "style": "danger",
      "confirmMessage": "Delete this draft comment?",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["comment", "delete", "--pr-url", "<prUrl>", "--draft-id", "<draft UUID>"]
      },
      "onSuccess": "keep"
    }
  ]
}
```

**Put it all together** -- a complete nested section for one comment:

```json
{
  "type": "section",
  "title": "<file_path>:<line_start> - <severity prefix or first ~50 chars of body>",
  "content": [
    {
      "type": "keyValue",
      "label": "Details",
      "pairs": {
        "Reviewer": ".NET Expert",
        "File": "src/main.cs",
        "Lines": "42-45",
        "Severity": "bug",
        "Draft ID": "550e8400-e29b-41d4-a716-446655440000"
      }
    },
    {
      "type": "markdown",
      "label": "Comment",
      "body": "bug: Null reference possible here when `user` is not found."
    },
    {
      "type": "code",
      "label": "Code",
      "language": "diff",
      "filename": "src/main.cs",
      "body": "@@ -40,6 +40,8 @@\n     var user = await _repo.FindAsync(id);\n-    return user.Name;\n+    return user.Name; // potential NullReferenceException"
    }
  ],
  "actions": [
    {
      "label": "Approve",
      "style": "success",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["comment", "approve", "--pr-url", "https://dev.azure.com/org/project/_git/repo/pullrequest/42", "--draft-id", "550e8400-e29b-41d4-a716-446655440000"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Delete",
      "style": "danger",
      "confirmMessage": "Delete this draft comment?",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["comment", "delete", "--pr-url", "https://dev.azure.com/org/project/_git/repo/pullrequest/42", "--draft-id", "550e8400-e29b-41d4-a716-446655440000"]
      },
      "onSuccess": "keep"
    }
  ]
}
```

Repeat this for **every draft comment** in the session.

#### 5-11. Expert sections (optional)

These sections are optional and provide a per-reviewer breakdown. They can contain markdown summaries from the consolidated review. Include them if the consolidated review provides per-reviewer narrative findings beyond what's in the individual comments.

- "Critical & Blocking Issues"
- ".NET Expert Findings"
- "Architecture & Design"
- "Security Findings"
- "Durable Tasks Review"
- "Test Coverage Assessment"
- "Requirements Alignment"

#### 12. Full Review Report (optional)

```json
{
  "type": "markdown",
  "label": "Full Review Report",
  "body": "<executive summary from consolidated review>"
}
```

#### 13. View PR link

```json
{
  "type": "link",
  "label": "View PR",
  "url": "<PR URL>",
  "body": "Open pull request in browser"
}
```

### Entry-level actions

These are the buttons at the top/bottom of the entry:

```json
{
  "actions": [
    {
      "label": "Open PR",
      "style": "primary",
      "command": {
        "type": "cli",
        "program": "cmd.exe",
        "args": ["/c", "start", "<prUrl>"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Approve All",
      "style": "success",
      "confirmMessage": "Approve all draft comments?",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["comment", "approve-all", "--pr-url", "<prUrl>"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Submit Review",
      "style": "success",
      "confirmMessage": "Submit all pending comments to Azure DevOps?",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["submit", "--pr-url", "<prUrl>"]
      },
      "onSuccess": "archive"
    },
    {
      "label": "Approve PR",
      "style": "success",
      "confirmMessage": "Cast an 'Approved' vote on this PR?",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["vote", "--pr-url", "<prUrl>", "--value", "approve"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Wait for Author",
      "style": "default",
      "confirmMessage": "Cast a 'Wait for Author' vote on this PR?",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["vote", "--pr-url", "<prUrl>", "--value", "wait-for-author"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Delete All",
      "style": "danger",
      "confirmMessage": "Delete ALL AI-authored draft comments? This cannot be undone.",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["comment", "delete-all", "--pr-url", "<prUrl>", "--author", "ai"]
      },
      "onSuccess": "archive"
    }
  ]
}
```

## Data mapping reference

| PowerReview Source | ActionView Target |
|---|---|
| `session.pull_request.title` | Entry `title`: `"PR Review: <title>"` |
| `session.pull_request.url` | "Open PR" action URL, "View PR" link URL, all action `--pr-url` args |
| `session.pull_request.source_branch` / `target_branch` | "Pull Request" keyValue `Branch` |
| `session.pull_request.author.name` | "Pull Request" keyValue `Author` |
| `session.files.length` | "Pull Request" keyValue `Files Changed` |
| `consolidated.overallStatus` | Entry `subtitle`, `severity`, `tags` |
| `consolidated.totalComments` | Entry `subtitle` |
| `consolidated.totalCriticalIssues` | Alert block (if > 0) |
| `consolidated.reviewerSummaries` | "Review Summary" table rows |
| `consolidated.executiveSummary` | "Full Review Report" markdown body |
| `consolidated.crossCuttingConcerns` | Expert sections content |
| `consolidated.requirementsAlignment` | "Requirements Alignment" section |
| `draft.id` (UUID) | Per-comment `--draft-id` in Approve/Delete actions |
| `draft.author_name` | Per-comment "Details" keyValue `Reviewer` |
| `draft.file_path` | Per-comment "Details" keyValue `File`, nested section `title` |
| `draft.line_start` / `line_end` | Per-comment "Details" keyValue `Lines` |
| `draft.body` prefix | Per-comment "Details" keyValue `Severity` |
| `draft.body` | Per-comment "Comment" markdown body |
| `fileDiff.diff` (hunk) | Per-comment "Code" block body |

## Checklist

Before saving the entry, verify:

```
Entry Checklist:
- [ ] type is "pr-review-summary"
- [ ] source is the orchestration name
- [ ] title includes the PR title
- [ ] severity is mapped from overall status
- [ ] PR metadata keyValue block is present
- [ ] Review Summary table has one row per reviewer
- [ ] Every draft comment has its own nested section
- [ ] Every nested section has Details (keyValue), Comment (markdown), and optionally Code
- [ ] Every nested section has Approve and Delete actions with the correct draft UUID
- [ ] All action commands use the correct prUrl
- [ ] Entry-level actions include: Open PR, Approve All, Submit Review, Approve PR, Wait for Author, Delete All
- [ ] View PR link is present with the correct URL
```

## Important notes

- **Draft IDs are critical.** Without them, the per-comment Approve/Delete buttons won't work. Make sure every draft comment's UUID is included in both the "Details" keyValue and the action command args.
- **The `author_name` field** on drafts identifies which reviewer agent created the comment. If reviewer agents don't pass `agentName` when calling `CreateComment`, this field will be null. Make sure the orchestration's reviewer prompts include `agentName`.
- **Code diffs are optional but valuable.** If fetching per-file diffs is too expensive, the entry still works without them -- the user can read the comment text and navigate to the file manually.
- **Save the entry using `orchestra_save_file`.** The orchestration's next step will submit it to ActionView via `actionview add --file <path>`.

