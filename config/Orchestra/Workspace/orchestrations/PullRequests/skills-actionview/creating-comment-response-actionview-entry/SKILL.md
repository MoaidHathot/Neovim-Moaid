---
name: creating-comment-response-actionview-entry
description: Creates an ActionView entry of type 'pr-comment-response' summarizing how AI agents responded to incoming PR comments. Shows each reviewer comment paired with the AI's draft reply, draft operation, and/or proposed code fix, with per-response approve/delete/reject actions and safe entry-level actions. Use after the AI agent has finished processing incoming comments on a PR.
compatibility: Requires the PowerReview MCP server connected via stdio. Requires the ActionView entry schema. Requires a completed comment-response run with draft replies, draft operations, and/or proposals in the PowerReview session.
---

# Creating a Comment Response ActionView Entry

This skill tells you how to build an ActionView entry of type `pr-comment-response` from PowerReview data after AI agents have responded to incoming PR comments. The entry lets the user review each AI response, approve or reject it, and submit the results.

## When to use this skill

Use this skill in the final step of a comment-response orchestration, **after**:
1. The dispatcher has provided targeted `commentEvents`
2. The AI agent has processed those incoming comments
3. Draft replies, draft operations, and/or proposals have been created in the PowerReview session

## Prerequisites

- A PowerReview session is open for the PR
- The PR URL (`prUrl`) is known
- The AI agent has already created draft replies, draft operations, and/or proposals via PowerReview

## Data collection

You need four pieces of data to build the entry.

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
  }
}
```

### Step 2: Get comment threads and draft actions

Call `ListCommentThreads(prUrl)` to get all threads, draft replies, and draft operations:

```json
{
  "threads": [
    {
      "id": 100,
      "file_path": "src/main.cs",
      "line_start": 42,
      "status": "Active",
      "comments": [
        {
          "id": 1,
          "thread_id": 100,
          "body": "This needs a null check. What happens when user is not found?",
          "author": { "name": "Alice Smith" }
        }
      ]
    }
  ],
  "drafts": [
    {
      "id": "draft-uuid-123",
      "draft": {
        "body": "Fixed: added null check for user input.",
        "status": "Draft",
        "author": "Ai",
        "author_name": "CodeFixer",
        "thread_id": 100
      }
    }
  ],
  "draft_operations": [
    {
      "id": "operation-uuid-789",
      "operation": {
        "operation_type": "ThreadStatusChange",
        "thread_id": 100,
        "status": "Draft",
        "to_thread_status": "Fixed",
        "author_name": "PR Author Assistant"
      }
    }
  ]
}
```

The key linkage: a draft reply has `thread_id` matching the thread it responds to. Match each draft to its parent thread to pair the original comment with the AI's reply.

Draft operations also link by `operation.thread_id`. Include them when the response uses a user-approved thread-status change or comment reaction.

### Step 3: Get proposals

Call `ListProposals(prUrl)` to get all proposed code fixes:

```json
{
  "counts": { "draft": 1, "approved": 0, "applied": 0, "rejected": 0, "total": 1 },
  "proposals": [
    {
      "id": "proposal-uuid-456",
      "proposal": {
        "thread_id": 100,
        "description": "Added null check for user input",
        "status": "Draft",
        "author": "Ai",
        "author_name": "CodeFixer",
        "branch_name": "powerreview/fix/thread-100",
        "files_changed": ["src/main.cs"],
        "reply_draft_id": "draft-uuid-123"
      }
    }
  ]
}
```

A proposal has `thread_id` linking it to the comment thread, and optionally `reply_draft_id` linking it to the draft reply.

### Step 4: Get targeted context and proposal diffs

For each proposal, call `GetProposalDiff(prUrl, proposalId)`:

```json
{
  "proposal_id": "proposal-uuid-456",
  "description": "Added null check for user input",
  "branch": "powerreview/fix/thread-100",
  "status": "Draft",
  "diff": "diff --git a/src/main.cs b/src/main.cs\n..."
}
```

For file/line-specific comments, optionally call `GetFileDiff(prUrl, filePath)` to include a small hunk around the commented line. Do not fetch or embed full PR diffs just to satisfy the ActionView template. PR-level comments and text-only discussions can omit Code Context.

## Linking the data together

The data connects through `thread_id`:

```
Thread (id: 100)
  └── Original comment: "This needs a null check..."  (from reviewer)
  └── Draft reply (thread_id: 100): "Fixed: added null check..."  (from AI)
  └── Draft operation (thread_id: 100): ThreadStatusChange -> Fixed  (from AI)
  └── Proposal (thread_id: 100): code changes on branch  (from AI)
         └── reply_draft_id: links back to the draft reply
