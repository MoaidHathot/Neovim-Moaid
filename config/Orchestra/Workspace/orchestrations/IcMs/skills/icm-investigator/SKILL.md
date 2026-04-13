---
name: icm-investigator
description: "Reusable KQL queries, cluster mappings, and investigation templates for ZTS ICM incident investigation. Use when: fetching ICM data, querying ZTS Kusto logs, building investigation reports."
---

# ICM Investigator Skill

Reusable assets for the ICM Investigator agent: KQL query templates, cluster mappings, investigation templates.

## Shift Scratch Pad

Always try to read `references/shift-scratchpad.md` before starting or resuming an investigation.

- `references/shift-scratchpad.md` is a personal, git-ignored file for live shift notes.
- Do not commit this file to the repository.
- If the file exists, treat it as high-priority context alongside the current investigation playbooks.
- If the file is missing, continue normally.

## Structure

```
references/
  shift-scratchpad.md            # Personal, git-ignored on-call shift notes
  # Investigation playbooks (loaded on demand by ICM pattern)
  playbook-http-error.md          # HTTP 5xx error investigation
  playbook-health-probe.md        # Health probe failure investigation
  playbook-tip-test.md            # TIP test failure/monitor/duration investigation (includes pipeline data gap)
  playbook-unknown.md             # Fallback for unrecognized ICM patterns
  playbook-skill-maintenance.md   # Post-investigation playbook maintenance based on current session findings
  # KQL query templates
  list-zts-icms.kql               # Active/mitigated ZTS ICMs
  get-icm-details.kql             # Full ICM details with description
  error-summary.kql               # Aggregate errors by type
  http-errors.kql                 # HTTP error investigation (correlationId + ranked dedup)
  request-timeline.kql            # Full request trace by correlationId
  request-errors.kql              # Errors-only trace (RP/CCG Service column)
  duration-distribution.kql       # Request duration distribution
  error-timeline.kql              # Error count over time
  tip-test-results.kql            # TIP PASSED/FAILED/SKIPPED/TIMEOUT
  tip-job-timeline.kql            # Full job lifecycle
  tip-test-frequency.kql          # Hourly test counts
  tip-test-errors.kql             # TIP exceptions (extracts x-ms-client-request-id)
  rpaas-incoming-requests.kql     # RPaaS HttpIncomingRequests
  rpaas-outgoing-requests.kql     # RPaaS HttpOutgoingRequests
  pipeline-child-run-gap.kql      # Parent periodic run scheduling and skipped/missing child windows
  pipeline-worker-occupancy.kql   # Generator pod availability, postprocess occupancy, and queue pickup timing
  tip-test-output.kql             # Detailed test method output
  health-probe.kql                # Health probe status/duration distribution
  health-probe-concurrent-load.kql # Concurrent heavy requests during probe failures
  # Shared references
  cluster-mapping.md              # ICM signal to Kusto cluster
  investigation-template.md       # Report template
```

## KQL Placeholders

| Placeholder | Description |
|---|---|
| `{start}` / `{end}` | ISO 8601 datetime |
| `{tenant}` | Log tenant name for the target environment (for example `ztsppe`, `zts-stage`, `zts-dev`) |
| `{correlationId}` | Request correlation ID |
| `{statusCode}` | HTTP status code (e.g. 500) |
| `{armId}` | ARM resource ID (empty = all) |
| `{jobGroupName}` | TIP job group (e.g. `ZtsTipJobGroup-uksouth`) |
| `{jobName}` | TIP job name |
| `{testDisplayName}` | Fully qualified test name |

## Kusto Clusters

- ICM: `https://icmcluster.kusto.windows.net` / `IcmDataWarehouse`
- ZTS logs: see `references/cluster-mapping.md`
- RPaaS: `https://rpsaas.kusto.windows.net` / `RPaaSProd` - filter by `providerNamespace =~ "MICROSOFT.ZEROTRUSTSEGMENTATION"`. For HTTP 400: match `clientRequestId`. For HTTP 504: match `correlationId` (from `x-ms-correlation-request-id`).

### Kusto Access

If the user gets an authorization/access error when querying any Kusto cluster, provide the appropriate access request instructions below.

#### ICM Kusto (`icmcluster.kusto.windows.net` / `IcmDataWarehouse`)

1. Request membership for the **IcM-Kusto-Access** CoreIdentity entitlement: <https://coreidentity.microsoft.com/manage/Entitlement/entitlement/icmkustoacce-ufk0>
2. This entitlement controls access to IcM's Kusto data warehouse.
3. Manager approval is required — the request will be routed to the user's manager for approval.

**Bypass:** The agent can proceed without ICM Kusto access. Ask the user to manually paste the ICM details (incident ID, title, full description, time window, affected API, datacenter, correlationIds) instead of querying the ICM cluster.

#### ZTS Kusto (region-specific cluster from `references/cluster-mapping.md` / `Log`)

ZTS has multiple Kusto clusters — one per environment/region. The agent must check the cluster that matches the ICM's region (see Cluster Resolution above and the full cluster table in `references/cluster-mapping.md`).

