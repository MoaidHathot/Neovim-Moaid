# Orchestra Orchestration Full Schema Reference

This is the complete property-level reference for every field, step type, trigger type, and supporting object available in an orchestration file. For a condensed overview, see the main [SKILL.md](../SKILL.md).

## Contents

- [File Structure Overview](#file-structure-overview)
- [Top-Level Properties](#top-level-properties)
- [Typed Inputs](#typed-inputs)
- [Steps](#steps)
  - [Base Step Properties](#base-step-properties)
  - [Prompt Step](#prompt-step)
  - [Http Step](#http-step)
  - [Transform Step](#transform-step)
  - [Command Step](#command-step)
  - [Script Step](#script-step)
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
| `defaultSystemPromptMode` | `string` | No | `null` | Default system prompt mode for all Prompt steps. Values: `"append"` or `"replace"`. |
| `defaultRetryPolicy` | `RetryPolicy` | No | `null` | Default retry policy applied to all steps unless overridden at the step level. |
| `defaultStepTimeoutSeconds` | `int` | No | `null` | Default per-step timeout in seconds. Individual steps can override this. |
| `timeoutSeconds` | `int` | No | `3600` | Maximum time in seconds for the entire orchestration run. Set to `0` or `null` to disable. |
| `variables` | `object` | No | `{}` | Key-value pairs of user-defined variables. Values can contain template expressions. Accessed via `{{vars.name}}`. |
| `tags` | `string[]` | No | `[]` | Tags for categorizing and filtering orchestrations. |

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

## Steps

Steps are the building blocks of an orchestration. They form a DAG: steps with no `dependsOn` run first (and in parallel with each other), and downstream steps run once all their dependencies have completed.

### Base Step Properties

These properties are shared by **all** step types.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | **Yes** | -- | Unique name within the orchestration. Used to reference this step in `dependsOn` and template expressions. |
| `type` | `string` | **Yes** | -- | Step type. One of: `"Prompt"`, `"Http"`, `"Transform"`, `"Command"`, `"Script"` (case-insensitive). |
| `dependsOn` | `string[]` | No | `[]` | Names of steps that must complete before this step runs. Defines the DAG edges. |
| `parameters` | `string[]` | No | `[]` | Parameter names this step expects. Values are provided at runtime and accessed via `{{param.name}}`. |
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
| `systemPromptMode` | `string` | No | `null` | How the system prompt interacts with the SDK's built-in prompts. `"append"` adds to them; `"replace"` removes them. |
| `mcps` | `string[]` | No | `[]` | Names of MCP servers (defined at orchestration level or in `mcp.json`) to attach as tools for this step. |
| `loop` | `LoopConfig` | No | `null` | Loop/checker configuration for iterative refinement. |
| `subagents` | `Subagent[]` | No | `[]` | Subagent definitions for multi-agent delegation. |
| `skillDirectories` | `string[]` | No | `[]` | Directories containing `SKILL.md` files that provide additional context/instructions. |

> **\*Mutual exclusion rules:**
> - Exactly one of `systemPrompt` or `systemPromptFile` is required.
> - Exactly one of `userPrompt` or `userPromptFile` is required.
> - `inputHandlerPrompt` and `inputHandlerPromptFile` are mutually exclusive.
> - `outputHandlerPrompt` and `outputHandlerPromptFile` are mutually exclusive.

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

Executes a shell command as a child process and captures stdout.

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

Executes an inline or file-based script via a shell interpreter. The script's stdout is captured as output.

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
| `{{step.name}}` | The current step's name. |
| `{{step.type}}` | The current step's type. |
| `{{server.url}}` | Orchestra server URL. |
| `{{workingDirectory}}` | The working directory context. |

---

## Enums Reference

### Step Types
`Prompt`, `Http`, `Transform`, `Command`, `Script` (case-insensitive)

### System Prompt Mode
`Append` (adds to SDK built-in prompts), `Replace` (removes SDK built-in prompts)

### Reasoning Level
`Low`, `Medium`, `High`

### Trigger Type
`Manual` (default), `Scheduler`, `Loop`, `Webhook`

### MCP Type
`Local` (stdio), `Remote` (HTTP)

### Execution Status (runtime)
`Pending`, `Running`, `Succeeded`, `Failed`, `Skipped`, `Cancelled`, `NoAction`

---

## Registering Orchestrations

Orchestrations can be registered in Orchestra via:

1. **REST API** `POST /api/orchestrations/json` with body `{ "json": "<orchestration JSON string>" }` -- registers from raw JSON content.
2. **REST API** `POST /api/orchestrations` with body `{ "paths": ["<file path>"] }` -- registers from file path.
3. **MCP Control Plane** `register_orchestration` tool -- registers from file path.
4. **Directory Scan** -- Orchestra can auto-scan a directory on startup.
