---
name: reusable-orchestrations
description: Catalogue of architecturally useful Orchestra orchestrations already registered in THIS workspace that should be reused (via the `Orchestration` step type or the data-plane `invoke_orchestration` MCP tool) instead of being re-implemented inline. Use this skill when authoring a new orchestration that needs to publish ActionView entries, upsert a Microsoft To Do task, dedupe work against Zakira state, idempotently mutate a tracked item, or generate / repair other orchestrations. Pair it with `orchestration-authoring` (schema reference) and `mcp-catalog` (MCP wiring).
---

# Reusable Orchestrations Catalogue

This skill documents the orchestrations in this workspace that exist specifically
to be reused as building blocks. Treat them as the **standard library** of the
workspace: prefer invoking them over reimplementing their behaviour inline.

They fall into two families:

- **State & output utilities** — domain-agnostic side-effect helpers that every
  tracker / digest / pipeline can call: publish to ActionView, upsert a To Do
  task, dedupe against Zakira, mutate a tracked item.
- **Generation & resiliency** — meta-orchestrations that author or repair other
  orchestrations.

Each entry answers:

1. **What it does** — single-sentence summary of the contract.
2. **When to use it** — the scenario that should make you reach for it.
3. **When NOT to use it** — the failure modes that make it the wrong tool.
4. **Inputs** — runtime parameters and their shapes.
5. **Invocation** — the canonical call (a `type: Orchestration` step is the
   default; the data-plane MCP is the alternative for agent-driven flows).

Every value is passed as a **string** at runtime, even for `boolean` / `number`
inputs. The child's final output is read by dependants via `{{stepName.output}}`.

