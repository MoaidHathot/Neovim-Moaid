# Raindrop classifier pilot — 2026-11-18

**Recommendation: promote the candidate classifier.** Both arms returned all four required fields and matched all 16 reference routes. On the eight saved bookmarks alone, classification went from a median of **20.51 s to 2.11 s (9.7×)**, including the two PowerShell steps. The candidate was faster in every pair. These are classification timings, not timings for processing a whole bookmark.

| Inputs | Correct: Prompt / candidate | Requests: Prompt / candidate | Median classification: Prompt / candidate | Median isolated CLI wall: Prompt / candidate |
|---|---|---|---|---|
| 8 archived bookmarks | 8/8 / 8/8 | 16 / 8 | 20.51 s / 2.11 s | 21.66 s / 3.20 s |
| 8 constructed controls | 8/8 / 8/8 | 16 / 4 | 23.27 s / 1.43 s | 24.46 s / 2.41 s |
| All 16 | 16/16 / 16/16 | 32 / 12 | 21.38 s / 2.08 s | 22.54 s / 3.15 s |

- **Measured models:** `gpt-6-astra` (current Prompt; configured Max reasoning) against `microsoft-decision-1` (observed upstream `microsoft-decision-1.1` on all 12 calls). The Prompt invoked the `skill` tool 16 times in total. The candidate made one decision call per unresolved intent; median SDK latency was 1,354 ms. Four tag/URL overrides bypassed inference (median classification 0.69 s).
- **Tokens:** 492,368 input / 6,427 output across the Prompt arm; 2,683 input / 12 output across the candidate arm. Prompt totals count all inference turns, including cached inputs. No monetary saving was inferred from token counts.
- **Edge cases:** all six `(medium, intent)` pairs were covered. An article tagged `talk` retained `intent=session` and selected `raindrop-article-generic-processor`. Explicit `food` overrode a known session URL. A recipe described only in the note, an untagged keynote and a vague generic bookmark also matched.
- **Uncertainty:** archive-08, an article about a live series, selected the expected `generic` with probability **0.610**. The next-lowest winning probability was **0.917**. One pass on 16 rubric-labeled cases does not establish a confidence cutoff. Recent archived data was mostly generic, with no prior session classifications; the session controls are constructed, not historical.
- **Operational check:** the offline rule audit projected 112/112 unique historical bookmarks would still need inference. The realistic benefit here is the faster inference path, not frequent tag bypasses. Both generated pilot definitions passed `validate --schema`; a temporary full workflow with the proposed substitution also passed schema validation and a 10-step dry-run. No live processor, dispatch, Raindrop move or Zakira write ran in the comparison. The production YAML was not edited.

## Reproducibility

The paired run used the local Orchestra 0.13.0 assembly with GitHub.Copilot.SDK 1.0.34 and CLI 1.0.112. Input labels are in `cases.jsonl`. The classifier step was extracted from `raindrop-processor.yaml` (SHA-256 `2ae854154001504c0ff94006f29bddc9e8643d69433016d10d61e71cc01ea938`); the router skill SHA-256 was `0ff51696dab66a7a019a275401434e8d2db6f41b7a6c8b0d665f6870ed0e9ade`. The local raw evidence directory is `%LOCALAPPDATA%/Temp/opencode/raindrop-paired-20261118`; `analyze.py --per-case` reads it without making further calls. See [replay instructions](README.md#reproduce).

**Rollout (2026-11-19):** the measured classifier is now in `raindrop-processor.yaml` version 1.4.0. Its two scripts live under `tools/scripts/`. The dispatcher still consumes `classify.output`, and `verify-dispatch` still precedes `move-to-processed`. Use `--arm candidate` to replay the shipped definition.

An isolated replay extracted from 1.4.0 passed **16/16** cases (12 calls to upstream `microsoft-decision-1.1`, 4 rule-only routes). Median classification time was **2.04 s** on the eight archived bookmarks. The full workflow passed schema validation and a 10-step dry-run. Boundary checks confirmed that a failed child blocks both the move and completion, and that conflicting intent tags block dispatch. Raw replay evidence: `%LOCALAPPDATA%/Temp/opencode/raindrop-promoted-20261119-001034`.