1. ZTS Kusto clusters are managed by the ZTS team. The user must be a member of the appropriate security group for the target environment.
2. Request access through the ZTS team's onboarding process or ask the ZTS on-call lead to grant reader access to the target cluster.

**Bypass:** None — the agent CANNOT investigate without ZTS log access. STOP and wait for the user to obtain access.

#### RPaaS Kusto (`rpsaas.kusto.windows.net` / `RPaaSProd`)

1. Request access to the RPaaS Kusto cluster through the RPaaS CoreIdentity entitlement.
2. This cluster contains `HttpIncomingRequests` and `HttpOutgoingRequests` tables filtered by `providerNamespace =~ "MICROSOFT.ZEROTRUSTSEGMENTATION"`.

**Bypass:** The agent can proceed without RPaaS Kusto access. RPaaS correlation steps will be skipped. Note this limitation in the investigation report.

## Log Table Schema

Key columns in ZTS `Log` table:
- `body` - main message text (NOT `env_msg` which does not exist)
- `message`, `severityText`, `pod_name`, `Tenant`, `runid`, `correlationId`
- `exception.message`, `exception.stacktrace`
- `env_name` - log category (e.g. "RequestResponseLog")
- `env_properties` - JSON bag, parse with `todynamic()`

Tenant names vary by cluster. Stage has `zts-stage` only (no separate `ccg-api` tenant). Dev has `zts-dev`. TIP test logs always use `Tenant == "SyntheticsProd"`.

## Fetching ICMs

Use `references/list-zts-icms.kql` to fetch active/mitigated ZTS ICMs from the ICM Kusto cluster.
Use `references/get-icm-details.kql` to get full ICM details including the description field.

Key fields to extract from the ICM description:
- `Monitor.DataStartTime` / `Monitor.DataEndTime` — investigation time window
- `HttpPath`, `HttpStatusCode` — affected API endpoint and error code
- Datacenter / device names — cluster hint
- `correlationId` values — for request tracing

## Cluster Resolution

To determine which ZTS Kusto cluster to query, apply this priority order:
1. ICM description names a cluster explicitly
2. `OccurringDatacenter` / `OccurringDeviceName` matches an entry in `references/cluster-mapping.md`
3. Monitor name contains an environment hint (e.g. "stage", "prod", region name)
4. Ask the user — present the cluster table and let them choose

Update `references/cluster-mapping.md` when you discover a new mapping.

## ICM Type Classification

Classify the ICM by its title pattern to determine which investigation section to follow:

| Title Pattern | Type | Playbook Reference |
|---|---|---|
| `HTTP Request [METHOD] returns status code [5xx]` | HTTP Error | `references/playbook-http-error.md` |
| `Monitor Execution is unhealthy. TIP Test [X] was not executed` | TIP Monitor | `references/playbook-tip-test.md` |
| `Monitor Duration is unhealthy. TIP Test [X]...exceeded duration threshold` | TIP Duration | `references/playbook-tip-test.md` |
| `Test Execution in [TestName] has Failed` | TIP Test Failure | `references/playbook-tip-test.md` |
| `Http Health Probe is unhealthy` | Health Probe | `references/playbook-health-probe.md` |
| **Unknown pattern** | Unknown | `references/playbook-unknown.md` |

## Post-Investigation Skill Maintenance

When an investigation discovers a new recurring signature, a more precise root cause, or better branching guidance for an existing pattern, load `references/playbook-skill-maintenance.md` before finishing. Use it to decide whether to update an existing playbook, add a new playbook, or leave the skill unchanged.

## ADO Work Items

ZTS backend work items live in:
- **Project:** `One`
- **Area path:** `One\Networking\Network Security\ZTS\Backend`

## Investigation Playbooks

After classifying the ICM type using the table above, load the matching playbook from `references/` for detailed investigation steps, KQL queries to run, and known patterns:

- **HTTP Error** → read `references/playbook-http-error.md`
- **Health Probe** → read `references/playbook-health-probe.md`
- **TIP Test / TIP Monitor / TIP Duration** → read `references/playbook-tip-test.md` (includes pipeline data gap investigation for GetGraphAndSetLabelsAvailabilityTest)
- **Unknown pattern** → read `references/playbook-unknown.md` (runs broad diagnostics, matches to closest known playbook, then investigates from first principles if truly new)

## Key Source Directories

| Area | Path | Description |
|---|---|---|
| Resource Provider | `src/ResourceProvider/` | RP API controllers, request handling |
| Common libraries | `src/common/` | Shared code (Synthetics, test runner, etc.) |
| Service clients | `src/clients/` | Client libraries for dependencies |
| Data Processing | `src/DataProcessing/` | Data processing pipelines |
| Data Acquisition | `src/DataAcquisition/` | Data ingestion |
| CCG Pipeline (Python) | `src/python/` | pipeline_runner.py, pipeline_engine.py, metadata_client_synapse.py |