> **Two ways to invoke any of these:**
> 1. A `type: Orchestration` step with `orchestration: <registered-name>` and
>    `mode: sync` (the default; parent waits and consumes the child's output).
> 2. The Orchestra **data-plane** MCP tool `invoke_orchestration` (for
>    agent-driven flows from inside a Prompt step that has `mcps: [orchestra]`).

If something is not listed here, it is not part of this skill — consult
`orchestration-authoring` for the YAML schema or `mcp-catalog` for MCP wiring.

---

# Family A — State & output utilities

## 1. `actionview-submit` — publish entries to ActionView

**File:** `config/Orchestra/Workspace/orchestrations/ActionView/actionview-submit.yaml`
**Registered name:** `actionview-submit` — the **most-reused** block in the
workspace (invoked by ~11 orchestrations).

### What it does
Takes a pre-built ActionView entry as a JSON string, optionally validates it
against an ActionView template, optionally overrides its `groupId`, then submits
it via `dnx ActionView.Cli ... add --file <file>`. It fetches the live
ActionView schema and the named template (if any), uses an LLM step to validate
+ merge defaults, saves the cleaned JSON, and runs the CLI add command.

### When to use it
- Any orchestration that produces a finding, recommendation, or notification
  that needs to land in ActionView. Author the entry JSON in your own step,
  then invoke this orchestration to submit it.
- When you want template-based defaulting and severity / groupId normalisation
  without re-implementing that logic.
- When multiple steps in the same parent run should land in the same ActionView
  group — pass a single `groupId` to every invocation.

### When NOT to use it
- For bulk imports of dozens of pre-validated entries: call
  `dnx ActionView.Cli ... add --file` directly in a loop; the per-invocation
  LLM validation step is overhead.
- When you only need to *read* from ActionView (`list`, `show`, `templates`):
  call the CLI or the MCP directly.

### Inputs
| Name        | Required | Default | Description                                                                                                  |
|-------------|----------|---------|--------------------------------------------------------------------------------------------------------------|
| `entryJson` | Yes      | --      | Full entry JSON string. Must include at least `type`, `source`, `title`.                                     |
| `template`  | No       | `""`    | Optional template name. When set, the entry is validated and merged against the named template's definition. |
| `groupId`   | No       | `""`    | When non-empty, overrides any `groupId` in `entryJson`. Use to group entries from the same parent run.        |

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

---

## 2. `todo-upsert` — idempotent Microsoft To Do task

**File:** `config/Orchestra/Workspace/orchestrations/Shared/todo-upsert.yaml`
**Registered name:** `todo-upsert` (reused by ~5 trackers/digests).

### What it does
Idempotently creates or updates a Microsoft To Do task identified by a
caller-supplied stable `externalId`. Backed by Microsoft Graph plus an
`externalId -> taskId` mapping persisted in Zakira.Exchange, so repeat calls
converge on the same task instead of duplicating it. Resolves a Graph token
per run from the Azure CLI session (never persisted).

### When to use it
- Any tracker / digest that needs to surface actionable items as native To Do
  tasks the user already lives in (PR follow-ups, waiting-on items, meeting
  action items, daily digest tasks).
- When you need create-or-update semantics keyed off your own stable id, and
  want "completed today" entries to be created already-done (`status: completed`).

### When NOT to use it
- Bulk task creation where you do not need dedupe — call Graph directly.
- Non–To Do task systems (Planner, AzDO work items, IcM) — those have their own
  MCPs / utilities.

### Inputs
| Name         | Required | Default        | Description                                                                 |
|--------------|----------|----------------|-----------------------------------------------------------------------------|
| `listName`   | Yes      | --             | To Do list display name (auto-created when missing).                        |
| `externalId` | No       | `""`           | Caller-stable id used to dedupe (mapped to a Graph `taskId` via Zakira).    |
| `title`      | No       | `""`           | Task title.                                                                 |
| `body`       | No       | `""`           | Optional markdown body (sent as text).                                      |
| `dueDate`    | No       | `""`           | Optional ISO-8601 due date/time (UTC); empty clears it.                     |
| `importance` | No       | `normal`       | `low` \| `normal` \| `high`.                                                |
| `status`     | No       | `notStarted`   | `notStarted` \| `inProgress` \| `completed` \| `deferred` \| `waitingOnOthers`. |
| `categories` | No       | `""`           | Optional comma-separated category names.                                    |
| `dbPath`     | No       | `{{env.XDG_CONFIG_HOME}}/orchestra/zakira.db` | Zakira DB for the externalId→taskId map + list-id cache. |
| `todoItem`   | No       | `""`           | Auto-injected per-item object for `forEach` dispatch; backfills empty scalar inputs. |

### Output
`{ operation: created|updated|no-op, listName, listId, externalId, taskId, status, webLink, graphResponse }`

### Invocation
```yaml
- name: upsert-followup
  type: Orchestration
  orchestration: todo-upsert
  mode: sync
  parameters:
    listName: "PR Follow-ups"
    externalId: "pr-{{param.prId}}"
    title: "Respond to PR {{param.prId}}"
    importance: high
```

---

## 3. `zakira-find-or-skip` — idempotency / dedupe gate

**File:** `config/Orchestra/Workspace/orchestrations/Shared/zakira-find-or-skip.yaml`
**Registered name:** `zakira-find-or-skip`.

### What it does
Classifies a list of items into "needs-processing" vs "already-handled" buckets
using Zakira.Exchange as the source of truth. Generalises the per-item
state-filter pattern (look up `<category>/<key>`, skip when the stored status
matches and is still fresh). **Fail-open**: any Zakira hiccup routes the item to
`toProcess` rather than silently dropping it.

### When to use it
- The front gate of a batch processor: feed it the items you *might* process and
  forward only the returned `toProcess` bucket to the worker step / child.
- When you want freshness-aware reprocessing (`freshnessField` + `freshnessHours`)
  so an item is re-handled after its state goes stale.

### When NOT to use it
- Single-item idempotency where you are about to write anyway — use
  `tracker-item-mutate` (it no-ops naturally).
- Live data fetch — this only reads Zakira state, it does not fetch your items.

### Inputs
| Name                 | Required | Default      | Description                                                            |
|----------------------|----------|--------------|------------------------------------------------------------------------|
| `itemsJson`          | Yes      | --           | JSON array (serialized) of item objects.                               |
| `category`           | Yes      | --           | Zakira.Exchange category to look each item up against.                 |
| `itemKeyField`       | No       | `zakiraKey`  | Property on each item holding the canonical Zakira key.                |
| `dbPath`             | No       | `{{env.XDG_CONFIG_HOME}}/orchestra/zakira.db` | Zakira SQLite DB path.                |
| `statusField`        | No       | `status`     | Field within the stored `Data:` payload holding lifecycle status.      |
| `skipIfStatusEquals` | No       | `processed`  | Comma-separated status values meaning "already-handled" (case-insensitive). |
| `freshnessField`     | No       | `""`         | Optional payload field with an ISO-8601 timestamp for freshness gating. |
| `freshnessHours`     | No       | `"0"`        | When non-zero, stored timestamp must be within the last N hours to count as handled. |
| `forceProcess`       | No       | `"false"`    | When true, bypass all checks and route every item to `toProcess`.      |

### Output
`{ toProcess: [...full items...], skipped: [{key,summary,matchedAt}], stats: {total,toProcess,skipped,errors} }`

### Invocation
```yaml
- name: dedupe
  type: Orchestration
  orchestration: zakira-find-or-skip
  mode: sync
  parameters:
    itemsJson: "{{fetch-items.output}}"
    category: "raindrop-bookmarks"
    skipIfStatusEquals: "processed,archived"
# downstream: iterate over {{dedupe.output}} -> .toProcess
```

---

## 4. `tracker-item-mutate` — idempotent single-item Zakira edit

**File:** `config/Orchestra/Workspace/orchestrations/Shared/tracker-item-mutate.yaml`
**Registered name:** `tracker-item-mutate`.

### What it does
Performs an idempotent Zakira.Exchange edit on one tracker item: deep-merges a
`patch` JSON object into the stored `Data:` payload (creating the entry first
when `createIfMissing: true`), and always stamps `mutatedAt`. Designed as the
indirection layer behind ActionView dismiss / resolve / not-an-ask buttons so
the entry's command body stays simple and the state schema lives in one place.

### When to use it
- Recording a state transition on a tracked item (dismissed, resolved,
  acknowledged) without re-reading and re-serialising the whole payload yourself.
- ActionView action buttons that POST to the invoke endpoint with `category`,
  `key`, and a small `patch`.

### When NOT to use it
- Bulk classification of many items — use `zakira-find-or-skip`.
- Reads — call the Zakira MCP / CLI directly.

### Inputs
| Name             | Required | Default   | Description                                                            |
|------------------|----------|-----------|------------------------------------------------------------------------|
| `category`       | Yes      | --        | Zakira.Exchange category to mutate.                                    |
| `key`            | Yes      | --        | Stable key within the category.                                        |
| `patch`          | Yes      | --        | JSON object (serialized) deep-merged into the stored `Data:` payload.  |
| `createIfMissing`| No       | `"false"` | When true, create the entry from `patch` if absent; else no-op.        |
| `dbPath`         | No       | `{{env.XDG_CONFIG_HOME}}/orchestra/zakira.db` | Zakira SQLite DB path.                |
| `author`         | No       | `""`      | Optional author recorded with the edit/create (defaults to run id).    |
| `reason`         | No       | `""`      | Optional reason recorded with the edit/create.                         |

### Output
`{ category, key, operation: edit|create|noop, mutatedAt, previousData, newData }`

### Invocation
```yaml
- name: mark-dismissed
  type: Orchestration
  orchestration: tracker-item-mutate
  mode: sync
  parameters:
    category: "pr-comments"
    key: "{{param.threadId}}"
    patch: '{"status":"dismissed"}'
    createIfMissing: "false"
```

---

# Family B — Generation & resiliency

## 5. `generate-orchestration-fast` — single-shot orchestration generator

**File:** `config/Orchestra/Workspace/orchestrations/System/orchestration-generator-fast.yaml`
**Registered name:** `generate-orchestration-fast`.

### What it does
Generates a complete orchestration YAML file from a natural-language description
in **one** LLM call, then sanitises and validates the output with deterministic
PowerShell (strips markdown fences, truncates at multi-document and context-leak
markers, structural-validates required top-level keys) before writing it to disk
as UTF-8 without BOM. It loads the `orchestration-authoring` and `mcp-catalog`
skills so the model already knows the schema and MCP catalogue.

### When to use it
- Ephemeral / throwaway orchestrations where iteration speed matters more than
  rigorous review. `run-self-healing` and `run-ephemeral` both use it per attempt.
- Inside meta-orchestrations that programmatically produce orchestration files.
- When the description is small, well-scoped, and the surrounding workflow will
  exercise / validate the generated YAML anyway.

### When NOT to use it
- Production, long-lived orchestrations you intend to commit and maintain — use
  the slower `generate-orchestration` (semantic review + validation loop).
- When you need the result in-memory rather than written to disk — this always
  writes a file via its final step.

### Inputs
| Name          | Required | Default | Description                                                                 |
|---------------|----------|---------|-----------------------------------------------------------------------------|
| `description` | Yes      | --      | Natural-language spec. Be specific about steps, triggers, MCPs, inputs/outputs. |
| `outputPath`  | Yes      | --      | **Absolute** path where the YAML is written. Parent dirs are created. Use `{{orchestration.sourceDirectory}}` to derive relative paths. |

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

The filesystem watcher discovers the new file under the watched workspace; poll
`list_orchestrations` if the next step needs to invoke it.

---

## 6. `generate-orchestration` — thorough orchestration generator

**File:** `config/Orchestra/Workspace/orchestrations/System/orchestration-generator.yaml`
**Registered name:** `generate-orchestration`.

### What it does
The multi-step, higher-quality sibling of `generate-orchestration-fast`. Adds
intent-validation and best-practices subagents, an LLM-driven validation loop,
and semantic review before saving (and optionally registering) the orchestration.
Also loads `orchestration-authoring` + `mcp-catalog`.

### When to use it
- Hand-in-the-loop authoring of orchestrations you intend to commit and maintain.
- When correctness / best-practices compliance matters more than turnaround time.

### When NOT to use it
- Throwaway / ephemeral generation in a tight retry loop — use the fast variant.

### Inputs
| Name               | Required | Default | Description                                                            |
|--------------------|----------|---------|------------------------------------------------------------------------|
| `description`      | Yes      | --      | Natural-language description of the orchestration.                     |
| `outputPath`       | No       | --      | File path to save the generated file; if omitted, saved only to the temp dir. |
| `workingDirectory` | No       | `"."`   | Working dir for the `filesystem` MCP (the server is sandboxed to it).  |

### Invocation
```yaml
- name: author-orchestration
  type: Orchestration
  orchestration: generate-orchestration
  mode: sync
  parameters:
    description: "{{spec.output}}"
    outputPath: "{{orchestration.sourceDirectory}}/../Generated/new-flow.yaml"
```

---

## 7. `run-ephemeral` — generate-and-run a one-off orchestration

**File:** `config/Orchestra/Workspace/orchestrations/System/run-ephemeral.yaml`
**Registered name:** `run-ephemeral`.

### What it does
Given a natural-language task, generates a one-off orchestration (via
`generate-orchestration-fast`), saves it under the watched `Ephemeral/` folder,
waits for the watcher to register it, then executes it once as a child
`Orchestration` step. The single-attempt cousin of `run-self-healing` — **no
repair loop**.

### When to use it
- A one-off task that justifies an orchestration but not hand-authoring one, and
  where a single generation+run attempt is acceptable.

### When NOT to use it
- Tasks likely to need repair on failure — use `run-self-healing`.
- Recurring / committed work — author a real orchestration with proper triggers.

### Inputs
| Name   | Required | Default | Description                                          |
|--------|----------|---------|------------------------------------------------------|
| `task` | Yes      | --      | Natural-language description of the task to perform. |

### Invocation
```yaml
- name: do-one-off
  type: Orchestration
  orchestration: run-ephemeral
  mode: sync
  parameters:
    task: "Summarise today's failed pipeline runs into a markdown table."
```

---

## 8. `run-self-healing` — self-healing ephemeral runner

**File:** `config/Orchestra/Workspace/orchestrations/System/run-self-healing.yaml`
**Registered name:** `run-self-healing`.

### What it does
Generic controller for "give me a task, I'll write an orchestration for it and
keep repairing it until it works, or I run out of attempts." Per attempt it uses
`generate-orchestration-fast` to write a per-attempt ephemeral YAML under the
watched `Ephemeral/` directory, polls `list_orchestrations` until the watcher
discovers it, invokes it synchronously with the caller-supplied `parametersJson`,
and — on generation / invocation / `successCriteria` failure — captures all
evidence (execution IDs, failed step names, error messages, the generated YAML)
and feeds it back into the next generation request as repair guidance. The repair
loop runs in a single long-running Prompt step (`self-healing-controller`) with
infinite sessions, using the **data-plane** MCP only.

### When to use it
- One-off tasks worth an orchestration but not worth hand-crafting and committing
  ("let an agent figure out the orchestration and retry on its own").
- Tasks where transient failures make a single fixed YAML unreliable, but the
  shape of the work is well-defined enough for an LLM to author and repair it.

### When NOT to use it
- Recurring scheduled work / webhook handlers / anything needing a stable
  registered name — commit a real orchestration.
- Tasks where you already have a known-good orchestration — invoke it directly.
- Pure agentic work that does not benefit from being split across attempts.

### Inputs
| Name                  | Required | Default   | Description                                                                 |
|-----------------------|----------|-----------|-----------------------------------------------------------------------------|
| `task`                | Yes      | --        | Natural-language description of the work to perform.                        |
| `parametersJson`      | No       | `"{}"`    | JSON object (as a string) of parameters passed to each generated child.     |
| `successCriteria`     | No       | `""`      | Extra criteria the child output must satisfy. Empty means "child success is enough." |
| `maxAttempts`         | No       | `"3"`     | Bounded 1-10. Each attempt may launch long-running agents — keep it small.  |
| `childTimeoutSeconds` | No       | `"21600"` | `timeoutSeconds` baked into each generated child (its own hard abort cap).  |

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

The final step returns a single JSON object summarising every attempt; consume it
via `{{run-task.output}}` downstream.

---

## Picking between them

| Need                                                                 | Use                              |
|----------------------------------------------------------------------|----------------------------------|
| Land an entry in ActionView                                          | `actionview-submit`              |
| Create / update a Microsoft To Do task without duplicating it        | `todo-upsert`                    |
| Filter a batch down to only the items that still need work           | `zakira-find-or-skip`            |
| Record a state change on one tracked item idempotently               | `tracker-item-mutate`            |
| Programmatically write a new orchestration file (fast / throwaway)   | `generate-orchestration-fast`    |
| Author a production-quality orchestration (reviewed)                 | `generate-orchestration`         |
| Generate and run a one-off task once                                 | `run-ephemeral`                  |
| Run a one-off task that may need to be re-authored on failure        | `run-self-healing`               |
| Hand-author a long-lived orchestration                               | Neither — write it yourself, using `orchestration-authoring` |

## Domain dispatcher → worker orchestrations (not general-purpose)

Several feature areas decompose into a parent **dispatcher** that fans out to a
reusable **worker** child (also a `type: Orchestration` call): e.g.
`pr-review-dispatcher → pr-code-reviewer`, `pr-comment-dispatcher → pr-comment-responder`,
`meeting-action-items-extractor → meeting-action-items-processor`,
`meeting-prep-brief → meeting-prep-briefer`,
`zts-official-pipeline-manual-tracker → zts-official-pipeline-dispatcher`, and the
`raindrop-*` processors. These are **domain-specific** — reuse them only inside
their own pipeline, not as general building blocks. The IcM and Raindrop flows
additionally invoke children **dynamically** through the `orchestra` MCP
`invoke_orchestration` tool rather than a static `Orchestration` step.

## Related skills

- `orchestration-authoring` — complete property-level YAML reference for
  authoring orchestrations. Required reading before invoking
  `generate-orchestration-fast`, `generate-orchestration`, `run-ephemeral`, or
  `run-self-healing`, because all ultimately emit YAML that must conform to the
  same schema.
- `mcp-catalog` — the source of truth for MCP server wiring. The generators load
  it automatically; if you author a child orchestration by hand and need to reach
  an MCP, consult it directly.
