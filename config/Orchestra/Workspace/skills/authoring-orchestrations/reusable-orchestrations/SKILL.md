---
name: reusable-orchestrations
description: Catalogue of architecturally useful Orchestra orchestrations already registered in this workspace that should be reused (via the `Orchestration` step type or the data-plane `invoke_orchestration` MCP tool) instead of being re-implemented inline. Use this skill when authoring a new orchestration that needs to publish ActionView entries, generate other orchestrations from natural-language descriptions, or run an ephemeral self-healing task. Pair it with `writing-orchestrations` (schema reference) and `mcp-catalog` (MCP wiring).
---

# Reusable Orchestrations Catalogue

This skill documents the small set of orchestrations in this workspace that exist
specifically to be reused as building blocks. Authors should treat them as the
"standard library" of the workspace: prefer invoking them over reimplementing
their behaviour inline.

The three entries below are kept deliberately short. Each section answers:

1. **What it does** -- single-sentence summary of the contract.
2. **When to use it** -- the trigger phrase / scenario that should make you reach
   for this orchestration instead of writing custom steps.
3. **When NOT to use it** -- the failure modes that make it the wrong tool.
4. **Inputs** -- the runtime parameters and their shapes.
5. **Invocation** -- the canonical way to call it (a `type: Orchestration` step
   is the default; the data-plane MCP is the alternative for agent-driven flows).

If something is not listed here, it is not part of this skill -- consult
`writing-orchestrations` for the YAML schema or `mcp-catalog` for MCP wiring.

---

## 1. `actionview-submit` -- publish entries to ActionView

**File:** `config/Orchestra/workspace/orchestrations/ActionView/actionview-submit.yaml`

### What it does
Takes a pre-built ActionView entry as a JSON string, optionally validates it
against an ActionView template, optionally overrides its `groupId`, then submits
it via `dnx ActionView.Cli ... add --file <file>`. It fetches the live
ActionView schema and the named template (if any), uses an LLM step to validate
+ merge defaults, saves the cleaned JSON, and then runs the CLI add command.

### When to use it
- Any orchestration that produces a finding, recommendation, or notification
  that needs to land in ActionView. Author the entry JSON in your own step,
  then invoke this orchestration to submit it.
- When you want template-based defaulting and severity / groupId normalisation
  without re-implementing that logic.
- When multiple steps in the same parent run should land in the same
  ActionView group -- pass a single `groupId` to every invocation.

### When NOT to use it
- For bulk imports of dozens of pre-validated entries: call
  `dnx ActionView.Cli ... add --file` directly in a loop; the LLM validation
  step in this orchestration is per-invocation overhead.
- When you only need to *read* from ActionView (`list`, `show`, `templates`):
  call the CLI or the MCP directly.

### Inputs
| Name        | Required | Description                                                                                                  |
|-------------|----------|--------------------------------------------------------------------------------------------------------------|
| `entryJson` | Yes      | Full entry JSON string. Must include at least `type`, `source`, `title`.                                     |
| `template`  | No       | Optional template name. When set, the entry is validated and merged against the named template's definition. |
| `groupId`   | No       | When non-empty, overrides any `groupId` in `entryJson`. Use to group entries from the same parent run.       |

### Invocation
```yaml
- name: publish-finding
  type: Orchestration
  orchestration: actionview-submit
  mode: sync
  parameters:
    entryJson: "{{build-entry.output}}"
    template: "code-review-finding"
    groupId: "{{orchestration.runId}}"
```

For agent-driven invocation, use the Orchestra data-plane MCP tool
`invoke_orchestration` with the same parameters.

---

## 2. `generate-orchestration-fast` -- single-shot orchestration generator

**File:** `config/Orchestra/workspace/orchestrations/System/orchestration-generator-fast.yaml`
**Name registered with Orchestra:** `generate-orchestration-fast`

### What it does
Generates a complete orchestration YAML file from a natural-language description
in **one** LLM call, then sanitises and validates the output with deterministic
PowerShell (strips markdown fences, truncates at multi-document and
context-leak markers, structural-validates required top-level keys) before
writing it to disk as UTF-8 without BOM.

It is the fast variant of the (slower, multi-step) `generate-orchestration`.
Both load the `writing-orchestrations` and `mcp-catalog` skills so the model
already knows the schema and the MCP catalogue when it writes the YAML.

### When to use it
- Ephemeral / throwaway orchestrations where iteration speed matters more than
  rigorous review. The `run-self-healing` orchestration uses this generator
  per attempt for exactly that reason.
- Inside other meta-orchestrations that programmatically produce orchestration
  files (generation pipelines, codegen, scaffolding tools).
- When the description is small, well-scoped, and the surrounding workflow
  will exercise / validate the generated YAML anyway.

### When NOT to use it
- Production, long-lived orchestrations you intend to commit and maintain.
  Use the slower `generate-orchestration` -- it adds intent / best-practices
  subagents, an LLM-driven validation loop, and semantic review.
- When you need the result returned in-memory rather than written to disk.
  This orchestration always writes a file via its final `save` step.

