# TIP Test Investigation Playbook

Applies to ICMs matching:
- `Monitor Execution is unhealthy. TIP Test [X] was not executed` (TIP Monitor — test not running)
- `Monitor Duration is unhealthy. TIP Test [X]...exceeded duration threshold` (TIP Duration — test too slow)
- `Test Execution in [TestName] has Failed` (TIP Test Failure — test ran but failed)

Note: "Test Execution has Failed" ICMs are always TIP tests. DVT test failures do not open ICMs.

## TIP Test Logs

TIP test logs: `Log | where Tenant == "SyntheticsProd"`. Key columns: `type` (fully qualified test name), `JobGroupName`, `JobName`, `status`, `exceptionMessage`, `body`, `output`.

## Test Types

Test types follow pattern: `Microsoft.Azure.ZTS.E2E.Tests.V{version}.ZTS_V{version}_{TestName}` with tests: AvailabilityTests, Create, Delete, Edit, Get_Graph, Set_Labels, TestResourcesCleanup.

## Architecture

```
Geneva Synthetics -> ZtsTipJobGroup-{region}
  -> ResourceProviderApi-V{version} (every 10 min, 9 min timeout)
    -> XUnitTestsRunnerJob -> tests run sequentially
    -> Emit TestExecution metric -> Geneva Monitor -> ICM if 0 for 30 min
```

## Key Config

- `deploy/ev2/synthetics/synthetics-jobs-settings.json`
- `src/common/Synthetics/TestRunner/XUnitTestRunnerJob.cs`

## Investigation Steps

**Step 1: Triage** — Run `tip-test-results.kql` and use the result pattern to determine the investigation branch:

| Result Pattern | ICM Type | Investigation Branch |
|---|---|---|
| All PASSED, no FAILED | Duration threshold | → **Branch A: Slow Execution** |
| TIMEOUT in every bucket, few/no PASSED | Not executed | → **Branch B: Budget Exhaustion** |
| FAILED results present | Test failure | → **Branch C: Test Failure** |

**Step 2: Common queries** — Run regardless of branch:
- `tip-job-timeline.kql` — check job scheduling, timeout budget, and duration
- `tip-test-frequency.kql` — check execution rate drops

**Branch A: Slow Execution** (duration threshold ICMs)
- Tests pass but take too long. No exceptions to trace.
- Check concurrent load on the pod (heavy API calls like getGraph/setLabels running in parallel)
- Check pod resource pressure (CPU, memory, thread pool)
- Check dependency latency (CCG API, Synapse response times)

Known pattern: **backend orchestration latency after a successful TIP CRUD flow**
- Signature:
   - the TIP test itself passes,
   - the job either times out immediately after the pass or leaves almost no budget headroom,
   - backend logs show slow orchestration work rather than a functional RP failure.
- Current example: TIP duration ICM 763757788 in `ztsppe` for `SegmentationManagerBasicCrudOperations`
   - test passed in `584.58s`, then the job hit the `00:09:50` budget about `1.5s` later,
   - patch flow spent time in managed-identity and MoboBroker setup,
   - delete flow spent about `103s` deleting the MoboBroker.
- Investigation additions for this subtype:
   1. Trace the test phase markers from TIP output (`Creating`, `Updating`, `Deleting`, `Verifying deletion`)
   2. Query RP logs by the segmentation manager resource name
   3. Look for `ProvisioningManagedIdentity`, `CreatingMoboBroker`, `MrgSetupCompleted`, `DeletingMoboBroker`, and `MoboBrokerDeleted`
   4. Compare backend timestamps with the test phase durations to identify which orchestration stage consumed the budget
   5. Parent the ICM under the active MoboBroker incident if the evidence shows MoboBroker setup or deletion dominating the slow path
   6. If the same test later opens `Monitor Execution is unhealthy` incidents in adjacent buckets, treat those monitor ICMs as the same slow-CRUD family rather than a separate root cause

**Branch B: Budget Exhaustion** (not-executed ICMs)
- Tests time out because a preceding test consumes the 9-min job budget. That preceding test is often an Availability test, but it can also be the same monitored test in the prior or adjacent run.
- Focus on `tip-job-timeline.kql` — which test consumed the budget?
- Check if the budget-consuming test is itself slow (Branch A root causes) or stuck
- Check for infrastructure issues preventing job scheduling entirely (no test logs at all = Geneva Synthetics problem)

