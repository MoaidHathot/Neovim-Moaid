# Provider controls (Orchestra 0.11+)

Read this before authoring Prompt steps with structured output, autopilot, skills, or mixed
Copilot/OpenCode providers. These settings are orchestration fields, not CLI arguments.

## Directory rules

Prompt, Command, and Script steps default to the **orchestration definition's directory**,
including when Orchestra runs as a .NET tool. Relative `workingDirectory` overrides resolve
from that directory. For `repo/orchestrations/build.yaml`, use `workingDirectory: ".."` to
work in `repo`. This changes the pre-0.11 process-CWD default.

Explicit skill/instruction directories always resolve from the definition directory, even
when the agent works elsewhere. Templates such as `{{vars.instructions}}` follow the same
rule. In-memory definitions without source metadata retain the process-CWD fallback.

## Provider matrix

| Setting | Copilot | OpenCode V2 |
|---|---|---|
| `responseSchema` | Native constrained generation and engine validation | Schema guidance and engine validation |
| `executionPolicy.mode: autopilot` | Native continuation | Orchestra-managed continuation |
| `humanInput: true` | Native questions/elicitation | Native forms rendered as questions |
| `skillDirectories` | Explicit native skill directories | Explicit native skill paths; no project-file copying |
| `instructionDirectories` | Omission retains the legacy skill-directory fallback; `[]` disables it | Omission supplies no extra instruction files; explicit directories load Markdown files |
| Ambient/nested discovery | Independently configurable booleans | Enabled by the runtime; `true` accepted, `false` rejected |
| `reasoningLevel` | Native reasoning effort | Corresponding advertised model variant |
| `reasoningSummary`, `contextTier`, `githubToken`, `sandbox`, system-prompt `append`/`customize` | Supported | Rejected when requested |
| Subagent `model`, `tools`, prompt/description | Supported | Supported |
| Subagent-specific `mcps`, `skills`, `infer: false` | Supported | Rejected; do not assume they are forwarded |
| `infiniteSessions.enabled` | Native compaction setting | Native compaction toggle |
| Compaction utilization thresholds | Supported | Rejected |

For mixed-provider workflows, put provider-specific settings on the appropriate steps.
A global discovery default of `false` also reaches OpenCode steps and is rejected. OpenCode
accepts qualified `provider/model#variant` model names; bare names use its host
`fallbackProvider`, whose default is `github-copilot`.

## Validated JSON

```yaml
name: verified-count
description: Compute a value and consume its validated JSON field.
defaultModel: claude-opus-4.8
defaultProvider: copilot
steps:
  - name: calculate
    type: Prompt
    systemPrompt: Complete the calculation and verify the result with a tool.
    userPrompt: Calculate 17 + 25 and return count.
    responseSchema:
      type: object
      properties:
        count: { type: integer }
      required: [count]
      additionalProperties: false
    executionPolicy:
      mode: autopilot
      maxContinues: 2
    timeoutSeconds: 180
  - name: consume
    type: Transform
    dependsOn: [calculate]
    template: "The count is {{calculate.output.count}}."
```

The example can also use `defaultProvider: opencode` with an authenticated V2 installation.
The model still uses its agent tools. The final exported result must satisfy the schema.
Prose prefixes, Markdown fences, missing fields, wrong types, and forbidden extra properties
fail validation. This checks the data contract, not the truth of the answer; use deterministic
verification for correctness.

**No special completion prompt, tool call, or marker is required from authors.** Orchestra
internally filters immediate-stop tools (`orchestra_set_status`, `orchestra_complete`) for
structured/autopilot steps. Do not add internal markers to your schema. Branch on JSON fields
downstream; a `status` field is data, not an implicit engine command.

`outputHandlerPrompt` runs as a separate non-interactive transformation with the same schema
and step-level authentication, directory, discovery, permission, and sandbox controls. It
does not repeat the main step's autopilot policy or orchestration-control tools. Validation
also covers its exported output.

## Bounded continuation

`executionPolicy` is **per Prompt step**:

- `mode`: `standard` (default) or `autopilot`.
- `maxContinues`: non-negative integer, default **5**. Zero permits the initial full tool
  loop and no extra continuations. It does not limit individual tool calls or tokens.
- Exhaustion fails the step; set `timeoutSeconds` to bound elapsed execution too.
- OpenCode autopilot uses this same budget to correct invalid structured output based on
  completed work. Standard mode fails invalid output without extra model calls.
- Retries, worker recovery, DAG checker loops, and autopilot are separate controls. A new
  attempt may repeat work; make external side effects idempotent when enabling retries.

Keep the task's session independent from other DAG steps. Pass outputs/artifacts through
dependencies. Normal internal planning is available; native plan mode is not selected.

Do not invent `autopilot: true`, `maxTurns`, `defaultExecutionPolicy`, or `responseFormat`
fields. Use `executionPolicy` and `responseSchema` exactly as shown.

## Automatic plan visibility

`defaultCapturePlans` defaults to true and Prompt `capturePlans` overrides it. Explicit agent
task lists/documents appear read-only in the Portal and are saved with execution history.
This is separate from native plan mode, autopilot, and DAG completion. Copilot uses native
plan/todo APIs; OpenCode also offers the labelled `orchestra_update_plan` compatibility tool
for versions without native todos. A complex-work prompt may ask the agent to keep its plan
current; simple tasks can finish with no plan. Output handlers do not create additional plans.

## Human input and errors

`humanInput` defaults to false: complete the task autonomously instead of offering to proceed
later. True enables native questions. Legacy `enableTools: [request_user_input]` implies true
only when `humanInput` is omitted. Explicit false overrides that opt-in.

`permissionPolicy.mode: requireHumanApproval` separately enables permission waits, even when
ordinary questions are disabled. All input paths serialize on the same step waiter.

OpenCode forms display titles/descriptions and choice labels. Numbers/booleans become typed
answers; multiple selections accept comma-separated choices or a JSON string array. External
browser forms are unsupported. Missing required MCP servers fail before prompt submission.

For tasks that intentionally recover from expected tool failures, choose `failOnToolError`
deliberately. When enabled, recovered failed calls can still fail the step; structured and
autopilot steps do not have a status tool to waive that policy.

Copilot native persistent memory and cross-session recall are disabled. OpenCode uses fresh
step conversations in its authenticated database and removes terminal sessions; it has no
equivalent native memory-disable switch. Configure explicit MCP memory when wanted.

After authoring, run `orchestra validate path/to/workflow.yaml --schema` with the installed
version's bundled schema, then exercise the intended provider and model.
