"""Exercise the shipped routing DAG and verify-dispatch with inert dispatch, move and state probes."""

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

import yaml
from replay import SUITE, definitions, write_json


def check(cli, root):
    definitions(root, 'Max', ('candidate',))
    workflow = json.loads((root / 'candidate.json').read_bytes())
    steps = {s['name']: s for s in yaml.safe_load((SUITE / 'raindrop-processor.yaml').read_bytes())['steps']}

    def probe(name, template):
        # Preserve the actual dependency edges and run conditions; replace only the external operation.
        routing = {k: v for k, v in steps[name].items() if k in ('name', 'dependsOn', 'when', 'enabled')}
        return {**routing, 'type': 'Transform', 'template': template}

    workflow['inputs']['outcome'] = {'type': 'string', 'required': True}
    workflow['steps'] += [
        probe('dispatch-processor', '{"processor":"{{classify.output.processor}}","status":"{{param.outcome}}"}'),
        steps['verify-dispatch'], probe('move-to-processed', 'moved'), probe('mark-completed', 'completed'),
    ]
    path = root / 'boundary.json'
    write_json(path, workflow)
    (root / 'empty-scan').mkdir()
    for name, tags, outcome, expected in (
        ('ok', '["talk"]', 'Succeeded', ('Succeeded', 'Succeeded', 'Succeeded', 'Succeeded', 'Succeeded')),
        ('child-failed', '["talk"]', 'Failed', ('Succeeded', 'Succeeded', 'Failed', 'Skipped', 'Skipped')),
        ('conflicting-tags', '["talk","recipe"]', 'Succeeded', ('Failed', 'Skipped', 'Skipped', 'Skipped', 'Skipped')),
    ):
        report = root / (name + '.json')
        cmd = ['dotnet', str(cli), 'exec', '--no-config', '--quiet', '--no-interactive', '--run-timeout', '45',
               '--data-path', str(root / 'host'), '--orchestrations-path', str(root / 'empty-scan'),
               '--run-file', str(path), '--report', 'json', '--report-output', str(report),
               '--param', 'url=https://example.org/article', '--param', 'title=Fixture',
               '--param', 'tags=' + tags, '--param', 'outcome=' + outcome]
        run = subprocess.run(cmd, cwd=root, capture_output=True, timeout=60)
        if not report.exists():
            raise RuntimeError(f'{name}: no run report (CLI exit {run.returncode}): {run.stderr.decode(errors="replace")}')
        result = json.loads(report.read_bytes())
        records = {s['name']: s for s in result['steps']}
        observed = tuple(records[s]['status'] for s in ('route-rules', 'dispatch-processor', 'verify-dispatch', 'move-to-processed', 'mark-completed'))
        assert observed == expected, (name, observed, expected)
        assert (run.returncode == 0) == (name == 'ok'), (name, run.returncode)
        if name != 'conflicting-tags':
            assert json.loads(records['dispatch-processor']['content'])['processor'] == 'raindrop-article-generic-processor'
        print(f'PASS {name}: {observed}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli-dll', required=True, type=Path)
    opts = parser.parse_args()
    scratch = Path(tempfile.gettempdir()) / 'opencode'
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='raindrop-guard-', dir=scratch) as out:
        check(opts.cli_dll.resolve(strict=True), Path(out))
