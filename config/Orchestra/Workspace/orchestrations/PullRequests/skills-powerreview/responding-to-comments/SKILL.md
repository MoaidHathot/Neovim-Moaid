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

## Tool invocation

This skill assumes the AI agent is connected to the **PowerReview MCP server** (`powerreview mcp` via stdio). Tools are called by their MCP tool name (e.g., `SyncThreads`, `CreateProposal`).

If using the CLI instead of MCP, each tool has an equivalent CLI command. The mapping:

| MCP Tool | CLI Equivalent |
|----------|---------------|
| `SyncThreads(prUrl)` | `powerreview sync --pr-url <url>` |
| `ListCommentThreads(prUrl)` | `powerreview threads --pr-url <url>` |
| `GetReviewSession(prUrl)` | `powerreview session --pr-url <url>` |
| `ReplyToThread(prUrl, threadId, body)` | `powerreview reply --pr-url <url> --thread-id <n> --body <text>` |
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
| Submit replies | `powerreview submit --pr-url <url>` |

## Comment response workflow

When the user wants you to respond to comments on their PR, follow these steps:

```
Response Progress:
- [ ] Step 1: Sync and load the latest comment threads
- [ ] Step 2: Identify new/unaddressed comments
- [ ] Step 3: For each comment, decide the action (reply, code fix, or won't fix)
- [ ] Step 4: Execute the appropriate action
- [ ] Step 5: Summarize what was done
```

### Step 1: Sync and load threads

1. Call `SyncThreads` to fetch the latest comment threads from the remote provider.
2. Call `ListCommentThreads` to see all threads and their statuses.
3. Call `GetReviewSession` to understand the PR context (branches, files, iteration).

### Step 2: Identify new/unaddressed comments

Look through the threads for comments that need a response. Focus on:

- Threads with status `Active` or `Pending` (not yet resolved)
- Comments from reviewers (not from the PR author)
- Comments that ask questions, request changes, or point out issues
- Comments that don't already have a reply addressing them

### Step 3: Decide the action

For each comment that needs a response, decide one of these actions:

#### Action A: Draft reply (no code change needed)
Use when the comment is a question, clarification request, or the fix is trivial enough to describe in words.

#### Action B: Code fix (code change needed)
Use when the comment identifies an actual code issue that should be fixed. The AI will make the change on a temporary branch.

#### Action C: Won't fix / By design
Use when the comment raises a valid point but the current approach is intentional or the change is out of scope. Reply with an explanation.

### Step 4: Execute the action

#### For replies (Action A and C):

Call `ReplyToThread` with:
- `prUrl` -- the pull request URL
- `threadId` -- the thread ID to reply to
- `body` -- the reply in markdown
- `agentName` -- your agent name (optional)

The reply is created as a draft. The user must approve it before it is submitted.

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

Call `ListProposals` and `GetDraftCounts` to verify all actions were recorded.

## Safety rules

These constraints are enforced by the server and cannot be bypassed:

1. **All replies start as drafts.** The user must approve each draft before it can be submitted.
2. **All proposals start as drafts.** The user must approve and explicitly apply each proposal.
3. **Code changes are isolated.** The fix worktree is separate from the user's working directory. No changes affect the user's branch until explicitly applied.
4. **AI can only modify AI-authored items.** AI cannot edit or delete user-authored drafts or proposals.
5. **Approve, apply, and reject are user-only operations.** These are not available as MCP tools.

## Writing effective responses

- **Be concise.** One issue per reply.
- **Acknowledge the reviewer.** Show you understood their concern.
- **For code fixes:** Describe what was changed and why in the reply.
- **For won't fix:** Explain the reasoning clearly and respectfully.
- **Use markdown** for code references, links, and formatting.

## Tool reference

See [../reviewing-prs/references/TOOLS.md](../reviewing-prs/references/TOOLS.md) for complete tool API documentation including all parameters, return types, and error handling.
