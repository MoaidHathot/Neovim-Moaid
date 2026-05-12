---
name: responding-to-comments
description: Responds to PR comments using the PowerReview MCP server. Reads incoming comments on the user's PRs, creates draft replies and proposed code fixes. Use when asked to respond to PR feedback, fix issues raised in review comments, or address reviewer concerns.
compatibility: Requires the PowerReview MCP server connected via stdio. Requires .NET 10 SDK and a review session opened beforehand.
---

# Responding to PR Comments with PowerReview

## Prerequisites

A review session must already be open for the PR. If `GetReviewSession` returns an error, ask the user to open the session first:

```
powerreview open --pr-url <url> --repo-path <path>
```

All tools require `prUrl` -- the full pull request URL (Azure DevOps or GitHub format).

If `GetReviewSession` shows `local_identity: null` on the session, ask the user
to run `powerreview identity refresh --pr-url <url>` once. Reply classification
still works in this state (via `published_comment_id` on AI-submitted drafts),
but identity-based matching helps recognize comments the user posted directly
from the provider's web UI as "self" rather than as third-party replies.

## Tool invocation

This skill assumes the AI agent is connected to the **PowerReview MCP server** (`powerreview mcp` via stdio). Tools are called by their MCP tool name (e.g., `SyncThreads`, `CreateProposal`).

If using the CLI instead of MCP, each tool has an equivalent CLI command. The mapping:

| MCP Tool | CLI Equivalent |
|----------|---------------|
| `SyncThreads(prUrl)` | `powerreview sync --pr-url <url>` |
| `GetNewReplies(prUrl, scope?, threadId?)` | `powerreview replies --pr-url <url> [--scope <scope>] [--thread-id <n>]` |
| `AcknowledgeReplies(prUrl, acks, ackedBy?)` | `powerreview ack --pr-url <url> --thread-id <n> [--through <comment_id>] [--by ai\|human]` |
| `ListCommentThreads(prUrl)` | `powerreview threads --pr-url <url>` |
| `GetReviewSession(prUrl)` | `powerreview session --pr-url <url>` |
| `ReplyToThread(prUrl, threadId, body)` | `powerreview reply --pr-url <url> --thread-id <n> --body <text>` |
| `DraftThreadStatusChange(prUrl, threadId, status)` | `powerreview action create-thread-status --pr-url <url> --thread-id <n> --status <status>` |
| `DraftCommentReaction(prUrl, threadId, commentId, reaction)` | `powerreview action create-reaction --pr-url <url> --thread-id <n> --comment-id <n> --reaction like` |
| `PrepareFixWorktree(prUrl)` | `powerreview fix-worktree prepare --pr-url <url>` |
| `CreateFixBranch(prUrl, threadId)` | `powerreview fix-worktree create-branch --pr-url <url> --thread-id <n>` |
| `ReadFile(prUrl, filePath)` | `powerreview read-file --pr-url <url> --file <path>` |
| `CreateProposal(prUrl, ...)` | `powerreview proposal create --pr-url <url> --thread-id <n> --branch <b> --description <d>` |
| `ListProposals(prUrl)` | `powerreview proposal list --pr-url <url>` |
| `GetDraftCounts(prUrl)` | (available via `GetReviewSession` output) |

User-only operations (not available as MCP tools):

| Operation | CLI Command |
|-----------|-------------|
| Approve proposal | `powerreview proposal approve --pr-url <url> --proposal-id <id>` |
| Apply proposal | `powerreview proposal apply --pr-url <url> --proposal-id <id> [--push]` |
| Reject proposal | `powerreview proposal reject --pr-url <url> --proposal-id <id>` |
| View proposal diff | `powerreview proposal diff --pr-url <url> --proposal-id <id>` |
| Approve draft operation | `powerreview action approve --pr-url <url> --action-id <id>` |
| Delete draft operation | `powerreview action delete --pr-url <url> --action-id <id>` |
| Submit operations | `powerreview submit --pr-url <url>` |

## Comment response workflow

When the user wants you to respond to comments on their PR, follow these steps:

```
Response Progress:
- [ ] Step 1: Sync and load the latest comment threads (call SyncThreads)
- [ ] Step 2: Identify new/unaddressed comments (call GetNewReplies)
- [ ] Step 3: For each comment, decide the action (reply, code fix, or won't fix)
- [ ] Step 4: Execute the appropriate action
- [ ] Step 4b: Acknowledge handled comments (call AcknowledgeReplies)
- [ ] Step 5: Summarize what was done
```

