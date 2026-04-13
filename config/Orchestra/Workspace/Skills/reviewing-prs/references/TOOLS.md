# PowerReview MCP Tool Reference

Complete API documentation for all PowerReview MCP server tools.

The MCP server name is `PowerReview`. All tool calls should use the format `PowerReview:<tool_name>`.

All tools return JSON. Errors are returned as `{ "error": "message" }`.

## Contents

- Read-only tools (session, files, diff, threads, draft counts)
- Write tools (create comment, reply, edit, delete)
- Working directory and file access tools (working directory, read file, list files)

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
    "reviewers": [{ "name": "...", "vote": 0, "is_required": true }],
    "labels": [],
    "work_items": [{ "id": 456, "title": "...", "url": "..." }]
  },
  "files": [...],
  "drafts": { "uuid-1": { ... }, "uuid-2": { ... } },
  "vote": null,
  "git": { "repo_path": "...", "worktree_path": "...", "strategy": "Worktree" }
}
```

**Error:** `"No session found for this PR. Run 'powerreview open --pr-url <url>' first."`

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

**Returns:**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "draft": {
    "file_path": "src/main.cs",
    "line_start": 42,
    "line_end": null,
    "body": "Consider handling null here",
    "status": "Draft",
    "author": "Ai",
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

**Returns:**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "draft": {
    "file_path": "",
    "body": "Good point, I agree this should be handled.",
    "status": "Draft",
    "author": "Ai",
    "thread_id": 1
  },
  "note": "Draft reply created. The user must approve it before it can be submitted."
}
```

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
