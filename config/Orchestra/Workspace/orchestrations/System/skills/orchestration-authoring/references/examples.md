# Orchestra Orchestration Examples

Real-world examples demonstrating common orchestration patterns. All examples use `claude-opus-4.6` as the default model.

## Contents
- [Minimal Orchestration](#minimal-orchestration)
- [Code Review Pipeline (YAML)](#code-review-pipeline-yaml)
- [Typed Inputs with Validation](#typed-inputs-with-validation)
- [Script Step with Inline PowerShell](#script-step-with-inline-powershell)
- [Multi-Step DAG with All Step Types](#multi-step-dag-with-all-step-types)
- [Loop/Checker Pattern](#loopchecker-pattern)
- [Multi-Agent with Subagents](#multi-agent-with-subagents)
- [Webhook with Synchronous Response](#webhook-with-synchronous-response)
- [Meta-Orchestration (Generates Orchestrations)](#meta-orchestration-generates-orchestrations)

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

## Script Step with Inline PowerShell

Demonstrates the Script step type with inline scripts and YAML block scalars:

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
      - "@anthropic/mcp-server-filesystem"
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
