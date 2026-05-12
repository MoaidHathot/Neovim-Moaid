# PowerReview MCP Tool Reference

Complete API documentation for all PowerReview MCP server tools.

The MCP server name is `PowerReview`. Tools are listed below by their short name (e.g., `SyncThreads`). When calling via MCP, the server may prefix the tool name depending on your MCP client configuration.

All tools return JSON. Errors are returned as `{ "error": "message" }`.

## Contents

- Read-only tools (session, PR description, files, diff, threads, draft counts)
- Sync and iteration tools (sync threads, check iteration, iteration diff)
- New-replies tools (get new replies, acknowledge replies)
- Write tools (create comment/reply drafts, edit/delete drafts, create draft operations)
- Working directory and file access tools (working directory, read file, list files)
- Fix worktree tools (prepare worktree, get path, create branch)
- Proposal tools (create proposal, list proposals, get proposal diff)

---

## GetReviewSession

Get PR review session metadata.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |

**Returns:** Session object with fields:

```json
{
  "id": "azdo_org_project_repo_123",
  "provider": { "type": "AzDo", "organization": "...", "project": "...", "repository": "..." },
  "pull_request": {
    "id": 123,
    "url": "https://...",
    "title": "...",
    "description": "...",
    "author": { "name": "...", "unique_name": "..." },
    "source_branch": "feature/...",
    "target_branch": "main",
    "status": "Active",
    "is_draft": false,
    "merge_status": "Succeeded",
    "created_at": "2025-01-01T00:00:00Z",
    "closed_at": null,
    "reviewers": [{ "name": "...", "vote": 0, "vote_label": "no_vote", "is_required": true }],
    "labels": [],
    "work_items": [{ "id": 456, "title": "...", "url": "...", "type": "Bug", "state": "Active" }]
  },
  "iteration": {
    "id": 3,
    "source_commit": "abc123...",
    "target_commit": "def456..."
  },
  "review": {
    "reviewed_iteration_id": 2,
    "reviewed_source_commit": "999888...",
    "reviewed_files": ["src/file.cs"],
    "changed_since_review": ["src/other.cs"]
  },
  "files": [...],
  "draft_operations": { "uuid-1": { ... }, "uuid-2": { ... } },
  "metadata": {
    "reviewers": { "total": 3, "required": 1, "required_pending": 1, "rejected": 0 },
    "files": { "total": 5, "added": 1, "edited": 3, "deleted": 0, "renamed": 1 },
    "threads": { "total": 4, "active": 2, "pending": 0, "line_level": 3, "pr_level": 1 },
    "draft_operations": {
      "total": 2,
      "draft": 2,
      "pending": 0,
      "submitted": 0,
      "ai_authored": 2,
      "comments": 1,
      "replies": 1,
      "thread_status_changes": 0,
      "comment_reactions": 0
    },
    "work_items": { "total": 1, "by_type": { "Bug": 1 }, "by_state": { "Active": 1 } },
    "review": { "reviewed_files": 1, "changed_since_review": 0, "unreviewed_files": 4, "total_files": 5 },
    "iteration": { "id": 3, "source_commit": "abc123...", "target_commit": "def456..." },
    "state": { "status": "active", "is_draft": false, "merge_status": "succeeded", "has_merge_conflicts": false, "vote_label": "no_vote" },
    "timestamps": { "updated_at": "2025-01-01T00:00:00Z", "threads_synced_at": "2025-01-01T00:00:00Z" }
  },
  "vote": null,
  "git": { "repo_path": "...", "worktree_path": "...", "strategy": "Worktree" }
}
```

The `metadata` block is derived from the session and is useful for AI agents deciding review priority, readiness, remaining unresolved feedback, and stale session risk.

**Error:** `"No session found for this PR. Run 'powerreview open --pr-url <url>' first."`

---

## GetPullRequestDescription

Get the full pull request description, title, metadata, reviewers, labels, and work items. Returns the complete PR context useful for understanding what the PR is about.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |

**Returns:**

