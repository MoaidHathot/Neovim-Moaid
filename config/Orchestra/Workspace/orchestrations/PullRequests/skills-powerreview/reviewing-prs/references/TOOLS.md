# PowerReview MCP Tool Reference

Complete API documentation for all PowerReview MCP server tools.

The MCP server name is `PowerReview`. Tools are listed below by their short name (e.g., `SyncThreads`). When calling via MCP, the server may prefix the tool name depending on your MCP client configuration.

All tools return JSON. Errors are returned as `{ "error": "message" }`.

## Contents

- Read-only tools (session, PR description, files, diff, threads, draft counts)
- Sync and iteration tools (sync threads, check iteration, iteration diff)
- Write tools (create comment, reply, edit, delete, update thread status)
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
    "reviewers": [{ "name": "...", "vote": 0, "is_required": true }],
    "labels": [],
    "work_items": [{ "id": 456, "title": "...", "url": "..." }]
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
  "drafts": { "uuid-1": { ... }, "uuid-2": { ... } },
  "vote": null,
  "git": { "repo_path": "...", "worktree_path": "...", "strategy": "Worktree" }
}
```

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
    { "name": "Alice Smith", "vote": 0, "is_required": true }
  ],
  "labels": ["backend", "validation"],
  "work_items": [
    { "id": 1234, "title": "Implement input validation", "url": "https://..." }
  ]
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

The `diff` field contains the full unified diff output. If no local git repo is available, `diff` is `null` and a `note` field explains why.

**Errors:**
- `"File 'path' not found in the changed files list."` -- file path doesn't match any changed file
- `"No session found for this PR."` -- no active session
- `"Failed to generate diff: ..."` -- git error

---

## ListCommentThreads

List all remote comment threads and local draft comments, optionally filtered by file.

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
  "drafts": [
    {
      "id": "uuid-1",
      "draft": {
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

Get a summary of draft comment counts by status.

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
  "total": 6
}
```

---

## SyncThreads

Sync comment threads from the remote provider (e.g., Azure DevOps). Updates the local session with the latest threads and checks for new iterations. Call this before reading threads to ensure you have the most up-to-date data.

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
  }
}
```

When no new iteration is detected, `iteration_check` is `null`.

**Errors:**
- `"No session found for this PR."` -- no active session
- Provider-specific sync errors

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

## UpdateThreadStatus

Update the status of a comment thread on the remote provider. Use this to resolve threads that have been addressed, or reactivate them.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `prUrl` | string | Yes | The pull request URL |
| `threadId` | int | Yes | The remote thread ID to update |
| `status` | string | Yes | New thread status. One of: `active`, `fixed`, `wontfix`, `closed`, `bydesign`, `pending` |

**Returns:**

```json
{
  "thread_id": 100,
  "status": "fixed",
  "thread": {
    "id": 100,
    "file_path": "src/main.cs",
    "line_start": 42,
    "status": "Fixed",
    "comments": [...]
  }
}
```

Valid status values: `active`, `fixed` (also accepts `resolved`), `wontfix` (also accepts `wont-fix`), `closed`, `bydesign` (also accepts `by-design`), `pending`.

**Errors:**
- `"Invalid thread status: '<value>'. Use: active, fixed, wontfix, closed, bydesign, pending"` -- unrecognized status
- `"No session found for this PR."` -- no active session
- Provider-specific errors (e.g., thread not found on AzDO)

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
