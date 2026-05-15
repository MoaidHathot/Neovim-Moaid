---
name: writing-orchestrations
description: Creates and validates Orchestra orchestration files (JSON/YAML) that define DAGs of steps (Prompt, Command, Script, Http, Transform, Approval, Orchestration) with triggers, hooks, MCPs, subagents, loops, typed inputs, human-in-the-loop pauses, and template expressions. Use when authoring new orchestrations, generating orchestration files from descriptions, reviewing existing orchestrations for correctness, or debugging orchestration issues.
---

# Orchestra Orchestration Authoring Reference

Complete reference for creating valid, idiomatic Orchestra orchestration files.

**Detailed references** (read on demand):
- [references/examples.md](references/examples.md) -- Full real-world example orchestrations
- [references/full-schema-reference.md](references/full-schema-reference.md) -- Complete property-level documentation with all edge cases

## Format

Orchestrations are single JSON or YAML objects. Three fields are required: `name`, `description`, `steps`. YAML is recommended for orchestrations with multi-line prompts (use `|` block scalars).

**Editor schema validation.** Bind the orchestration JSON Schema for autocomplete, type-checking, and unknown-field errors. Pick one of three options based on how you obtained Orchestra:

1. **Public URL** (works anywhere, requires network the first time):
   - JSON: `"$schema": "https://raw.githubusercontent.com/MoaidHathot/orchestra/main/schemas/orchestration.schema.json"`
   - YAML: `# yaml-language-server: $schema=https://raw.githubusercontent.com/MoaidHathot/orchestra/main/schemas/orchestration.schema.json`
   - Same pattern for `orchestra.mcp.schema.json` and `orchestra.services.schema.json`.
   - For version-pinned validation, replace `main` with a release tag (e.g., `v0.2.0`).

2. **Local copy bundled with the tool** (offline, version-pinned to your installed Orchestra):
   - Run once in your project root: `orchestra schemas`
   - This writes the three schemas to `./.orchestra/schemas/`.
   - Then reference them with a relative path:
     - JSON: `"$schema": ".orchestra/schemas/orchestration.schema.json"`
     - YAML: `# yaml-language-server: $schema=./.orchestra/schemas/orchestration.schema.json`
   - Use `--output <dir>` to choose a different folder; `--force` to overwrite.