```json
{
  "title": "Add input validation to user registration",
  "description": "This PR adds server-side validation...",
  "author": { "name": "John Doe", "id": "c3d4e5f6-..." },
  "source_branch": "feature/user-validation",
  "target_branch": "main",
  "status": "Active",
  "is_draft": false,
  "merge_status": "Succeeded",
  "created_at": "2026-03-27T10:00:00Z",
  "closed_at": null,
  "reviewers": [
    { "name": "Alice Smith", "vote": 0, "vote_label": "no_vote", "is_required": true }
  ],
  "labels": ["backend", "validation"],
  "work_items": [
    { "id": 1234, "title": "Implement input validation", "url": "https://...", "type": "User Story", "state": "Active", "tags": ["backend"] }
  ],
  "metadata": { "reviewers": { "required_pending": 1 }, "threads": { "active": 2 } }
}
```

**Errors:**
- `"No session found for this PR."` -- no active session

---

## ListChangedFiles

List all files changed in the pull request.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |

**Returns:**

```json
{
  "count": 5,
  "files": [
    { "change_type": "edit", "path": "src/main.cs", "original_path": null },
    { "change_type": "add", "path": "src/new-file.cs", "original_path": null },
    { "change_type": "rename", "path": "src/renamed.cs", "original_path": "src/old-name.cs" },
    { "change_type": "delete", "path": "src/removed.cs", "original_path": null }
  ]
}
```

Change types: `add`, `edit`, `delete`, `rename`.

---

## GetFileDiff

Get the unified git diff for a specific changed file.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `filePath` | string | Yes | Relative file path within the repository |

**Returns:**

```json
{
  "file": { "path": "src/main.cs", "change_type": "edit", "original_path": null },
  "diff": "diff --git a/src/main.cs b/src/main.cs\n..."
}
```

The `diff` field contains the full unified diff output generated from the local PR worktree.

**Errors:**
- `"File 'path' not found in the changed files list."` -- file path doesn't match any changed file
- `"No session found for this PR."` -- no active session
- `"No local git repository available..."` -- session was opened without a local repo/worktree
- `"Failed to generate diff: ..."` -- git error

---

## ListCommentThreads

List all remote comment threads and local draft operations, optionally filtered by file.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `filePath` | string | No | Filter threads to a specific file path |

**Returns:**

```json
{
  "thread_count": 3,
  "draft_count": 2,
  "threads": [
    {
      "id": 1,
      "file_path": "src/main.cs",
      "line_start": 42,
      "line_end": 42,
      "status": "Active",
      "comments": [
        {
          "id": 100,
          "thread_id": 1,
          "author": { "name": "Reviewer" },
          "body": "Consider handling null here",
          "created_at": "2025-01-01T00:00:00Z"
        }
      ]
    }
  ],
  "draft_operations": [
    {
      "id": "uuid-1",
      "operation": {
        "operation_type": "Comment",
        "file_path": "src/main.cs",
        "line_start": 50,
        "body": "This could throw...",
        "status": "Draft",
        "author": "Ai"
      }
    }
  ]
}
```

Thread statuses: `Active`, `Fixed`, `WontFix`, `Closed`, `ByDesign`, `Pending`.

---

## GetDraftCounts

Get a summary of draft operation counts by status and kind.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |

**Returns:**

```json
{
  "draft": 3,
  "pending": 1,
  "submitted": 2,
  "total": 6,
  "comments": 3,
  "replies": 2,
  "thread_status_changes": 1,
  "comment_reactions": 0
}
```

---

## SyncThreads

Sync comment threads from the remote provider (e.g., Azure DevOps). Updates the
local session with the latest threads and checks for new iterations.

Also computes a **reply-classification delta** against the snapshot taken on the
previous sync, writes it to the session's `last_deltas`, and returns a count
summary in the response. Call this before reading threads to ensure you have
the most up-to-date data. To fetch the actual new replies after a sync, call
`GetNewReplies`.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |

**Returns:**

```json
{
  "synced": true,
  "thread_count": 8,
  "iteration_check": {
    "old_iteration_id": 2,
    "new_iteration_id": 3,
    "has_new_iteration": true,
    "changed_files": ["src/main.cs", "src/utils.cs"],
    "review": {
      "reviewed_iteration_id": 3,
      "reviewed_source_commit": "abc123...",
      "reviewed_files": ["src/config.cs"],
      "changed_since_review": ["src/main.cs", "src/utils.cs"]
    }
  },
  "silent_priming": false,
  "deltas": {
    "reply_to_ai": 1,
    "reply_to_human": 0,
    "reply_in_others_thread": 4,
    "new_thread_others": 1
  }
}
```

