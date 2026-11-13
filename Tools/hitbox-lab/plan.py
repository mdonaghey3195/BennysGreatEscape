#!/usr/bin/env python3
"""Work out the shared boundary distances both builds' cases run at.

Reads before/sweep.jsonl and after/sweep.jsonl from the results folder and
writes plan.json there, plus windows.json (each build's clear windows).
"""
import json, sys, os
from collections import defaultdict

root = sys.argv[1] if len(sys.argv) > 1 else '.'


def load(build):
    out = defaultdict(lambda: defaultdict(list))
    meta = {}
    path = os.path.join(root, build, 'sweep.jsonl')
    for line in open(path):
        r = json.loads(line)
        out[r['target']][round(r['d'], 3)].append(r['outcome'])
        meta[r['target']] = r
    return out, meta


def verdicts(points):
    """d -> CLEAR / HIT / FLAKY (any disagreement between repeats)."""
    res = {}
    for d, outs in points.items():
        s = set(outs)
        res[d] = outs[0] if len(s) == 1 else 'FLAKY'
    return dict(sorted(res.items()))


def windows(v):
    """Contiguous runs of CLEAR, as (first clear d, last clear d). FLAKY breaks nothing."""
    runs, cur = [], None
    for d, o in v.items():
        if o == 'CLEAR':
            cur = [d, d] if cur is None else [cur[0], d]
        elif o == 'HIT':
            if cur: runs.append(tuple(cur)); cur = None
    if cur: runs.append(tuple(cur))
    return runs


def main_window(v):
    w = windows(v)
    return max(w, key=lambda r: r[1] - r[0]) if w else None


b, bmeta = load('before')
a, ameta = load('after')
plan, report = {}, {}
for target in sorted(set(b) | set(a)):
    vb, va = verdicts(b[target]), verdicts(a[target])
    wb, wa = main_window(vb), main_window(va)
    meta = bmeta.get(target) or ameta.get(target)
    speed = meta['speed']
    report[target] = {
        'speed': speed, 'height': meta['height'], 'action': meta['action'],
        'before': {'window': wb, 'flaky': [d for d, o in vb.items() if o == 'FLAKY']},
        'after': {'window': wa, 'flaky': [d for d, o in va.items() if o == 'FLAKY']},
        # The invariant: anywhere CLEAR on master that HITs on the branch.
        'regressions': sorted(d for d in set(vb) & set(va) if vb[d] == 'CLEAR' and va[d] == 'HIT'),
        'improvements': sorted(d for d in set(vb) & set(va) if vb[d] == 'HIT' and va[d] == 'CLEAR'),
    }
    p = {}
    if wb and wa:
        lo_both, hi_both = max(wb[0], wa[0]), min(wb[1], wa[1])
        p['centre'] = round((lo_both + hi_both) / 2, 2)
        p['lateMiss'] = round(lo_both + 0.25, 2)
        p['lateHit'] = round(min(wb[0], wa[0]) - 0.5, 2)
        p['earlyMissBoth'] = round(hi_both - 0.25, 2)
        p['earlyMiss'] = p['earlyMissBoth']
        p['earlyHitAfter'] = round(max(wb[1], wa[1]) + 0.5, 2)
        p['earlyHit'] = p['earlyHitAfter']
        if wa[1] > wb[1] + 0.2:
            p['phantom'] = round((wa[1] + wb[1]) / 2 + 0.125, 2)
        if wa[0] < wb[0] - 0.2:
            p['latePhantom'] = round((wa[0] + wb[0]) / 2 - 0.125, 2)
        p['d'] = p['centre']
    elif wa or wb:
        w = wa or wb
        p['d'] = round((w[0] + w[1]) / 2, 2)
        p['centre'] = p['d']
    plan[target] = p

json.dump(plan, open(os.path.join(root, 'plan.json'), 'w'), indent=1, sort_keys=True)
json.dump(report, open(os.path.join(root, 'windows.json'), 'w'), indent=1, sort_keys=True)
for t, r in report.items():
    def ms(w):
        return '-' if not w else f"{w[0]:.2f}..{w[1]:.2f} ({(w[1]-w[0])/r['speed']*1000:.1f} ms)"
    print(f"{t:18} before {ms(r['before']['window']):30} after {ms(r['after']['window']):30} "
          f"regress {len(r['regressions'])} improve {len(r['improvements'])} flaky {len(r['before']['flaky'])}/{len(r['after']['flaky'])}")
