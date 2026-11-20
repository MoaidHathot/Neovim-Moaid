# Raindrop classification replay

This compares the 1.3.1 `classify` Prompt (arm `prompt`) to the shipped rules-plus-Decision classifier (arm `candidate`), one bookmark at a time. Both must produce exactly `{medium, intent, processor, reasoning}` and match the preassigned `(medium, intent, processor)` tuple. The runner also checks that the Decision step actually skipped inference on a hard override.

[Measured results, 2026-11-18](RESULTS.md)

**Isolation.** `replay.py` extracts `route-rules`, `infer-intent` and `classify` from `raindrop-processor.yaml` and copies the two shipped scripts at their production-relative paths. For the comparison arm it loads `prompt-v1.3.1.step` and the original router skill. Both arms use a `Transform` returning the real `mark-processing` result (`{ "ok": true }`). Each run uses `orchestra exec --no-config`, an empty scan directory and a fresh data directory outside the scanned workspace. Neither definition contains a dispatch, hook, state write or collection move.

**Candidate.** `route-rules.ps1` decides medium from the URL, then honors recognized intent tags before known Microsoft session URLs. For the other bookmarks, `infer-intent` sends the host/path, title, note and tags to `microsoft-decision-1` as JSON and accepts a `recipe`, `session` or `generic` choice. `route-result.ps1` constructs the old four-field object; an article/session keeps `intent=session` while selecting the generic article processor. Conflicting explicit tag families or a missing, refused or tied answer are errors: the pilot never invents a successful route. No new probability threshold is calibrated on this sample.

**Cases.** `cases.jsonl` fixes the labels and expected call/skip path before the live comparison. Eight cases use actual saved bookmark metadata, matched by SHA-256 of the five classifier inputs; only fingerprints and reference routes are stored here. Eight constructed cases cover the missing tag/URL overrides, a written session, vague metadata and a recipe identified by its note. These are rubric-based reference labels, not operator-verified ground truth. Only inputs, never labels, go to the classifiers.

**Archive coverage (2026-11-18).** The offline audit read 238 saved processor runs (July 12–October 30), taking the most recent inputs for each of 112 distinct bookmark IDs. All 112 would call `infer-intent`; zero matched a hard intent override. The latest stored classification for each item was generic in 109 cases and recipe in 3; none was session. This is why the live sample includes separate constructed controls and why their call savings should not be extrapolated to the historical workload.

## Reproduce

Requires a local Orchestra CLI build with `Decision` support, Copilot sign-in, `pwsh`, Python 3 and PyYAML. From this directory on Windows:

```powershell
pwsh -NoProfile -File ./test-rules.ps1
$history = Join-Path $env:LOCALAPPDATA 'OrchestraHost/executions/raindrop-processor'
pwsh -NoProfile -File ./audit-history.ps1 -HistoryDir $history

$cli = 'W:/Github/Orchestra/src/Orchestra.Cli/bin/Release/net10.0/Orchestra.Cli.dll'
python -B test-dispatch-boundary.py --cli-dll $cli
python -B replay.py --cli-dll $cli --history-dir $history
python -B analyze.py '<evidence directory printed by replay.py>' --per-case
```

Use `--arm candidate` to verify just the deployed classifier. Omit `--history-dir` to run only the portable constructed cases, or use `--cases <id> ...` for a subset. The default Prompt reasoning setting is `Max`, matching the host used for this pilot; override with `--reasoning` if the host changes. Each selected definition is schema-validated before replay. A route mismatch exits nonzero and preserves the evidence.

`test-dispatch-boundary.py` runs the shipped classifier and `verify-dispatch` with local stand-ins for the child, collection move and state writes. It checks a successful tagged article/session, a failed child that must block the move, and conflicting tags that must block dispatch itself.

`analyze.py` works offline. Classification time is step start to final output (including both PowerShell starts on the candidate); CLI wall time also includes host startup and teardown. Each bookmark is run once per arm, sequentially, with arm order alternated. Prompt request and token counts come from Copilot's cumulative chat-inference histograms; Decision counts come from the actual step status and SDK usage. Input token counts include cached tokens and are not a price quote. Raw reports in the temporary evidence directory contain the original bookmark metadata; the summary only uses case IDs and routes.
