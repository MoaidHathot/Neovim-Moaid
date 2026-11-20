"""Summarize saved reports. No inference, network access or writes to the bookmark store."""

import argparse
import json
import statistics
from pathlib import Path


def chat_usage(path):
    # With content capture off, SDK 1.0.34 emits metrics even when it emits no chat spans.
    # Retain the last cumulative histogram per series (including process start), not every export.
    series = {}
    if path.exists():
        for line in path.read_text(encoding='utf-8-sig').splitlines():
            record = json.loads(line)
            name = record.get('name')
            if record.get('type') != 'metric' or name not in (
                'gen_ai.client.inference.duration', 'gen_ai.client.inference.operation.input_tokens',
                'gen_ai.client.inference.operation.output_tokens',
            ):
                continue
            for point in record['dataPoints']:
                attrs = point['attributes']
                if attrs.get('gen_ai.operation.name') == 'chat':
                    key = (name, tuple(point['startTime']), json.dumps(attrs, sort_keys=True))
                    series[key] = point['value']

    def total(name, field):
        values = [v[field] for k, v in series.items() if k[0] == name]
        return sum(values) if values else None

    return (total('gen_ai.client.inference.duration', 'count'),
            total('gen_ai.client.inference.operation.input_tokens', 'sum'),
            total('gen_ai.client.inference.operation.output_tokens', 'sum'))


def summarize(out):
    rows = json.loads((out / 'observations.json').read_bytes())
    for r in rows:
        if r['arm'] == 'prompt':
            r['calls'], r['inputTokens'], r['outputTokens'] = chat_usage(out / r['case'] / 'prompt' / 'telemetry.jsonl')
        elif r['decisionStatus'] == 'Skipped':
            r['calls'], r['inputTokens'], r['outputTokens'] = 0, 0, 0
        elif r['decisionStatus'] == 'Succeeded':
            usage = r['stepUsage'] or {}
            r['calls'], r['inputTokens'], r['outputTokens'] = 1, usage.get('inputTokens'), usage.get('outputTokens')
        else:
            r['calls'], r['inputTokens'], r['outputTokens'] = None, None, None

    def total(group, key):
        return sum(r[key] for r in group) if all(r[key] is not None for r in group) else 'unknown'

    print('| Cohort | Method | Passed / total | Calls | Median classifier (s) | Median CLI wall (s) | Input tokens | Output tokens |')
    print('|---|---|---:|---:|---:|---:|---:|---:|')
    for cohort in ('archive', 'constructed', 'all'):
        for arm in ('prompt', 'candidate'):
            g = [r for r in rows if r['arm'] == arm and (cohort == 'all' or r['cohort'] == cohort)]
            if not g:
                continue
            print(f'| {cohort} | {arm} | {sum(r["passed"] for r in g)}/{len(g)} | {total(g,"calls")} | '
                  f'{statistics.median(r["classifySeconds"] for r in g):.2f} | {statistics.median(r["cliWallSeconds"] for r in g):.2f} | '
                  f'{total(g,"inputTokens")} | {total(g,"outputTokens")} |')
    for r in rows:
        if not r['passed']:
            print(f'{r["case"]}/{r["arm"]}: expected {r["expected"]}, observed {r["observed"]}; '
                  f'contract={r["strictContract"]}, status={r["status"]}, selected probability={r["selectedProbability"]}')
    return rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--per-case', action='store_true', help='also print anonymized paired routes and timings')
    opts = parser.parse_args()
    rows = summarize(opts.evidence)
    if opts.per_case:
        def display(row):
            if row is None:
                return '-'
            route = '/'.join(str(v) for v in row['observed'][:2]) if row['observed'] else 'invalid output'
            return f'{route} ({row["classifySeconds"]:.2f} s)'

        print('\n| Case | Expected | Prompt | Candidate | Decision called? |')
        print('|---|---|---|---|---|')
        for case in dict.fromkeys(r['case'] for r in rows):
            pair = {r['arm']: r for r in rows if r['case'] == case}
            p, c = pair.get('prompt'), pair.get('candidate')
            expected = (c or p)['expected']
            print(f'| {case} | {"/".join(expected[:2])} | {display(p)} | {display(c)} | {c["decisionStatus"] if c else "-"} |')
