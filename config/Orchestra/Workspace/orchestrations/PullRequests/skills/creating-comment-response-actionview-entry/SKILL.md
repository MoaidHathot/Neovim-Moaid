---
name: creating-comment-response-actionview-entry
description: Creates an ActionView entry of type 'pr-comment-response' summarizing how AI agents responded to incoming PR comments. Shows each reviewer comment paired with the AI's draft reply and/or proposed code fix, with per-response approve/delete/reject actions and entry-level bulk actions. Use after the AI agent has finished processing all incoming comments on a PR.
compatibility: Requires the PowerReview MCP server connected via stdio. Requires the ActionView entry schema. Requires a completed comment-response run with drafts and/or proposals in the PowerReview session.
---

# Creating a Comment Response ActionView Entry

This skill tells you how to build an ActionView entry of type `pr-comment-response` from PowerReview data after AI agents have responded to incoming PR comments. The entry lets the user review each AI response, approve or reject it, and submit the results.

## When to use this skill

Use this skill in the final step of a comment-response orchestration, **after**:
1. Threads have been synced from the remote provider
2. The AI agent has processed all incoming comments
3. Draft replies and/or proposals have been created in the PowerReview session

## Prerequisites

- A PowerReview session is open for the PR
- The PR URL (`prUrl`) is known
- The AI agent has already created draft replies and/or proposals via PowerReview

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

### Step 2: Get comment threads and draft replies

Call `ListCommentThreads(prUrl)` to get all threads and drafts:

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
  ]
}
```

The key linkage: a draft reply has `thread_id` matching the thread it responds to. Match each draft to its parent thread to pair the original comment with the AI's reply.

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

### Step 4: Get proposal diffs

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

## Linking the data together

The data connects through `thread_id`:

```
Thread (id: 100)
  └── Original comment: "This needs a null check..."  (from reviewer)
  └── Draft reply (thread_id: 100): "Fixed: added null check..."  (from AI)
  └── Proposal (thread_id: 100): code changes on branch  (from AI)
         └── reply_draft_id: links back to the draft reply
```

For each thread that was addressed:
1. Find the thread in `threads` by ID
2. Get the last comment in the thread (the reviewer's comment the AI is responding to)
3. Find the draft reply in `drafts` where `draft.thread_id == thread.id`
4. Find the proposal in `proposals` where `proposal.thread_id == thread.id` (if any)
5. If there's a proposal, get the diff via `GetProposalDiff`

Threads that have no matching draft reply or proposal were not addressed by the AI -- skip them.

## Building the entry

### Entry-level fields

```json
{
  "schemaVersion": "1",
  "type": "pr-comment-response",
  "source": "<orchestration name>",
  "title": "PR Comment Responses: <PR title>",
  "subtitle": "<N> comments addressed | <M> replies | <K> code fixes",
  "severity": "<see mapping below>",
  "icon": "message-square-reply",
  "tags": ["pr-response", "comment-response"]
}
```

Severity mapping:
- Any proposals with code fixes -> `"medium"` (needs your review of code changes)
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

#### 2. PR metadata (keyValue)

```json
{
  "type": "keyValue",
  "label": "Pull Request",
  "pairs": {
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
    ["Total Comments Addressed", "<total>"]
  ]
}
```

Determine the action type by checking:
- If a thread has a proposal -> "Code Fix"
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
    "Proposal ID": "proposal-uuid-456"
  }
}
```

- `Commenter` -- the name of the person who left the original comment (from `thread.comments[last].author.name`)
- `Action` -- "Reply", "Code Fix", or "Won't Fix"
- `Agent` -- from `draft.author_name`
- `Reply Draft ID` -- the draft UUID (needed for per-response actions)
- `Proposal ID` -- the proposal UUID (only for code fixes, needed for proposal actions)

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

**d) code "Proposed Fix"** (optional -- only for code fix actions):