- When no new iteration is detected, `iteration_check` is `null`.
- `silent_priming: true` (with `deltas: null`) means this was the **first sync
  after the session was upgraded to schema v8 or after the snapshot was
  cleared**. The classifier intentionally produces no deltas in this case to
  avoid flagging every existing comment as "new". Treat the session as caught
  up; rely on `ListCommentThreads` for the current state.
- `deltas` counts only **unacked** comments. After calling
  `AcknowledgeReplies` on a thread, those comments are excluded from future
  syncs' deltas.

**Bucket definitions** (see `GetNewReplies` for full schema):

| Bucket | Meaning |
|---|---|
| `reply_to_ai` | New/edited comments on threads where the AI participated (via published drafts). Highest priority for AI follow-up. |
| `reply_to_human` | New/edited comments on threads where the local human user participated, AI did not. |
| `reply_in_others_thread` | New/edited comments on threads where neither the local user nor AI ever participated. |
| `new_thread_others` | Brand-new threads opened by someone other than the local user / AI. |

The classifier also computes a `self_echo` bucket for our own publishes
reflected back from the server; it is never surfaced as actionable. Comments
authored by the local user (matched by id from `local_identity`) or by AI
(matched via `published_comment_id`) are always routed to `self_echo`.

**Errors:**
- `"No session found for this PR."` -- no active session
- Provider-specific sync errors

---

## GetNewReplies

Get new/edited comments since the previous sync, classified by recipient. Reads
from the cached `last_deltas` populated by `SyncThreads` — does **not** make a
remote call. Comments already covered by an `AcknowledgeReplies` watermark are
suppressed.

Use this as the primary discovery path for "what does the AI need to respond
to?" — it returns only actionable items, grouped by thread, with a body preview
so you can decide whether to fetch the full thread.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `scope` | string | No | Filter scope (default: `"to_me"`). See below. |
| `threadId` | number | No | Limit to a single thread id. |

**Scope values:**

| Scope | Returns |
|---|---|
| `"to_ai"` | Replies on threads where AI participated (most relevant for AI follow-up). |
| `"to_me"` *(default)* | `to_ai` + replies on threads where the human user participated. Recommended default for AI agents assisting the user. |
| `"to_others"` | Replies on threads with no local participation + new threads opened by others (full-PR awareness). |
| `"all"` | Union of all actionable buckets (excludes `self_echo`). |
| `"self_echo"` | Debug: our own published comments reflected back. UI/AI should never act on these. |

**Returns:**

```json
{
  "scope": "to_me",
  "computed_at": "2026-05-11T10:00:00Z",
  "total_comments": 1,
  "threads": [
    {
      "thread_id": 123,
      "file_path": "src/foo.cs",
      "comments": [
        {
          "thread_id": 123,
          "comment_id": 789,
          "parent_comment_id": null,
          "change": "new",
          "file_path": "src/foo.cs",
          "line_start": 42,
          "line_end": 42,
          "author": {
            "name": "Reviewer Name",
            "id": "00000000-0000-0000-0000-000000000000",
            "unique_name": "reviewer@example.com"
          },
          "created_at": "2026-05-11T09:55:00Z",
          "updated_at": "2026-05-11T09:55:00Z",
          "body_preview": "Could you rename `foo` to `bar` for consistency...",
          "ai_participated": true,
          "human_participated": false
        }
      ]
    }
  ]
}
```

- `change` is `"new"` if the comment id wasn't in the previous snapshot, or
  `"edited"` if the id existed but its `updated_at` changed.
- `body_preview` is the first 200 chars of the body collapsed to a single line.
- `ai_participated` / `human_participated` describe the **thread**, not the
  individual comment, so the AI can decide whether to keep the conversation
  going or hand it back to the user.

**Workflow:** call `SyncThreads` first, then call `GetNewReplies` to fetch the
detail. After acting on a comment, call `AcknowledgeReplies` so it doesn't
re-appear on the next sync.

**Errors:**
- `"No session found for this PR."` -- no active session
- `"Unknown scope '...'"` -- invalid scope value

---

## AcknowledgeReplies

Mark replies as acknowledged by advancing per-thread watermarks. Comments with
`id <= through_comment_id` on a given thread are suppressed from `GetNewReplies`
and from the `deltas` summary on subsequent `SyncThreads` calls.

