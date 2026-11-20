"""Paired, classification-only Raindrop replay. Requires Python 3, PyYAML, pwsh and a built Orchestra CLI."""

import argparse
import hashlib
import json
import os
import shutil
import statistics
import subprocess
import tempfile
import time
from datetime import datetime
from pathlib import Path

import yaml


HERE = Path(__file__).resolve().parent
SUITE = HERE.parent.parent
FIELDS = ('url', 'title', 'note', 'tags', 'addedAt')
ROUTE = ('medium', 'intent', 'processor')


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')


def metadata(values):
    return {k: values.get(k) or ('[]' if k == 'tags' else '') for k in FIELDS}


def load_cases(history):
    cases = [json.loads(line) for line in (HERE / 'cases.jsonl').read_text(encoding='utf-8').splitlines() if line.strip()]
    if not history:
        return [c for c in cases if 'input' in c]
    wanted = {c['fingerprint']: c for c in cases if 'fingerprint' in c}
    for path in sorted(history.glob('*/run.json'), reverse=True):
        record = json.loads(path.read_bytes())
        data = metadata(record.get('parameters') or {})
        digest = hashlib.sha256(json.dumps(data, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
        if digest in wanted:
            wanted.pop(digest)['input'] = data
        if not wanted:
            break
    if wanted:
        raise ValueError('Missing exact archive inputs: ' + ', '.join(c['id'] for c in wanted.values()))
    return cases


def definitions(out, effort, arms):
    source = yaml.safe_load((SUITE / 'raindrop-processor.yaml').read_text(encoding='utf-8-sig'))
    by_name = {s['name']: s for s in source['steps']}
    # Match the actual dependency OUTPUT appended to the production user prompt, without the state write.
    stub = {'name': 'mark-processing', 'type': 'Transform', 'template': '{ "ok": true }'}
    for arm in arms:
        variables = {}
        if arm == 'prompt':
            steps = [yaml.safe_load((HERE / 'prompt-v1.3.1.step').read_text(encoding='utf-8'))]
            skills = out / 'skills'
            shutil.copytree(SUITE / 'skills' / 'raindrop-router', skills / 'raindrop-router')
            variables['routerSkillsDir'] = str(skills)
        else:
            steps = [by_name[k] for k in ('route-rules', 'infer-intent', 'classify')]
            if by_name['infer-intent']['type'] != 'Decision':
                raise ValueError('Expected the deployed infer-intent Decision step.')
            # Mirror the production relative paths. Never copy or execute dispatch or state-write scripts.
            for name, script in [('route-rules', 'route-rules.ps1'), ('classify', 'route-result.ps1')]:
                relative = Path('tools', 'scripts', script)
                if by_name[name]['type'] != 'Script' or Path(by_name[name]['scriptFile']) != relative:
                    raise ValueError(f'Unexpected script for {name}; review the replay before running it.')
                (out / relative).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(SUITE / relative, out / relative)
        write_json(out / f'{arm}.json', {
            'name': f'raindrop-classify-pilot-{arm}', 'description': 'Isolated one-bookmark classification replay.',
            'defaultProvider': 'copilot', 'defaultModel': source['defaultModel'], 'defaultReasoningLevel': effort,
            'inputs': {k: source['inputs'][k] for k in FIELDS}, 'variables': variables,
            'steps': [stub, *steps],
        })


def grade(raw, expected):
    try:
        obj = json.loads(raw)
    except (ValueError, TypeError):
        return None, False, False
    if not isinstance(obj, dict):
        return None, False, False
    route = [obj.get(k) for k in ROUTE]
    contract = set(obj) == {*ROUTE, 'reasoning'} and all(isinstance(v, str) and v.strip() for v in obj.values())
    return route, bool(contract), route == expected


def run_arm(cli, out, case, arm):
    path = out / case['id'] / arm
    path.mkdir(parents=True)
    report_file = path / 'report.json'
    telemetry = path / 'telemetry.jsonl'
    args = [*cli, 'exec', '--no-config', '--no-interactive', '--quiet', '--run-timeout', '210',
            '--orchestrations-path', str(out / 'empty-scan'), '--data-path', str(path / 'host'),
            '--run-file', str(out / f'{arm}.json'), '--report', 'json', '--report-output', str(report_file)]
    for name, value in metadata(case['input']).items():
        if value:
            args.extend(['--param', f'{name}={value}'])
    env = {**os.environ, 'COPILOT_OTEL_EXPORTER_TYPE': 'file', 'COPILOT_OTEL_FILE_EXPORTER_PATH': str(telemetry),
           'OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT': 'false'}
    started = time.monotonic()
    with (path / 'cli.log').open('wb') as log:
        run = subprocess.run(args, cwd=out, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=250)
    wall = round(time.monotonic() - started, 3)
    if not report_file.exists():
        raise RuntimeError(f'{case["id"]}/{arm}: no run report (exit {run.returncode}); see {path / "cli.log"}')
    report = json.loads(report_file.read_bytes())
    steps = {s['name']: s for s in report['steps']}
    last = steps['classify']
    first = steps['route-rules' if arm == 'candidate' else 'classify']
    seconds = (datetime.fromisoformat(last['completedAt']) - datetime.fromisoformat(first['startedAt'])).total_seconds()
    route, contract, matched = grade(last.get('content'), case['expected'])
    infer = steps.get('infer-intent', {})
    model_step = infer if arm == 'candidate' else last
    decision = json.loads(infer['content']) if infer.get('status') == 'Succeeded' else {}
    answer = decision.get('answers', {}).get('intent', {})
    call_path_ok = (infer.get('status') == ('Succeeded' if case['decision'] else 'Skipped')) if arm == 'candidate' else True
    passed = run.returncode == 0 and report['status'] == 'Succeeded' and contract and matched and call_path_ok
    return {
        'case': case['id'], 'cohort': 'archive' if 'fingerprint' in case else 'constructed', 'arm': arm,
        'expected': case['expected'], 'observed': route, 'strictContract': contract, 'passed': passed,
        'status': report['status'], 'selectedModel': model_step.get('selectedModel'), 'actualModel': model_step.get('actualModel'),
        'decisionStatus': infer.get('status'), 'decisionRpcMs': decision.get('latencyMs'),
        'selectedProbability': answer.get('probabilities', {}).get(answer.get('value')), 'tied': answer.get('tied'),
        'stepUsage': model_step.get('usage'), 'classifySeconds': round(seconds, 3), 'cliWallSeconds': wall,
        'runId': report['runId'],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli-dll', required=True, type=Path)
    parser.add_argument('--history-dir', type=Path, help='raindrop-processor executions folder; omit for constructed cases only')
    parser.add_argument('--reasoning', default='Max', help='match the configured Prompt reasoning default')
    parser.add_argument('--arm', choices=('both', 'candidate', 'prompt'), default='both',
                        help='candidate runs only the shipped classifier; prompt runs the 1.3.1 baseline')
    parser.add_argument('--cases', nargs='+', help='optional case IDs for a targeted replay')
    parser.add_argument('--out', type=Path, help='new private evidence directory outside the scanned workspace')
    opts = parser.parse_args()
    cli = ['dotnet', str(opts.cli_dll.resolve(strict=True))]
    cases = load_cases(opts.history_dir)
    if opts.cases:
        missing = set(opts.cases) - {c['id'] for c in cases}
        if missing:
            parser.error('unknown or unavailable case IDs: ' + ', '.join(sorted(missing)))
        cases = [c for c in cases if c['id'] in opts.cases]
    if opts.out:
        out = opts.out.resolve()
        if out.is_relative_to(SUITE.parents[2]):
            parser.error('--out must be outside the Orchestra Workspace')
        out.mkdir(parents=True, exist_ok=False)
    else:
        scratch = Path(tempfile.gettempdir()) / 'opencode'
        scratch.mkdir(exist_ok=True)
        out = Path(tempfile.mkdtemp(prefix='raindrop-classify-', dir=scratch))
    print(f'Evidence: {out}', flush=True)
    arms = ('prompt', 'candidate') if opts.arm == 'both' else (opts.arm,)
    definitions(out, opts.reasoning, arms)
    (out / 'empty-scan').mkdir()
    for arm in arms:
        subprocess.run([*cli, 'validate', str(out / f'{arm}.json'), '--schema'], check=True, cwd=out)
    rows = []
    for i, case in enumerate(cases):
        # Alternate order; each arm gets its own host and Copilot worker. No parallel latency measurements.
        for arm in (arms if i % 2 == 0 else reversed(arms)):
            row = run_arm(cli, out, case, arm)
            rows.append(row)
            write_json(out / 'observations.json', rows)
            print(f'{row["case"]} {arm}: {"PASS" if row["passed"] else "FAIL"} {row["observed"]} {row["classifySeconds"]:.3f}s', flush=True)
    for arm in arms:
        selected = [r for r in rows if r['arm'] == arm]
        print(f'{arm}: {sum(r["passed"] for r in selected)}/{len(selected)}; median classification {statistics.median(r["classifySeconds"] for r in selected):.3f}s')
    return 0 if all(r['passed'] for r in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())
