Review this Pull Request using the loaded `pr-review-as-liabadi` skill.

## PR metadata
{{prepare-pr-data.output}}

## PR Changes
{{fetch-pr-diff.output}}

## Work Item Context
{{fetch-work-items.output}}

## Review Session
{{open-review-session.output}}

Focus only on comments that this persona would realistically leave. Prefer a smaller number of high-signal comments over broad coverage.

It is not mandatory to leave comments. Leave draft comments only if you find substantive, in-scope issues that this persona would realistically raise.

If you find meaningful issues within this persona's scope:
1. Use the PowerReview MCP CreateComment tool to leave draft comments on the specific file and line range.
2. Use the PR URL from the review session data.
3. Keep one issue per comment.

IMPORTANT: When calling CreateComment or ReplyToThread, always pass agentName: "Lior Abadi" so your comments are attributed correctly.

If you find nothing meaningful within this persona's scope, leave no comments and return a summary that clearly states there is nothing substantive for this persona to add.

After completing the review, output a JSON summary:
{
  "reviewer": "Lior Abadi",
  "commentsLeft": <count, may be 0>,
  "criticalIssues": <count>,
  "outOfScope": true/false,
  "summary": "1-3 sentences",
  "status": "approved|approved-with-suggestions|needs-work"
}
