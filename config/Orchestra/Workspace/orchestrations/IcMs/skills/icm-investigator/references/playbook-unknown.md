# Unknown / Unclassified ICM Pattern Playbook

Applies to ICMs that do not match any known title pattern in the ICM Type Classification table.

## Purpose

Provide a systematic investigation approach for new or unrecognized ICM patterns by leveraging broad diagnostic queries first, then narrowing toward the closest known playbook.

## Investigation Steps

### Phase 1: Broad Diagnostics

Run these queries against the target ZTS Kusto cluster to understand the error landscape:

1. Run `error-summary.kql` — aggregate errors by type in the ICM time window. This is the single most useful starting query for any unknown pattern.
2. Run `http-errors.kql` — check for HTTP error patterns even if the ICM title doesn't mention HTTP status codes.
3. Check TIP test logs: `Log | where Tenant == "SyntheticsProd"` in the time window — look for FAILED/TIMEOUT/SKIPPED tests.
4. Run `health-probe.kql` — check if health probes were degraded during the incident.

### Phase 2: Pattern Matching

Based on the Phase 1 results, determine which known playbook is the closest match:

| If you find... | Likely pattern | Load playbook |
|---|---|---|
| HTTP 5xx errors with correlationIds in `env_properties` | HTTP Error | `playbook-http-error.md` |
| Health probe non-200 status codes (499, 503) | Health Probe | `playbook-health-probe.md` |
| TIP test FAILED/TIMEOUT/SKIPPED entries or `useful_child_runs= []` | TIP Test | `playbook-tip-test.md` |
| **None of the above** | Truly new pattern | Continue to Phase 3 |

If a match is found, load that playbook and continue the investigation from its steps.

### Phase 3: First-Principles Investigation

If no existing playbook matches:

1. **Examine error details:** For each distinct error type from `error-summary.kql`, pick a sample correlationId and run `request-timeline.kql` to trace the full request lifecycle.
2. **Check dependencies:** Run `rpaas-incoming-requests.kql` / `rpaas-outgoing-requests.kql` to see if RPaaS routing or upstream services are involved.
3. **Check pod health:** Look for pod restarts, OOM kills, or deployment rollouts in the time window using log queries filtered by `pod_name`.
4. **Trace the code path:** Search `src/` for exception types and source classes found in the logs. Identify the entry point and failure location.
5. **Ask the user:** Present what you found, describe the error patterns, and ask for additional context or guidance.

### Phase 4: Document the New Pattern

After completing the investigation, recommend updating the skill:

1. Propose a title pattern regex for the new ICM type
2. Suggest which KQL queries were most useful (candidates for a new dedicated query template)
3. Suggest creating a new playbook file if this pattern is likely to recur
4. Update `cluster-mapping.md` if a new signal-to-cluster mapping was discovered
5. Load `playbook-skill-maintenance.md` and apply its checklist so the current session findings are folded back into the skill consistently

## Follow-Up Maintenance

If the investigation revealed a clearer subtype of an existing pattern rather than a fully new pattern, do not stop at Phase 4. Load `playbook-skill-maintenance.md` and decide whether the result belongs as:

- a new known-pattern section in an existing playbook,
- a new standalone playbook, or
- a clarification in `SKILL.md` classification or workflow guidance.

This is especially important for incidents that initially looked generic but turned out to have a strong recurring backend cause.
