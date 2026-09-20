"""Compare fresh pwsh startup-to-input-ready through ConPTY (Windows only)."""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', required=True, help='Baseline runtime profile.ps1')
parser.add_argument('--candidate', default='src/profile.ps1')
parser.add_argument('--runs', type=int, default=7)
parser.add_argument('--max-ratio', type=float, help='Fail when candidate/baseline median ratio exceeds this value')
parser.add_argument('--output', type=Path, help='Optional JSON evidence file')
args = parser.parse_args()
if args.runs < 3:
    parser.error('--runs must be at least 3')
if args.max_ratio is not None and args.max_ratio <= 0:
    parser.error('--max-ratio must be positive')
profiles = {key: str(Path(value).resolve()) for key, value in [('baseline', args.baseline), ('candidate', args.candidate)]}
for profile in profiles.values():
    if not Path(profile).is_file():
        parser.error('Missing profile: ' + profile)
probe = Path(__file__).with_name('bench_console.py')
rows = []
for run in range(args.runs):
    order = ['baseline', 'candidate'] if run % 2 == 0 else ['candidate', 'baseline']
    for name in order:
        result = subprocess.run([sys.executable, str(probe), profiles[name], '--samples', '1'],
                                capture_output=True, encoding='utf-8', timeout=90, check=True)
        data = json.loads(result.stdout)
        rows.append({'run': run, 'variant': name, **data})
        print(f'{run + 1}/{args.runs} {name}: {data["startup_to_prompt_ms"]:.2f} ms', file=sys.stderr)
summary = {}
for name in profiles:
    values = [r['startup_to_prompt_ms'] for r in rows if r['variant'] == name]
    summary[name] = {'median_ms': statistics.median(values), 'min_ms': min(values), 'max_ms': max(values)}
ratio = summary['candidate']['median_ms'] / summary['baseline']['median_ms']
evidence = {'profiles': profiles, 'runs': args.runs, 'summary': summary, 'median_ratio': ratio,
            'delta_ms': summary['candidate']['median_ms'] - summary['baseline']['median_ms'],
            'max_ratio': args.max_ratio, 'passed': args.max_ratio is None or ratio <= args.max_ratio,
            'samples': rows}
if args.output:
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
print(json.dumps({key: value for key, value in evidence.items() if key != 'samples'}, indent=2))
if not evidence['passed']:
    sys.exit(1)