### Step 1: Sync and load threads

1. Call `SyncThreads` to fetch the latest comment threads from the remote provider.
   The response now includes a `deltas` summary with counts of new/edited comments
   classified by recipient (`reply_to_ai`, `reply_to_human`, `reply_in_others_thread`,
   `new_thread_others`). If `silent_priming` is `true`, this was the first sync after
   upgrade — treat the session as "caught up" (no actionable deltas exist yet) and
   proceed by summarizing the current open threads from `ListCommentThreads` rather
   than waiting for deltas. The next sync onward will produce real deltas.
2. If `deltas.reply_to_ai > 0` (or `deltas.reply_to_human > 0` and the user wants
   AI to handle their replies too), call `GetNewReplies(prUrl, scope="to_me")` to
   get the actual list of new replies that need attention. This avoids re-scanning
   every thread on a busy PR.
3. Optionally call `ListCommentThreads` if you need the full thread context for
   threads that aren't in the deltas.
4. Call `GetReviewSession` to understand the PR context (branches, files, iteration,
   reviewers, work items, and `metadata`).

Use session `metadata` when relevant:

- `metadata.threads.active` and `metadata.threads.pending` show how much unresolved feedback remains.
- `metadata.reviewers.required_pending`, `metadata.reviewers.rejected`, and `metadata.reviewers.waiting_for_author` help identify whether required reviewers are still blocking the PR.
- `metadata.files` helps estimate whether a requested fix is isolated or likely to touch broad areas.
- `metadata.work_items.by_type` and `metadata.work_items.by_state` can explain product context and whether a comment relates to a bug, task, or story.
- `metadata.state.has_merge_conflicts`, `metadata.state.is_draft`, and `metadata.state.merge_status` should influence the final readiness summary.
- `metadata.iteration` helps confirm which source/target commits the comments and fix proposals are based on.
- `metadata.timestamps.threads_synced_at` helps detect stale thread data; if old or missing, sync before acting.

### Step 2: Identify new/unaddressed comments

**Preferred path: use `GetNewReplies`.** It returns only the comments that have
arrived (or been edited) since the previous sync, grouped by thread, with a
`body_preview` so you can decide whether to fetch the full thread.

Scopes to use:
- `to_ai` (default for AI agents): replies on threads where AI participated. Highest priority.
- `to_me`: `to_ai` + replies on threads the human user participated in.
- `to_others` / `all`: full PR awareness — usually only when the user explicitly asks.