Watermarks are **monotonic**: calling with a lower id than the existing
watermark is a no-op for that thread (it cannot un-ack).

Use this after the AI has either drafted a follow-up reply or has explicitly
decided to ignore the reply, so the same comment doesn't keep appearing in
`GetNewReplies` forever.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `acks` | string | Yes | Pairs of thread id + through-comment id. Format: `"threadId:throughCommentId"` separated by commas, e.g. `"123:789,456:1011"`. |
| `ackedBy` | string | No | Who is acknowledging: `"ai"` (default for MCP) or `"human"`. Recorded for audit. |

The `through_comment_id` is the highest comment id you have processed on that
thread. Acknowledging through a higher id implicitly acks all lower ids on the
same thread.

**Returns:**

```json
{
  "acknowledged": 2,
  "requested": 3,
  "acked_by": "ai"
}
```

- `requested` is the number of pairs parsed from `acks`.
- `acknowledged` is the number of pairs that actually advanced the watermark
  (i.e. were strictly greater than the existing value). `requested - acknowledged`
  pairs were no-ops because the existing watermark was already at or above the
  requested value.

Side-effect: the call also re-runs reply-classification against the current
threads and the existing snapshot, so the just-acknowledged comments are
removed from `last_deltas` immediately. The next `GetNewReplies` call will
reflect the new state without waiting for the next sync.

**Errors:**
- `"No valid ack pairs provided..."` -- the `acks` string couldn't be parsed
- `"Session not found: ..."` -- no active session

---

## CheckIteration

Check whether the PR author has pushed new commits since your last review. If a new iteration is detected, performs a smart reset: identifies which files changed, removes them from the reviewed list, and updates the review baseline. Returns the list of files that changed between iterations.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |

**Returns:**

```json
{
  "old_iteration_id": 2,
  "new_iteration_id": 3,
  "has_new_iteration": true,
  "changed_files": ["src/main.cs", "src/utils.cs"],
  "review": {
    "reviewed_iteration_id": 3,
    "reviewed_source_commit": "abc123...",
    "reviewed_files": ["src/config.cs"],
    "changed_since_review": ["src/main.cs", "src/utils.cs"]
  }
}
```

When no new iteration exists:

```json
{
  "old_iteration_id": 3,
  "new_iteration_id": 3,
  "has_new_iteration": false,
  "changed_files": [],
  "review": null
}
```

**Errors:**
- `"No session found for this PR."` -- no active session

---

## GetIterationDiff

Get the diff between the previously reviewed iteration and the current iteration for a specific file. This shows only what changed since you last reviewed, not the full PR diff. Requires that a review baseline exists (files must have been marked as reviewed previously).

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `filePath` | string | Yes | Relative file path to get the iteration diff for |

**Returns:**

```json
{
  "file": "src/main.cs",
  "diff": "diff --git a/src/main.cs b/src/main.cs\n..."
}
```

**Errors:**
- `"No session found for this PR."` -- no active session
- Review baseline errors (no previous review to diff against)

---

## CreateComment

Create a new draft review comment on a file and line, or a file-level comment.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `filePath` | string | Yes | Relative file path to comment on |
| `body` | string | Yes | Comment body in markdown format |
| `lineStart` | int | No | Line number (1-indexed). Omit for file-level comments |
| `lineEnd` | int | No | End line for range comments (1-indexed) |
| `colStart` | int | No | Starting column (character offset) within the start line for highlighting a specific word or expression |
| `colEnd` | int | No | Ending column (character offset) within the end line |
| `agentName` | string | No | Name identifying this agent (e.g. "SecurityReviewer", "StyleChecker"). Helps distinguish comments when multiple AI agents review the same PR |

**Returns:**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "draft": {
    "file_path": "src/main.cs",
    "line_start": 42,
    "line_end": null,
    "col_start": null,
    "col_end": null,
    "body": "Consider handling null here",
    "status": "Draft",
    "author": "Ai",
    "author_name": "SecurityReviewer",
    "thread_id": null,
    "created_at": "2025-01-01T00:00:00Z",
    "updated_at": "2025-01-01T00:00:00Z"
  },
  "note": "Draft created. The user must approve it before it can be submitted."
}
```

The comment is always created with `author=Ai` and `status=Draft`.

---

## ReplyToThread

Create a draft reply to an existing remote comment thread.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `threadId` | int | Yes | The remote thread ID to reply to |
| `body` | string | Yes | Reply body in markdown format |
| `agentName` | string | No | Name identifying this agent (e.g. "SecurityReviewer", "StyleChecker"). Helps distinguish comments when multiple AI agents review the same PR |

**Returns:**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "draft": {
    "file_path": "",
    "body": "Good point, I agree this should be handled.",
    "status": "Draft",
    "author": "Ai",
    "author_name": "SecurityReviewer",
    "thread_id": 1
  },
  "note": "Draft reply created. The user must approve it before it can be submitted."
}
```