```

For each thread that was addressed:
1. Find the thread in `threads` by ID
2. Get the last comment in the thread (the reviewer's comment the AI is responding to)
3. Find the draft reply in `drafts` where `draft.thread_id == thread.id`
4. Find draft operations in `draft_operations` where `operation.thread_id == thread.id` (if any)
5. Find the proposal in `proposals` where `proposal.thread_id == thread.id` (if any)
6. If there's a proposal, get the diff via `GetProposalDiff`

Threads that have no matching draft reply, draft operation, or proposal were not addressed by the AI -- skip them.

## Building the entry

### Entry-level fields

```json
{
  "schemaVersion": "1",
  "type": "pr-comment-response",
  "source": "<orchestration name>",
  "title": "PR Comment Responses: <PR title>",
  "subtitle": "<N> comments addressed | <M> replies | <K> code fixes | <O> operations",
  "severity": "<see mapping below>",
  "icon": "message-square-reply",
  "tags": ["pr-response", "comment-response"]
}
```

Severity mapping:
- Any proposals with code fixes -> `"medium"` (needs your review of code changes)
- Draft thread-status or reaction operations -> `"medium"` (needs your approval before submit)
- Only replies, no proposals -> `"low"` (just text replies to review)
- No comments addressed or errors -> `"high"` (something may have gone wrong)

### Content blocks (in order)

#### 1. Alert (optional)

Include if there were errors, conflicts, or comments that couldn't be addressed:

```json
{
  "type": "alert",
  "level": "warning",
  "body": "2 comments could not be addressed: thread 200 (file deleted), thread 300 (merge conflict in proposal)."
}
```

#### 2. PR metadata (keyValue, required)

```json
{
  "type": "keyValue",
  "label": "Pull Request",
  "pairs": {
    "PR Title": "<PR title>",
    "Repository": "<org>/<project>/<repo>",
    "Branch": "<source_branch> -> <target_branch>",
    "Author": "<PR author name>",
    "PR URL": "<full PR URL>"
  }
}
```

#### 3. Response Summary table

```json
{
  "type": "table",
  "label": "Response Summary",
  "columns": ["Action", "Count"],
  "rows": [
    ["Replies", "<N>"],
    ["Code Fixes", "<M>"],
    ["Won't Fix / By Design", "<K>"],
    ["Draft Operations", "<O>"],
    ["Total Comments Addressed", "<total>"]
  ]
}
```

Determine the action type by checking:
- If a thread has a proposal -> "Code Fix"
- If a thread has a ThreadStatusChange operation to `wontfix` or `bydesign` -> "Won't Fix" or "By Design"
- If a thread has a ThreadStatusChange operation to `fixed` -> "Fixed"
- If a thread has a CommentReaction operation -> "Acknowledge"
- If a thread has only a reply and the body contains "won't fix" or "by design" (case-insensitive) -> "Won't Fix"
- Otherwise -> "Reply"

#### 4. Comment Responses section (required -- one nested section per addressed comment)

Each addressed comment becomes a nested section. The section title should identify the comment at a glance.

**a) keyValue "Details"** -- response metadata:

```json
{
  "type": "keyValue",
  "label": "Details",
  "pairs": {
    "Thread ID": "100",
    "Commenter": "Alice Smith",
    "File": "src/main.cs",
    "Lines": "42",
    "Action": "Code Fix",
    "Agent": "CodeFixer",
    "Reply Draft ID": "draft-uuid-123",
    "Draft Operation ID": "operation-uuid-789",
    "Draft Operation Type": "ThreadStatusChange -> Fixed",
    "Proposal ID": "proposal-uuid-456"
  }
}
```

- `Commenter` -- the name of the person who left the original comment (from `thread.comments[last].author.name`)
- `Action` -- "Reply", "Code Fix", "Won't Fix", "By Design", "Fixed", or "Acknowledge"
- `Agent` -- from `draft.author_name`, draft operation `author_name`, or proposal `author_name`
- `Reply Draft ID` -- the draft UUID (needed for per-response actions)
- `Draft Operation ID` -- the draft operation UUID for thread status changes or reactions
- `Draft Operation Type` -- human-readable operation type, such as "ThreadStatusChange -> Fixed" or "CommentReaction -> Like"
- `Proposal ID` -- the proposal UUID (only for code fixes, needed for proposal actions)

Omit `Draft Operation ID` and `Draft Operation Type` if there is no draft operation for this thread.
Omit `Proposal ID` if there is no proposal for this thread.

**b) markdown "Original Comment"** -- what the reviewer said:

```json
{
  "type": "markdown",
  "label": "Original Comment",
  "body": "> **Alice Smith** (thread #100):\n>\n> This needs a null check. What happens when user is not found?"
}
```

Format the original comment as a blockquote with the commenter's name and thread ID.

**c) markdown "AI Response"** -- the draft reply:

```json
{
  "type": "markdown",
  "label": "AI Response",
  "body": "Fixed: added null check for user input. The method now throws `ArgumentNullException` if the user is not found."
}
```

**d) code "Code Context"** (optional -- targeted code around the commented area):

Include the code diff or snippet around the lines the reviewer commented on when it materially helps the user review the response. Use `GetFileDiff` to get the unified diff and extract the hunk covering the commented line range. Omit this block for PR-level comments, general discussion, or when fetching context would require broad/eager diff loading.

```json
{
  "type": "code",
  "label": "Code Context",
  "language": "diff",
  "filename": "src/main.cs",
  "body": "@@ -38,8 +38,8 @@\n     public async Task<string> GetUserName(int id)\n     {\n         var user = await _repo.FindAsync(id);\n-        return user.Name;\n+        return user.Name; // reviewer flagged: potential NullReferenceException"
}
```

Extract the relevant hunk from the full file diff that covers the commented line range (+/- a few lines of context). If the diff is short, include the entire file diff. Use `language: "diff"` for unified diffs. Keep this targeted; do not include unrelated file diffs.

**e) code "Proposed Fix"** (optional -- only for code fix actions):

When the AI made a code change proposal, include the proposal diff showing exactly what was changed. Call `GetProposalDiff` to get this.

```json
{
  "type": "code",
  "label": "Proposed Fix",
  "language": "diff",
  "filename": "src/main.cs",
  "body": "diff --git a/src/main.cs b/src/main.cs\n@@ -40,6 +40,9 @@\n     var user = await _repo.FindAsync(id);\n+    if (user == null)\n+        throw new ArgumentNullException(nameof(id));\n+\n     return user.Name;"
}
```

**f) Per-response actions:**

Include only the actions relevant to this response. If it has a reply, include "Approve Reply" and "Delete Reply". If it has a draft operation, include "Approve Operation" and "Delete Operation". If it has a proposal, include "Approve Proposal" and "Reject Proposal".

**Reply-only response:**

```json
{
  "actions": [
    {
      "label": "Approve Reply",
      "style": "success",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["comment", "approve", "--pr-url", "<prUrl>", "--draft-id", "<draft UUID>"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Delete Reply",
      "style": "danger",
      "confirmMessage": "Delete this draft reply?",
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

**Status/reaction operation response:**

```json
{
  "actions": [
    {
      "label": "Approve Operation",
      "style": "success",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["action", "approve", "--pr-url", "<prUrl>", "--action-id", "<operation UUID>"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Delete Operation",
      "style": "danger",
      "confirmMessage": "Delete this draft operation?",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["action", "delete", "--pr-url", "<prUrl>", "--action-id", "<operation UUID>"]
      },
      "onSuccess": "keep"
    }
  ]
}
```

**Code fix response (reply + proposal):**

```json
{
  "actions": [
    {
      "label": "Approve Reply",
      "style": "success",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["comment", "approve", "--pr-url", "<prUrl>", "--draft-id", "<draft UUID>"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Delete Reply",
      "style": "danger",
      "confirmMessage": "Delete this draft reply?",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["comment", "delete", "--pr-url", "<prUrl>", "--draft-id", "<draft UUID>"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Approve Proposal",
      "style": "success",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["proposal", "approve", "--pr-url", "<prUrl>", "--proposal-id", "<proposal UUID>"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Reject Proposal",
      "style": "danger",
      "confirmMessage": "Reject this proposed code fix?",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["proposal", "reject", "--pr-url", "<prUrl>", "--proposal-id", "<proposal UUID>"]
      },
      "onSuccess": "keep"
    }
  ]
}
```

**Complete nested section example (code fix):**

```json
{
  "type": "section",
  "title": "src/main.cs:42 - Code Fix: Added null check",
  "content": [
    {
      "type": "keyValue",
      "label": "Details",
      "pairs": {
        "Thread ID": "100",
        "Commenter": "Alice Smith",
        "File": "src/main.cs",
        "Lines": "42",
        "Action": "Code Fix",
        "Agent": "CodeFixer",
        "Reply Draft ID": "draft-uuid-123",
        "Proposal ID": "proposal-uuid-456"
      }
    },
    {
      "type": "markdown",
      "label": "Original Comment",
      "body": "> **Alice Smith** (thread #100):\n>\n> This needs a null check. What happens when user is not found?"
    },
    {
      "type": "markdown",
      "label": "AI Response",
      "body": "Fixed: added null check for user input. The method now throws `ArgumentNullException` if the user is not found."
    },
    {
      "type": "code",
      "label": "Code Context",
      "language": "diff",
      "filename": "src/main.cs",
      "body": "@@ -38,8 +38,8 @@\n     public async Task<string> GetUserName(int id)\n     {\n         var user = await _repo.FindAsync(id);\n-        return user.Name;\n+        return user.Name; // potential NullReferenceException"
    },
    {
      "type": "code",
      "label": "Proposed Fix",
      "language": "diff",
      "filename": "src/main.cs",
      "body": "@@ -40,6 +40,9 @@\n     var user = await _repo.FindAsync(id);\n+    if (user == null)\n+        throw new ArgumentNullException(nameof(id));\n+\n     return user.Name;"
    }
  ],
  "actions": [
    {
      "label": "Approve Reply",
      "style": "success",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["comment", "approve", "--pr-url", "https://dev.azure.com/org/project/_git/repo/pullrequest/42", "--draft-id", "draft-uuid-123"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Delete Reply",
      "style": "danger",
      "confirmMessage": "Delete this draft reply?",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["comment", "delete", "--pr-url", "https://dev.azure.com/org/project/_git/repo/pullrequest/42", "--draft-id", "draft-uuid-123"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Approve Proposal",
      "style": "success",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["proposal", "approve", "--pr-url", "https://dev.azure.com/org/project/_git/repo/pullrequest/42", "--proposal-id", "proposal-uuid-456"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Reject Proposal",
      "style": "danger",
      "confirmMessage": "Reject this proposed code fix?",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["proposal", "reject", "--pr-url", "https://dev.azure.com/org/project/_git/repo/pullrequest/42", "--proposal-id", "proposal-uuid-456"]
      },
      "onSuccess": "keep"
    }
  ]
}
```

#### 5. Proposed Code Fixes section (optional)

If there are multiple proposals, you can optionally add a dedicated section that lists all proposals together for easier bulk review:

```json
{
  "type": "section",
  "title": "Proposed Code Fixes",
  "content": [
    {
      "type": "table",
      "label": "Proposals",
      "columns": ["Thread", "File", "Description", "Status", "Proposal ID"],
      "rows": [
        ["100", "src/main.cs", "Added null check", "Draft", "proposal-uuid-456"]
      ]
    }
  ]
}
```

This is a convenience view. The per-response sections already contain the diffs and actions.

#### 6. Summary (optional)

```json
{
  "type": "markdown",
  "label": "Summary",
  "body": "Processed 3 incoming comments: 1 code fix proposed, 1 reply drafted, 1 draft status operation created. All responses are drafts pending your approval."
}
```

#### 7. View PR link

```json
{
  "type": "link",
  "label": "View PR",
  "url": "<PR URL>",
  "body": "Open pull request in browser"
}
```

### Entry-level actions

```json
{
  "actions": [
    {
      "label": "Open PR",
      "style": "primary",
      "command": {
        "type": "cli",
        "program": "pwsh",
        "args": ["-NoProfile", "-Command", "Start-Process '<prUrl>'"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Approve All Replies",
      "style": "success",
      "confirmMessage": "Approve all draft replies?",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["comment", "approve-all", "--pr-url", "<prUrl>"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Submit Replies",
      "style": "success",
      "confirmMessage": "Submit all approved replies to Azure DevOps?",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["submit", "--pr-url", "<prUrl>"]
      },
      "onSuccess": "archive"
    },
    {
      "label": "Delete All",
      "style": "danger",
      "confirmMessage": "Delete ALL draft replies and reject ALL proposals? This cannot be undone.",
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

Only include bulk proposal actions such as "Approve All Proposals" or "Apply All Proposals" if the installed PowerReview CLI explicitly supports them. Otherwise rely on the per-response proposal actions (Approve Proposal / Reject Proposal), which work individually.

## Data mapping reference

| PowerReview Source | ActionView Target |
|---|---|
| `session.pull_request.title` | Entry `title`: `"PR Comment Responses: <title>"` |
| `session.pull_request.url` | All action `--pr-url` args, "View PR" link, "Open PR" action |
| `session.pull_request.source_branch` / `target_branch` | "Pull Request" keyValue `Branch` |
| `session.pull_request.author.name` | "Pull Request" keyValue `Author` |
| `thread.id` | Per-response "Details" keyValue `Thread ID` |
| `thread.comments[last].author.name` | Per-response "Details" keyValue `Commenter` |
| `thread.comments[last].body` | Per-response "Original Comment" markdown body |
| `thread.file_path` | Per-response "Details" keyValue `File`, section title |
| `thread.line_start` | Per-response "Details" keyValue `Lines`, section title |
| `draft.id` (UUID) | Per-response "Details" keyValue `Reply Draft ID`, Approve/Delete Reply action `--draft-id` |
| `draft.author_name` | Per-response "Details" keyValue `Agent` |
| `draft.body` | Per-response "AI Response" markdown body |
| `draftOperation.id` (UUID) | Per-response "Details" keyValue `Draft Operation ID`, Approve/Delete Operation action `--action-id` |
| `draftOperation.operation.operation_type` | Per-response "Details" keyValue `Draft Operation Type` |
| `proposal.id` (UUID) | Per-response "Details" keyValue `Proposal ID`, Approve/Reject Proposal action `--proposal-id` |
| `proposal.description` | Section title suffix |
| `proposal.files_changed` | "Proposed Fix" code block `filename` |
| `proposalDiff.diff` | "Proposed Fix" code block body |

## Determining the action type

For each addressed thread, determine the action type:

| Condition | Action Type |
|---|---|
| Thread has a matching proposal | **Code Fix** |
| Thread has a matching ThreadStatusChange operation to `Fixed` | **Fixed** |
| Thread has a matching ThreadStatusChange operation to `WontFix` or `ByDesign` | **Won't Fix** / **By Design** |
| Thread has a matching CommentReaction operation | **Acknowledge** |
| Thread has a reply containing "won't fix", "wontfix", "by design", or "out of scope" (case-insensitive) | **Won't Fix** |
| Thread has a reply but no proposal and not won't fix | **Reply** |

## Section title format

Use a consistent title format for each nested section:

```
<file_path>:<line_start> - <Action>: <first ~60 chars of AI response or proposal description>
```

Examples:
- `src/main.cs:42 - Code Fix: Added null check for user input`
- `src/utils.cs:15 - Reply: Agreed, will refactor in follow-up PR`
- `src/config.cs:8 - Won't Fix: Intentional for backwards compatibility`

## Checklist

Before saving the entry, verify:

```
Entry Checklist:
- [ ] type is "pr-comment-response"
- [ ] source is the orchestration name
- [ ] title includes the PR title
- [ ] PR metadata keyValue block is present with PR Title, Repository, Branch, Author, and PR URL
- [ ] Response Summary table has correct counts
- [ ] Every addressed comment has its own nested section
- [ ] Every nested section has Details (keyValue), Original Comment (markdown), and either AI Response, Draft Operation details, or Proposed Fix; Code Context is included only when targeted context is useful
- [ ] Code fix sections additionally include the Proposed Fix (code block with proposal diff)
- [ ] Every nested section has the correct actions (reply draft: Approve/Delete Reply, draft operation: Approve/Delete Operation, proposal: Approve/Reject Proposal)
- [ ] All action commands use the correct prUrl, draft UUID, draft operation UUID, and proposal UUID
- [ ] Entry-level actions include: Open PR, Approve All Replies, Submit Replies, and Delete All; bulk proposal actions are included only when supported by the installed CLI
- [ ] View PR link is present with the correct URL
- [ ] Threads with no AI response/action are excluded (not shown in the entry)
```

## Important notes

- **Pair original comments with AI responses via `thread_id`.** The thread ID is the key that connects everything: the original comment, the draft reply, draft operation, and proposal.
- **Not all threads are addressed.** Only include threads where the AI created a draft reply, draft operation, and/or a proposal. Skip threads with no AI response/action.
- **Per-response actions are conditional.** Reply drafts get Approve/Delete Reply, draft operations get Approve/Delete Operation, and code fix proposals get Approve/Reject Proposal. Don't include actions for artifacts that do not exist on that response.
- **Proposal diffs may be large.** If a proposal diff is very long, consider truncating it and adding a note that the full diff is available via `powerreview proposal diff --pr-url <url> --proposal-id <id>`.
- **The `reply_draft_id` on proposals links replies to proposals.** When a proposal is approved, the linked reply is auto-approved too. This means the user can approve the proposal and the reply goes to Pending automatically.
- **Save the entry using `orchestra_save_file`.** The orchestration's next step submits it to ActionView via `actionview add --file <path>`.
