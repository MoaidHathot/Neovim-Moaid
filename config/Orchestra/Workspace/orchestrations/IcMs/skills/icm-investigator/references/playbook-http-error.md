# HTTP Error Investigation Playbook

Applies to ICMs matching: `HTTP Request [METHOD] returns status code [5xx]`

## Key Concept

`request-errors.kql` distinguishes RP vs CCG errors via `service_name` column. CCG errors (Python/pyodbc/SQLAlchemy) are upstream root cause; RP errors (DataPipelineException/GetGraphFailed) are downstream.

## Investigation Steps

1. Run `http-errors.kql` (primary — finds correlationIds, deduplicates errors, aggregates patterns)
2. Run `error-summary.kql` (supplement — broader error view)
3. Pick top 3–5 error patterns. For each `SampleCorrelationId`, run `request-errors.kql` (errors with RP/CCG service_name column) then `request-timeline.kql` if needed
4. For request-time CCG/Synapse failures, extract the observed retry behavior before deciding whether the issue is actionable or transient:
	- RP retries: look for `service_name == "resourceprovider"` and `env_name == "ExecutionAttempt"`, then extract `Attempt: 'N'` from the body
	- CCG retries: look for `service_name == "ccg-api"` and `body has "Retry attempt "`
	- Measure the span from the first retry-related log to the final failing `RequestResponseLog` entry for the same correlationId
5. Optional: `duration-distribution.kql`, `error-timeline.kql`
6. If correlationId already known: start with `request-errors.kql`, then `http-errors.kql` for broader pattern

## KQL Queries Used

| Query | Purpose |
|---|---|
| `http-errors.kql` | Find correlationIds, deduplicate errors, aggregate patterns |
| `error-summary.kql` | Broader error view across all types |
| `request-errors.kql` | Errors with RP/CCG Service column distinction |
| `request-timeline.kql` | Full request trace by correlationId |
| `duration-distribution.kql` | Request duration distribution |
| `error-timeline.kql` | Error count over time |

## RPaaS Cross-Reference

For HTTP 400: match `clientRequestId` in RPaaS logs.
For HTTP 504: match `correlationId` (from `x-ms-correlation-request-id`) in RPaaS logs.

Use `rpaas-incoming-requests.kql` and `rpaas-outgoing-requests.kql` against `https://rpsaas.kusto.windows.net` / `RPaaSProd`, filtering by `providerNamespace =~ "MICROSOFT.ZEROTRUSTSEGMENTATION"`.

## Known Root Cause: Synapse Error 40613

Recurring transient issue: `Database 'metadb' on server '{server}' is not currently available (40613)`.

When it hits CCG API at request time, it causes HTTP 500 on getGraph/setLabels endpoints (ICM examples: 758265216, 758382900, 759277215).

When it hits the pipeline runner during execution, it causes child run crashes and data gaps — see the pipeline data gap section in `playbook-tip-test.md`.

## Known Root Cause: Request-Time CCG/Synapse Transient Failures

Recurring request-time pattern on `getGraph`:

- RP surfaces `DataPipelineException` / `GetGraphFailed`
- CCG logs the real dependency failure
- the underlying dependency error is a transient Synapse or SQL connectivity issue, not an RP controller bug

Observed request-time signatures from this session:

- Synapse `40613` on `metadb`
- Synapse `40613` on `graphdb`
- SQL connectivity `08S01`
- wrapped `HY000` where the transient SQL Server code appears later in the message text

### How To Interpret Retries

- RP retry logs show retries of the HTTP call to CCG; they do not mean one request was retried for the full IcM duration
- CCG retry logs show retries of the inner Synapse operation; missing CCG retry logs can still be consistent with a transient dependency failure if the exception shape was not classified as transient at the time
- In the incidents investigated in this session, RP exhausted 4 total attempts over seconds to tens of seconds per request, while the IcMs stayed open for much longer because fresh probes kept failing during the same backend outage window

### Resolution Guidance For External Dependency Outages

If all of the following are true, the issue can be classified as transient external dependency impact rather than an RP/CCG functional bug:

1. RP exhausted its configured retry budget against CCG
2. CCG either exhausted its transient DB retry budget or the latest deployed version already contains a targeted classifier fix for the missing wrapped transient shape
3. The final root cause in logs is still Synapse `40613`, SQL connectivity `08S01`, or another clearly external transient dependency error
4. Repeated probe requests fail over the incident window, showing backend unavailability persisted longer than a single request retry budget

Do not call the issue transient if the logs instead show:

- a stable RP or CCG logic bug after dependency recovery,
- no retries where the code path should have retried and no fix exists,
- or a new dependency error shape that current retry classification still misses.

## EUAP Region Considerations

EUAP regions (`eastus2euap`, `centraluseuap`) are canary regions with more frequent transient infrastructure failures. When investigating HTTP errors from EUAP:

**Do not assume transience without evidence.** Always run the full investigation steps above. EUAP ICMs can reveal real ZTS bugs. ZTS code should be resilient to transient infrastructure failures where possible — if it isn't, that's a finding worth reporting.

Known EUAP-specific error signatures:
- `Resource temporarily unavailable` for `eastus2euap.login.microsoft.com`, `.management.azure.com`, `graph.microsoft.com`
- `MiseCancelledException` (MISE12013)
- `ResourceCreationValidateFailed` (400): may mask 503 from ZTS RP. Cross-ref RPaaS — MetaRP translates 503 to 400.
- `GatewayTimeout` (504): RPaaS shows `httpStatusCode=0`. Use `x-ms-correlation-request-id` (not `clientRequestId`). Check ZTS RP for CCG API / Synapse 40613 causing timeouts.

To confirm transience: check if the error pattern is isolated to the EUAP region, resolved without intervention, and has no ongoing impact. If errors persist, spread to other regions, or reveal missing resilience, treat as actionable.
