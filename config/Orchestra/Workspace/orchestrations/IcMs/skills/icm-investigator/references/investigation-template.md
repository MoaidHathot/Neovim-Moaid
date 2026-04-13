# ICM Investigation Report Template

Use this template to format the investigation summary presented in the chat.

---

# ICM {IncidentId}: {Title}

**Date:** {investigation_date}
**Investigator:** (OCE agent-assisted)
**ICM Link:** https://portal.microsofticm.com/imp/v3/incidents/incident/{IncidentId}/summary
**Status:** {Status} | **Severity:** {Severity}
**Cluster/Environment:** {affected_cluster}
**Time Window:** {start_time} – {end_time}

## Incident Summary

{Brief description from ICM. Include monitor metadata if available: DataStartTime, DataEndTime, HttpPath, HttpStatusCode.}

## Key Findings

### Error Scale

| Metric | Value |
|--------|-------|
| Total errors | {count} |
| Success rate | {rate}% |
| Affected time window | {duration} |
| Top exception type | {type} ({count}) |

{Error distribution table by type, count, and sample correlationId.}

### Root Cause

{Detailed root cause analysis. Must be grounded in log evidence, not speculation.}

**Summary:** {One-sentence root cause.}

### Timeline

{Representative request timeline showing the failure sequence. Include timestamps, events, and durations.}

| Time | Event | Detail |
|------|-------|--------|
| {timestamp} | {event} | {detail} |

### Duration Distribution

{If relevant: how request durations cluster. Useful for timeout-related issues.}

## Code Path

{Trace from entry point to failure, with file:line references.}

```
Controller (entry point)
  → ServiceClass.MethodAsync
    → DependencyClient.CallAsync
      → Exception thrown at [file.cs#L42]
```

## Evidence

{Key log excerpts, formatted as tables or code blocks. Include correlationIds for reproducibility.}

## Existing ADO Work Items

| ID | Title | State | Assigned To |
|----|-------|-------|-------------|
| {id} | {title} | {state} | {assignee} |

{Or "No matching ADO work items found under `One\Networking\Network Security\ZTS\Backend`."}

## Proposed Fix

{If root cause is clear, propose a fix with code snippets. Reference specific files and lines.}

```csharp
// Proposed change in [path/to/file.cs]
```

## Recommendations

{Prioritized next steps for the OCE:}
1. {Action item}
2. {Action item}

## Appendix: Queries Used

{All KQL queries executed during this investigation, with cluster/database info, for reproducibility.}

### Query 1: Error Summary
```kql
// Cluster: {cluster}
// Database: Log
{query}
```

### Query 2: Request Timeline
```kql
// Cluster: {cluster}
// Database: Log
{query}
```
