---
name: mcp-catalog
description: Authoritative catalog of MCP servers actually configured and working in this Orchestra workspace. Use this skill whenever you author or generate an orchestration so every `mcps:` entry references a real MCP. Distinguishes pre-registered MCPs (in orchestra.mcp.json, no top-level declaration needed) from inline-only MCPs (must be declared in the orchestration's top-level `mcps:` block).
---

# MCP Catalog (workspace-authoritative)

This is the canonical list of MCP servers wired up in this Orchestra workspace.
Two classes exist:

1. **Pre-registered MCPs** — declared globally in
   `config/Orchestra/orchestra.mcp.json` and automatically available to every
   orchestration. **Reference them by name only** in a step's `mcps:` array.
   Do **NOT** add a top-level `mcps:` entry for them in your orchestration —
   re-declaring them is redundant noise that bloats the YAML.
2. **Inline-only MCPs** — not in the global registry. **Must be declared in
   the orchestration's top-level `mcps:` block** with full configuration
   (`type`, `command`+`arguments` for `local`, or `endpoint` for `remote`),
   then referenced by name in each step's `mcps:` array.

If a name is not in this catalog, it is not registered — do not fabricate.

> **Canonical example of mixed usage:**
> `Debug/debug-general-validation.yaml` declares only `orchestra` at the
> top-level (inline-only) and references seven pre-registered MCPs via a
> single step `mcps: [icm-readonly, icm-full, orchestra, azdo, azure,
> powerreview, debug-mcp]`. Match this idiom.

---

## Quick Selector — pick the right MCP by intent

| Intended capability | Use this MCP |
|---|---|
| Microsoft 365 calendar (events, attendees, scheduling) | `calendar` or `workiq` |
| Microsoft 365 mail (Outlook, send/read) | `mail` or `workiq` |
| Microsoft Teams chats / channel messages / meeting transcripts | `workiq` |
| Microsoft 365 People / contact lookup / "about me" | `me` or `workiq` |
| Microsoft 365 Copilot capabilities | `m365-copilot` |
| Azure DevOps (PRs, work items, repositories, comments) | `azdo` |
| Azure resources (subscriptions, resource groups, ARM, etc.) | `azure` |
| Microsoft IcM — read-only (incident lookup, status) | `icm-readonly` |
| Microsoft IcM — read/write (acknowledge, mitigate, comment) | `icm-full` |
| PowerReview (PR review tooling — fetch threads, reply, vote, fix branches) | `powerreview` |
| MCP debugging / introspection harness | `debug-mcp` |
| Persistent state / memory across runs (key-value, lists, history) | `zakira` |
| Live web search / general research | `recall` |
| Library or framework documentation lookup | `context7` |
| Microsoft Learn / docs.microsoft.com / Azure / .NET docs | `microsoft-learn` |
| Browser automation, screenshots, scraping non-API web sources | `playwright` |
| Introspecting Orchestra runs / launching child orchestrations from MCP | `orchestra` |
| Local filesystem read/write (sandboxed to a working directory) | `filesystem` |

---

# Pre-registered MCPs (`orchestra.mcp.json`)

These are declared globally. **Do NOT add a top-level `mcps:` entry for any
of these** — Orchestra resolves them automatically. Just list the name in a
step's `mcps:` array.

The pre-registered set in this workspace:
`calendar`, `mail`, `me`, `m365-copilot`, `azdo`, `azure`, `icm-full`,
`icm-readonly`, `powerreview`, `debug-mcp`.

Each entry below describes purpose, when-to-use, when-NOT-to-use, and a
copy-paste step-level reference snippet.

---

## Microsoft 365 HTTP proxy MCPs (`calendar`, `mail`, `me`, `m365-copilot`)

These four are served over HTTP by the `m365-remote-mcps` background service
(see `orchestra.services.json`) on port `5113`, fronting
`config/Orchestra/m365.proxy.json` with `routing.mode: perServer` and
`basePath: /mcp` — endpoints land at `http://localhost:5113/mcp/<name>`.

**`workiq` vs proxy MCPs — when to choose which:**
- Prefer **`workiq`** when an orchestration touches multiple M365 concerns
  (e.g. calendar + mail) or when consistency with existing workspace
  orchestrations matters. workiq is local stdio with a broad toolset.
- Prefer a **proxy MCP** (`calendar` / `mail` / `me` / `m365-copilot`) when
  you want a smaller, focused toolset for a single concern, or when you
  specifically need M365 Copilot (`m365-copilot`) which is not part of
  workiq.

**Auth note:** all four use `InteractiveBrowser` auth with
`deferConnection: true`. The first time an orchestration step touches one of
these in a new session, the proxy will prompt for browser auth via
`${VSCODE_CLIENT_ID}` and `${CORP_TENANT_ID}`.

### `calendar`

**Use for:** listing and inspecting calendar events, attendees, organizers,
free/busy, scheduling helpers, time-window searches.
**Do not use for:** mail or Teams operations — pick the matching focused
MCP, or `workiq`.
**Step-level reference:**

```yaml
steps:
  - name: list-meetings
    type: Prompt
    mcps: [calendar]
```

### `mail`

**Use for:** reading, searching, composing, and managing Outlook messages;
thread/conversation lookup.
**Do not use for:** calendar or Teams operations.
**Step-level reference:**

```yaml
steps:
  - name: triage-inbox
    type: Prompt
    mcps: [mail]
```

### `me`

**Use for:** the signed-in user's profile and personal information; "me /
my org / my manager"-type queries.
**Do not use for:** other people's profiles in bulk — `workiq` has broader
People tooling.
**Step-level reference:**

```yaml
steps:
  - name: load-my-profile
    type: Prompt
    mcps: [me]
```

### `m365-copilot`

**Use for:** Microsoft 365 Copilot tools (search M365 content, generate
from M365 data, Copilot-side tooling not in workiq).
**Do not use for:** generic LLM completions — use a Prompt step with
`model:` directly.
**Step-level reference:**

```yaml
steps:
  - name: search-m365-content
    type: Prompt
    mcps: [m365-copilot]
```

---

## `azdo` — Azure DevOps (full)

**Use for:** Azure DevOps via the official `@azure-devops/mcp` package —
PRs, work items, repos, builds, releases, comments, threads. Configured for
the `msazure` organization.
**Do not use for:** anything outside AzDO. Microsoft 365 needs go to
`workiq` / proxy MCPs. Note `workiq` also has *some* AzDO tools but `azdo`
is the dedicated, broader option.
**Step-level reference:**

```yaml
steps:
  - name: fetch-pr-details
    type: Prompt
    mcps: [azdo]
```

---

## `azure` — Azure resources

**Use for:** Azure subscriptions, resource groups, ARM operations,
deployments, KQL/Log Analytics, RBAC — anything served by `Azure.Mcp`
(`azmcp server start`).
**Do not use for:** Azure DevOps (use `azdo`); Microsoft Learn docs
(use `microsoft-learn`).
**Step-level reference:**

```yaml
steps:
  - name: list-subscriptions
    type: Prompt
    mcps: [azure]
```

---

## `icm-readonly` and `icm-full` — Microsoft IcM (incident management)

Two flavors of the same `IcM.Mcp` package, sourced from the
`msazure/One/_packaging/ZTS` Azure DevOps feed:

- **`icm-readonly`** — read-only mode (`-- --read-only`). Use this by
  default. Cannot acknowledge, mitigate, comment, or otherwise change
  incident state.
- **`icm-full`** — full read/write. Use only when the orchestration must
  change incident state (acknowledge, transfer, mitigate, post comments).

**Use for:** querying incidents, fetching IcM history, change-management
data, RP/SAR investigations.
**Do not use for:** non-IcM tickets (Jira, AzDO work items) — those go to
`azdo`.
**Step-level reference:**

```yaml
steps:
  - name: investigate-incident
    type: Prompt
    mcps: [icm-readonly]   # or [icm-full] when state changes are required
```

---

## `powerreview` — PR review tooling

**Use for:** authoritative PR review workflow — sync threads from the
remote provider, draft replies, vote (approve / wait-for-author),
submit reviews, create fix branches (`powerreview/fix/thread-{threadId}`),
and apply other automated PR actions.
**Do not use for:** generic AzDO operations not specific to review state
— prefer `azdo`.
**Step-level reference:**

```yaml
steps:
  - name: respond-to-comment
    type: Prompt
    mcps: [powerreview]
```

---

## `debug-mcp` — MCP debugging harness

**Use for:** smoke-testing the engine's MCP plumbing during diagnostics
(used by `Debug/debug-general-validation.yaml`).
**Do not use for:** production work — this is a developer harness, not a
real capability surface.
**Step-level reference:**

```yaml
steps:
  - name: smoke-test-mcp
    type: Prompt
    mcps: [debug-mcp]
```

---

# Inline-only MCPs (declare in top-level `mcps:`)

These are NOT in the global registry. You MUST declare each one your
orchestration uses in its top-level `mcps:` block before referencing it
from a step.

The inline-only set in this workspace:
`workiq`, `zakira`, `recall`, `context7`, `microsoft-learn`,
`playwright`, `orchestra`, `filesystem`.

---

## `workiq` — Microsoft 365 + Azure DevOps super-MCP

**Use for:**
- Calendar: list/find/inspect upcoming meetings, attendees, organizers,
  acceptance status, recurrence, free/busy.
- Mail: search and read Outlook mail; thread/conversation lookup.
- Teams: chat messages, channel posts, meeting transcripts.
- People / contacts: resolve a name to an attendee record, look up
  organizational hierarchy, find teammates.
- Azure DevOps: pull requests (metadata, comments, diffs, threads),
  work items, repositories, iterations.

**Do not use for:** anything outside Microsoft 365 / AzDO.

**Top-level definition:**

```yaml
mcps:
  - name: workiq
    type: local
    command: npx
    arguments:
      - "-y"
      - "@microsoft/workiq"
      - mcp
```

**Step-level reference:**

```yaml
steps:
  - name: find-next-meeting
    type: Prompt
    mcps: [workiq]
```

---

## `zakira` — persistent state / memory (Zakira.Exchange)

**Use for:** persisting structured state across orchestration runs
(category + key with arbitrary JSON-ish data plus free-form `reason`);
"have I already processed this PR / meeting / item?" patterns;
append-only history logs scoped to an orchestration.

**Do not use for:** live data fetch — it's a memory store, not a query
layer.

**Top-level definition:**

```yaml
mcps:
  - name: zakira
    type: local
    command: dnx
    arguments:
      - Zakira.Exchange
      - "--yes"
```

---

## `recall` — live web research (Zakira.Recall)

**Use for:** open-web search, broad fact-finding, fresh research where
the agent determines its own search/follow-up strategy.

**Do not use for:** documentation of specific named libraries (prefer
`context7`); Microsoft documentation (prefer `microsoft-learn`).

**Top-level definition:**

```yaml
mcps:
  - name: recall
    type: local
    command: dnx
    arguments:
      - Zakira.Recall
      - "--yes"
      - --
      - "mcp"
```

---

## `context7` — library / framework documentation (REMOTE)

**Use for:** looking up usage docs and code snippets for a specific
named library or framework; pre-flight research before generating code
that depends on a third-party library.

**Do not use for:** general web search (prefer `recall`); Microsoft-
specific docs (prefer `microsoft-learn`).

**Top-level definition:**

```yaml
mcps:
  - name: context7
    type: remote
    endpoint: "https://mcp.context7.com/mcp"
```

> Note: `context7` is a **remote** MCP — do not use a `npx`-based local
> command. The endpoint above is the canonical Context7 MCP service.

---

## `microsoft-learn` — Microsoft documentation

**Use for:** anything documented on `learn.microsoft.com` — Azure, .NET,
Windows, PowerShell, M365 admin, Power Platform, etc.

**Do not use for:** non-Microsoft third-party libraries (prefer
`context7`).

**Top-level definition:**

```yaml
mcps:
  - name: microsoft-learn
    type: remote
    endpoint: "https://learn.microsoft.com/api/mcp"
```

---

## `playwright` — browser automation

**Use for:** scraping or automating a site that has no API; reproducing
a bug that requires browser interaction; headless screenshot / DOM-
state capture.

**Do not use for:** anything that has a documented API or MCP — those
are cheaper and more reliable.

**Top-level definition:**

```yaml
mcps:
  - name: playwright
    type: local
    command: npx
    arguments:
      - "@playwright/mcp@latest"
      - "--headless"
```

---

## `orchestra` — Orchestra control/data plane introspection

**Use for:** querying status of past orchestration runs; saving small
files via the engine's helpers; working with Orchestra's own state
from inside an orchestration.

**Do not use for:** anything other than Orchestra introspection. The
endpoint `{{server.url}}/mcp/data` is *not* a Microsoft Graph endpoint,
*not* a generic data API, and *not* a passthrough to anything else.

**Top-level definition:**

```yaml
mcps:
  - name: orchestra
    type: remote
    endpoint: "{{server.url}}/mcp/data"
```

---

## `filesystem` — sandboxed local file I/O

**Use for:** reading or writing files inside a known working directory;
creating sub-directories, listing, deleting, moving files.

**Do not use for:** reaching outside the sandboxed working directory
(the MCP refuses paths outside its argument root); filesystem
operations on a remote machine (this is local-only).

**Top-level definition:**

```yaml
mcps:
  - name: filesystem
    type: local
    command: npx
    arguments:
      - "-y"
      - "@modelcontextprotocol/server-filesystem"
      - "{{param.workingDirectory}}"
```

The last argument is the **sandbox root** — every path the MCP touches
must be a descendant of that directory. Pass it via an orchestration
input (`workingDirectory`) so the caller controls the sandbox.

---

# Hard rules of usage

1. **Pre-registered MCPs need NO top-level definition.** If you list a
   pre-registered name in a step's `mcps:` array, do not also add it
   to the orchestration's top-level `mcps:` block. Re-declaring it is
   redundant noise.
2. **Inline-only MCPs MUST be defined in the top-level `mcps:` block**
   with full configuration before any step references them.
3. **Step `mcps:` is always a list of names** (strings) referencing
   either pre-registered names or names defined in the top-level
   `mcps:` block. Never inline a definition at step scope.
4. **Define each inline MCP at most once per orchestration** in the
   top-level `mcps:` block. Multiple steps reference it by name.
5. **If a step needs no MCP, omit `mcps:` on that step entirely.**
   Don't include it as an empty list.
6. **Never invent an MCP name or endpoint.** If the task seems to need
   a capability not in this catalog, write a `# TODO:` note in the
   orchestration's `description:` rather than fabricating an MCP.
7. **Endpoints are not interchangeable.**
   - `{{server.url}}/mcp/data` belongs to `orchestra` only.
   - `http://localhost:5113/mcp/<name>` belongs to the M365 HTTP proxy
     MCPs (`calendar`, `mail`, `me`, `m365-copilot`); the path segment
     must match the MCP name exactly. (And these are pre-registered, so
     you should not be writing endpoints for them at all — just
     reference the name from a step.)
   - `https://mcp.context7.com/mcp` belongs to `context7` only.
   - `https://learn.microsoft.com/api/mcp` belongs to
     `microsoft-learn` only.