```json
{
  "type": "code",
  "label": "Proposed Fix",
  "language": "diff",
  "filename": "src/main.cs",
  "body": "diff --git a/src/main.cs b/src/main.cs\n@@ -40,6 +40,9 @@\n     var user = await _repo.FindAsync(id);\n+    if (user == null)\n+        throw new ArgumentNullException(nameof(id));\n+\n     return user.Name;"
}
```

**e) Per-response actions:**

Include only the actions relevant to this response. If it's just a reply (no proposal), include only "Approve Reply" and "Delete Reply". If it has a proposal, include all four.

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
  "body": "Processed 3 incoming comments: 1 code fix proposed, 1 reply drafted, 1 marked as won't fix. All responses are drafts pending your approval."
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
        "program": "cmd.exe",
        "args": ["/c", "start", "<prUrl>"]
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
      "label": "Approve All Proposals",
      "style": "success",
      "confirmMessage": "Approve all proposed code fixes?",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["proposal", "approve-all", "--pr-url", "<prUrl>"]
      },
      "onSuccess": "keep"
    },
    {
      "label": "Apply All Proposals",
      "style": "success",
      "confirmMessage": "Apply all approved proposals and push to remote?",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["proposal", "apply-all", "--pr-url", "<prUrl>", "--push"]
      },
      "onSuccess": "keep"
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

**Note about "Approve All Proposals" and "Apply All Proposals":** These reference `proposal approve-all` and `proposal apply-all` CLI commands that may not exist yet. The orchestration or user may need to loop over proposals individually. Document the intended CLI commands -- the PowerReview CLI can be extended later to support bulk proposal operations. In the meantime, the per-response proposal actions (Approve Proposal / Reject Proposal) work individually.

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
| `proposal.id` (UUID) | Per-response "Details" keyValue `Proposal ID`, Approve/Reject Proposal action `--proposal-id` |
| `proposal.description` | Section title suffix |
| `proposal.files_changed` | "Proposed Fix" code block `filename` |
| `proposalDiff.diff` | "Proposed Fix" code block body |

## Determining the action type

For each addressed thread, determine the action type:

| Condition | Action Type |
|---|---|
| Thread has a matching proposal | **Code Fix** |
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
- [ ] PR metadata keyValue block is present with PR URL
- [ ] Response Summary table has correct counts
- [ ] Every addressed comment has its own nested section
- [ ] Every nested section has Details (keyValue), Original Comment (markdown), and AI Response (markdown)
- [ ] Code fix sections include the Proposed Fix (code block with diff)
- [ ] Every nested section has the correct actions (reply-only: 2 buttons, code fix: 4 buttons)
- [ ] All action commands use the correct prUrl, draft UUID, and proposal UUID
- [ ] Entry-level actions include: Open PR, Approve All Replies, Submit Replies, Approve All Proposals, Apply All Proposals, Delete All
- [ ] View PR link is present with the correct URL
- [ ] Threads with no AI response are excluded (not shown in the entry)
```

## Important notes

- **Pair original comments with AI responses via `thread_id`.** The thread ID is the key that connects everything: the original comment, the draft reply, and the proposal.
- **Not all threads are addressed.** Only include threads where the AI created a draft reply and/or a proposal. Skip threads with no AI response.
- **Per-response actions are conditional.** Reply-only responses get 2 buttons (Approve Reply, Delete Reply). Code fix responses get 4 buttons (+ Approve Proposal, Reject Proposal). Don't include proposal actions for reply-only responses.
- **Proposal diffs may be large.** If a proposal diff is very long, consider truncating it and adding a note that the full diff is available via `powerreview proposal diff --pr-url <url> --proposal-id <id>`.
- **The `reply_draft_id` on proposals links replies to proposals.** When a proposal is approved, the linked reply is auto-approved too. This means the user can approve the proposal and the reply goes to Pending automatically.
- **Save the entry using `orchestra_save_file`.** The orchestration's next step submits it to ActionView via `actionview add --file <path>`.