Known pattern: **SegmentationManager CRUD budget exhaustion caused by MoboBroker-heavy orchestration**
- Signature:
   - `SegmentationManagerBasicCrudOperations` is the budget-consuming test,
   - successful runs take roughly `470s-550s`, or later retries time out inside the same test,
   - backend logs show repeated `CreatingMoboBroker` and `MrgSetupCompleted` spans plus slow `DeletingMoboBroker`,
   - DCR / Log Analytics handling is also slow, but MoboBroker delete is usually the single largest stage,
   - downstream tests such as `CleanupOldResources` may not start at all because the budget is already exhausted.
- Current examples:
   - `763911630`, `763949577`, `764044256`, `764102674` in `ztsppe` and `763951395`, `764134542` in `ztsdev` opened as execution monitor ICMs after the same slow SegmentationManager CRUD path.
   - `764005441` in `ztsppe` and `764085736` in `ztsdev` were downstream `CleanupOldResources` execution monitor ICMs caused by the preceding slow `SegmentationManagerBasicCrudOperations` run.
- Investigation additions for this subtype:
   1. Identify the last successful or nearly successful `SegmentationManagerBasicCrudOperations` run before the monitor gap.
   2. Capture the TIP phase markers and total duration for that run.
   3. Query RP logs by the segmentation manager resource name and measure `CreatingMoboBroker`, `MrgSetupCompleted`, `CreatingDcr`, `LogAnalyticsHandlingCompleted`, `DeletingMoboBroker`, and `MoboBrokerDeleted`.
   4. Distinguish this from a cleanup-local failure by checking whether the downstream test ever started and whether it made immediate forward progress once it did start.
   5. Parent the ICM under the active MoboBroker incident when MoboBroker setup or deletion dominates the slow path.

**Branch C: Test Failure** (test execution failed ICMs)
1. Run `tip-test-errors.kql` — extract `x-ms-client-request-id` from exceptions
2. Cross-reference with RPaaS (`https://rpsaas.kusto.windows.net` / `RPaaSProd`): run both `rpaas-incoming-requests.kql` and `rpaas-outgoing-requests.kql` using the extracted client request ID
3. Run `tip-test-output.kql` for detailed test traces
4. If the failing test is `GetGraphAndSetLabelsAvailabilityTest` with `Assert.NotEmpty` + HTTP 200, follow the **Pipeline Data Gap** section below

## GetGraphAndSetLabelsAvailabilityTest: Pipeline Data Gap

When `GetGraphAndSetLabelsAvailabilityTest` fails with `Assert.NotEmpty` after receiving HTTP 200, the issue is a pipeline data gap — the graph is empty because no pipeline child run produced output for the requested time window.

### How It Happens

1. The test calculates graph window as `[truncated_hour - 3h, truncated_hour - 2h]`
2. CCG API queries Synapse for child runs with completed output tables in that window
3. If a child run failed (e.g. Synapse 40613 killed it) or was never created, no output tables exist → empty graph
4. A child run failure causes tests to fail until the window shifts past the gap

### Additional Investigation Steps

After completing the general TIP test investigation steps above:

1. Get the correlationId from test output, trace RP logs — confirm CCG API returned `useful_child_runs= []`
2. Find the parent pipeline run ID from CCG logs (`Tenant == "zts-stage"` for stage, `Tenant` varies by env)
3. Run `pipeline-child-run-gap.kql` to compare the parent's expected hourly windows, launched child runs, and latest ended child before/after the gap
4. Determine whether the missing hour maps to:
   - a child run that exists but never reached a terminal success state, or
   - no child run at all (the hour was skipped)
5. If the child run exists, find the runner pod (`ccg-generator-deployment-*`) and get its error logs for that child run
6. When the child run exists but has no terminal success state, explicitly search the child-run logs for startup interruption signals before concluding the run never started. Look for:
   - `Received SIGTERM, shutting down...`
   - `report_run_has_begun`
   - `report_run_ends`
   - `Retry attempt`
   - pod startup-only markers such as `started pipeline_runner.py` and configuration or DB initialization with no later pipeline progress
7. If the child run does not exist or the parent was picked up late, run `pipeline-worker-occupancy.kql` around the parent's due time to answer two questions:
   - were generator pods still busy in postprocess from other runs, and
   - when a pod became free, did it pick older overdue parents first

### Known Root Causes for Data Gaps

**Synapse `metadb` error 40613:** `Database 'metadb' on server '{server}' is not currently available (40613)` during `reportProgress` kills the child run. The `recurring_runner` has no retry, so data for that hour is permanently lost. ADO #36903562 tracks this.

| Context | Impact | ICM Examples |
|---|---|---|
| CCG API at request time | HTTP 500 on getGraph/setLabels | 758265216, 758382900, 759277215 |
| Pipeline runner during execution | Child run crash, data gap, empty graph | 758302307 |