3. **Repository-relative path** (only inside this repository's `examples/` folder):
   - JSON: `"$schema": "../schemas/orchestration.schema.json"`
   - YAML: `# yaml-language-server: $schema=../schemas/orchestration.schema.json`

YAML modelines work in VS Code (Red Hat YAML extension), JetBrains IDEs, and any editor on `yaml-language-server`. A top-level `$schema:` key is also supported.

## Top-Level Properties

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | string | Yes | -- | Unique kebab-case name |
| `description` | string | Yes | -- | Human-readable description |
| `steps` | Step[] | Yes | -- | Array of steps forming a DAG |
| `version` | string | No | `"1.0.0"` | Semantic version |
| `inputs` | object | No | null | Typed input schema (keys = names, values = InputDefinition) |
| `trigger` | TriggerConfig | No | Manual | How the orchestration is triggered |
| `mcps` | Mcp[] | No | [] | Inline MCP server definitions |
| `defaultModel` | string | No | null | Default model for all Prompt steps. Steps can override. |
| `agentPool` | object | No | provider defaults | Provider worker-pool capacity request for prompt execution |
| `defaultSystemPromptMode` | string | No | null | `"append"`, `"replace"`, or `"customize"` for all Prompt steps |
| `defaultRetryPolicy` | RetryPolicy | No | null | Default retry for all steps |
| `defaultStepTimeoutSeconds` | int | No | null | Default per-step timeout |
| `timeoutSeconds` | int | No | 3600 | Orchestration-level timeout (0 to disable) |
| `variables` | object | No | {} | Key-value pairs accessed via `{{vars.name}}` |
| `tags` | string[] | No | [] | Categorization tags |
| `hooks` | Hook[] | No | [] | Lifecycle hooks that run after step or orchestration outcomes |
| `pauseTimeoutDuringWait` | bool | No | true | When true, the orchestration timeout clock pauses while a step is awaiting human input (Approval step or `orchestra_request_user_input`). Set to false for hard SLAs that include human response latency. |
| `defaultEnableTools` | string[] | No | [] | Opt-in engine tool names enabled by default for every Prompt step that does not specify its own `enableTools`. Currently supports `"request_user_input"`. |
| `metadata` | object | No | {} | Free-form metadata (any JSON shape: string, number, bool, array, nested object). Not inspected by the runtime; for authors and managers only. Use for datetime, owners, ticket links, environment, SLA, etc. |

## Typed Inputs (InputDefinition)

Each key in `inputs` is the input name. Values:

| Property | Type | Default | Description |
|---|---|---|---|
| `type` | string | `"string"` | `"string"`, `"boolean"`, or `"number"` |
| `description` | string | null | For docs and MCP schema generation |
| `required` | bool | true | Must be provided at runtime |
| `default` | string | null | Default for optional inputs |
| `enum` | string[] | [] | Allowed values (case-insensitive) |
| `multiline` | bool | false | UI hint: renders textarea instead of single-line input |

## Hooks

Hooks run after step or orchestration lifecycle events. They are top-level orchestration configuration, not DAG steps. Use them for follow-up automation such as notifications, archival, incident creation, or failure triage.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | string | No | null | Optional hook name for diagnostics and reporting |
| `on` | string | Yes | -- | Event: `step.success`, `step.failure`, `step.after`, `step.awaitingInput`, `orchestration.success`, `orchestration.failure`, or `orchestration.after` |
| `when` | HookWhen | No | null | Optional filter to decide whether the hook should run |
| `payload` | HookPayload | No | `{ detail: compact, includeRefs: false }` | Controls how much run/step data is included in the JSON payload |
| `action` | HookAction | Yes | -- | What to execute when the hook fires |
| `failurePolicy` | string | No | `warn` | `warn` or `ignore` when the hook action fails |

### Hook Filters (`when`)

In v1, filtering is intentionally small and step-focused:

```yaml
when:
  steps:
    names: [build, deploy]
    status: failed
    match: any
```

`when.steps` properties:

| Property | Type | Default | Description |
|---|---|---|---|
| `names` | string[] | [] | Optional step names to evaluate |
| `status` | string | `any` | `any`, `succeeded`, `failed`, `cancelled`, `skipped`, `noAction`, or `nonSucceeded` |
| `match` | string | `any` | Whether `any` or `all` named steps must satisfy the condition |

### Hook Payload (`payload`)

Hook payloads are structured JSON sent to the action on stdin.

| Property | Type | Default | Description |
|---|---|---|---|
| `detail` | string | `compact` | `compact`, `standard`, or `full` step detail level |
| `steps` | string or string[] | null | `none`, `current`, `failed`, `nonSucceeded`, `terminal`, `all`, or explicit step names |
| `includeRefs` | bool | `false` | Include API and MCP references for fetching more run data |

### Hook Action (`action`)

In v1, hooks support `script` actions only.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | string | Yes | -- | Must be `script` |
| `shell` | string | No | `pwsh` | Shell/interpreter used to execute the hook |
| `script` | string | Yes* | -- | Inline script content |
| `scriptFile` | string | Yes* | -- | Path to script file, resolved relative to the orchestration file |
| `arguments` | string[] | No | [] | Arguments passed to the script |
| `workingDirectory` | string | No | null | Optional working directory for the hook process |
| `environment` | object | No | {} | Environment variables for the hook process |
| `includeStdErr` | bool | No | false | Include stderr in the action output when the script succeeds |

*Use exactly one of `script` or `scriptFile`.

Example:

```yaml
hooks:
  - name: archive-run-failure
    on: orchestration.failure
    payload:
      detail: compact
      steps: failed
      includeRefs: true
    action:
      type: script
      shell: pwsh
      scriptFile: ./hooks/archive-failure.ps1
```

Hooks are different from Prompt step handlers:

- `inputHandlerPrompt` and `outputHandlerPrompt` transform Prompt step input/output
- hooks run after lifecycle events and do not alter orchestration execution

## Steps

Steps form a DAG. Steps with no `dependsOn` run first (in parallel). Downstream steps run when all dependencies complete.

### Base Step Properties (all types)

| Property | Type | Required | Default |
|---|---|---|---|
| `name` | string | Yes | -- |
| `type` | string | Yes | -- |
| `dependsOn` | string[] | No | [] |
| `parameters` | string[] or object | No | [] |
| `enabled` | bool | No | true |
| `timeoutSeconds` | int | No | null |
| `retry` | RetryPolicy | No | null |

### Prompt Step (type: "Prompt")

Calls an LLM.

| Property | Type | Required | Default |
|---|---|---|---|
| `systemPrompt` | string | Yes* | -- |
| `systemPromptFile` | string | Yes* | -- |
| `userPrompt` | string | Yes* | -- |
| `userPromptFile` | string | Yes* | -- |
| `model` | string | No | from `defaultModel` |
| `inputHandlerPrompt` | string | No | null |
| `inputHandlerPromptFile` | string | No | null |
| `outputHandlerPrompt` | string | No | null |
| `outputHandlerPromptFile` | string | No | null |
| `reasoningLevel` | string | No | null |
| `systemPromptMode` | string | No | null |
| `systemPromptSections` | object | No | null |
| `infiniteSessions` | object | No | null |
| `attachments` | Attachment[] | No | [] |
| `mcps` | string[] | No | [] |
| `loop` | LoopConfig | No | null |
| `subagents` | Subagent[] | No | [] |
| `skillDirectories` | string[] | No | [] |
| `enableTools` | string[] | No | null | Opt-in engine tool names this Prompt step grants the agent access to. Currently supports `"request_user_input"` (the LLM-decided human-in-the-loop tool). Falls back to the orchestration's `defaultEnableTools` when null. |

*Mutual exclusion: use `systemPrompt` OR `systemPromptFile`, not both. Same for `userPrompt`/`userPromptFile`, `inputHandlerPrompt`/`inputHandlerPromptFile`, `outputHandlerPrompt`/`outputHandlerPromptFile`.

### System Prompt Modes

- **`append`** (default): Your system prompt is added to the SDK's built-in prompts, preserving coding capabilities.
- **`replace`**: Your system prompt completely replaces the SDK's built-in prompts.
- **`customize`**: Selectively override individual sections of the built-in prompt. Use with `systemPromptSections`.

### System Prompt Section Overrides (`systemPromptSections`)

Used with `systemPromptMode: "customize"`. Keys are section identifiers, values are override objects:

| Section Key | Description |
|---|---|
| `identity` | Agent identity |
| `tone` | Communication style |
| `tool_efficiency` | Tool usage instructions |
| `environment_context` | Workspace/environment context |
| `code_change_rules` | Rules for code changes |
| `guidelines` | General guidelines |
| `safety` | Safety instructions |
| `tool_instructions` | Tool-specific instructions |
| `custom_instructions` | Custom user instructions |
| `last_instructions` | Final priority instructions |

Each section override:
| Property | Type | Required | Description |
|---|---|---|---|
| `action` | string | Yes | `"replace"`, `"remove"`, `"append"`, or `"prepend"` |
| `content` | string | No | Content for replace/append/prepend (ignored for remove) |

### Infinite Sessions (`infiniteSessions`)

Controls automatic context compaction for long-running steps.

| Property | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | true (SDK default) | Enable/disable infinite sessions |
| `backgroundCompactionThreshold` | number (0-1) | 0.80 | Context utilization ratio at which background compaction begins |
| `bufferExhaustionThreshold` | number (0-1) | 0.95 | Context utilization ratio at which the session blocks until compaction completes |

### Image Attachments (`attachments`)

Send images to the LLM alongside the prompt for vision/analysis tasks.

Each attachment has a `type`:

**File attachment** (`type: "file"`): reads an image from disk.
| Property | Type | Required | Description |
|---|---|---|---|
| `type` | string | Yes | `"file"` |
| `path` | string | Yes | Absolute path to image file. Supports template expressions. |
| `displayName` | string | No | Display name for the attachment |

**Blob attachment** (`type: "blob"`): inline base64-encoded image data.
| Property | Type | Required | Description |
|---|---|---|---|
| `type` | string | Yes | `"blob"` |
| `data` | string | Yes | Base64-encoded image data. Supports template expressions. |
| `mimeType` | string | Yes | MIME type (e.g., `"image/png"`, `"image/jpeg"`) |
| `displayName` | string | No | Display name for the attachment |

### Http Step (type: "Http")

Makes an HTTP request, captures response body.

| Property | Type | Required | Default |
|---|---|---|---|
| `url` | string | Yes | -- |
| `method` | string | No | `"GET"` |
| `headers` | object | No | {} |
| `body` | string | No | null |
| `contentType` | string | No | `"application/json"` |

### Transform Step (type: "Transform")

Pure string interpolation (no LLM, no I/O).

| Property | Type | Required | Default |
|---|---|---|---|
| `template` | string | Yes | -- |
| `contentType` | string | No | `"text/plain"` |

### Command Step (type: "Command")

Executes a direct executable as a child process, captures stdout. Use this for commands such as `dotnet`, `git`, `dnx`, or `npx`.

Do not use `Command` for shell snippets or wrappers such as `pwsh -Command`, `powershell -Command`, `bash -c`, or `sh -c`. Use a `Script` step instead so quoting, pipes, multiline logic, and JSON values are handled by the script file invocation.

| Property | Type | Required | Default |
|---|---|---|---|
| `command` | string | Yes | -- |
| `arguments` | string[] | No | [] |
| `workingDirectory` | string | No | current dir |
| `environment` | object | No | {} |
| `includeStdErr` | bool | No | false |
| `stdin` | string | No | null |

### Script Step (type: "Script")

Executes an inline or file-based script via a shell interpreter (e.g., `pwsh`, `bash`, `python`, `node`). Captures stdout. Use this for shell snippets, pipelines, multi-line scripts, quoting-sensitive values, JSON manipulation, and anything that would otherwise be passed to `pwsh -Command` or `bash -c`. Use YAML `|` blocks for best readability.

| Property | Type | Required | Default |
|---|---|---|---|
| `shell` | string | Yes | -- |
| `script` | string | Yes* | -- |
| `scriptFile` | string | Yes* | -- |
| `arguments` | string[] | No | [] |
| `workingDirectory` | string | No | current dir |
| `environment` | object | No | {} |
| `includeStdErr` | bool | No | false |
| `stdin` | string | No | null |

*Mutual exclusion: use `script` OR `scriptFile`, not both. `scriptFile` paths resolve relative to the orchestration file's directory.

Pass values into scripts with `arguments` or `stdin` instead of interpolating large or heavily quoted values into the script body. In PowerShell, `arguments` are available as `$args[0]`, `$args[1]`, and so on.

For file paths that should be relative to the orchestration file, anchor them explicitly with `{{orchestration.sourceDirectory}}`. Do not pass bare relative paths to runtime file-writing code, because process working directories can differ between hosts.

### Orchestration Step (type: "Orchestration")

Invokes another registered orchestration. Use this when a flow should delegate to a reusable child orchestration instead of duplicating its steps.

| Property | Type | Required | Default |
|---|---|---|---|
| `orchestration` | string | Yes | -- |
| `parameters` | object | No | {} |
| `mode` | string | No | `sync` |
| `inputHandlerPrompt` | string | No | null |
| `inputHandlerModel` | string | No | from `defaultModel` |

`mode` is `sync` or `async`. In `sync` mode, the parent waits for the child to finish and uses the child's final output as this step's output. In `async` mode, the parent continues after dispatch.

`parameters` maps child input names to values. Values support template expressions and are passed as strings at runtime.

`inputHandlerPrompt` can reshape child parameters before launch. It must return a JSON object mapping parameter names to string values. If handler parsing fails, runtime falls back to the original parameters, so use Script validation for hard guarantees.

**Drill-in template bindings.** For every step whose `type` is `Orchestration`, dependants can read the child run's per-step data via these template accessors. The data is populated on every terminal branch (success, failure, cancellation) and is in-process / untruncated — no MCP round-trip needed.

| Expression | Resolves to |
|---|---|
| `{{S.output}}` | Child's final content on success, or top-level error on failure (backward-compatible behavior) |
| `{{S.executionId}}` | Child run's execution id |
| `{{S.status}}` | Lowercase child status (`succeeded`/`failed`/`cancelled`/`pending`) |
| `{{S.errorMessage}}` | Child's top-level error |
| `{{S.completionReason}}` | `orchestra_complete` reason if early-completed |
| `{{S.childResult}}` | Full JSON blob of executionId/status/error/finalContent/stepResults |
| `{{S.steps}}` | JSON map of all child step results |
| `{{S.steps.<childStep>.output}}` | Untruncated content of one child step |
| `{{S.steps.<childStep>.rawOutput}}` | Pre-output-handler content of one child step |
| `{{S.steps.<childStep>.error}}` | Error message of one child step |
| `{{S.steps.<childStep>.status}}` | Lowercase status of one child step |
| `{{S.steps.<childStep>.files}}` / `files[N]` | Saved file paths of one child step |

Use these for self-healing repair patterns: a downstream Prompt step can inspect `{{attempt-1.steps.build.error}}` and `{{attempt-1.steps.codegen.output}}` to build a corrective prompt — works whether attempt-1 succeeded, failed, or was cancelled. See `examples/self-healing-with-child-bindings.yaml` for a complete pattern, or `docs/orchestration-step-deep-dive.md` for the full reference.

### Approval Step (type: "Approval")

Pauses the orchestration and waits for human input. The step persists a pending input record, transitions to `AwaitingInput` status, fires the `step.awaitingInput` hook event, and blocks until a user responds via the host's HumanInput API (or via the CLI / Portal). The user's response (`reply` or `choice`, with `reply` winning) becomes the step's output content and can be referenced by downstream steps via `{{stepName.output}}`.

Approval steps survive host restarts: the persisted record is preserved, and on resume the step re-attaches to the still-outstanding wait.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `prompt` | string | Yes | -- | Human-readable prompt presented to the user. Supports template expressions resolved at execution time. |
| `choices` | string[] | No | [] | Allowed responses. When non-empty, the response endpoint validates that the supplied `choice` is one of these (case-insensitive). When empty, free-form replies are accepted. |
| `timeoutSeconds` | int | No | null | Per-step timeout. When elapsed without a response, behavior is governed by `onTimeout`. When null, the wait runs indefinitely (subject to the orchestration timeout, which by default pauses during waits per `pauseTimeoutDuringWait`). |
| `onTimeout` | string | No | `fail` | Behavior when `timeoutSeconds` fires. One of: `fail` (mark step Failed), `defaultResponse` (use `defaultResponse` as the answer), `cancel` (cancel the entire orchestration). |
| `defaultResponse` | string | No | null | Required when `onTimeout: defaultResponse`. The fallback content used as the step's output. |

Example:
```yaml
- name: review-deploy
  type: Approval
  dependsOn: [build]
  prompt: "Approve deploy of {{param.service}} to {{param.env}}? Build: {{build.output}}"
  choices: [approve, reject]
```

Respond via API or CLI:
```bash
orchestra pending
orchestra respond <orchestration-name> <runId> review-deploy --choice approve --by alice
```

Or via raw HTTP:
```http
POST /api/orchestrations/<orchestration-name>/runs/<runId>/respond?step=review-deploy
{ "choice": "approve", "respondedBy": "alice" }
```

### Engine-Tool HITL Variant: `orchestra_request_user_input`

For LLM-decided "ask the human only when needed" pauses inside `Prompt` steps, opt the Prompt step into the `request_user_input` engine tool. The agent can then call `orchestra_request_user_input(prompt, choices?)` mid-conversation; the call blocks until the user responds, and the reply is returned as the tool result so the agent continues with the answer in hand.

```yaml
- name: writer
  type: Prompt
  systemPrompt: |
    You write articles. Use orchestra_request_user_input ONLY when the topic is
    genuinely ambiguous and a clarifying decision would meaningfully improve the
    output. Otherwise, just write the article.
  userPrompt: "Write an article about {{param.topic}}."
  model: claude-opus-4.6
  enableTools: [request_user_input]
```

Differences from the declarative `Approval` step:

| Aspect | Approval step | `orchestra_request_user_input` |
|---|---|---|
| Decided by | Author (always pauses) | LLM (only if needed) |
| Step status during wait | `AwaitingInput` (agent session torn down) | `Running` (agent session held in memory) |
| Survives host restart | Yes (persistent record + checkpoint resume) | No — run is marked `Failed (HostShutdownDuringWait)`; retry from previous step's checkpoint |
| Use case | Explicit deploy/compliance/destructive-op gates | Mid-task clarifications the LLM uses to keep working |

Both paths emit the `step.awaitingInput` hook event with the same payload structure, both persist a `PendingInputRecord`, and both route through `POST /api/orchestrations/{name}/runs/{runId}/respond?step={stepName}`.

## Loop Configuration (Checker Pattern)

A Prompt step with `loop` acts as a checker for iterative refinement.

| Property | Type | Required |
|---|---|---|
| `target` | string | Yes |
| `maxIterations` | int (1-10) | Yes |
| `exitPattern` | string | Yes |

The checker evaluates the target's output. If `exitPattern` is NOT found (case-insensitive), the target re-runs with checker feedback. Repeats up to `maxIterations`.

## Subagents

Multi-agent delegation within a single Prompt step.

| Property | Type | Required | Default |
|---|---|---|---|
| `name` | string | Yes | -- |
| `prompt` | string | Yes* | -- |
| `promptFile` | string | Yes* | -- |
| `displayName` | string | No | null |
| `description` | string | No | null |
| `tools` | string[] | No | null (all) |
| `mcps` | string[] | No | [] |
| `infer` | bool | No | true |

*Exactly one of `prompt` or `promptFile` required.

## Retry Policy

| Property | Type | Default |
|---|---|---|
| `maxRetries` | int | 3 |
| `backoffSeconds` | double | 1.0 |
| `backoffMultiplier` | double | 2.0 |
| `retryOnTimeout` | bool | true |

## Triggers

### Manual (default)
```yaml
trigger:
  type: manual
```

### Scheduler
| Property | Type | Default |
|---|---|---|
| `cron` | string | null |
| `intervalSeconds` | int | null |
| `maxRuns` | int | null (unlimited) |

### Loop Trigger
| Property | Type | Default |
|---|---|---|
| `delaySeconds` | int | 0 |
| `maxIterations` | int | null (unlimited) |
| `continueOnFailure` | bool | false |

### Webhook
| Property | Type | Default |
|---|---|---|
| `secret` | string | null |
| `maxConcurrent` | int | 1 |
| `response` | WebhookResponseConfig | null |

WebhookResponseConfig: `waitForResult` (bool), `responseTemplate` (string), `timeoutSeconds` (int, default 120).

All triggers share: `type` (required), `enabled` (bool, default true), `inputHandlerPrompt` (string), `inputHandlerModel` (string).

## MCP Definitions

### Local MCP (stdio transport)
```yaml
mcps:
  - name: filesystem
    type: local
    command: npx
    arguments:
      - "-y"
      - "@modelcontextprotocol/server-filesystem"
      - "{{workingDirectory}}"
```

### Remote MCP (HTTP transport)
```yaml
mcps:
  - name: cloud-tools
    type: remote
    endpoint: "https://mcp.example.com/tools"
    headers:
      Authorization: "Bearer {{env.TOKEN}}"
```

MCPs defined at orchestration level. Steps reference by name: `mcps: [filesystem]`.
A companion `mcp.json` or `orchestra.mcp.json` file can define MCPs externally.

## Template Expressions

Syntax: `{{expression}}` -- supported in prompts, URLs, headers, bodies, templates, command arguments, working directories, environment values, stdin, variable values, MCP configs, skill directory paths.

| Expression | Description |
|---|---|
| `{{param.name}}` | Runtime parameter |
| `{{vars.name}}` | Orchestration variable (recursive expansion) |
| `{{env.VAR_NAME}}` | Environment variable |
| `{{stepName.output}}` | Step's processed output |
| `{{stepName.rawOutput}}` | Step's raw output (before output handler) |
| `{{stepName.files}}` | JSON array of saved file paths |
| `{{stepName.files[N]}}` | Nth file path (0-indexed) |
| `{{orchestration.name}}` | Orchestration name |
| `{{orchestration.version}}` | Version |
| `{{orchestration.runId}}` | Run ID |
| `{{orchestration.startedAt}}` | Start timestamp |
| `{{orchestration.tempDir}}` | Temp directory for this run |
| `{{step.name}}` | Current step name |
| `{{step.type}}` | Current step type |
| `{{server.url}}` | Orchestra server URL |
| `{{workingDirectory}}` | Working directory |

**Orchestration-step accessors** (only on steps whose `type` is `Orchestration`):

| Expression | Description |
|---|---|
| `{{S.executionId}}` | Child run's execution id |
| `{{S.status}}` | Lowercase child status (succeeded/failed/cancelled/pending) |
| `{{S.errorMessage}}` | Child's top-level error |
| `{{S.completionReason}}` | `orchestra_complete` reason if early-completed |
| `{{S.childResult}}` | Full JSON of child run (executionId/status/error/finalContent/stepResults) |
| `{{S.steps}}` | JSON map of all child step results |
| `{{S.steps.X.output}}` / `rawOutput` / `error` / `status` / `files` / `files[N]` | Drill into one child step |

## Engine Tools (Built-in, available to all Prompt steps)

| Tool | Description |
|---|---|
| `orchestra_save_file` | Save content to a file in the run's temp directory |
| `orchestra_read_file` | Read a previously saved file |
| `orchestra_set_status` | Override step status: `success`, `failed`, or `no_action` (skips downstream) |
| `orchestra_complete` | Halt entire orchestration immediately |

### Opt-in Engine Tools (per-step or default)

These tools must be explicitly enabled via `enableTools` on a Prompt step (or `defaultEnableTools` at the orchestration level). Existing pipelines see no behavior change.

| Tool (opt-in name) | Tool ID exposed to LLM | Description |
|---|---|---|
| `request_user_input` | `orchestra_request_user_input` | Pause inside a Prompt step and ask the human a question. Blocks until the user responds via the HumanInput API; the reply (or constrained choice) is returned as the tool result so the agent can naturally continue with the answer. Does NOT survive host restarts (the agent session is volatile). For long-lived approval gates, use the declarative `Approval` step instead. |


## Common Patterns

### 1. Fan-Out / Fan-In
Multiple root steps (no dependsOn) run in parallel; a downstream step depends on all of them to synthesize results.
```yaml
defaultModel: claude-opus-4.6
steps:
  - name: research-a
    type: Prompt
    systemPrompt: Research topic A.
    userPrompt: "{{param.topic}}"
  - name: research-b
    type: Prompt
    systemPrompt: Research topic B.
    userPrompt: "{{param.topic}}"
  - name: synthesize
    type: Prompt
    dependsOn: [research-a, research-b]
    systemPrompt: Synthesize the research.
    userPrompt: |
      Research A: {{research-a.output}}
      Research B: {{research-b.output}}
```

### 2. Loop/Checker (Iterative Refinement)
A checker step loops a target step until quality is met.
```yaml
- name: review
  type: Prompt
  dependsOn: [write-draft]
  systemPrompt: Review. Say APPROVED if good, REVISE if not.
  userPrompt: "{{write-draft.output}}"
  loop:
    target: write-draft
    maxIterations: 3
    exitPattern: APPROVED
```

### 3. Subagent Delegation
Coordinator delegates to specialized subagents.
```yaml
- name: coordinator
  type: Prompt
  systemPrompt: Delegate to your specialists.
  userPrompt: "{{param.task}}"
  subagents:
    - name: researcher
      description: Finds facts from the web.
      prompt: You are a researcher.
      mcps: [web-fetch]
      infer: true
    - name: writer
      description: Writes polished content.
      prompt: You are a writer.
      infer: true
```

### 4. Gate / Early Exit
A step checks conditions and halts the orchestration if nothing to do.
```yaml
- name: gate
  type: Prompt
  systemPrompt: |
    Check if there are incidents.
    If none, call orchestra_complete.
    If there are, list them.
  userPrompt: "{{check-incidents.output}}"
```

### 5. Input/Output Handlers
Pre-process dependency outputs or post-process LLM output.
```yaml
- name: analyze
  type: Prompt
  dependsOn: [fetch-data]
  inputHandlerPrompt: Extract only numeric data points from the input.
  outputHandlerPrompt: Format as a markdown table.
  systemPrompt: Analyze the data.
  userPrompt: "{{fetch-data.output}}"
```

### 6. Multi-Step Pipeline (all 5 step types)
Command -> Script -> Prompt -> Transform -> Http -> Orchestration
```yaml
defaultModel: claude-opus-4.6
steps:
  - name: build
    type: Command
    command: dotnet
    arguments: [build]
  - name: gather-info
    type: Script
    dependsOn: [build]
    shell: pwsh
    script: |
      Get-ChildItem bin -Recurse -Filter '*.dll' |
        Select-Object -ExpandProperty Name |
        ConvertTo-Json
  - name: analyze
    type: Prompt
    dependsOn: [build, gather-info]
    systemPrompt: Analyze build output.
    userPrompt: |
      Build: {{build.output}}
      Artifacts: {{gather-info.output}}
  - name: report
    type: Transform
    dependsOn: [analyze]
    template: |
      # Report
      {{analyze.output}}
  - name: notify
    type: Http
    dependsOn: [report]
    method: POST
    url: "{{vars.webhookUrl}}"
    body: '{"text": "{{report.output}}"}'
```

### 7. Webhook with Input Handler
Normalize arbitrary payloads into expected parameters.
```yaml
trigger:
  type: webhook
  maxConcurrent: 5
  inputHandlerPrompt: Extract 'eventType' and 'data' from the JSON payload.
```

### 8. Scheduled Monitoring
Run on interval, gate on no-action.
```yaml
trigger:
  type: scheduler
  intervalSeconds: 300
```

### 9. Cross-Step File References
Steps save files, downstream steps reference them.
```yaml
- name: consumer
  type: Prompt
  dependsOn: [producer]
  systemPrompt: Read and analyze the saved files.
  userPrompt: |
    Files: {{producer.files}}
    First file: {{producer.files[0]}}
```

### 10. Variables with Recursive Expansion
```yaml
variables:
  appName: my-app
  registry: "{{env.CONTAINER_REGISTRY}}/{{vars.appName}}"
  artifactPath: "/artifacts/{{vars.appName}}/{{orchestration.runId}}"
```

### 11. Customize System Prompt with Section Overrides
Surgically control specific sections while preserving others.
```yaml
- name: code-review
  type: Prompt
  systemPrompt: Review the code for accessibility.
  systemPromptMode: customize
  systemPromptSections:
    tone:
      action: replace
      content: Be direct and structured.
    code_change_rules:
      action: remove  # Read-only, no modifications
    guidelines:
      action: append
      content: |
        - Follow WCAG 2.1 AA guidelines.
        - Flag contrast ratio violations.
  userPrompt: "{{code-step.output}}"
```

### 12. Image Attachments for Vision Analysis
Send images from files or prior step output.
```yaml
- name: analyze-screenshot
  type: Prompt
  systemPrompt: Analyze this UI for accessibility issues.
  userPrompt: Describe what you see and identify problems.
  attachments:
    - type: file
      path: "{{param.imagePath}}"
      displayName: "Screenshot"
```

### 13. Infinite Sessions for Long-Running Tasks
Control context compaction thresholds per step.
```yaml
- name: large-refactor
  type: Prompt
  systemPrompt: Refactor the entire module.
  userPrompt: "{{gather-code.output}}"
  infiniteSessions:
    enabled: true
    backgroundCompactionThreshold: 0.85
    bufferExhaustionThreshold: 0.97
```

### 14. Human-in-the-Loop Approval Gate (Declarative)
A deploy that pauses for a human reviewer; the response feeds the next step.
```yaml
defaultModel: claude-opus-4.6
inputs:
  service: { type: string, required: true }
  env: { type: string, enum: [staging, production], required: true }
steps:
  - name: build
    type: Command
    command: dotnet
    arguments: [build]

  - name: review-deploy
    type: Approval
    dependsOn: [build]
    prompt: |
      Approve deploy of {{param.service}} to {{param.env}}?

      {{build.output}}
    choices: [approve, reject]
    # No timeoutSeconds — wait indefinitely. Orchestration timeout is paused
    # while awaiting input by default (pauseTimeoutDuringWait: true).

  - name: announce
    type: Transform
    dependsOn: [review-deploy]
    template: "Decision: {{review-deploy.output}}"
```

### 15. LLM-Decided HITL (Engine Tool)
The agent only pauses if it needs clarification. Existing pipelines without `enableTools` are unaffected.
```yaml
- name: writer
  type: Prompt
  systemPrompt: |
    You write articles. Use orchestra_request_user_input ONLY when the topic
    is genuinely ambiguous and a clarifying decision from the user would
    meaningfully improve the output. Otherwise just write the article.
  userPrompt: "Write a 200-word article about {{param.topic}}."
  model: claude-opus-4.6
  enableTools: [request_user_input]
```

### 16. Notify on HITL Pause via Hook
Wire `step.awaitingInput` into a script hook that posts to Slack/Teams/email.
```yaml
hooks:
  - name: slack-on-pause
    on: step.awaitingInput
    payload:
      detail: compact
      includeRefs: true
    action:
      type: script
      shell: pwsh
      script: |
        $payload = $input | Out-String | ConvertFrom-Json
        $body = @{
          text = "[$($payload.orchestration.name)] needs input on '$($payload.step.name)'"
        } | ConvertTo-Json
        Invoke-RestMethod -Uri $env:SLACK_WEBHOOK -Method Post -Body $body -ContentType 'application/json'
```

### 17. Approval with Timeout Fallback
Auto-acknowledge a low-priority alert if no one responds within 5 minutes.
```yaml
- name: triage
  type: Approval
  prompt: "Acknowledge incident {{param.incidentId}}? (auto-acknowledge in 5m)"
  choices: [acknowledge, escalate]
  timeoutSeconds: 300
  onTimeout: defaultResponse
  defaultResponse: acknowledge
```

## Registering Orchestrations

Orchestrations can be registered in Orchestra via:

1. **REST API** `POST /api/orchestrations/json` with body `{ "json": "<orchestration JSON string>" }` -- registers from raw JSON content.
2. **REST API** `POST /api/orchestrations` with body `{ "paths": ["<file path>"] }` -- registers from file path.
3. **MCP Control Plane** `register_orchestration` tool -- registers from file path.
4. **Directory Scan** -- Orchestra can auto-scan a directory on startup.

## Common Mistakes to Avoid

1. **Do NOT invent properties.** Only use properties documented above. There is no `if`, `condition`, `forEach`, `parallel`, or `output` property.
2. **Do NOT use `systemPrompt` AND `systemPromptFile` together.** They are mutually exclusive. Same for all `*File` pairs (including `script`/`scriptFile`).
3. **Loop target must be a dependency.** The checker step must have the target in its `dependsOn`.
4. **Step names must be unique** within the orchestration.
5. **No circular dependencies.** The DAG must be acyclic.
6. **`parameters` is a string array of names**, not key-value pairs. Values come at runtime.
7. **Model is required** for Prompt steps unless `defaultModel` is set at the orchestration level. Use `"claude-opus-4.6"` as default.
8. **Template expressions are `{{...}}`**, not `${...}` or `{...}`.
9. **Boolean/Number inputs**: values are always strings in JSON. `"true"`, `"false"`, `"42"`.
10. **`dependsOn` references step names**, not types or indices.
11. **`mcps` on steps is an array of strings** (MCP names), not MCP definition objects.
12. **Script steps require `shell`**. It has no default -- always specify it (e.g., `"pwsh"`, `"bash"`).
13. **Do NOT use `Command` with `pwsh -Command`, `powershell -Command`, or `bash -c` for script logic.** Use `type: Script`, `shell: pwsh`, and `script: |` instead.
14. **Do NOT rely on the host process working directory for runtime file paths.** Use `{{orchestration.sourceDirectory}}` to build absolute paths relative to the orchestration file.
15. **`systemPromptSections` requires `systemPromptMode: "customize"`**. Section overrides are ignored with `append` or `replace`.
16. **Image attachments require a vision-capable model** (e.g., `claude-opus-4.6`, `gpt-4o`). Non-vision models will not understand the images.
17. **`infiniteSessions` thresholds are ratios (0.0-1.0)**, not token counts. `0.80` means 80% of context used.
18. **`hooks` is a top-level array**, not a step-level property.
19. **Hook actions require exactly one of `script` or `scriptFile`.** Do not specify both.
20. **Hook `failurePolicy` only supports `warn` or `ignore`** in v1.
21. **Approval steps require `prompt`.** Without it, parsing fails.
22. **`onTimeout: defaultResponse` requires a `defaultResponse` value.** Parsing fails otherwise.
23. **`enableTools` only accepts opt-in tool names** (currently just `"request_user_input"`). Always-on tools (`orchestra_set_status`, `orchestra_complete`, file save/read) are not listed here.
24. **`orchestra_request_user_input` does NOT survive host restarts.** Agent sessions are volatile. Use the declarative `Approval` step for long-lived gates that must endure restarts.
25. **Approval and engine-tool waits both fire `step.awaitingInput`** — use a single hook to handle notifications for both paths.

## Naming Conventions

- Orchestration names: kebab-case (`my-deployment-pipeline`)
- Step names: kebab-case (`build-artifact`, `security-scan`)
- Variable names: camelCase (`appName`, `slackWebhookUrl`)
- Input names: camelCase (`serviceName`, `dryRun`)
