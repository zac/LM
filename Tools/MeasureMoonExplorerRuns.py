#!/usr/bin/env python3
"""Measure completed Explorer captures and compare alternating triplicates.

A callback is excluded from the non-texture maximum if any part of its elapsed
interval overlaps a globe-texture interval. Raw maxima and hitch counts remain.
"""
import argparse
import datetime as dt
import json
from pathlib import Path
import re
import statistics


def timestamp(line):
    return dt.datetime.fromisoformat(line[:26]).timestamp()


def overlaps(start, end, intervals):
    return any(start <= b and end >= a for a, b in intervals)


def measure(folder):
    folder = Path(folder)
    lines = (folder / 'performance.log').read_text().splitlines()
    windows, memory, hitches, phases, texture = [], [], [], [], []
    pending = None
    for line in lines:
        if 'Terrain phase begin=globe-texture ' in line:
            assert pending is None, 'Overlapping texture intervals'
            pending = timestamp(line)
        if 'Terrain phase end=globe-texture ' in line:
            assert pending is not None, 'Missing texture interval start'
            texture.append((pending, timestamp(line)))
            pending = None
        if 'Explorer performance preset=' in line:
            values = dict(re.findall(r'(\w+)=([^ ]+)', line))
            window = {key: float(values[key].removesuffix('ms').removesuffix('MiB'))
                      for key in ['frames', 'mean', 'p95', 'p99', 'max', 'missed', 'physical']}
            window['end'] = timestamp(line)
            window['start'] = window['end'] - window['frames'] * window['mean'] / 1000
            window['preset'] = values['preset']
            windows.append(window)
        match = re.search(r'Terrain memory phase=(\S+) physical=(\d+) peak=(\d+)', line)
        if match:
            memory.append(dict(phase=match[1], physical_mib=int(match[2]) / 2**20,
                               peak_mib=int(match[3]) / 2**20, time=timestamp(line)))
        match = re.search(r'Explorer hitch elapsed=([0-9.]+)ms', line)
        if match:
            end, elapsed = timestamp(line), float(match[1])
            hitches.append(dict(start=end - elapsed / 1000, end=end, elapsed=elapsed))
        match = re.search(r'Terrain phase end=(\S+) elapsed=([0-9.]+)ms', line)
        if match:
            phases.append(dict(phase=match[1], milliseconds=float(match[2]), time=timestamp(line)))
    assert pending is None, 'Incomplete texture interval'
    assert windows and memory, 'Missing frame windows or kernel memory markers'
    outside = [h['elapsed'] for h in hitches if not overlaps(h['start'], h['end'], texture)]
    outside += [w['max'] for w in windows if not overlaps(w['start'], w['end'], texture)]
    assert outside, 'No callbacks outside texture interval'
    result = dict(windows=len(windows), footprint_min_mib=min(w['physical'] for w in windows),
                  footprint_max_mib=max(w['physical'] for w in windows),
                  lifetime_peak_mib=max(m['peak_mib'] for m in memory),
                  max_window_mean_ms=max(w['mean'] for w in windows),
                  max_window_p99_ms=max(w['p99'] for w in windows),
                  largest_callback_ms=max(w['max'] for w in windows),
                  largest_callback_excluding_texture_ms=max(outside),
                  hitches_over_25ms=len(hitches),
                  texture_interval_ms=[p['milliseconds'] for p in phases if p['phase'] == 'globe-texture'],
                  texture_intervals=texture,
                  texture_markers=[m for m in memory if m['phase'].startswith('globe-texture')],
                  checkpoints=[m for m in memory if m['phase'].startswith('soak-')],
                  phases=phases, memory=memory)
    (folder / 'metrics-v2.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def distribution(values):
    assert len(values) == 3, 'Exactly three runs required'
    return dict(min=min(values), max=max(values), median=statistics.median(values))


def compare(controls, candidates, changes_texture=False, spread='upper'):
    """Owner wrap-up correction: only peak, hitch count and non-texture max gate.

    Legacy flags remain accepted so saved drivers still run. They do not change
    the gate definitions; texture/raw maxima and window summaries are reported.
    """
    assert len(controls) == len(candidates) == 3
    keys = ['footprint_min_mib', 'footprint_max_mib', 'lifetime_peak_mib',
            'max_window_mean_ms', 'max_window_p99_ms', 'hitches_over_25ms',
            'largest_callback_ms', 'largest_callback_excluding_texture_ms']
    metrics = {}
    for key in keys:
        control = distribution([r[key] for r in controls])
        candidate = distribution([r[key] for r in candidates])
        limit = None
        if key == 'lifetime_peak_mib':
            limit = control['median'] + max(25, control['median'] * .02)
        elif key == 'hitches_over_25ms':
            limit = control['median'] + max(2, control['median'] * .15)
        elif key == 'largest_callback_excluding_texture_ms':
            limit = max(control['max'], control['median'] * 1.10)
        metrics[key] = dict(control=control, candidate=candidate,
                            noise_limit=control['max'], hard_cap=limit,
                            gated=limit is not None,
                            passed=candidate['median'] <= limit + 1e-9 if limit is not None else None)
    return dict(protocol='owner named gates with callback margin and 16.70 ms settle', spread='upper',
                changes_texture=changes_texture,
                passed=all(m['passed'] for m in metrics.values() if m['gated']), metrics=metrics)


def settled_window_passes(window):
    return all(0 <= window[key] <= 16.70 + 1e-9 for key in ['mean', 'p99', 'max']) and window['missed'] == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    single = sub.add_parser('measure'); single.add_argument('folder')
    group = sub.add_parser('compare')
    group.add_argument('folder', help='Contains Control-1..3 and Candidate-1..3')
    group.add_argument('--changes-texture', action='store_true')
    group.add_argument('--spread', choices=['range', 'upper'], default='upper')
    settle = sub.add_parser('settled')
    settle.add_argument('folder')
    settle.add_argument('--preset', default='11-surface')
    settle.add_argument('--windows', type=int, default=12)
    args = parser.parse_args()
    if args.command == 'measure':
        result = measure(args.folder)
        print(json.dumps({k: v for k, v in result.items() if k not in ['phases', 'memory']}, indent=2))
    elif args.command == 'settled':
        folder = Path(args.folder)
        lines = [line for line in (folder / 'performance.log').read_text().splitlines()
                 if f'Explorer performance preset={args.preset} ' in line][-args.windows:]
        windows = []
        for line in lines:
            values = dict(re.findall(r'(\w+)=([^ ]+)', line))
            windows.append({key: float(values[key].removesuffix('ms'))
                            for key in ['mean', 'p99', 'max', 'missed']})
        result = dict(passed=len(windows) == args.windows and args.windows > 0 and
                      all(settled_window_passes(w) for w in windows), windows=windows)
        (folder / 'settled.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result, indent=2))
        if not result['passed']: raise SystemExit(1)
    else:
        folder = Path(args.folder)
        controls = [measure(folder / f'Control-{i}') for i in range(1, 4)]
        candidates = [measure(folder / f'Candidate-{i}') for i in range(1, 4)]
        result = compare(controls, candidates, args.changes_texture, args.spread)
        (folder / 'comparison-v2.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
