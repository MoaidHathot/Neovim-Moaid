# Skill Maintenance Playbook

Applies after any investigation that uncovered a new recurring signature, refined an existing root cause, or showed that the current playbooks branch too broadly.

## Purpose

Use the current chat session as the primary source of truth for what was actually learned during the investigation, then decide whether the skill should be updated.

This playbook exists to prevent useful findings from staying trapped in a single session.

## Inputs To Review

Before updating the skill, review the session so far and extract:

1. The final incident classification that best matched the evidence
2. The concrete root cause, with log evidence and timestamps
3. The specific queries that produced the decisive evidence
4. Any decision points where the existing playbooks were too vague, misleading, or missing a branch
5. Whether the current investigation fits an existing playbook or represents a new subtype that should be called out explicitly

## Decision Tree

### Case 1: Existing playbook was correct, but incomplete

Update the existing playbook when:

- the title pattern already routes to the right playbook,
- the current playbook missed an important branch or known pattern,
- the investigation used the same general workflow but needed sharper guidance.

Typical updates:

- add a `Known Patterns` entry,
- add a branch under `Investigation Steps`,
- add a table of distinguishing signals,
- add the most useful KQL templates for that subtype.

### Case 2: Existing playbook was too broad

Create a new standalone playbook when:

- the incident has a stable, repeatable signature,
- the investigation flow differs materially from the parent playbook,
- the subtype is important enough that future triage should load a dedicated document instead of relying on a broad catch-all section.

If a new playbook is created, also update `SKILL.md` so the structure list and pattern-routing guidance reference it.

### Case 3: No skill update needed

Do not change the skill when:

- the issue was one-off noise,
- the evidence did not establish a repeatable pattern,
- the current playbooks already led directly to the right answer without ambiguity.

## Required Updates When You Change The Skill

If you update or add playbooks, make all relevant follow-up changes in the same pass:

1. Update `SKILL.md` structure list if a new reference file was added
2. Update `SKILL.md` classification or workflow guidance if routing should change
3. Update the affected playbook with the new branch, pattern, or checklist
4. Keep the new guidance grounded in observed evidence from the current session, not speculation

## Current Session Template

Use this compact checklist while reviewing the current investigation:

- Pattern investigated:
- Existing playbook used:
- What that playbook got right:
- What it missed:
- New recurring signal, if any:
- Queries that proved it:
- Files to update:
- New playbook needed: yes or no

## Example: TIP Duration With MoboBroker Latency

If a TIP duration incident shows the test itself passed but budget was consumed by backend orchestration work, and the decisive evidence is repeated MoboBroker setup or deletion latency, then:

1. Start from `playbook-tip-test.md`
2. Add or refine a `Slow Execution` subtype for backend orchestration latency
3. Call out the distinguishing evidence:
   - test passes,
   - job still times out or nearly times out,
   - MoboBroker setup or deletion dominates patch or delete phases,
   - no separate RP functional failure is required
4. If this becomes common enough, split it into a dedicated TIP duration sub-playbook and update `SKILL.md` routing notes

## Output Goal

By the end of this playbook, one of these should be true:

- an existing playbook was improved,
- a new playbook was added and wired into `SKILL.md`, or
- the session showed no durable learning and the skill was intentionally left unchanged.
