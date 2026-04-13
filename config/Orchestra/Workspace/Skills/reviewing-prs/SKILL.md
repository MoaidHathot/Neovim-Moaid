---
name: reviewing-prs
description: Reviews pull requests using the PowerReview MCP server. Reads PR metadata, diffs, and comment threads, then creates draft review comments. Use when asked to review a pull request, provide code review feedback, or analyze PR changes.
compatibility: Requires the PowerReview MCP server connected via stdio. Requires .NET 10 SDK and a review session opened beforehand.
---

# Reviewing Pull Requests with PowerReview

## Prerequisites

A review session must already be open for the PR. If `GetReviewSession` returns an error, ask the user to open the session first:

```
powerreview open --pr-url <url> --repo-path <path>
```

All tools require `prUrl` -- the full pull request URL (Azure DevOps or GitHub format).

## PR review workflow

Follow these steps in order. Copy this checklist and track progress:

```
Review Progress:
- [ ] Step 1: Load session and understand the PR
- [ ] Step 2: List changed files and discover project structure
- [ ] Step 3: Review each file's diff (with context from surrounding code)
- [ ] Step 4: Check existing comment threads
- [ ] Step 5: Create draft comments for findings
- [ ] Step 6: Summarize the review
```

### Step 1: Load the session

Call `PowerReview:GetReviewSession` with the PR URL. This returns:

- PR title, description, author, branches
- Current vote status
- Draft and file counts
- Reviewer list and work items

Read the PR description carefully. Understand the intent of the change before reviewing code.

Also call `PowerReview:GetWorkingDirectory` to get the filesystem path where the repository code is checked out. This tells you the working directory path, git strategy, and repo path -- useful for reading files later.

### Step 2: List changed files and discover project structure

Call `PowerReview:ListChangedFiles` with the PR URL. Returns each file's:

- `path` -- relative file path
- `change_type` -- `add`, `edit`, `delete`, or `rename`
- `original_path` -- previous path for renames

Plan the review order. Prioritize:
1. Core logic files over config/test files
2. Files with `add` or `edit` changes over `delete`
3. Smaller focused files before large ones

Use `PowerReview:ListRepositoryFiles` to understand the project structure around changed files. For example, if a file in `src/Services/` was changed, list that directory to see what other services exist and understand the architecture.

### Step 3: Review each file's diff

For each file, call `PowerReview:GetFileDiff` with `prUrl` and `filePath`.

Returns a unified diff showing all changes. If no local git repo is available, only file metadata is returned.

**Reading context beyond the diff:** Use `PowerReview:ReadFile` to read files that are not part of the PR diff but are relevant to the review. This is critical for thorough reviews:

- Read interfaces or base classes that changed code implements
- Read callers of modified functions to check for breaking changes
- Read test files to verify adequate test coverage
- Read configuration files that might be affected by the changes
- Read related files in the same module to understand conventions

Use `offset` and `limit` parameters to read specific sections of large files instead of loading entire files.

When reviewing a diff, look for:
- Bugs, logic errors, edge cases
- Security issues (injection, auth bypass, secrets)
- Performance problems (N+1 queries, unnecessary allocations)
- Readability and maintainability concerns
- Missing error handling or validation
- Naming and convention violations
- Missing or inadequate tests for the changes

### Step 4: Check existing threads

Call `PowerReview:ListCommentThreads` to see existing remote comments and local drafts. Use the optional `filePath` parameter to filter by file.

Avoid duplicating feedback that already exists in threads. Read existing threads to understand ongoing discussions.

### Step 5: Create draft comments

For each finding, call `PowerReview:CreateComment` with:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `prUrl` | Yes | The pull request URL |
| `filePath` | Yes | Relative file path to comment on |
| `body` | Yes | Comment body in markdown |
| `lineStart` | No | Line number (1-indexed). Omit for file-level comments |
| `lineEnd` | No | End line for range comments (1-indexed) |

To reply to an existing thread instead, call `PowerReview:ReplyToThread` with `prUrl`, `threadId`, and `body`.

#### Writing effective comments

- Be specific: reference the exact code and explain the issue
- Be actionable: suggest a fix or alternative
- Use markdown: code blocks, bold, lists
- Categorize severity: prefix with `nit:`, `suggestion:`, `bug:`, or `critical:` when appropriate
- Be concise: one issue per comment

### Step 6: Summarize

After reviewing all files, check your draft counts with `PowerReview:GetDraftCounts` to confirm all comments were created. Then provide a summary to the user covering:

- Overall assessment of the PR
- Key findings (bugs, security, performance)
- Number of comments left
- Whether the PR is ready to approve or needs changes

## Safety rules

These constraints are enforced by the server and cannot be bypassed:

1. **All comments start as drafts.** The user must approve each draft before it can be submitted to the remote provider.
2. **AI can only modify AI-authored drafts.** User-authored drafts cannot be edited or deleted by AI.
3. **Only `Draft` status comments can be edited/deleted.** Once a draft is approved to `Pending`, editing it resets it back to `Draft` (requires re-approval).
4. **Submitted comments are immutable.** No changes after submission.

The draft lifecycle is: `Draft` -> `Pending` -> `Submitted`.

## Managing drafts

If you need to revise a comment you already created:

- **Edit**: Call `PowerReview:EditDraftComment` with `prUrl`, `draftId`, and `newBody`
- **Delete**: Call `PowerReview:DeleteDraftComment` with `prUrl` and `draftId`

Both only work on AI-authored drafts in `Draft` status.

## File access tools

These tools allow you to read any file in the repository, not just the files changed in the PR:

- **`GetWorkingDirectory`** -- Get the filesystem path to the working directory
- **`ReadFile`** -- Read file contents (supports offset/limit for large files)
- **`ListRepositoryFiles`** -- List directory contents (supports recursive listing and glob patterns)

All file access tools enforce path security -- you cannot read files outside the working directory.

## Tool reference

See [references/TOOLS.md](references/TOOLS.md) for complete tool API documentation including all parameters, return types, and error handling.