---

## DraftThreadStatusChange

Create a local draft operation to update a comment thread status after user approval. This does not update the remote provider directly. Use this when you want to propose resolving a thread as fixed/won't-fix/by-design, or reactivate a thread.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `threadId` | int | Yes | The remote thread ID to update after approval |
| `status` | string | Yes | Target thread status. One of: `active`, `fixed`, `wontfix`, `closed`, `bydesign`, `pending` |
| `reason` | string | No | Rationale shown to the user before approval |
| `agentName` | string | No | Name identifying this agent |

**Returns:**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440002",
  "operation": {
    "operation_type": "ThreadStatusChange",
    "status": "Draft",
    "author": "Ai",
    "author_name": "SecurityReviewer",
    "thread_id": 100,
    "from_thread_status": "Active",
    "to_thread_status": "Fixed",
    "note": "The requested fix was implemented."
  },
  "note": "Draft operation created. The user must approve it before submit applies it remotely."
}
```

Valid status values: `active`, `fixed` (also accepts `resolved`), `wontfix` (also accepts `wont-fix`), `closed`, `bydesign` (also accepts `by-design`), `pending`.

The user approves the draft operation and then runs submit; only then is the remote thread status updated.

**Errors:**
- `"Invalid thread status: '<value>'. Use: active, fixed, wontfix, closed, bydesign, pending"` -- unrecognized status
- `"No session found for this PR."` -- no active session

---

## DraftCommentReaction

Create a local draft operation to react to a thread comment after user approval. This does not update the remote provider directly. Currently supported reaction: `like`.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `threadId` | int | Yes | The remote thread ID containing the comment |
| `commentId` | int | Yes | The remote comment ID to react to |
| `reaction` | string | Yes | Reaction to apply after approval. Supported: `like` |
| `reason` | string | No | Rationale shown to the user before approval |
| `agentName` | string | No | Name identifying this agent |

**Returns:**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440003",
  "operation": {
    "operation_type": "CommentReaction",
    "status": "Draft",
    "author": "Ai",
    "author_name": "SecurityReviewer",
    "thread_id": 100,
    "comment_id": 201,
    "reaction": "Like",
    "note": "Acknowledges the reviewer reply."
  },
  "note": "Draft operation created. The user must approve it before submit applies it remotely."
}
```

The user approves the draft operation and then runs submit; only then is the remote reaction applied.

**Errors:**
- `"Invalid reaction: '<value>'. Use: like"` -- unsupported reaction
- `"No session found for this PR."` -- no active session

---

## EditDraftComment

Edit the body of an existing draft comment. Only works on AI-authored drafts.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `draftId` | string | Yes | The draft comment UUID to edit |
| `newBody` | string | Yes | New comment body in markdown format |

**Returns:** Updated draft object. If the draft was previously `Pending`, its status resets to `Draft` (requires re-approval).

**Errors:**
- `"Draft not found: <id>"` -- invalid draft ID
- `"Cannot edit draft: author mismatch"` -- trying to edit a user-authored draft
- `"Cannot edit draft: status is 'Submitted'"` -- submitted drafts are immutable

---

## DeleteDraftComment

Delete a draft comment. Only works on AI-authored drafts in `Draft` status.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `draftId` | string | Yes | The draft comment UUID to delete |

**Returns:** `{ "deleted": true, "id": "..." }`

**Errors:**
- `"Draft not found: <id>"` -- invalid draft ID
- `"Cannot delete draft: author mismatch"` -- trying to delete a user-authored draft
- `"Cannot delete draft: status is 'Pending'"` -- only `Draft` status can be deleted

---

## GetWorkingDirectory

Get the filesystem path to the working directory for a PR review. This is the git worktree (or repo checkout) where the full source code can be read on disk.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |

