# Actions

An action is a button on an entry (or inside a section) that triggers a `command` when clicked. Commands are HTTP requests or CLI processes. Clicking runs the command as a **background job** — the button shows live progress (spinner, elapsed timer, streamed output, Cancel) and the outcome is recorded in the entry's activity log.

## Action shape

```json
{
  "label": "Approve PR",
  "style": "success",
  "confirmMessage": "Approve PR #482?",
  "parameters": [ /* optional, see below */ ],
  "command": { /* http or cli, see below */ },
  "onSuccess": "archive",
  "undoCommand": { /* optional, mirror of command */ },
  "undoWindowSeconds": 10
}
```

| Field | Required | Notes |
|-------|----------|-------|
| `label` | yes | Button text. Keep imperative ("Approve PR", "Post Comment"). |
| `style` | no | `default` \| `primary` \| `success` \| `danger`. Visual hint, not behavior. |
| `confirmMessage` | no | Without `parameters`: shows a confirm pill. With `parameters`: shown above the form as guidance. |
| `command` | yes | What runs on click. |
| `parameters` | no | Inline form fields. See [Parameterized actions](#parameterized-actions). |
| `onSuccess` | no | `archive` (default), `keep`, or `delete` — what happens to the entry after success. |
| `undoCommand` | no | If set, an undo toast appears for `undoWindowSeconds` (default 10) after success. |

## `command.type: "http"`

```json
{
  "type": "http",
  "method": "POST",
  "url": "https://api.github.com/repos/acme/backend/pulls/482/reviews",
  "headers": {
    "Authorization": "Bearer {{GITHUB_TOKEN}}",
    "Accept": "application/vnd.github+json"
  },
  "body": {
    "event": "APPROVE",
    "body": "{{param.message}}"
  }
}
```

- `method`: GET / POST / PUT / PATCH / DELETE. Defaults to POST.
- `url`, header values, and string leaves of `body` all support `{{param.NAME}}`, `{{content.*}}`/`{{entry.*}}`, and `{{SECRET}}` substitution.
- `body` is a JSON value — prefer an object over a stringified one.

## `command.type: "cli"`

```json
{
  "type": "cli",
  "program": "gh",
  "args": ["pr", "review", "482", "--approve", "--body", "{{param.message}}"],
  "workingDirectory": "/path/to/repo"
}
```

Each arg is a separate process argument — no shell quoting needed. Arg strings support all three placeholder namespaces (`{{param.NAME}}`, `{{content.*}}`/`{{entry.*}}`, `{{SECRET}}`).

## Parameterized actions

When the user must supply or edit something before the command runs (a draft comment, an approval message, a reason, a number), declare `parameters`. The UI replaces the simple confirm pill with an inline form, and the user's input is substituted into the command via `{{param.NAME}}` placeholders.

### Parameter object

```json
{
  "name": "body",
  "label": "Comment",
  "type": "multiline",
  "default": "Consider making CacheTTL configurable via appsettings.",
  "required": true,
  "placeholder": "Write your comment...",
  "helpText": "Markdown is supported by GitHub."
}
```

| Field | Required | Notes |
|-------|----------|-------|
| `name` | yes | Identifier referenced as `{{param.NAME}}`. Must match `[A-Za-z_][A-Za-z0-9_]*`. |
| `label` | yes | Form label. |
| `type` | no | `text` (default) \| `multiline` \| `select` \| `number` \| `boolean`. |
| `default` | no | Initial value (your AI's draft). For numeric/boolean fields the string is parsed. |
| `options` | required for `select` | Allowed values. |
| `required` | no | If true, must be non-empty before submission. |
| `placeholder` | no | Hint text inside the input. |
| `helpText` | no | Help text under the input. |

### Substitution rules

1. **Order: `{{param.NAME}}` → `{{content.*}}`/`{{entry.*}}` → `{{SECRET}}`.** Namespaces are separate; a parameter named `GITHUB_TOKEN` would NOT collide with a secret named `GITHUB_TOKEN`.
2. **JSON body substitution** walks string leaves only. Special characters in user input (quotes, backslashes, newlines) are JSON-escaped automatically; the resulting body is always valid JSON.
3. **CLI args** are substituted per-element, so quoting/escaping is handled by the OS process API — no shell injection surface.
4. **Unknown placeholders are left in place** if not supplied/resolvable. Pair a `{{param.X}}` with `required: true` if it must always resolve.

## Content & entry references

Beyond `{{param.NAME}}` (user input) and `{{SECRET}}` (config/env), a command can pull data from the entry itself, resolved server-side at execution time:

| Reference | Expands to |
|-----------|-----------|
| `{{content.self}}` | The text of the block that owns a **section** action (e.g. the comment being approved). |
| `{{content.ID}}` | The text of the block whose `id` matches `ID` (searched at any depth). |
| `{{entry.FIELD}}` | An entry field: `title`, `subtitle`, `type`, `id`, `source`, `severity`, or `tags` (comma-joined). |

These are the mechanism for "edit the comment, then the action uses the edited text." Mark the comment block `editable: true` and give it an `id` (or use `{{content.self}}` on a section action); when the user edits it inline, the edit persists to the entry, and any command referencing it expands to the **current** text — for both an Approve action and a later Submit.

```json
{
  "type": "section",
  "title": "Comment on Provisioner.cs:68",
  "content": [
    { "type": "markdown", "id": "draft-abc", "editable": true, "body": "Consider reconciling drift here." }
  ],
  "actions": [
    {
      "label": "Approve",
      "style": "success",
      "onSuccess": "keep",
      "command": {
        "type": "cli",
        "program": "powerreview",
        "args": ["comment", "approve", "--draft-id", "abc", "--body", "{{content.self}}"]
      }
    }
  ]
}
```

A parameter `default` may also contain a content reference (e.g. `"default": "{{content.self}}"`) to seed the form from a block without duplicating its text.

### Validation (server-side)

The server validates the supplied dict against the declared `parameters` before execution and returns 400 on:

- Missing required values.
- Numeric values that don't parse.
- Boolean values that don't parse as `true`/`false`.
- Select values not in `options`.
- Unknown keys (not declared on the action) — surfaces typos like `"bdy"` instead of `"body"`.

The dashboard performs the same checks client-side as a UX courtesy but the server is authoritative.

### Drafts persist

Parameter form values are saved to `localStorage` per `entry+action` so a SignalR refresh or unrelated re-render won't wipe a long edit. The draft is cleared on successful submission or explicit Cancel.

## Use cases for parameters

- **AI-drafted PR comment the user should edit before posting.** `multiline`, required, `default` = your draft.
- **Approval message (optional).** `multiline`, not required, `default` = a friendly LGTM.
- **Reason for requesting changes (required).** `multiline`, required, no default.
- **Severity selector for a finding.** `select` with `options: ["nit", "suggestion", "blocker"]`.
- **Quantity for a batched operation.** `number`, default `1`.
- **"Skip CI" toggle on a deploy.** `boolean`, default `"false"`.

## OnSuccess behavior

| Value | Effect |
|-------|--------|
| `archive` (default) | Entry moves to history. Most common. |
| `keep` | Entry stays in the active list. Use for actions the user may repeat — e.g., per-section "Post Comment" buttons in a PR review. |
| `delete` | Entry is permanently removed. Use sparingly. |

`onSuccess` is applied when the background job **finishes successfully** (not when the button is clicked).

## Long-running actions

Every action runs as a background job, so a slow command (a deploy, a long CLI) doesn't block the request or the UI:

- The button shows a spinner, an elapsed timer, a live tail of streamed CLI output, and a **Cancel** button (cancelling kills the process tree).
- A per-job timeout can be set globally via `actions.defaultTimeoutSeconds` in `actionview.json`; concurrency is bounded by `actions.maxConcurrentJobs`.
- The run — start, streamed output, exit code, duration, and outcome — is recorded in the entry's activity log (`GET /api/entries/{id}/history`), which survives archive/dismiss/delete.

You don't author anything special for this; it applies to all actions. Just prefer commands that stream progress to stdout so the user sees something while they wait.

If `undoCommand` is set, a toast appears after success with an "Undo" button for `undoWindowSeconds` (default 10). Clicking it executes `undoCommand` and unarchives the entry. Useful for soft-irreversible operations (e.g., posted a comment by mistake → delete it via the GitHub API).

When the original action declares `parameters`, the undo command can reference the same `{{param.NAME}}` placeholders — the values used for the original submission are reused for undo.

## Anti-patterns

- ❌ Hard-coding user-editable text into `command.args`.
  ✅ Declare a `parameter` and reference `{{param.body}}`.
- ❌ Putting a secret in `default`.
  ✅ Use `{{SECRET}}` in the command and store the value in `actionview.json`.
- ❌ Using `confirmMessage` to remind the user to edit something.
  ✅ Use `parameters` so they actually can.
- ❌ Stringifying a JSON body manually.
  ✅ Pass an object; substitution happens at the leaf level and escapes correctly.
