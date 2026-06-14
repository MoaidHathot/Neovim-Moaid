# Orchestra Orchestration Full Schema Reference

This is the complete property-level reference for every field, step type, trigger type, and supporting object available in an orchestration file. For a condensed overview, see the main [SKILL.md](../SKILL.md).

## Contents

- [File Structure Overview](#file-structure-overview)
- [Top-Level Properties](#top-level-properties)
- [Editor Schema Validation](#editor-schema-validation)
- [Typed Inputs](#typed-inputs)
- [Hooks](#hooks)
- [Steps](#steps)
  - [Base Step Properties](#base-step-properties)
  - [Prompt Step](#prompt-step)
  - [Http Step](#http-step)
  - [Transform Step](#transform-step)
  - [Command Step](#command-step)
  - [Script Step](#script-step)
  - [Orchestration Step](#orchestration-step)
  - [Approval Step](#approval-step)
- [Loop Configuration](#loop-configuration)
- [Subagents](#subagents)
- [Retry Policy](#retry-policy)
- [Triggers](#triggers)
  - [Manual Trigger](#manual-trigger)
  - [Scheduler Trigger](#scheduler-trigger)
  - [Loop Trigger](#loop-trigger)
  - [Webhook Trigger](#webhook-trigger)
- [MCP Definitions](#mcp-definitions)
- [Template Expressions](#template-expressions)
- [Enums Reference](#enums-reference)

---

## File Structure Overview

An orchestration file is a single JSON or YAML object with three required fields (`name`, `description`, `steps`) and several optional fields for versioning, triggers, variables, MCPs, and defaults.

Minimal valid orchestration:

```yaml
name: my-orchestration
description: A simple orchestration
steps:
  - name: greet
    type: Prompt
    systemPrompt: You are a helpful assistant.
    userPrompt: Say hello.
    model: claude-opus-4.6
```

---

## Top-Level Properties

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | **Yes** | -- | Unique name identifying the orchestration. |
| `description` | `string` | **Yes** | -- | Human-readable description of what this orchestration does. |
| `steps` | `Step[]` | **Yes** | -- | Array of step definitions forming the execution DAG. |
| `version` | `string` | No | `"1.0.0"` | Semantic version for tracking changes. Accessible via `{{orchestration.version}}`. |
| `inputs` | `object` | No | `null` | Typed input schema. Keys are input names, values are `InputDefinition` objects. When defined, provides type validation, descriptions, defaults, and enum constraints. |
| `trigger` | `TriggerConfig` | No | Manual | How the orchestration is triggered. Defaults to manual (on-demand). |
| `mcps` | `Mcp[]` | No | `[]` | Inline MCP (Model Context Protocol) server definitions available to steps. |
| `defaultModel` | `string` | No | `null` | Default model for all Prompt steps. Steps can override. |
| `agentPool` | `AgentPoolConfig` | No | Provider defaults | Provider worker-pool capacity request for prompt execution. Providers map instances to their own resources, such as Copilot CLI clients. |
| `defaultSystemPromptMode` | `string` | No | `null` | Default system prompt mode for all Prompt steps. Values: `"append"`, `"replace"`, or `"customize"`. |
| `defaultRetryPolicy` | `RetryPolicy` | No | `null` | Default retry policy applied to all steps unless overridden at the step level. |
| `defaultStepTimeoutSeconds` | `int` | No | `null` | Default per-step timeout in seconds. Individual steps can override this. |
| `timeoutSeconds` | `int` | No | `3600` | Maximum time in seconds for the entire orchestration run. Set to `0` or `null` to disable. |
| `variables` | `object` | No | `{}` | Key-value pairs of user-defined variables. Values can contain template expressions. Accessed via `{{vars.name}}`. |
| `tags` | `string[]` | No | `[]` | Tags for categorizing and filtering orchestrations. |
| `hooks` | `Hook[]` | No | `[]` | Lifecycle hooks that run after step or orchestration outcomes. Hooks receive structured JSON payloads on stdin and can execute follow-up scripts. |
| `pauseTimeoutDuringWait` | `bool` | No | `true` | When true, the orchestration timeout clock pauses while a step (Approval or `orchestra_request_user_input`) is waiting for human input. Set to `false` for hard SLAs that include human response latency. Implemented via the `ClockPauseTracker`: on `BeginWait` the orchestration timeout CTS is suspended, on `EndWait` it is re-armed with `(originalTimeout + totalWaitElapsed - alreadyElapsed)` so the wait is excluded from the budget. |
| `defaultEnableTools` | `string[]` | No | `[]` | Opt-in engine tool names enabled by default for every Prompt step that does not specify its own `enableTools`. Currently supports `"request_user_input"`. Always-on tools (`orchestra_set_status`, `orchestra_complete`, file save/read) are unaffected. |
| `defaultPermissionPolicy` | `PermissionPolicy` | No | `null` | Default Copilot permission policy for every Prompt step that does not specify its own `permissionPolicy`. See [Permission Policy](#permission-policy). Null = auto-approve. |
| `defaultSandboxPolicy` | `SandboxPolicy` | No | `null` | Default opt-in sandbox for every Prompt step that does not specify its own `sandbox`. See [Sandbox](#sandbox). Null = no sandbox. |
| `metadata` | `object` | No | `{}` | Free-form metadata. Values may be any JSON type (string, number, boolean, array, nested object). Purely informational -- the runtime never inspects this dictionary. Use for authorship, datetime, ticket links, environment, SLA, or any other semi-structured data. |

---

## Editor Schema Validation

The `schemas/orchestration.schema.json` JSON Schema works for both JSON and YAML files in any editor that supports JSON Schema. Once bound, you get autocomplete, hover documentation, type validation, and unknown-field errors.

**JSON files** -- editors auto-detect via the `$schema` property:

```json
{
  "$schema": "../schemas/orchestration.schema.json",
  "name": "my-orchestration",
  "description": "...",
  "steps": []
}
```

**YAML files** -- because YAML has no built-in schema indirection, declare it explicitly. Two conventions are supported:

```yaml
# yaml-language-server: $schema=../schemas/orchestration.schema.json
name: my-orchestration
description: ...
steps: []
```

or

```yaml
$schema: ../schemas/orchestration.schema.json
name: my-orchestration
description: ...
steps: []
```

The modeline form is recommended -- it works in VS Code (Red Hat YAML extension), JetBrains IDEs (Rider/IntelliJ), Neovim/Helix via `yaml-language-server`, and any other editor built on the same LSP. The top-level `$schema` form works in JetBrains IDEs and recent versions of `yaml-language-server`.

### Metadata field caveats in YAML

The `metadata` field accepts any JSON-compatible shape (`additionalProperties: true` in the schema). Two YAML-specific gotchas:

1. **Quote ISO-8601 datetimes** (`"2026-04-30T12:00:00Z"`) so YAML does not coerce them to native date nodes. Quoted values stay as strings, which is what most consumers expect.
2. **Indentation matters** for nested objects -- standard YAML rules apply.

Example:

```yaml
metadata:
  createdAt: "2026-04-30T12:00:00Z"
  author: platform-team
  owners:
    - alice@example.com
    - bob@example.com
  ticket: JIRA-1234
  environment: staging
  sla:
    responseTimeMinutes: 15
    businessHoursOnly: true
```

---

## Typed Inputs

The `inputs` property defines a strongly-typed schema for orchestration parameters. When present, it is the authoritative source for parameter definitions, providing type validation, descriptions, default values, and enum constraints.

When `inputs` is not defined, the orchestration uses legacy behavior: parameter names are collected from step-level `parameters` arrays and treated as required string values.

### InputDefinition Properties

Each key in the `inputs` object is the input name. Each value is an `InputDefinition`:

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `string` | No | `"string"` | Data type. One of: `"string"`, `"boolean"`, `"number"`. |
| `description` | `string` | No | `null` | Human-readable description. Used for documentation and MCP tool schema generation. |
| `required` | `bool` | No | `true` | Whether this input must be provided at runtime. |
| `default` | `string` | No | `null` | Default value for optional inputs. Ignored when `required` is `true`. |
| `enum` | `string[]` | No | `[]` | Allowed values. When non-empty, the provided value must be one of these (case-insensitive). |
| `multiline` | `bool` | No | `false` | UI hint: when true, the Portal renders a multiline textarea instead of a single-line input. Only meaningful for `"string"` type inputs. Has no effect on validation or execution. |

### Validation Rules

1. **Missing required inputs** produce an error listing the input name and its description.
2. **Type validation**: Boolean inputs must be `"true"` or `"false"`. Number inputs must be parseable as a numeric value.
3. **Enum constraints**: When `enum` is non-empty, the provided value must match one of the allowed values (case-insensitive comparison).
4. **Default application**: Optional inputs (`required: false`) that are not provided receive their `default` value automatically.

---

## Hooks

Hooks are top-level orchestration configuration that run after step or orchestration lifecycle events. They are intended for follow-up automation such as notifications, archival, incident creation, or failure triage. They do not participate in the execution DAG.

### HookDefinition Properties

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | No | `null` | Optional hook name for diagnostics and reporting. |
| `on` | `string` | **Yes** | -- | Hook event to subscribe to. One of: `"orchestration.success"`, `"orchestration.failure"`, `"orchestration.after"`, `"step.success"`, `"step.failure"`, `"step.after"`, `"step.awaitingInput"`. |
| `when` | `HookWhen` | No | `null` | Optional filter deciding whether the hook should run. |
| `payload` | `HookPayload` | No | schema defaults | Controls how much run and step data is included in the hook payload. |
| `action` | `HookAction` | **Yes** | -- | Action to execute when the hook fires. |
| `failurePolicy` | `string` | No | `"warn"` | What to do if the hook action fails. One of: `"warn"`, `"ignore"`. |

Example:

```yaml
hooks:
  - name: capture-deploy-failures
    on: orchestration.failure
    when:
      steps:
        names: [build, deploy]
        status: failed
        match: any
    payload:
      detail: standard
      steps: failed
      includeRefs: true
    action:
      type: script
      shell: pwsh
      scriptFile: ./hooks/write-hook-payload.ps1
      arguments:
        - ./artifacts/orchestration-failure-payload.json
```

### HookWhen

Filtering is intentionally small in v1 and currently only supports step-based conditions.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `steps` | `HookStepCondition` | No | `null` | Filter the hook based on the status of one or more named steps. |

### HookStepCondition

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `names` | `string[]` | No | `[]` | Optional list of step names to evaluate. |
| `status` | `string` | No | `"any"` | One of: `"any"`, `"succeeded"`, `"failed"`, `"cancelled"`, `"skipped"`, `"noAction"`, `"nonSucceeded"`. |
| `match` | `string` | No | `"any"` | Whether `any` or `all` named steps must satisfy the status condition. |

Example:

```yaml
when:
  steps:
    names: [build, deploy]
    status: failed
    match: any
```

### HookPayload

The hook payload is serialized as structured JSON and provided to the hook action on stdin.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `detail` | `string` | No | `"compact"` | Preset detail level for included step records. One of: `"compact"`, `"standard"`, `"full"`. |
| `steps` | `string` or `string[]` | No | implementation default | Step records to include: `"none"`, `"current"`, `"failed"`, `"nonSucceeded"`, `"terminal"`, `"all"`, or an explicit list of step names. |
| `includeRefs` | `bool` | No | `false` | Includes API and MCP references for fetching more run data. |

### HookAction

In v1, hooks support `script` actions only.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `string` | **Yes** | -- | Hook action type. Must be `"script"`. |
| `shell` | `string` | No | `"pwsh"` | Shell/interpreter used to execute the hook script. |
| `script` | `string` | **Yes*** | -- | Inline script content. The hook payload is provided through stdin. |
| `scriptFile` | `string` | **Yes*** | -- | Path to a script file. Relative paths resolve from the orchestration file directory. |
| `arguments` | `string[]` | No | `[]` | Optional arguments passed to the script. |
| `workingDirectory` | `string` | No | `null` | Optional working directory for the hook process. Relative paths resolve from the orchestration file directory. |
| `environment` | `object` | No | `{}` | Optional environment variables for the hook process. |
| `includeStdErr` | `bool` | No | `false` | When true, stderr is included in the script output if it succeeds. |

*Exactly one of `script` or `scriptFile` is required.

---

## Steps

Steps are the building blocks of an orchestration. They form a DAG: steps with no `dependsOn` run first (and in parallel with each other), and downstream steps run once all their dependencies have completed.

### Base Step Properties

These properties are shared by **all** step types.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | **Yes** | -- | Unique name within the orchestration. Used to reference this step in `dependsOn` and template expressions. |
| `type` | `string` | **Yes** | -- | Step type. One of: `"Prompt"`, `"Http"`, `"Transform"`, `"Command"`, `"Script"`, `"Orchestration"`, `"Approval"` (case-insensitive). |
| `dependsOn` | `string[]` | No | `[]` | Names of steps that must complete before this step runs. Defines the DAG edges. |
| `parameters` | `string[]` or `object` | No | `[]` | For most step types, parameter names this step expects. For Orchestration steps, child parameter values keyed by child input name. |
| `enabled` | `bool` | No | `true` | When `false`, the step is skipped during execution. |
| `timeoutSeconds` | `int` | No | `null` | Per-step timeout in seconds. Falls back to `defaultStepTimeoutSeconds` if not set. Set to `0` to explicitly disable timeout. |
| `retry` | `RetryPolicy` | No | `null` | Per-step retry policy. Overrides `defaultRetryPolicy`. |

---

### Prompt Step

**Type value:** `"Prompt"`

Sends a prompt to an LLM and captures the response as output. Supports input/output handlers for pre/post-processing, subagents for delegation, loops for iterative refinement, MCP tool access, and reasoning levels.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `systemPrompt` | `string` | **Yes*** | -- | System prompt text provided inline. |
| `systemPromptFile` | `string` | **Yes*** | -- | Path to a file containing the system prompt. Mutually exclusive with `systemPrompt`. |
| `userPrompt` | `string` | **Yes*** | -- | User prompt text provided inline. |
| `userPromptFile` | `string` | **Yes*** | -- | Path to a file containing the user prompt. Mutually exclusive with `userPrompt`. |
| `model` | `string` | **Yes** | -- | LLM model identifier (e.g., `"claude-opus-4.6"`, `"gpt-4o"`). Falls back to `defaultModel` if set. |
| `inputHandlerPrompt` | `string` | No | `null` | An LLM prompt that pre-processes dependency outputs before the main prompt sees them. |
| `inputHandlerPromptFile` | `string` | No | `null` | Path to file containing the input handler prompt. Mutually exclusive with `inputHandlerPrompt`. |
| `outputHandlerPrompt` | `string` | No | `null` | An LLM prompt that post-processes the main LLM output. |
| `outputHandlerPromptFile` | `string` | No | `null` | Path to file containing the output handler prompt. Mutually exclusive with `outputHandlerPrompt`. |
| `reasoningLevel` | `string` | No | `null` | Controls the model's extended thinking. Values: `"Low"`, `"Medium"`, `"High"`. |
| `reasoningSummary` | `string` | No | `null` | Verbosity of the model's reasoning summary. Values: `"none"`, `"concise"`, `"detailed"`. Opt-in. |
| `contextTier` | `string` | No | `null` | Context-window tier. `"default"` or `"longContext"` (opts into the model's extended context window where supported). Opt-in. |
| `workingDirectory` | `string` | No | `null` | Working directory for the agent's shell/file tools and config discovery (custom instructions, `.github/agents`, `.github/mcp.json`). Template-resolved (`{{param.*}}`/`{{env.*}}`/`{{vars.*}}`) and validated to exist at run time. |
| `githubToken` | `string` | No | `null` | GitHub token for this step's Copilot session, overriding the host default. Prefer a template reference such as `{{env.GITHUB_TOKEN}}`; never logged. Falls back to `orchestra.json` `copilot.gitHubToken`/`useLoggedInUser`, then the CLI's stored credentials. |
| `humanInput` | `bool` | No | `false` | When `true`, the agent's elicitation and exit-plan-mode (plan approval) requests are routed to Orchestra's human-in-the-loop instead of resolving autonomously. See [Human-in-the-Loop](#human-in-the-loop). |
| `permissionPolicy` | `PermissionPolicy` | No | `null` | Controls how the agent's permission requests (shell/file/url/mcp/…) are resolved. See [Permission Policy](#permission-policy). Overrides `defaultPermissionPolicy`; omit for auto-approve. |
| `sandbox` | `SandboxPolicy` | No | `null` | Opt-in filesystem/network sandbox for this step's tool access. See [Sandbox](#sandbox). Overrides `defaultSandboxPolicy`; omit for no sandbox. |
| `systemPromptMode` | `string` | No | `null` | How the system prompt interacts with the SDK's built-in prompts. `"append"` adds to them; `"replace"` removes them; `"customize"` selectively overrides individual sections. |
| `systemPromptSections` | `object` | No | `null` | Section-level overrides when using `"customize"` mode. See [System Prompt Section Overrides](#system-prompt-section-overrides). |
| `infiniteSessions` | `object` | No | `null` | Configuration for infinite sessions (automatic context compaction). See [Infinite Sessions](#infinite-sessions). |
| `attachments` | `Attachment[]` | No | `[]` | Image attachments to send with the prompt. See [Image Attachments](#image-attachments). |
| `mcps` | `string[]` | No | `[]` | Names of MCP servers (defined at orchestration level or in `mcp.json`) to attach as tools for this step. |
| `loop` | `LoopConfig` | No | `null` | Loop/checker configuration for iterative refinement. |
| `subagents` | `Subagent[]` | No | `[]` | Subagent definitions for multi-agent delegation. |
| `skillDirectories` | `string[]` | No | `[]` | Directories containing `SKILL.md` files that provide additional context/instructions. |
| `enableTools` | `string[]` | No | `null` | Opt-in engine tool names this Prompt step grants the agent access to. Currently supports `"request_user_input"` (the LLM-decided human-in-the-loop tool). Falls back to the orchestration's `defaultEnableTools` when null. Always-on tools (`orchestra_set_status`, `orchestra_complete`, file save/read) are unaffected. |

> **\*Mutual exclusion rules:**
> - Exactly one of `systemPrompt` or `systemPromptFile` is required.
> - Exactly one of `userPrompt` or `userPromptFile` is required.
> - `inputHandlerPrompt` and `inputHandlerPromptFile` are mutually exclusive.
> - `outputHandlerPrompt` and `outputHandlerPromptFile` are mutually exclusive.

#### System Prompt Section Overrides

Used when `systemPromptMode` is `"customize"`. The `systemPromptSections` object allows surgical control over individual sections of the SDK's built-in system prompt while preserving the rest.

Keys are section identifiers:

| Section Key | Description |
|---|---|
| `identity` | Agent identity and role |
| `tone` | Communication style and formatting |
| `tool_efficiency` | Instructions for efficient tool usage |
| `environment_context` | Workspace and environment context |
| `code_change_rules` | Rules governing code modifications |
| `guidelines` | General behavioral guidelines |
| `safety` | Safety and content policy instructions |
| `tool_instructions` | Tool-specific usage instructions |
| `custom_instructions` | Custom user-provided instructions |
| `last_instructions` | Final priority instructions (applied last) |

Each section override value:

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | `string` | **Yes** | -- | One of: `"replace"`, `"remove"`, `"append"`, `"prepend"`. |
| `content` | `string` | No | `null` | The content to use for `replace`, `append`, or `prepend`. Ignored for `remove`. |

Example:
```yaml
systemPromptMode: customize
systemPromptSections:
  tone:
    action: replace
    content: "Be concise and direct. Use bullet points."
  code_change_rules:
    action: remove  # Read-only step, no code modifications
  guidelines:
    action: append
    content: "\n- Always cite sources.\n- Follow WCAG 2.1 AA."
```

#### Infinite Sessions

The `infiniteSessions` object controls automatic context compaction for long-running Prompt steps that may exceed the model's context window.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `enabled` | `bool` | No | `true` (SDK default) | Whether infinite sessions are enabled. Set to `false` for short tasks where compaction is unnecessary. |
| `backgroundCompactionThreshold` | `number` | No | `0.80` | Context utilization ratio (0.0-1.0) at which background compaction begins. |
| `bufferExhaustionThreshold` | `number` | No | `0.95` | Context utilization ratio (0.0-1.0) at which the session blocks until compaction completes. |

Example:
```yaml
infiniteSessions:
  enabled: true
  backgroundCompactionThreshold: 0.85
  bufferExhaustionThreshold: 0.97
```

#### Image Attachments

The `attachments` array allows sending images to the LLM alongside the prompt. Requires a vision-capable model. Each attachment is an object with a `type` discriminator.

**File Attachment** (`type: "file"`):

| Property | Type | Required | Description |
|---|---|---|---|
| `type` | `string` | **Yes** | Must be `"file"`. |
| `path` | `string` | **Yes** | Absolute path to the image file. Supports template expressions (e.g., `{{param.imagePath}}`). |
| `displayName` | `string` | No | Human-readable name for the attachment. |

**Blob Attachment** (`type: "blob"`):

| Property | Type | Required | Description |
|---|---|---|---|
| `type` | `string` | **Yes** | Must be `"blob"`. |
| `data` | `string` | **Yes** | Base64-encoded image data. Supports template expressions (e.g., `{{screenshot-step.output}}`). |
| `mimeType` | `string` | **Yes** | MIME type of the image (e.g., `"image/png"`, `"image/jpeg"`). |
| `displayName` | `string` | No | Human-readable name for the attachment. |

Example:
```yaml
attachments:
  - type: file
    path: "{{param.mockupPath}}"
    displayName: "UI Mockup"
  - type: blob
    data: "{{screenshot-step.output}}"
    mimeType: "image/png"
```

---

#### Model Tuning, Working Directory & Authentication

These per-step Copilot controls are all opt-in; omit a field to inherit the host/provider default.

- `reasoningSummary` — `"none"` / `"concise"` / `"detailed"`. Verbosity of the model's reasoning summary (distinct from `reasoningLevel`, which is the reasoning *effort*).
- `contextTier` — `"default"` / `"longContext"`. Opts into the model's extended context window where the provider supports it.
- `workingDirectory` — the agent's working directory for shell/file tools and config discovery. Template-resolved (`{{param.*}}`/`{{env.*}}`/`{{vars.*}}`) and validated to exist at run time.
- `githubToken` — authenticates this step's Copilot session, overriding the host default. Prefer `{{env.GITHUB_TOKEN}}` over a literal secret. The host-level default is `orchestra.json` `copilot.gitHubToken` / `copilot.useLoggedInUser`.

```json
{
  "name": "analyze",
  "type": "Prompt",
  "model": "claude-opus-4.6",
  "reasoningSummary": "concise",
  "contextTier": "longContext",
  "workingDirectory": "{{env.PROJECT_DIR}}",
  "githubToken": "{{env.GITHUB_TOKEN}}"
}
```

#### Human-in-the-Loop

`humanInput: true` routes the agent's **elicitation** and **exit-plan-mode (plan approval)** requests to Orchestra's human-in-the-loop — the same pending-input surface as the `Approval` step and `orchestra_request_user_input` (operators answer via `POST /api/orchestrations/{name}/runs/{runId}/respond`). Like the engine-tool variant, these waits are session-bound and do **not** survive a host restart. Default (off) resolves them autonomously. Pairs naturally with `permissionPolicy: requireHumanApproval`.

#### Permission Policy

`permissionPolicy` controls how the agent's permission requests (shell, file read/write, url, mcp, …) are resolved.

| Property | Type | Default | Description |
|---|---|---|---|
| `mode` | `string` | `approveAll` | `approveAll` (auto-approve everything — default), `denyList` (approve unless a deny glob matches), or `requireHumanApproval` (route each request to a human operator; serialized per step; falls back to "user not available" with no operator). |
| `deny` | `string[]` | `[]` | Globs matched (case-insensitive, `*`/`?` wildcards) against a request's kind (`read`/`write`/`shell`/`url`/`mcp`/…) or target (path/command/url/tool). Used only when `mode` is `denyList`. |

```json
{ "permissionPolicy": { "mode": "denyList", "deny": ["shell", "url", "*.env"] } }
```

#### Sandbox

`sandbox` constrains the agent's shell/file/network tool access, applied to the live session via the runtime's options-update RPC.

| Property | Type | Default | Description |
|---|---|---|---|
| `enabled` | `bool` | `true` | When `false`, the policy is ignored (no sandbox). |
| `filesystem.readonly` | `string[]` | `[]` | Paths the agent may read but not write. |
| `filesystem.readwrite` | `string[]` | `[]` | Paths the agent may read and write. |
| `filesystem.denied` | `string[]` | `[]` | Paths the agent may not access. |
| `network.allowedHosts` | `string[]` | `[]` | Hosts the agent's tools may reach (allow-list). |
| `network.blockedHosts` | `string[]` | `[]` | Hosts the agent's tools may not reach (deny-list). |
| `network.allowOutbound` | `bool` | provider default | Whether outbound network access is permitted at all. |
| `network.allowLocalNetwork` | `bool` | provider default | Whether loopback / private-range access is permitted. |

Sandbox paths are passed to the runtime verbatim (not template-resolved). Enforcement is provided on Linux/macOS.

```json
{
  "sandbox": {
    "enabled": true,
    "filesystem": { "readonly": ["/work/repo"], "denied": ["/etc"] },
    "network": { "allowOutbound": false }
  }
}
```

---

### Http Step

**Type value:** `"Http"`

Makes an HTTP request and captures the response body as output. No LLM is involved.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `url` | `string` | **Yes** | -- | URL to send the request to. Supports template expressions. |
| `method` | `string` | No | `"GET"` | HTTP method: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`. |
| `headers` | `object` | No | `{}` | Key-value pairs of request headers. Values support template expressions. |
| `body` | `string` | No | `null` | Request body. Supports template expressions. |
| `contentType` | `string` | No | `"application/json"` | Content-Type header for the request body. |

---

### Transform Step

**Type value:** `"Transform"`

Performs pure string interpolation with no LLM call and no external requests.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `template` | `string` | **Yes** | -- | Template string with `{{expression}}` placeholders. |
| `contentType` | `string` | No | `"text/plain"` | Content type hint for downstream consumers. |

---

### Command Step

**Type value:** `"Command"`

Executes a direct executable as a child process and captures stdout. Use this for commands such as `dotnet`, `git`, `dnx`, or `npx`.

Do not use `Command` for shell snippets or wrappers such as `pwsh -Command`, `powershell -Command`, `bash -c`, or `sh -c`. Use a `Script` step instead.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `command` | `string` | **Yes** | -- | Executable to run (e.g., `"dotnet"`, `"python"`, `"git"`). |
| `arguments` | `string[]` | No | `[]` | Command-line arguments. Each element supports template expressions. |
| `workingDirectory` | `string` | No | Current directory | Working directory for the process. |
| `environment` | `object` | No | `{}` | Environment variables to set. Values support template expressions. |
| `includeStdErr` | `bool` | No | `false` | Whether to append stderr to the captured output. |
| `stdin` | `string` | No | `null` | Content to pipe to the process's standard input. |

---

### Script Step

**Type value:** `"Script"`

Executes an inline or file-based script via a shell interpreter. The script's stdout is captured as output. Use this for shell snippets, pipelines, multi-line scripts, quoting-sensitive values, JSON manipulation, and anything that would otherwise be passed to `pwsh -Command` or `bash -c`.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `shell` | `string` | **Yes** | -- | Shell interpreter to use (e.g., `"pwsh"`, `"bash"`, `"python"`, `"node"`). |
| `script` | `string` | **Yes*** | -- | Inline script content. Mutually exclusive with `scriptFile`. |
| `scriptFile` | `string` | **Yes*** | -- | Path to an external script file. Relative paths resolve from the orchestration file's directory. |
| `arguments` | `string[]` | No | `[]` | Arguments passed to the script. |
| `workingDirectory` | `string` | No | Current directory | Working directory for the process. |
| `environment` | `object` | No | `{}` | Environment variables to set. |
| `includeStdErr` | `bool` | No | `false` | Whether to append stderr to the captured output. |
| `stdin` | `string` | No | `null` | Content to pipe to the process's standard input. |

> **\*Mutual exclusion:** Exactly one of `script` or `scriptFile` is required.

Pass values into scripts with `arguments` or `stdin` instead of interpolating large or heavily quoted values into the script body. In PowerShell, `arguments` are available as `$args[0]`, `$args[1]`, and so on.

---

### Orchestration Step

**Type value:** `"Orchestration"`

Invokes another registered orchestration. Use this when a parent flow should delegate to a reusable child orchestration.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `orchestration` | `string` | **Yes** | -- | Registered child orchestration name or ID. Supports template expressions. |
| `parameters` | `object` | No | `{}` | Child orchestration parameters. Values support template expressions and are passed as strings at runtime. |
| `mode` | `string` | No | `sync` | `sync` waits for child completion; `async` dispatches and continues. |
| `inputHandlerPrompt` | `string` | No | `null` | Optional LLM prompt to transform child parameters before launch. Must return a JSON object mapping parameter names to string values. |
| `inputHandlerModel` | `string` | No | `null` | Model to use for the input handler. Defaults to the orchestration default model. |

If an Orchestration step input handler returns invalid JSON or an empty object, runtime falls back to the original parameters. Use Script steps for deterministic validation or canonicalization when malformed input must fail or be repaired before child launch.

---

### Approval Step

**Type value:** `"Approval"`

Pauses the orchestration and waits for human input. The step persists a `PendingInputRecord` to disk under `{DataPath}/pending/{orchestrationName}/{runId}/{stepName}.json`, transitions to `ExecutionStatus.AwaitingInput`, fires the `step.awaitingInput` hook event, and blocks until a user responds via the host's HumanInput API.

The user's response (`reply` or `choice`, with `reply` winning when both are supplied) becomes the step's content via `{{stepName.output}}`. Approval steps survive host restarts: the persisted record is preserved across process bounces, and on resume the step re-attaches to the still-outstanding wait.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `prompt` | `string` | **Yes** | -- | Human-readable prompt presented to the user. Supports template expressions resolved at execution time (e.g., `{{param.x}}`, `{{vars.x}}`, `{{stepName.output}}`). |
| `choices` | `string[]` | No | `[]` | Allowed responses. When non-empty, the response endpoint validates that the supplied `choice` is one of these (case-insensitive). When empty, free-form replies are accepted. |
| `timeoutSeconds` | `int` | No | `null` | Per-step timeout. When elapsed without a response, behavior is governed by `onTimeout`. When null, the wait runs indefinitely (subject to the orchestration timeout, which by default pauses during waits per `pauseTimeoutDuringWait`). |
| `onTimeout` | `string` | No | `"fail"` | Behavior when `timeoutSeconds` fires. One of: `"fail"` (mark step Failed with `ErrorCategory.Timeout`), `"defaultResponse"` (use `defaultResponse` as the answer and continue), `"cancel"` (cancel the entire orchestration). |
| `defaultResponse` | `string` | No | `null` | Required when `onTimeout: "defaultResponse"`. The fallback content used as the step's output. |

#### Responding to an Approval Step

Three equivalent ways to submit a response:

**1. CLI:**
```bash
orchestra pending                                              # list runs awaiting input
orchestra respond <orchestration-name> <runId> <stepName> --choice approve [--reply "..."] [--by alice]
```

**2. REST:**
```http
POST /api/orchestrations/{orchestrationName}/runs/{runId}/respond?step={stepName}
Content-Type: application/json

{
  "choice": "approve",            // optional; must match one of the declared choices when present
  "reply": "ship it",             // optional free-form text; wins over choice for {{stepName.output}}
  "respondedBy": "alice"          // optional, persisted to the run record
}
```

**3. List endpoints:**
```http
GET  /api/runs/pending[?orchestration=<name>]
GET  /api/orchestrations/{orchestrationName}/runs/{runId}/pending/{stepName}
```

#### Engine-Tool HITL Variant: `orchestra_request_user_input`

For LLM-decided "ask the human only when needed" pauses inside `Prompt` steps, opt the Prompt step into the `request_user_input` engine tool. The tool blocks inside the agent's tool-call loop until the user responds; the reply is returned as the tool result so the agent continues its conversation with the answer in hand.

```yaml
- name: writer
  type: Prompt
  systemPrompt: |
    You write articles. Use orchestra_request_user_input ONLY when the topic is
    genuinely ambiguous and a clarifying decision would meaningfully improve
    the output. Otherwise just write the article.
  userPrompt: "Write an article about {{param.topic}}."
  model: claude-opus-4.6
  enableTools: [request_user_input]
```

Behavioral differences vs. the declarative `Approval` step:

| Aspect | `Approval` step | `orchestra_request_user_input` |
|---|---|---|
| Decided by | Author (always pauses) | LLM (only if needed) |
| Step status during wait | `AwaitingInput`; agent session torn down | `Running`; agent session held in memory |
| Survives host restart | Yes (persistent record + checkpoint resume) | No — run is marked `Failed` with `CancellationCauseKind.HostShutdownDuringWait`; previous step's checkpoint stays intact for retry |
| Use case | Explicit deploy/compliance/destructive-op gates | Mid-task clarifications the LLM uses to keep working |
| Persisted record `kind` | `Approval` | `EngineTool` |

Both paths share: the same `PendingInputRecord` shape, the same `step.awaitingInput` hook event, the same `POST /respond` endpoint, the same SSE events (`awaiting-input`, `input-received`, `input-timeout`), and clock-pause behavior governed by `pauseTimeoutDuringWait`.

On host restart, the startup recovery logic cleans up orphaned engine-tool records (their agent sessions cannot be re-attached) but preserves Approval records (their executor will re-attach on resume).

---

## Loop Configuration

A loop (or "checker") pattern allows a Prompt step to iteratively refine the output of a target step.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `target` | `string` | **Yes** | -- | Name of the step to re-run when the exit condition is not met. Must be a dependency of the checker step. |
| `maxIterations` | `int` | **Yes** | -- | Maximum number of loop iterations (1-10). |
| `exitPattern` | `string` | **Yes** | -- | Case-insensitive string to search for in the checker's output. When found, the loop exits. |

The checker evaluates the target's output. If `exitPattern` is NOT found (case-insensitive), the target re-runs with checker feedback. Repeats up to `maxIterations`.

---

## Subagents

Subagents enable multi-agent orchestration within a single Prompt step.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | **Yes** | -- | Unique subagent identifier. |
| `prompt` | `string` | **Yes*** | -- | System prompt for the subagent (inline). |
| `promptFile` | `string` | **Yes*** | -- | Path to a file containing the subagent's system prompt. Mutually exclusive with `prompt`. |
| `displayName` | `string` | No | `null` | Human-readable display name shown in the UI. |
| `description` | `string` | No | `null` | Description of the subagent's expertise. Helps the coordinator understand when to delegate. |
| `tools` | `string[]` | No | `null` (all) | Tool names the subagent can use. `null` grants access to all available tools. |
| `mcps` | `string[]` | No | `[]` | MCP server names available to this subagent. |
| `infer` | `bool` | No | `true` | Whether the runtime can auto-select this subagent based on user intent. |

---

## Retry Policy

Retry policies control automatic retries on step failure with exponential backoff.

| Property | Type | Default | Description |
|---|---|---|---|
| `maxRetries` | `int` | `3` | Maximum retry attempts after the initial failure. |
| `backoffSeconds` | `double` | `1.0` | Initial delay before the first retry (in seconds). |
| `backoffMultiplier` | `double` | `2.0` | Multiplier applied to the backoff delay after each retry. |
| `retryOnTimeout` | `bool` | `true` | Whether to retry when the failure is a timeout. |

---

## Triggers

Triggers define how an orchestration is started. When no `trigger` is specified, the orchestration defaults to manual (on-demand) execution.

### Base Trigger Properties

All trigger types share these properties:

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | `string` | **Yes** | -- | Trigger type: `"manual"`, `"scheduler"`, `"loop"`, or `"webhook"`. |
| `enabled` | `bool` | No | `true` | Whether the trigger is active. |
| `inputHandlerPrompt` | `string` | No | `null` | LLM prompt to transform raw trigger input into expected parameters. |
| `inputHandlerModel` | `string` | No | `null` | Model to use for the input handler prompt. |

### Manual Trigger

**Type value:** `"manual"` -- The default. No additional properties.

### Scheduler Trigger

**Type value:** `"scheduler"`

| Property | Type | Default | Description |
|---|---|---|---|
| `cron` | `string` | `null` | Cron expression (e.g., `"0 */6 * * *"`). Takes precedence over `intervalSeconds`. |
| `intervalSeconds` | `int` | `null` | Simple interval in seconds between runs. |
| `maxRuns` | `int` | `null` (unlimited) | Maximum number of scheduled runs. |

### Loop Trigger

**Type value:** `"loop"`

| Property | Type | Default | Description |
|---|---|---|---|
| `delaySeconds` | `int` | `0` | Delay in seconds before re-running after completion. |
| `maxIterations` | `int` | `null` (unlimited) | Maximum number of loop iterations. |
| `continueOnFailure` | `bool` | `false` | Whether to continue looping if the orchestration fails. |

### Webhook Trigger

**Type value:** `"webhook"`

| Property | Type | Default | Description |
|---|---|---|---|
| `secret` | `string` | `null` | HMAC secret for validating the `X-Webhook-Signature` header. |
| `maxConcurrent` | `int` | `1` | Maximum concurrent executions from incoming webhooks. |
| `response` | `WebhookResponseConfig` | `null` | Configuration for synchronous webhook responses. |

**WebhookResponseConfig:**

| Property | Type | Default | Description |
|---|---|---|---|
| `waitForResult` | `bool` | `false` | Whether to block the HTTP response until orchestration completes. |
| `responseTemplate` | `string` | `null` | Template string for formatting the response body. |
| `timeoutSeconds` | `int` | `120` | Maximum seconds to wait for completion. Returns 504 on timeout. |

---

## MCP Definitions

MCP servers provide tools to Prompt steps. They can be defined inline in the orchestration file or in a separate `mcp.json` / `orchestra.mcp.json` file in the same directory. When both exist, external definitions are merged and override inline ones on name conflicts.

### Local MCP (stdio transport)

| Property | Type | Required | Description |
|---|---|---|---|
| `name` | `string` | **Yes** | Unique MCP server name. Referenced by steps via the `mcps` array. |
| `type` | `string` | **Yes** | Must be `"local"`. |
| `command` | `string` | **Yes** | Executable to run (e.g., `"npx"`, `"uvx"`, `"python"`). |
| `arguments` | `string[]` | No | Command-line arguments. |
| `workingDirectory` | `string` | No | Working directory for the MCP process. |

### Remote MCP (HTTP transport)

| Property | Type | Required | Description |
|---|---|---|---|
| `name` | `string` | **Yes** | Unique MCP server name. |
| `type` | `string` | **Yes** | Must be `"remote"`. |
| `endpoint` | `string` | **Yes** | Remote MCP server URL. |
| `headers` | `object` | No | HTTP headers for authentication or other purposes. |

---

## Template Expressions

Template expressions use `{{expression}}` syntax and are supported in prompts, URLs, headers, bodies, templates, command arguments, working directories, environment variable values, stdin, variable values, MCP configs, and skill directory paths.

| Expression | Description |
|---|---|
| `{{param.name}}` | A runtime parameter value. |
| `{{vars.name}}` | An orchestration variable value (defined in `variables`). Supports recursive expansion. |
| `{{env.VAR_NAME}}` | An environment variable value. |
| `{{stepName.output}}` | The processed output of a dependency step (after output handler, if any). |
| `{{stepName.rawOutput}}` | The raw output of a dependency step (before output handler). |
| `{{stepName.files}}` | JSON array of all file paths saved by a step. |
| `{{stepName.files[N]}}` | A specific file path saved by a step (0-indexed). |
| `{{orchestration.name}}` | The orchestration's name. |
| `{{orchestration.version}}` | The orchestration's version. |
| `{{orchestration.runId}}` | The current execution's unique run ID. |
| `{{orchestration.startedAt}}` | Timestamp when the current run started. |
| `{{orchestration.tempDir}}` | Temp directory for this run. |
| `{{orchestration.sourcePath}}` | Absolute path to the orchestration source file, when parsed from disk. For managed copies, this points to the original source file. |
| `{{orchestration.sourceDirectory}}` | Absolute directory containing the orchestration source file. Use this to build orchestration-relative runtime file paths. |
| `{{step.name}}` | The current step's name. |
| `{{step.type}}` | The current step's type. |
| `{{server.url}}` | Orchestra server URL. |
| `{{workingDirectory}}` | The working directory context. |

### Orchestration-step accessors

For steps of type `Orchestration` (steps that invoke another orchestration), these
additional accessors expose the child run's data — populated on every terminal branch,
including failed and cancelled child runs:

| Expression | Description |
|---|---|
| `{{stepName.executionId}}` | The child run's execution id (use with `get_orchestration_status` / `get_orchestration_step`). |
| `{{stepName.status}}` | Lowercase child status (`succeeded`, `failed`, `cancelled`, `pending` for async dispatch). |
| `{{stepName.errorMessage}}` | Top-level error message from the child run. |
| `{{stepName.completionReason}}` | `orchestra_complete` reason, if any. |
| `{{stepName.childResult}}` | JSON of `executionId`, `status`, `errorMessage`, `finalContent`, `completionReason`, `cancellation`, `stepResults`. |
| `{{stepName.steps}}` | JSON map of all child-step results. |
| `{{stepName.steps.<childStepName>.output}}` | Untruncated content of one child step. |
| `{{stepName.steps.<childStepName>.rawOutput}}` | Pre-output-handler content of one child step. |
| `{{stepName.steps.<childStepName>.error}}` | Error message of one child step. |
| `{{stepName.steps.<childStepName>.status}}` | Lowercase status of one child step. |
| `{{stepName.steps.<childStepName>.files}}` / `files[N]` | Saved files of one child step. |

These accessors enable patterns like a self-healing parent orchestration that inspects
its child's per-step errors via `{{attempt-1.steps.failing-step.error}}` and reuses a
child's partial output via `{{attempt-1.steps.codegen.output}}` in the next attempt's
prompt — without any MCP round-trip.

Runtime file-writing steps should receive absolute paths. Build paths relative to the orchestration file with `{{orchestration.sourceDirectory}}/relative/path` rather than relying on the process working directory.

---

## Enums Reference

### Step Types
`Prompt`, `Http`, `Transform`, `Command`, `Script`, `Orchestration`, `Approval` (case-insensitive)

### System Prompt Mode
`Append` (adds to SDK built-in prompts), `Replace` (removes SDK built-in prompts), `Customize` (selectively override individual sections)

### Reasoning Level
`Low`, `Medium`, `High`

### Trigger Type
`Manual` (default), `Scheduler`, `Loop`, `Webhook`

### MCP Type
`Local` (stdio), `Remote` (HTTP)

### Execution Status (runtime)
`Pending`, `Running`, `Succeeded`, `Failed`, `Skipped`, `Cancelled`, `NoAction`, `AwaitingInput`

### CancellationCauseKind (runtime, when run ends in Cancelled/Failed)
`Unknown`, `External`, `OrchestrationTimeout`, `SyncInvokeTimeout`, `OrchestrationComplete`, `HostShutdown`, `AwaitingInputTimeout`, `HostShutdownDuringWait`

### Hook Events
`step.success`, `step.failure`, `step.after`, `step.awaitingInput`, `orchestration.success`, `orchestration.failure`, `orchestration.after`

### Pending Input Kinds
`Approval` (declarative `Approval` step), `EngineTool` (LLM-driven `orchestra_request_user_input`)

### Approval Timeout Behavior
`fail` (default when set), `defaultResponse`, `cancel`

---

## Registering Orchestrations

Orchestrations can be registered in Orchestra via:

1. **REST API** `POST /api/orchestrations/json` with body `{ "json": "<orchestration JSON string>" }` -- registers from raw JSON content.
2. **REST API** `POST /api/orchestrations` with body `{ "paths": ["<file path>"] }` -- registers from file path.
3. **MCP Control Plane** `register_orchestration` tool -- registers from file path.
4. **Directory Scan** -- Orchestra can auto-scan a directory on startup.