### Inputs
| Name          | Required | Description                                                                                                                  |
|---------------|----------|------------------------------------------------------------------------------------------------------------------------------|
| `description` | Yes      | Natural-language spec of the orchestration. Be specific about steps, triggers, MCPs, and inputs/outputs.                     |
| `outputPath`  | Yes      | **Absolute** path where the generated YAML will be written. Parent directories are created. Use `{{orchestration.sourceDirectory}}` to derive paths relative to the calling orchestration. |

### Invocation
```yaml
- name: scaffold-attempt
  type: Orchestration
  orchestration: generate-orchestration-fast
  mode: sync
  parameters:
    description: "{{compose-spec.output}}"
    outputPath: "{{orchestration.sourceDirectory}}/../Ephemeral/attempt-{{orchestration.runId}}.yaml"
```

The Orchestra filesystem watcher will discover the new file under the watched
workspace; poll `list_orchestrations` if the next step needs to invoke it.

---

## 3. `run-self-healing` -- self-healing ephemeral runner

**File:** `config/Orchestra/workspace/orchestrations/System/run-self-healing.yaml`

### What it does
Generic controller for "give me a task, I'll write an orchestration for it and
keep repairing it until it works, or I run out of attempts." For each attempt:

1. Uses `generate-orchestration-fast` to write a per-attempt ephemeral
   orchestration YAML under the watched `Ephemeral/` directory (sibling to the
   `System/` folder).
2. Polls `list_orchestrations` (data-plane MCP) until the watcher discovers it.
3. Invokes the generated orchestration synchronously with the caller-supplied
   `parametersJson`.
4. If generation, invocation, or `successCriteria` fails, captures all
   evidence (execution IDs, failed step names, error messages, the generated
   YAML) and feeds it back into the next generation request as repair guidance.

The repair loop is driven by a single long-running Prompt step
(`self-healing-controller`) with infinite sessions enabled. It only uses the
**data-plane** MCP -- registration of attempt YAMLs is via the filesystem
watcher, not the control plane.

### When to use it
- One-off tasks that justify writing an orchestration but are not worth
  hand-crafting and committing one. Anything in the
  "I want an agent to figure out the orchestration for me and retry on its
  own" shape.
- Tasks where transient failures (network, flaky MCPs, model drift) make a
  single fixed YAML unreliable, but the *shape* of the work is well-defined
  enough that an LLM can author and repair the YAML between attempts.
- Tasks that legitimately benefit from a small number of repair rounds
  (`maxAttempts` is bounded 1-10; default 3).

### When NOT to use it
- Recurring scheduled work, webhook handlers, or anything that needs a stable
  registered name -- commit a real orchestration and use the standard
  trigger types instead.
- Tasks where you already have a known-good orchestration: invoke that
  directly with a `type: Orchestration` step. Self-healing wraps a generator,
  which is overhead you do not need.
- Pure agentic work that does not benefit from being split across attempts.
  A single Prompt step with subagents may be cheaper and faster than this
  controller.

### Inputs
| Name                  | Required | Default | Description                                                                                                              |
|-----------------------|----------|---------|--------------------------------------------------------------------------------------------------------------------------|
| `task`                | Yes      | --      | Natural-language description of the work to perform. The controller turns this into a generation request per attempt.   |
| `parametersJson`      | No       | `"{}"`  | JSON object (as a string) of parameters to pass to each generated child invocation. Values should be strings.            |
| `successCriteria`     | No       | `""`    | Additional criteria the child output must satisfy. Empty means "child success is enough."                                |
| `maxAttempts`         | No       | `"3"`   | Bounded 1-10. Each attempt may launch long-running agents -- keep it small.                                              |
| `childTimeoutSeconds` | No       | `"7200"`| Per-attempt invocation timeout in seconds.                                                                               |

### Invocation
```yaml
- name: run-task
  type: Orchestration
  orchestration: run-self-healing
  mode: sync
  parameters:
    task: |
      Audit the build output at {{param.buildOutputDir}} for missing
      symbol files and emit a markdown report describing any gaps.
    parametersJson: '{"buildOutputDir":"{{param.buildOutputDir}}"}'
    successCriteria: "Report must include a 'Missing symbols' section."
    maxAttempts: "3"
```

Or, from an agent session, call the data-plane MCP tool `invoke_orchestration`
with `orchestration_name: run-self-healing` and the same parameters.

The final step returns a single JSON object summarising every attempt; consume
it via `{{run-task.output}}` in a downstream step.

---

## Picking between the three

| Need                                                                 | Use                              |
|----------------------------------------------------------------------|----------------------------------|
| Land an entry in ActionView                                          | `actionview-submit`              |
| Programmatically write a new orchestration file from a description   | `generate-orchestration-fast`    |
| Run a one-off task that may need to be re-authored on failure        | `run-self-healing`               |
| Hand-author a long-lived orchestration                               | Neither -- write it yourself, using `writing-orchestrations` |

## Related skills

- `writing-orchestrations` -- complete property-level YAML reference for
  authoring orchestrations. Required reading before invoking
  `generate-orchestration-fast` or `run-self-healing`, because both ultimately
  emit YAML that must conform to the same schema.
- `mcp-catalog` -- the source of truth for MCP server wiring. The two
  generators above load it automatically; if you author a child orchestration
  by hand and need to reach an MCP, consult it directly.