If `GetNewReplies` returns nothing actionable, fall back to scanning
`ListCommentThreads` for threads with status `Active`/`Pending` from required
reviewers (e.g. when starting a session and there's no diff yet).

### Step 2b: Acknowledge after acting

After you've drafted a follow-up reply (or explicitly decided not to respond),
call `AcknowledgeReplies` so the same reply doesn't keep appearing in
`GetNewReplies` on every subsequent sync. Format:

```
AcknowledgeReplies(prUrl="<url>", acks="123:789,456:1011", ackedBy="ai")
```

The `through_comment_id` should be the highest comment id you've handled on
that thread. Watermarks are monotonic so it's safe to re-ack — calling with a
lower id is a no-op.

### Step 3: Decide the action

For each comment that needs a response, decide one of these actions:

#### Action A: Draft reply (no code change needed)
Use when the comment is a question, clarification request, or the fix is trivial enough to describe in words.

#### Action B: Code fix (code change needed)
Use when the comment identifies an actual code issue that should be fixed. The AI will make the change on a temporary branch.

Before choosing a code fix, consider `metadata.files` and the linked work item metadata. If the comment is broader than the PR scope or conflicts with the work item type/state, prefer asking a clarifying question or drafting a scoped explanation.

#### Action C: Won't fix / By design
Use when the comment raises a valid point but the current approach is intentional or the change is out of scope. Reply with an explanation, then create a draft thread-status operation if the thread should be marked `wontfix` or `bydesign`.

#### Action D: Acknowledge a reviewer reply
Use when the appropriate response is a lightweight acknowledgement rather than another comment. Create a draft reaction operation with `DraftCommentReaction`.

### Step 4: Execute the action

#### For replies (Action A and C):

Call `ReplyToThread` with:
- `prUrl` -- the pull request URL
- `threadId` -- the thread ID to reply to
- `body` -- the reply in markdown
- `agentName` -- your agent name (optional)

The reply is created as a draft. The user must approve it before it is submitted.

#### For thread status decisions:

Call `DraftThreadStatusChange` with:
- `prUrl` -- the pull request URL
- `threadId` -- the thread ID to update after approval
- `status` -- one of `active`, `fixed`, `wontfix`, `closed`, `bydesign`, `pending`
- `reason` -- concise rationale for the user
- `agentName` -- your agent name (optional)

The operation is created as a draft. The user must approve it before `submit` applies it to the remote provider.

#### For comment reactions:

Call `DraftCommentReaction` with:
- `prUrl` -- the pull request URL
- `threadId` -- the thread ID containing the comment
- `commentId` -- the specific comment ID to react to
- `reaction` -- currently `like`
- `reason` -- concise rationale for the user
- `agentName` -- your agent name (optional)

The reaction is created as a draft operation. The user must approve it before `submit` applies it to the remote provider.

#### For code fixes (Action B):

Follow this sequence:

1. **Prepare the worktree** (once per PR):
   ```
   PrepareFixWorktree(prUrl)
   ```
   Returns the worktree path where you can make changes.

2. **Create a fix branch** for the specific thread:
   ```
   CreateFixBranch(prUrl, threadId)
   ```
   Returns the branch name and worktree path.

3. **Make code changes** in the worktree:
   - Read the relevant file(s) using `ReadFile`
   - Use your file editing tools to modify the files in the worktree path
   - The worktree is a separate git checkout -- changes here do NOT affect the user's working directory

4. **Commit the changes** in the worktree:
   - `git add .` and `git commit -m "description"` in the worktree path

5. **Create a reply draft** (optional but recommended):
   ```
   ReplyToThread(prUrl, threadId, "Fixed: <description of what was done>")
   ```
   Note the returned `draft_id`.

6. **Register the proposal**:
   ```
   CreateProposal(prUrl, threadId, branchName, description, filesChanged, replyDraftId)
   ```

The proposal is created as a draft. The user can:
- View the diff: `powerreview proposal diff --pr-url <url> --proposal-id <id>`
- Approve: `powerreview proposal approve --pr-url <url> --proposal-id <id>`
- Apply (merge into PR branch): `powerreview proposal apply --pr-url <url> --proposal-id <id> [--push]`
- Reject: `powerreview proposal reject --pr-url <url> --proposal-id <id>`

### Step 5: Summarize

After processing all comments, provide a summary:
- How many comments were addressed
- For each: what action was taken (reply, code fix, won't fix)
- How many proposals were created (pending user approval)
- How many draft replies were created (pending user approval)
- How many draft operations were created (pending user approval)
- Remaining active/pending thread count if available from `metadata.threads`
- Required reviewer status if available from `metadata.reviewers`
- Any PR state blockers such as draft/WIP or merge conflicts from `metadata.state`

Call `ListProposals` and `GetDraftCounts` to verify all actions were recorded.

## Safety rules

These constraints are enforced by the server and cannot be bypassed:

1. **All replies start as drafts.** The user must approve each draft before it can be submitted.
2. **All proposals start as drafts.** The user must approve and explicitly apply each proposal.
3. **Remote actions start as drafts.** Thread status changes and reactions are local draft operations until the user approves them and runs submit.
4. **Code changes are isolated.** The fix worktree is separate from the user's working directory. No changes affect the user's branch until explicitly applied.
5. **AI can only modify AI-authored items.** AI cannot edit or delete user-authored drafts or proposals.
6. **Approve, apply, and reject are user-only operations.** These are not available as MCP tools.

## Writing effective responses

- **Be concise.** One issue per reply.
- **Acknowledge the reviewer.** Show you understood their concern.
- **For code fixes:** Describe what was changed and why in the reply.
- **For won't fix:** Explain the reasoning clearly and respectfully.
- **Use markdown** for code references, links, and formatting.

## Tool reference

See [../reviewing-prs/references/TOOLS.md](../reviewing-prs/references/TOOLS.md) for complete tool API documentation including all parameters, return types, and error handling.
