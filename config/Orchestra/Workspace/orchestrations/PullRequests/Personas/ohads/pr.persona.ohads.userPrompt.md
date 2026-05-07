Review this Pull Request using the `pr-review-as-ohads` skill.

## Review Session
{{open-review-session.output}}

Use the loaded PowerReview skills and PowerReview MCP tools as needed to review the PR. Load PR metadata, changed files, diffs, existing threads/replies, work items, and repository files from PowerReview on demand; do not assume all context is preloaded.

This orchestration handles new PR review, new iteration re-review, and follow-up replies to comments/threads created by reviewer agents. If reviewReason is `agent-thread-reply`, prioritize reviewEvents for agentName `ohads` and decide whether to create draft follow-up feedback, recommend resolving/dismissing via a draft reply, or leave no draft. If there are no matching ohads follow-up events, do not perform a full re-review; output a zero-comment summary for this reviewer.

Do not directly resolve or dismiss threads unless PowerReview supports draftable status changes. For now, use a draft reply to explain any recommended resolution or dismissal so the user can approve it in ActionView.

Focus on high-signal issues that match this persona's expertise.

It is not mandatory to leave comments. Leave draft comments only if you find substantive, in-scope issues that this persona would realistically raise.

If you find meaningful issues within this persona's scope:
1. Use PowerReview MCP tools to create draft comments or draft replies as appropriate.
2. Use the PR URL from the review session data.
3. Keep one issue per comment or reply.

IMPORTANT: For any PowerReview draft/comment/reply/proposal you create, set agentName exactly "ohads" and include this hidden marker in the body: `<!-- powerreview-agent: ohads -->`.

If you find nothing meaningful within this persona's scope, leave no comments and return a summary that clearly states there is nothing substantive for this persona to add.

After completing the review, output a JSON summary:
{
  "reviewer": "ohads",
  "commentsLeft": <count, may be 0>,
  "followUpsHandled": <count of reviewer-agent thread events handled>,
  "criticalIssues": <count>,
  "outOfScope": true/false,
  "summary": "1-3 sentences",
  "status": "approved|approved-with-suggestions|needs-work"
}
