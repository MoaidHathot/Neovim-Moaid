# Health Probe Investigation Playbook

Applies to ICMs matching: `Http Health Probe is unhealthy`

## Key Differences from HTTP Error

Health probe ICMs fire when `GET /health` returns non-200 (typically 499 = NGINX client disconnect). These have **no application errors**; the root cause is infrastructure-level.

- `http-errors.kql` won't match (filters on `env_properties has "subscriptions"`)
- `request-errors.kql` won't find errors (health probes don't fail at the app level)
- CorrelationId tracing is not useful (health probes don't call dependencies)
- Focus on: concurrent load analysis, pod events, deployment timing, resource usage

## Known Patterns

- **499 from resource contention (ICM 758542654):** Heavy TIP test API calls (getGraph: 9s, setLabels: 16s) on the same pod cause CPU/thread contention, slowing health probe responses past the LB timeout (~1s). Auto-mitigates when the heavy workload completes.
- **503 from pod restart:** Readiness probe fails during restart. Check deployment rollout timing.

## Investigation Steps

1. Run `health-probe.kql` — status code distribution and duration percentiles per 5-min bucket
2. Run `health-probe-concurrent-load.kql` — find heavy concurrent API requests causing contention
3. Check for pod restarts / deployment rollouts in the time window
4. Classify root cause:
   - **499 (client disconnect):** Probe timeout from resource contention. Look for concurrent long-running requests (getGraph, setLabels, pipeline operations)
   - **503 (service unavailable):** Pod restart or readiness probe failure
   - **Persistent unhealthy:** Memory leaks, GC pauses, thread pool starvation
5. If heavy concurrent TIP test requests are the cause, this is a known pattern (ICM 758542654): resource contention from getGraph/setLabels during TIP test runs

## KQL Queries Used

| Query | Purpose |
|---|---|
| `health-probe.kql` | Status code distribution and duration percentiles per 5-min bucket |
| `health-probe-concurrent-load.kql` | Find heavy concurrent API requests causing contention |

## EUAP Region Considerations

EUAP regions (`eastus2euap`, `centraluseuap`) experience more frequent transient infrastructure failures that can trigger health probe ICMs.

**Do not assume transience without evidence.** Always run the full investigation steps above. Health probe failures in EUAP can reveal real resource contention or resilience issues. ZTS code should handle transient infrastructure instability gracefully — if health probes fail due to lack of resilience, that's actionable.

To confirm transience: check if the probe failures are isolated to the EUAP region, resolved without intervention, and have no ongoing impact.