**Returns:**

```json
{
  "path": "/home/user/projects/my-repo/.power-review-worktrees/42",
  "strategy": "Worktree",
  "repo_path": "/home/user/projects/my-repo"
}
```

- `path` -- the resolved working directory (prefers worktree path, falls back to repo path)
- `strategy` -- the git strategy used (`Worktree`, `Clone`, `Cwd`)
- `repo_path` -- the main repository path (may differ from `path` when using worktrees)

**Errors:**
- `"No session found for this PR."` -- no active session
- `"No local git repository is available for this session."` -- session was opened without a repo path

---

## ReadFile

Read the contents of a file from the PR working directory. The file does not need to be in the changed files list -- you can read any file in the repository. Useful for understanding context, checking callers, reviewing types/interfaces, or reading test files.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `filePath` | string | Yes | Relative file path within the repository (e.g., `src/Services/UserService.cs`) |
| `offset` | int | No | Line number to start reading from (1-indexed, default: 1) |
| `limit` | int | No | Maximum number of lines to return (default: all lines) |

**Returns:**

```json
{
  "path": "src/Services/UserService.cs",
  "content": "using System;\n\nnamespace MyApp.Services;\n\npublic class UserService\n{\n    ...\n}",
  "total_lines": 150,
  "offset": 1,
  "limit": null
}
```

When using `offset` and `limit`:

```json
{
  "path": "src/Services/UserService.cs",
  "content": "    public async Task<User> GetByIdAsync(int id)\n    {\n        ...\n    }",
  "total_lines": 150,
  "offset": 42,
  "limit": 20
}
```

**Errors:**
- `"No session found for this PR."` -- no active session
- `"No local git repository available for this session."` -- no repo path
- `"File not found: 'path'"` -- file does not exist
- `"Cannot read binary file: 'path'"` -- file contains binary content
- `"Path traversal detected: the file path escapes the working directory."` -- security violation

---

## ListRepositoryFiles

List files in the PR repository working directory. Can list all files or filter by subdirectory and/or glob pattern. Useful for discovering project structure and finding related files beyond the PR diff.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `directory` | string | No | Subdirectory path to list (e.g., `src/Services`). Omit to list from root |
| `pattern` | string | No | Glob pattern to filter files (e.g., `*.cs`, `*.ts`). Omit to list all files |
| `recursive` | bool | No | Whether to list files recursively (default: false) |

**Returns (non-recursive):**

```json
{
  "base_path": "src",
  "count": 4,
  "entries": [
    { "name": "Services", "type": "directory", "path": "src/Services" },
    { "name": "Models", "type": "directory", "path": "src/Models" },
    { "name": "Program.cs", "type": "file", "path": "src/Program.cs" },
    { "name": "Startup.cs", "type": "file", "path": "src/Startup.cs" }
  ]
}
```

**Returns (recursive):**

```json
{
  "base_path": "src",
  "count": 5,
  "entries": [
    { "name": "UserService.cs", "type": "file", "path": "src/Services/UserService.cs" },
    { "name": "AuthService.cs", "type": "file", "path": "src/Services/AuthService.cs" },
    { "name": "User.cs", "type": "file", "path": "src/Models/User.cs" },
    { "name": "Program.cs", "type": "file", "path": "src/Program.cs" },
    { "name": "Startup.cs", "type": "file", "path": "src/Startup.cs" }
  ]
}
```

Hidden directories (`.git`, etc.) are automatically excluded. All paths are relative to the repository root.

**Errors:**
- `"No session found for this PR."` -- no active session
- `"No local git repository available for this session."` -- no repo path
- `"Directory not found: 'path'"` -- directory does not exist
- `"Path traversal detected: the directory path escapes the working directory."` -- security violation

---

## PrepareFixWorktree

Prepare an isolated fix worktree for making code changes in response to PR comments. The worktree is created from the PR's source branch. Idempotent: if a worktree already exists, returns its path. Call this before creating fix branches or making code changes.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |

**Returns:**

```json
{
  "worktree_path": "/home/user/projects/my-repo/.power-review-fixes/42",
  "base_branch": "feature/user-validation",
  "created": true,
  "note": "Fix worktree created. Use CreateFixBranch to create a branch for each fix."
}
```

When the worktree already exists, `created` is `false`.

