---
name: orchestration-authoring
description: Creates and validates Orchestra orchestration files (JSON/YAML) that define DAGs of steps (Prompt, Command, Script, Http, Transform) with triggers, MCPs, subagents, loops, typed inputs, and template expressions. Use when authoring new orchestrations, generating orchestration files from descriptions, reviewing existing orchestrations for correctness, or debugging orchestration issues.
---

# Orchestra Orchestration Authoring Reference

Complete reference for creating valid, idiomatic Orchestra orchestration files.

**Detailed references** (read on demand):
- [references/examples.md](references/examples.md) -- Full real-world example orchestrations
- [references/full-schema-reference.md](references/full-schema-reference.md) -- Complete property-level documentation with all edge cases

## Format

Orchestrations are single JSON or YAML objects. Three fields are required: `name`, `description`, `steps`. YAML is recommended for orchestrations with multi-line prompts (use `|` block scalars).

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
| `defaultSystemPromptMode` | string | No | null | `"append"` or `"replace"` for all Prompt steps |
| `defaultRetryPolicy` | RetryPolicy | No | null | Default retry for all steps |
| `defaultStepTimeoutSeconds` | int | No | null | Default per-step timeout |
| `timeoutSeconds` | int | No | 3600 | Orchestration-level timeout (0 to disable) |
| `variables` | object | No | {} | Key-value pairs accessed via `{{vars.name}}` |
| `tags` | string[] | No | [] | Categorization tags |

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

## Steps

Steps form a DAG. Steps with no `dependsOn` run first (in parallel). Downstream steps run when all dependencies complete.

### Base Step Properties (all types)

| Property | Type | Required | Default |
|---|---|---|---|
| `name` | string | Yes | -- |
| `type` | string | Yes | -- |
| `dependsOn` | string[] | No | [] |
| `parameters` | string[] | No | [] |
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
| `mcps` | string[] | No | [] |
| `loop` | LoopConfig | No | null |
| `subagents` | Subagent[] | No | [] |
| `skillDirectories` | string[] | No | [] |

*Mutual exclusion: use `systemPrompt` OR `systemPromptFile`, not both. Same for `userPrompt`/`userPromptFile`, `inputHandlerPrompt`/`inputHandlerPromptFile`, `outputHandlerPrompt`/`outputHandlerPromptFile`.

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

Executes a shell command, captures stdout.

| Property | Type | Required | Default |
|---|---|---|---|
| `command` | string | Yes | -- |
| `arguments` | string[] | No | [] |
| `workingDirectory` | string | No | current dir |
| `environment` | object | No | {} |
| `includeStdErr` | bool | No | false |
| `stdin` | string | No | null |

### Script Step (type: "Script")

Executes an inline or file-based script via a shell interpreter (e.g., `pwsh`, `bash`, `python`, `node`). Captures stdout. Designed for multi-line scripts -- use YAML `|` blocks for best readability.

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
      - "@anthropic/mcp-server-filesystem"
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

## Engine Tools (Built-in, available to all Prompt steps)

| Tool | Description |
|---|---|
| `orchestra_save_file` | Save content to a file in the run's temp directory |
| `orchestra_read_file` | Read a previously saved file |
| `orchestra_set_status` | Override step status: `success`, `failed`, or `no_action` (skips downstream) |
| `orchestra_complete` | Halt entire orchestration immediately |

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
Command -> Script -> Prompt -> Transform -> Http
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

## Naming Conventions

- Orchestration names: kebab-case (`my-deployment-pipeline`)
- Step names: kebab-case (`build-artifact`, `security-scan`)
- Variable names: camelCase (`appName`, `slackWebhookUrl`)
- Input names: camelCase (`serviceName`, `dryRun`)
