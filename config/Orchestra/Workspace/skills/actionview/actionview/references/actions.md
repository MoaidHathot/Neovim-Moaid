# Actions

An action is a button on an entry (or inside a section) that triggers a `command` when clicked. Commands are HTTP requests or CLI processes.

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
- `url`, header values, and string leaves of `body` all support `{{SECRET}}` and `{{param.NAME}}` substitution.
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

Each arg is a separate process argument — no shell quoting needed. Arg strings support both placeholder namespaces.

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

1. **`{{param.NAME}}` is resolved before `{{SECRET}}`.** Namespaces are separate; a parameter named `GITHUB_TOKEN` would NOT collide with a secret named `GITHUB_TOKEN` — they live behind different placeholders.
2. **JSON body substitution** walks string leaves only. Special characters in user input (quotes, backslashes, newlines) are JSON-escaped automatically; the resulting body is always valid JSON.
3. **CLI args** are substituted per-element, so quoting/escaping is handled by the OS process API — no shell injection surface.
4. **Unknown `{{param.X}}` placeholders are left in place** if the parameter isn't supplied. This is intentional — pair with `required: true` if the placeholder must always resolve.

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

## Undo

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