**Errors:**
- `"No git repository path available."` -- session was opened without a local repo
- `"PR source branch is not set."` -- PR metadata missing source branch
- Git worktree creation errors

---

## GetFixWorktreePath

Get the filesystem path to the fix worktree. Returns the path where the AI agent should make code changes. Returns an error if the worktree has not been prepared yet.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |

**Returns:**

```json
{
  "path": "/home/user/projects/my-repo/.power-review-fixes/42"
}
```

**Errors:**
- `"No fix worktree exists. Call PrepareFixWorktree first."` -- worktree not yet created

---

## CreateFixBranch

Create a new fix branch in the worktree for a specific comment thread. The branch is created from the PR's source branch and named `powerreview/fix/thread-{threadId}`. After creating the branch, make your code changes in the worktree path and commit them. Then call CreateProposal to register the fix.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `threadId` | int | Yes | The thread ID to create a fix branch for |

**Returns:**

```json
{
  "branch": "powerreview/fix/thread-42",
  "worktree_path": "/home/user/projects/my-repo/.power-review-fixes/42",
  "thread_id": 42,
  "note": "Fix branch created. Make your changes in '/home/user/...', then: 1) git add + git commit in the worktree, 2) Call CreateProposal to register the fix."
}
```

If the branch already exists, it is checked out.

**Errors:**
- `"No fix worktree exists. Call PrepareFixWorktree first."` -- worktree not created
- `"Fix worktree directory does not exist."` -- worktree was deleted externally
- Git branch creation errors

---

## CreateProposal

Register a proposed code fix after making changes on a fix branch. The AI agent should have already: 1) Called PrepareFixWorktree, 2) Called CreateFixBranch, 3) Made code changes and committed them, 4) Optionally called ReplyToThread to create a linked reply draft. The proposal starts as a draft that the user must approve before it can be applied.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `threadId` | int | Yes | The remote thread ID this fix responds to |
| `branchName` | string | Yes | Name of the fix branch holding the committed changes |
| `description` | string | Yes | Human-readable description of what this fix does |
| `filesChanged` | string | No | Comma-separated list of file paths that were modified |
| `replyDraftId` | string | No | UUID of a linked reply draft (auto-approved when proposal is approved) |
| `agentName` | string | No | Name identifying this agent |

**Returns:**

```json
{
  "id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
  "proposal": {
    "thread_id": 42,
    "description": "Added null check for user input",
    "status": "Draft",
    "author": "Ai",
    "author_name": "CodeFixer",
    "branch_name": "powerreview/fix/thread-42",
    "files_changed": ["src/main.cs"],
    "reply_draft_id": "a1b2c3d4-...",
    "created_at": "2026-01-01T00:00:00Z",
    "updated_at": "2026-01-01T00:00:00Z"
  },
  "note": "Proposal created. The user must approve it before it can be applied to the PR branch."
}
```

The proposal is always created with `author=Ai` and `status=Draft`.

**Errors:**
- `"Branch name is required."` -- empty branch name
- `"Description is required."` -- empty description
- `"Thread N not found in the session."` -- thread doesn't exist (sync threads first)
- `"Linked reply draft not found: <id>"` -- invalid reply draft UUID

---

## ListProposals

List all proposed code fixes and their statuses (draft, approved, applied, rejected). Includes count summaries and full proposal details.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |

**Returns:**

```json
{
  "counts": {
    "draft": 2,
    "approved": 1,
    "applied": 0,
    "rejected": 0,
    "total": 3
  },
  "proposals": [
    {
      "id": "uuid-1",
      "proposal": {
        "thread_id": 42,
        "description": "Fixed null check",
        "status": "Draft",
        "branch_name": "powerreview/fix/thread-42",
        ...
      }
    }
  ]
}
```

---

## GetProposalDiff

Get the code diff for a proposed fix. Shows the changes between the fix branch and the PR source branch.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `proposalId` | string | Yes | The proposal UUID to get the diff for |

**Returns:**

```json
{
  "proposal_id": "uuid-1",
  "description": "Fixed null check",
  "branch": "powerreview/fix/thread-42",
  "status": "Draft",
  "diff": "diff --git a/src/main.cs b/src/main.cs\n..."
}
```

**Errors:**
- `"Proposal not found: <id>"` -- invalid proposal ID
- `"No fix worktree exists."` -- worktree not created
- Git diff errors
