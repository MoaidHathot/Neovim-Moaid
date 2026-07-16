# Orchestra Orchestration Examples

Real-world examples demonstrating common orchestration patterns. All examples use `claude-opus-4.6` as the default model.

> **A note on `$schema` paths.** The examples below use repository-relative paths like `../schemas/orchestration.schema.json` because they live inside the Orchestra repo. If you are authoring orchestrations outside this repo, replace those paths with **either** the public URL (`https://raw.githubusercontent.com/MoaidHathot/orchestra/main/schemas/orchestration.schema.json`) **or** a local copy produced by running `orchestra schemas` in your project (default location `./.orchestra/schemas/`). See [SKILL.md](../SKILL.md#format) for the full list of options.

## Contents
- [Minimal Orchestration](#minimal-orchestration)
- [Code Review Pipeline (YAML)](#code-review-pipeline-yaml)
- [Free-Form Metadata (JSON & YAML)](#free-form-metadata-json--yaml)
- [Typed Inputs with Validation](#typed-inputs-with-validation)
- [Lifecycle Hooks for Failure Triage](#lifecycle-hooks-for-failure-triage)
- [Script Step with Inline PowerShell](#script-step-with-inline-powershell)
- [Orchestration-Relative Runtime File Path](#orchestration-relative-runtime-file-path)
- [Multi-Step DAG with All Step Types](#multi-step-dag-with-all-step-types)
- [Loop/Checker Pattern](#loopchecker-pattern)
- [Multi-Agent with Subagents](#multi-agent-with-subagents)
- [Webhook with Synchronous Response](#webhook-with-synchronous-response)
- [Human-in-the-Loop: Declarative Approval Gate](#human-in-the-loop-declarative-approval-gate)
- [Human-in-the-Loop: LLM-Decided Pause via Engine Tool](#human-in-the-loop-llm-decided-pause-via-engine-tool)
- [Human-in-the-Loop: Notify on Pause via Hook](#human-in-the-loop-notify-on-pause-via-hook)
- [Meta-Orchestration (Generates Orchestrations)](#meta-orchestration-generates-orchestrations)
- [Advanced: Customize Mode, Image Attachments, Infinite Sessions](#advanced-customize-mode-image-attachments-infinite-sessions)

---

## Minimal Orchestration

A single Prompt step with no dependencies:

```json
{
  "name": "hello-world",
  "description": "A minimal orchestration with one step.",
  "steps": [
    {
      "name": "greet",
      "type": "Prompt",
      "systemPrompt": "You are a friendly assistant.",
      "userPrompt": "Say hello to the user.",
      "model": "claude-opus-4.6"
    }
  ]
}
```

---

## Code Review Pipeline (YAML)

Demonstrates YAML multiline prompts, step chaining, and Transform step:

```yaml
# yaml-language-server: $schema=../schemas/orchestration.schema.json
name: code-review
description: Multi-step code review pipeline demonstrating YAML multiline prompts
version: "1.0.0"

steps:
  - name: analyze-code
    type: Prompt
    model: claude-opus-4.6
    parameters:
      - code
    systemPrompt: |
      You are a senior software engineer performing a thorough code review.
      Focus on:
      - Code correctness and potential bugs
      - Performance implications
      - Security vulnerabilities
      - Adherence to best practices and coding standards
      - Code readability and maintainability

      Provide specific, actionable feedback with code examples where helpful.
    userPrompt: |
      Review the following code and provide detailed feedback:

      {{param.code}}

  - name: summarize-review
    type: Prompt
    model: claude-opus-4.6
    dependsOn:
      - analyze-code
    systemPrompt: |
      You are a technical writer. Summarize code review feedback into
      a concise, well-organized report with severity ratings for each
      finding (Critical, Warning, Suggestion).
    userPrompt: |
      Summarize the following code review into a brief report:

      {{analyze-code.output}}

  - name: format-output
    type: Transform
    dependsOn:
      - summarize-review
    template: |
      # Code Review Report

      {{summarize-review.output}}
```

---

## Free-Form Metadata (JSON & YAML)

The `metadata` top-level field accepts any JSON-compatible structure (string, number, boolean, array, nested object). It is purely informational -- the runtime never inspects it. Use it to record authorship, datetime, ticket links, environment, SLA, or any other semi-structured data that orchestration authors and managers want to keep alongside the file.

### JSON form

```json
{
  "$schema": "../schemas/orchestration.schema.json",
  "name": "deployment-with-metadata",
  "description": "Demonstrates the free-form metadata field.",
  "version": "1.0.0",
  "metadata": {
    "createdAt": "2026-04-30T12:00:00Z",
    "author": "platform-team",
    "owners": ["alice@example.com", "bob@example.com"],
    "ticket": "JIRA-1234",
    "environment": "staging",
    "sla": {
      "responseTimeMinutes": 15,
      "businessHoursOnly": true
    }
  },
  "steps": [
    {
      "name": "deploy",
      "type": "Prompt",
      "dependsOn": [],
      "systemPrompt": "You are a deployment assistant.",
      "userPrompt": "Deploy the service.",
      "model": "claude-opus-4.6"
    }
  ]
}
```

### YAML form (use the modeline so editors validate the file)

```yaml
# yaml-language-server: $schema=../schemas/orchestration.schema.json
name: deployment-with-metadata
description: Demonstrates the free-form metadata field.
version: "1.0.0"

metadata:
  createdAt: "2026-04-30T12:00:00Z"   # quote ISO-8601 dates so YAML keeps them as strings
  author: platform-team
  owners:
    - alice@example.com
    - bob@example.com
  ticket: JIRA-1234
  environment: staging
  sla:
    responseTimeMinutes: 15
    businessHoursOnly: true

steps:
  - name: deploy
    type: Prompt
    dependsOn: []
    model: claude-opus-4.6
    systemPrompt: You are a deployment assistant.
    userPrompt: Deploy the service.
```

**Notes**
- The schema declares `additionalProperties: true` for `metadata`, so any keys/value types are accepted.
- The runtime preserves the original JSON shape on parse (objects stay objects, arrays stay arrays, mixed types are kept).
- Metadata is **not** available in template expressions like `{{vars.*}}` -- it is purely a sidecar for humans and external tooling.

---

## Typed Inputs with Validation

Demonstrates typed input schema with type validation, enum constraints, and default values:

```json
{
  "name": "typed-inputs-deployment",
  "description": "Deployment with typed inputs: enum constraints, defaults, and validation.",
  "version": "1.0.0",
  "inputs": {
    "serviceName": {
      "type": "string",
      "description": "Name of the service to deploy",
      "required": true
    },
    "environment": {
      "type": "string",
      "description": "Target deployment environment",
      "required": true,
      "enum": ["staging", "production"]
    },
    "dryRun": {
      "type": "boolean",
      "description": "When true, simulates the deployment without making changes",
      "required": false,
      "default": "false"
    },
    "replicas": {
      "type": "number",
      "description": "Number of container replicas to deploy",
      "required": false,
      "default": "3"
    }
  },
  "variables": {
    "deployTag": "{{param.serviceName}}-{{param.environment}}-{{orchestration.runId}}"
  },
  "steps": [
    {
      "name": "validate-config",
      "type": "Prompt",
      "systemPrompt": "You are a deployment configuration validator. Check that the deployment parameters are sensible and flag any concerns.",
      "userPrompt": "Validate the following deployment configuration:\n- Service: {{param.serviceName}}\n- Environment: {{param.environment}}\n- Replicas: {{param.replicas}}\n- Dry Run: {{param.dryRun}}\n- Deploy Tag: {{vars.deployTag}}\n\nList any warnings or concerns. If everything looks good, respond with VALIDATED.",
      "parameters": ["serviceName", "environment", "replicas", "dryRun"],
      "model": "claude-opus-4.6"
    },
    {
      "name": "generate-manifest",
      "type": "Transform",
      "dependsOn": ["validate-config"],
      "template": "# Deployment Manifest\n\n**Service:** {{param.serviceName}}\n**Environment:** {{param.environment}}\n**Replicas:** {{param.replicas}}\n**Dry Run:** {{param.dryRun}}\n**Tag:** {{vars.deployTag}}\n**Run ID:** {{orchestration.runId}}\n**Started:** {{orchestration.startedAt}}\n\n## Validation\n{{validate-config.output}}",
      "parameters": ["serviceName", "environment", "replicas", "dryRun"]
    },
    {
      "name": "deploy",
      "type": "Prompt",
      "dependsOn": ["generate-manifest"],
      "systemPrompt": "You are a deployment automation assistant. Generate the deployment commands based on the manifest. If dry run is true, prefix each command with '# DRY RUN: '.",
      "userPrompt": "Based on the following deployment manifest, generate the deployment commands:\n\n{{generate-manifest.output}}",
      "parameters": ["serviceName", "environment", "dryRun"],
      "model": "claude-opus-4.6"
    }
  ]
}
```

---

## Lifecycle Hooks for Failure Triage

Demonstrates orchestration-level hooks that fire after failures and write a structured JSON payload to disk:

```yaml
$schema: ../schemas/orchestration.schema.json
name: hooks-step-failure
description: Demonstrates a step failure hook that only runs for selected step names and receives the current step payload.
version: 1.0.0

hooks:
  - name: capture-build-or-deploy-failure
    on: step.failure
    when:
      steps:
        names: [build, deploy]
        status: failed
        match: any
    payload:
      detail: compact
      steps: current
      includeRefs: true
    action:
      type: script
      shell: pwsh
      scriptFile: ./hooks/write-hook-payload.ps1
      arguments:
        - ./artifacts/step-failure-payload.json
    failurePolicy: warn

steps:
  - name: build
    type: Command
    command: dotnet
    arguments: [build, ./does-not-exist/Nope.csproj]
    includeStdErr: true

  - name: summarize
    type: Prompt
    dependsOn: [build]
    systemPrompt: You summarize build output.
    userPrompt: Summarize the build output.
    model: claude-opus-4.6
```

This example demonstrates: top-level `hooks`, `step.failure` subscriptions, `when.steps` filtering, payload shaping with `detail` and `steps`, script-based hook actions, and `failurePolicy`.

---

## Script Step with Inline PowerShell

Demonstrates the Script step type with inline scripts and YAML block scalars. Use this pattern instead of wrapping inline PowerShell in a `Command` step with `pwsh -Command`:

```yaml
name: script-step-example
description: >
  Demonstrates the Script step type with inline PowerShell scripts.
  Scripts run natively in their shell interpreter without the boilerplate
  of wrapping everything in Command step arguments.
version: "1.0.0"
tags: ["example", "scripting"]

steps:
  - name: gather-system-info
    type: Script
    shell: pwsh
    script: |
      $ErrorActionPreference = 'Stop'
      $info = [ordered]@{
          Hostname    = $env:COMPUTERNAME ?? (hostname)
          OS          = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
          DotNetVer   = dotnet --version
          PowerShell  = $PSVersionTable.PSVersion.ToString()
          Timestamp   = (Get-Date -Format 'o')
      }
      $info | ConvertTo-Json
    timeoutSeconds: 30

  - name: analyze-info
    type: Prompt
    dependsOn: [gather-system-info]
    model: claude-opus-4.6
    systemPrompt: |
      You are a systems analyst. Given system information in JSON format,
      provide a brief health assessment and note any concerns.
    userPrompt: |
      System information:

      {{gather-system-info.output}}

  - name: format-report
    type: Transform
    dependsOn: [gather-system-info, analyze-info]
    template: |
      # System Health Report

      ## Raw Data
      ```json
      {{gather-system-info.output}}
      ```

      ## Analysis
      {{analyze-info.output}}
```

---

## Deterministic Gate with the Script Control Channel

A scheduled poller that stops the tick early — with no LLM — when there is nothing to process, using the Script control channel (`Orchestra-Complete`). The same script extracts the items array for downstream steps. Prefer this over an LLM gate for structural checks.

```yaml
name: inbox-poller
description: Poll an inbox on a schedule and dispatch work only when items exist.
version: "1.0.0"

steps:
  - name: list-inbox
    type: Script
    shell: pwsh
    script: |
      # ... call your API, print { "count": N, "items": [ ... ] } as JSON ...
      '{ "count": 0, "items": [] }'

  - name: gate-empty
    type: Script
    shell: pwsh
    dependsOn: [list-inbox]
    script: |
      $ErrorActionPreference = 'Stop'
      $resp  = $args[0] | ConvertFrom-Json
      $items = @($resp.items)
      if (-not $resp -or [int]$resp.count -eq 0 -or $items.Count -eq 0) {
        Orchestra-Complete -Status success -Reason 'Inbox is empty, nothing to dispatch.'
        '[]'; return
      }
      $items | ConvertTo-Json -Depth 100 -Compress -AsArray   # hand items to downstream steps
    arguments:
      - "{{list-inbox.output}}"

  - name: process
    type: Prompt
    dependsOn: [gate-empty]
    model: claude-opus-4.6
    systemPrompt: Process each item.
    userPrompt: "{{gate-empty.output}}"

trigger:
  type: scheduler
  intervalSeconds: 300
```

Variants:
- `Orchestra-SetStatus -Status no_action -Reason '...'` — end this step as `no_action`, which skips only its dependents (the rest of the DAG continues).
- Any shell: `orchestra step complete --status success --reason '...'`, or write `{"action":"complete","status":"success","reason":"..."}` to `$ORCHESTRA_CONTROL_FILE`.

The signal is read only on exit 0; malformed contents fail the step.

---

## Orchestration-Relative Runtime File Path

Use `{{orchestration.sourceDirectory}}` when a runtime step writes files beside the orchestration file. This avoids accidentally resolving relative paths from the host process working directory.

```yaml
name: write-report-example
description: Writes a report next to this orchestration.
version: "1.0.0"

variables:
  reportPath: "{{orchestration.sourceDirectory}}/reports/{{orchestration.runId}}.md"

steps:
  - name: write-report
    type: Script
    shell: pwsh
    script: |
      $ErrorActionPreference = 'Stop'
      $path = $args[0]
      $dir = [System.IO.Path]::GetDirectoryName($path)
      if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
      }
      Set-Content -LiteralPath $path -Value '# Report' -Encoding utf8NoBOM
      Write-Output $path
    arguments:
      - "{{vars.reportPath}}"
```

---

## Multi-Step DAG with All Step Types

Demonstrates all five step types, dependencies, variables, and Http notification:

```json
{
  "name": "deployment-pipeline",
  "description": "Build, test, review, and notify pipeline.",
  "version": "2.1.0",
  "variables": {
    "appName": "customer-portal",
    "registry": "{{env.CONTAINER_REGISTRY}}/{{vars.appName}}",
    "slackWebhookUrl": "{{env.SLACK_WEBHOOK_URL}}"
  },
  "steps": [
    {
      "name": "build",
      "type": "Command",
      "command": "dotnet",
      "arguments": ["publish", "-c", "Release", "-o", "/artifacts"],
      "workingDirectory": "{{param.projectPath}}",
      "parameters": ["projectPath"],
      "timeoutSeconds": 120,
      "includeStdErr": true
    },
    {
      "name": "run-tests",
      "type": "Command",
      "command": "dotnet",
      "arguments": ["test", "--no-build"],
      "workingDirectory": "{{param.projectPath}}",
      "parameters": ["projectPath"],
      "timeoutSeconds": 180
    },
    {
      "name": "security-scan",
      "type": "Prompt",
      "dependsOn": ["build"],
      "systemPrompt": "You are a security analyst.",
      "userPrompt": "Review the build output for vulnerabilities:\n\n{{build.output}}",
      "model": "claude-opus-4.6"
    },
    {
      "name": "deploy-report",
      "type": "Transform",
      "dependsOn": ["security-scan", "run-tests"],
      "template": "# Report\n\n## Security\n{{security-scan.output}}\n\n## Tests\n{{run-tests.output}}"
    },
    {
      "name": "notify-team",
      "type": "Http",
      "dependsOn": ["deploy-report"],
      "method": "POST",
      "url": "{{vars.slackWebhookUrl}}",
      "headers": { "Content-Type": "application/json" },
      "body": "{\"text\": \"Deployment report ready for {{vars.appName}}.\"}"
    }
  ]
}
```

---

## Loop/Checker Pattern

An iterative review loop that re-runs the draft step until the checker approves:

```json
{
  "name": "iterative-writing",
  "description": "Write and review until quality standards are met.",
  "steps": [
    {
      "name": "write-draft",
      "type": "Prompt",
      "systemPrompt": "You are a professional writer.",
      "userPrompt": "Write an article about {{topic}}.",
      "model": "claude-opus-4.6",
      "parameters": ["topic"]
    },
    {
      "name": "review",
      "type": "Prompt",
      "dependsOn": ["write-draft"],
      "systemPrompt": "You are an editor. If the draft is good, say PUBLISH. Otherwise say REVISE and explain why.",
      "userPrompt": "Review this draft:\n\n{{write-draft.output}}",
      "model": "claude-opus-4.6",
      "loop": {
        "target": "write-draft",
        "maxIterations": 3,
        "exitPattern": "PUBLISH"
      }
    }
  ]
}
```

---

## Multi-Agent with Subagents

A coordinator step that delegates to specialized subagents:

```json
{
  "name": "research-team",
  "description": "Coordinator delegates to researcher, analyst, and writer subagents.",
  "mcps": [
    {
      "name": "web-fetch",
      "type": "local",
      "command": "npx",
      "arguments": ["-y", "@anthropic/mcp-fetch"]
    }
  ],
  "steps": [
    {
      "name": "coordinator",
      "type": "Prompt",
      "systemPrompt": "You manage a team of specialists. Delegate tasks based on what is needed.",
      "userPrompt": "{{topic}}",
      "model": "claude-opus-4.6",
      "parameters": ["topic"],
      "subagents": [
        {
          "name": "researcher",
          "displayName": "Research Specialist",
          "description": "Finds information from the web.",
          "prompt": "You are a thorough researcher. Search and organize information.",
          "mcps": ["web-fetch"],
          "infer": true
        },
        {
          "name": "analyst",
          "displayName": "Data Analyst",
          "description": "Analyzes data and draws insights.",
          "prompt": "You are an analytical expert. Identify patterns and draw conclusions.",
          "infer": true
        },
        {
          "name": "writer",
          "displayName": "Content Writer",
          "description": "Produces polished written content.",
          "prompt": "You are a skilled writer. Transform research into clear content.",
          "infer": true
        }
      ]
    }
  ]
}
```

---

## Webhook with Synchronous Response

Processes webhook payloads with LLM-powered input normalization and returns results:

```json
{
  "name": "webhook-processor",
  "description": "Processes webhook payloads with LLM-powered input normalization.",
  "steps": [
    {
      "name": "process",
      "type": "Prompt",
      "systemPrompt": "You are an event processor.",
      "userPrompt": "Process this event: {{eventData}}",
      "model": "claude-opus-4.6",
      "parameters": ["eventData"]
    }
  ],
  "trigger": {
    "type": "webhook",
    "enabled": true,
    "maxConcurrent": 5,
    "inputHandlerPrompt": "Extract 'eventData' from the raw JSON payload. Return only a JSON object with an 'eventData' key.",
    "secret": "my-webhook-secret",
    "response": {
      "waitForResult": true,
      "responseTemplate": "{{process.output}}",
      "timeoutSeconds": 60
    }
  }
}
```

---

## Human-in-the-Loop: Declarative Approval Gate

A deploy pipeline that builds, then pauses for a human reviewer, then announces the decision. The reviewer's response (`reply` or `choice`) becomes the Approval step's output and feeds the downstream `announce` step.

```yaml
# yaml-language-server: $schema=../schemas/orchestration.schema.json
name: hitl-approval-deploy
description: Deploy with a human approval gate.
version: 1.0.0
inputs:
  service:
    type: string
    description: Service to deploy.
    required: true
  env:
    type: string
    description: Target environment.
    enum: [staging, production]
    required: true
steps:
  - name: build
    type: Command
    command: dotnet
    arguments: [build, -c, Release]

  - name: review-deploy
    type: Approval
    dependsOn: [build]
    prompt: |
      Approve deploy of {{param.service}} to {{param.env}}?

      Build output:
      {{build.output}}
    choices: [approve, reject]
    # No timeoutSeconds — wait indefinitely. By default the orchestration timeout
    # clock is paused while awaiting (pauseTimeoutDuringWait: true), so a long
    # human review does not consume the orchestration's timeout budget.

  - name: announce
    type: Transform
    dependsOn: [review-deploy]
    template: |
      Decision: {{review-deploy.output}}
      Service: {{param.service}}
      Env:     {{param.env}}
```

Respond with the CLI:

```bash
orchestra pending
orchestra respond hitl-approval-deploy <runId> review-deploy --choice approve --by alice
```

Or with a raw HTTP call:

```http
POST /api/orchestrations/hitl-approval-deploy/runs/<runId>/respond?step=review-deploy
Content-Type: application/json

{ "choice": "approve", "respondedBy": "alice" }
```

### CLI walkthrough — interactive

Running this orchestration with `orchestra run` opens a live SSE stream and prompts inline whenever the run pauses:

```text
$ orchestra run hitl-approval-deploy --param service=foo --param env=staging --by alice

Run started: hitl-approval-deploy / 2025-05-09T12-34-56_abcd

> build      started
\u2713 build      completed

\u25cf review-deploy  awaiting input

  Approve deploy of foo to staging?

  Build output:
  ...

  ? Choose: (Use arrow keys)
  > approve
    reject

  ? Add a comment? (optional, blank to skip): looks fine

\u2192 review-deploy  response accepted by alice: choice=approve reply=looks fine
\u2713 review-deploy  completed
> announce   started
\u2713 announce   completed

Run finished: Succeeded
```

**Non-interactive (CI / piped):** when stdin is redirected, `orchestra run` prints actionable instructions instead of prompting and exits with code 2 so the caller can detect the pause:

```text
\u25cf review-deploy  awaiting input

Awaiting input \u2014 stdin is not interactive.
Run continues on the server. To respond:

  orchestra respond hitl-approval-deploy 2025-05-09T12-34-56_abcd review-deploy --choice <approve|reject>
```

**Re-attaching after Ctrl+C:** the run continues server-side; reconnect with:

```bash
orchestra attach hitl-approval-deploy 2025-05-09T12-34-56_abcd
```

Useful flags on `run` and `attach`: `--quiet` (HITL + summary only), `--verbose` (firehose all SSE events), `--no-interactive` (force the print-and-exit fallback), `--by <name>` (audit identifier on any HITL responses).

### Portal walkthrough

The Portal surfaces every paused run on the **Waiting for Input** sidebar button (bottom of the left pane) with a live count badge. Click the button to open a modal listing each pending wait; select a row to reveal its prompt, then pick a choice (and/or write a reply) and submit. The form posts to the same `POST /respond` endpoint used by `orchestra respond`, so audit trails stay consistent regardless of how the human answered. The Portal remembers your name in `localStorage` (key `orchestra.portal.respondedBy`) after the first submission so subsequent responses don't re-prompt.

Updates are pushed live via the dashboard SSE stream (`/api/events`): when a run pauses anywhere, the badge increments instantly; when anyone (CLI, MCP, another Portal tab) responds, the row disappears in real time. Running orchestration cards also surface a "Waiting" chip while their step is paused so you can spot pending work without opening the modal.

---

## Human-in-the-Loop: LLM-Decided Pause via Engine Tool

For "ask only when needed" pauses, opt the Prompt step into the `request_user_input` engine tool. The agent calls `orchestra_request_user_input` mid-conversation only when it genuinely needs a clarification; the user's reply is returned as the tool result so the agent can continue with the answer in hand.

```yaml
# yaml-language-server: $schema=../schemas/orchestration.schema.json
name: hitl-engine-tool-clarify
description: Article writer that clarifies with the user only when ambiguous.
version: 1.0.0
inputs:
  topic:
    type: string
    required: true
steps:
  - name: writer
    type: Prompt
    systemPrompt: |
      You write technical articles. Use orchestra_request_user_input when (and only
      when) the topic is genuinely ambiguous and a clarifying decision from the
      user would meaningfully improve the article. For unambiguous topics, just
      write the article. Keep clarifying questions short and focused on a single
      decision; do not chain multiple questions.
    userPrompt: "Write a 200-word article about {{param.topic}}."
    model: claude-opus-4.6
    enableTools: [request_user_input]
```

Differences from the declarative `Approval` step:

- The agent decides whether to pause; existing pipelines without `enableTools` are unaffected.
- During the wait the step status remains `Running` (the agent session is held in memory). It does **not** transition to `AwaitingInput`.
- The engine-tool wait does **not** survive a host restart. If the host bounces during the wait, the run is marked `Failed` with cause `HostShutdownDuringWait`; the previous step's checkpoint stays intact for retry. For long-lived gates that must endure restarts, use the declarative `Approval` step.

### CLI walkthrough \u2014 free-form reply

When the agent calls `orchestra_request_user_input` without a `choices` array, `orchestra run` shows the LLM-authored prompt and asks for a free-form reply:

```text
$ orchestra run hitl-engine-tool-clarify --param topic="cellular automata"

Run started: hitl-engine-tool-clarify / 2025-05-09T12-40-00_efgh

> writer  started

\u25cf writer  awaiting input

  Should I focus on the mathematical theory, real-world applications,
  or the artistic/visual side?

  ? Reply: focus on real-world applications, ~200 words

\u2192 writer  response accepted: reply=focus on real-world applications, ~200 words
\u2713 writer  completed

Run finished: Succeeded
```

The Portal handles this case identically — engine-tool prompts appear in the same **Waiting for Input** modal, but the response form shows only a free-form reply textarea (no radio group when `choices` is absent).

---

## Human-in-the-Loop: Notify on Pause via Hook

Both `Approval` steps and `orchestra_request_user_input` tool calls fire the `step.awaitingInput` hook event. Wire it to a single script hook to send a Slack/Teams/email notification when any run pauses for input.

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
        } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri $env:SLACK_WEBHOOK -Method Post -Body $body -ContentType 'application/json'
```

The hook payload's `step.name` and `orchestration.runId` are sufficient to construct the response URL: `{{server.url}}/api/orchestrations/{name}/runs/{runId}/respond?step={stepName}`. With `includeRefs: true`, the payload also includes `refs.api.run` for fetching more run data.

---

## Meta-Orchestration (Generates Orchestrations)

A complex orchestration that generates other orchestrations using skills, subagents, loops, and MCP tools:

```yaml
name: generate-orchestration
description: >
  Meta-orchestration that generates Orchestra orchestration files from natural
  language descriptions. Uses skills for knowledge, subagents for validation,
  and loops for iterative refinement.
version: 2.0.0
tags: [meta, generator, tooling, system]

inputs:
  description:
    type: string
    description: >
      Natural language description of what the orchestration should do.
    required: true
  register:
    type: boolean
    description: >
      Whether to register the generated orchestration in Orchestra after creation.
    required: false
    default: "false"
  outputPath:
    type: string
    description: >
      File path where the generated orchestration file should be saved.
    required: false

mcps:
  - name: orchestra-control
    type: remote
    endpoint: "{{server.url}}/mcp/control"
  - name: filesystem
    type: local
    command: npx
    arguments:
      - "-y"
      - "@modelcontextprotocol/server-filesystem"
      - "{{workingDirectory}}"

steps:
  - name: generate
    type: Prompt
    model: claude-opus-4.6
    parameters:
      - description
    mcps:
      - orchestra-control
    skillDirectories:
      - ./skills/orchestration-authoring
    systemPrompt: |
      You are an expert Orchestra orchestration author. Generate valid,
      production-quality Orchestra orchestration YAML files based on user
      descriptions. Use 'claude-opus-4.6' as the default model.
    userPrompt: |
      Generate an Orchestra orchestration based on this description:

      {{param.description}}
    subagents:
      - name: intent-validator
        displayName: Intent Validator
        description: >
          Validates that the generated orchestration accurately reflects the
          user's original intent and requirements.
        prompt: |
          You are an intent validation specialist. Compare the generated
          orchestration against the user's description and ensure they match.
          If everything matches, say "INTENT MATCH".
          If issues exist, say "INTENT MISMATCH:" and list specifics.
        infer: true
      - name: best-practices-expert
        displayName: Best Practices Expert
        description: >
          Reviews orchestrations for best practices compliance including DAG
          efficiency, naming, prompt quality, and error handling.
        prompt: |
          You are an Orchestra best practices expert. Review orchestrations
          for DAG efficiency, naming conventions, prompt quality, error
          handling, input validation, and common mistakes.
          If approved, say "BEST PRACTICES: APPROVED".
          If issues exist, say "BEST PRACTICES: NEEDS IMPROVEMENT:" and list.
        infer: true
    outputHandlerPrompt: >
      Extract ONLY the raw YAML orchestration content from the input.
      Remove any markdown formatting, code fences, or explanations.

  - name: validate
    type: Prompt
    dependsOn:
      - generate
    model: claude-opus-4.6
    skillDirectories:
      - ./skills/orchestration-authoring
    systemPrompt: |
      You are an Orchestra orchestration validator. Review the YAML for
      structural and semantic correctness. If valid, respond with VALID
      followed by the YAML unchanged. If invalid, respond with INVALID
      followed by issues and a corrected version.
    userPrompt: |
      Validate this orchestration:

      {{generate.output}}
    outputHandlerPrompt: >
      Extract ONLY the raw YAML orchestration content from the input.
    loop:
      target: generate
      maxIterations: 2
      exitPattern: "VALID"

  - name: save-orchestration
    type: Prompt
    dependsOn:
      - validate
    model: claude-opus-4.6
    parameters:
      - outputPath
    mcps:
      - filesystem
    systemPrompt: |
      Save the orchestration content using `orchestra_save_file` with
      extension "yaml". If an output path is provided, also save a copy
      to that path using filesystem MCP tools.
    userPrompt: |
      Save the following orchestration.
      Output path: {{param.outputPath}}
      Content:
      {{validate.output}}

  - name: register-orchestration
    type: Prompt
    dependsOn:
      - save-orchestration
    model: claude-opus-4.6
    parameters:
      - register
    mcps:
      - orchestra-control
    systemPrompt: |
      If registration is NOT requested, call `orchestra_set_status` with
      status "no_action". If registration IS requested, use the
      `register_orchestration` MCP tool with the saved file path.
    userPrompt: |
      Registration requested: {{param.register}}
      Saved file information:
      {{save-orchestration.output}}

  - name: format-output
    type: Transform
    dependsOn:
      - save-orchestration
      - register-orchestration
    template: |
      # Orchestration Generated Successfully

      **Run ID:** {{orchestration.runId}}

      ## File Location
      {{save-orchestration.output}}

      ## Registration
      {{register-orchestration.output}}

      ## Generated Orchestration
      ```yaml
      {{validate.output}}
      ```
```

This example demonstrates: typed inputs, MCP definitions (local + remote), skill directories, subagents, loop/checker pattern, output handlers, engine tools (`orchestra_save_file`, `orchestra_set_status`), Transform step, template expressions, and multi-step DAG with dependencies.

---

## Advanced: Customize Mode, Image Attachments, Infinite Sessions

Demonstrates `systemPromptMode: customize` with section overrides, image attachments from file paths, and infinite session configuration:

```yaml
name: ui-accessibility-audit
description: >
  Analyzes UI mockups for accessibility issues using vision capabilities,
  generates accessible React components, and reviews them in read-only mode.
defaultModel: claude-opus-4.6

steps:
  - name: analyze-ui
    type: Prompt
    parameters:
      - mockupPath
    systemPrompt: |
      You are a senior UX engineer specializing in accessibility audits.
      Analyze UI screenshots for WCAG 2.1 AA compliance violations.
    systemPromptMode: customize
    systemPromptSections:
      tone:
        action: replace
        content: >
          Be direct. Use severity ratings: [CRITICAL], [WARNING], [SUGGESTION].
      code_change_rules:
        action: remove
      guidelines:
        action: append
        content: |
          - Reference WCAG success criteria by number.
          - Flag contrast ratios below 4.5:1 for normal text.
    userPrompt: Analyze the attached UI mockup for accessibility issues.
    attachments:
      - type: file
        path: "{{param.mockupPath}}"
        displayName: "UI Mockup"
    infiniteSessions:
      enabled: true
      backgroundCompactionThreshold: 0.80

  - name: generate-components
    type: Prompt
    dependsOn: [analyze-ui]
    systemPrompt: Generate accessible React components that fix all findings.
    systemPromptMode: customize
    systemPromptSections:
      guidelines:
        action: append
        content: |
          - Include aria-label and role attributes.
          - Add keyboard event handlers for interactive elements.
    userPrompt: |
      Based on this analysis, generate accessible React components:

      {{analyze-ui.output}}
    infiniteSessions:
      enabled: true
      backgroundCompactionThreshold: 0.85
      bufferExhaustionThreshold: 0.97

  - name: code-review
    type: Prompt
    dependsOn: [generate-components]
    systemPrompt: Review the generated code for accessibility compliance.
    systemPromptMode: customize
    systemPromptSections:
      code_change_rules:
        action: replace
        content: >
          READ-ONLY mode. Do NOT create or modify files. Only analyze and report.
    userPrompt: |
      Review this code. Rate each component: PASS, NEEDS_WORK, or FAIL.

      {{generate-components.output}}
    infiniteSessions:
      enabled: false  # Short task

  - name: report
    type: Transform
    dependsOn: [analyze-ui, generate-components, code-review]
    template: |
      # Accessibility Audit Report

      ## Analysis
      {{analyze-ui.output}}

      ## Components
      {{generate-components.output}}

      ## Review
      {{code-review.output}}
```

This example demonstrates: `systemPromptMode: customize` with section overrides (`replace`, `remove`, `append`), image attachments via file path with template expressions, infinite sessions with custom thresholds (enabled/disabled per step), and read-only enforcement via `code_change_rules` replacement.