**Missed child run / no backfill:** `recurring_pipeline_runner.py` computes one child window from `now - PeriodicLagSeconds` on each wake and calls `recordNewChildRun` once. There is no catch-up loop for overdue hours, so a delayed wake can skip an entire hourly window. `metadata_client_synapse.py:getNextRunInstance()` selects the globally oldest overdue root run (`ORDER BY NextRunTime ASC`), so a freed worker may drain unrelated overdue parents first.

Signature: `get_graph: useful_child_runs= []`, `recurring_runner` later launches `...cYYYYMMDD02` with no `...cYYYYMMDD01` child ever logged.

Example: ICM 763571499 (`ztsppe`) skipped the `01:00` hour — parent launched `...c2026031700` at `01:27Z`, then `...c2026031702` at `03:00Z`, with no `01` child.

**Child launched, then shut down during startup:** the expected child run is inserted and launched, but the generator pod is terminated before the run reports that it has begun or produces output. This usually appears as startup-only logs followed by `Received SIGTERM, shutting down...`, sometimes with a retry around `report_run_has_begun`, and then no `report_run_ends` or successful child output for that hour.

Signature:
- `record_new_run` or equivalent metadata insert exists for the expected child window,
- `Launching new child run ...cYYYYMMDDHH...` exists exactly once,
- child logs show startup markers such as `started pipeline_runner.py`, config load, or DB init,
- the same child then logs `Received SIGTERM, shutting down...` before meaningful pipeline progress,
- the API later reports `useful_child_runs = []` for that hour,
- later hourly children may succeed, so the incident resolves without intervention once the test window moves forward.

Example: ICM 764518011 (`ztsdev`) created and launched child `vwekgx6jf6vuughvvvfdejc2026031815c2026031815`, then logged `Received SIGTERM, shutting down...` while retrying `report_run_has_begun`, and never produced a usable ended child for the `15:00-16:00` window.

Resolution guidance:
- If the evidence shows a one-time shutdown during child startup, no repeated failure for the same hour, later child runs succeed, and the incident clears when the graph window advances, recommend resolving the ICM as `Transient`.
- Do not use this resolution when shutdowns repeat, span multiple hours, or point to a persistent deployment or worker-stability issue.

**Worker saturation + oldest-due queueing:** Both generator pods are occupied by long-running postprocess work. Generator pods show `Pipeline run completed successfully` followed by long postprocess spans that extend past the due time. First free pod then picks globally oldest overdue roots, not the affected parent.

Example: ICM 763571499 (`ztsppe`) had parent due at `02:26:12Z`. One generator pod busy in postprocess until `02:56:00Z`; the other processing until `02:58:29Z`. First free pod drained older overdue roots, didn't launch the child until `03:00:29Z`.

### Pipeline Code

- PPE / Private Preview: `infrastructure/auto_pipeline_service/` (`recurring_pipeline_runner.py`, `pipeline_runner.py`, `metadata_client_synapse.py`)
- Public Preview: `src/python/`

## KQL Queries Used

| Query | Purpose |
|---|---|
| `tip-test-results.kql` | Identify PASSED/FAILED/SKIPPED/TIMEOUT |
| `tip-job-timeline.kql` | Full job lifecycle, timeout budget issues |
| `tip-test-frequency.kql` | Hourly test execution counts |
| `tip-test-errors.kql` | Extract x-ms-client-request-id from exceptions |
| `tip-test-output.kql` | Detailed test method output |
| `rpaas-incoming-requests.kql` | RPaaS incoming requests by client request ID |
| `rpaas-outgoing-requests.kql` | RPaaS outgoing requests by client request ID |
| `pipeline-child-run-gap.kql` | Compare parent's expected hourly windows vs actual child runs |
| `pipeline-worker-occupancy.kql` | Generator pod availability, postprocess occupancy, queue pickup timing |

## EUAP Region Considerations

EUAP regions (`eastus2euap`, `centraluseuap`) experience more frequent transient infrastructure failures that can cause TIP test failures.

**Do not assume transience without evidence.** Always run the full investigation steps above. TIP test failures in EUAP can reveal real ZTS bugs or missing resilience. ZTS code should be resilient to transient infrastructure failures where possible — if it isn't, that's a finding worth reporting.

To confirm transience: check if the test failures are isolated to the EUAP region, resolved without intervention, and have no ongoing impact. If failures persist, spread to other regions, or reveal missing retry/resilience logic, treat as actionable.
