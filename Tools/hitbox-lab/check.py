#!/usr/bin/env python3
"""Check a Hitbox Lab run against the expected results.

    check.py RESULTS_DIR [--expected expected.json]
    check.py RESULTS_DIR --record [--expected expected.json]
    check.py RESULTS_DIR --partial     # a run of some cases only (-LabOnly)
    check.py RESULTS_DIR --invariants-only   # e.g. a 120 Hz run, which has no golden file yet

RESULTS_DIR holds the lab's results.jsonl (cases mode). Exits 0 when every
check passes, 1 when any fails. --record writes the run as the new expected
results instead (do that only after reviewing the run's screenshots).

Two kinds of check:

* Golden: every case's outcome must match expected.json, and a hit must land
  within one frame of where it used to. These guard the hitbox itself: the
  phantom hits stay fixed, the real hits stay real.
* Invariants: properties that must hold whatever the golden file says, read
  from the per-frame traces. These guard the landing and body-swap behaviour.

Standard library only, so it runs anywhere python3 does.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load_results(path):
    if os.path.isdir(path):
        path = os.path.join(path, 'results.jsonl')
    cases = {}
    with open(path) as fh:
        for line in fh:
            if line.strip():
                r = json.loads(line)
                cases[r['id']] = r
    return cases


def poses_between(trace, start, stop):
    return [s['pose'] for s in trace if start <= s['frame'] < stop]


class Checks:
    def __init__(self):
        self.failures = []
        self.warnings = []
        self.passed = 0

    def ok(self, cond, what, detail=''):
        if cond:
            self.passed += 1
        else:
            self.failures.append(f'{what}: {detail}' if detail else what)

    def warn(self, what):
        self.warnings.append(what)


def golden(c, run, expected, partial=False):
    for cid, exp in sorted(expected.items()):
        got = run.get(cid)
        if got is None and partial:
            continue
        if got is None:
            c.ok(False, f'{cid}', 'missing from this run')
            continue
        c.ok(got['outcome'] == exp['outcome'], cid,
             f"expected {exp['outcome']}, got {got['outcome']} (runs {'/'.join(got.get('runs', []))}, d {got.get('d', 0):.2f})")
        if got['outcome'] == exp['outcome'] == 'HIT' and exp.get('hitFrame') is not None:
            drift = abs((got.get('hitFrame') or 0) - exp['hitFrame'])
            c.ok(drift <= 1, f'{cid} hit frame', f"expected f{exp['hitFrame']}, got f{got.get('hitFrame')}")
            if drift == 1:
                c.warn(f"{cid}: hit one frame {'later' if got['hitFrame'] > exp['hitFrame'] else 'earlier'} than expected")
    for cid in sorted(set(run) - set(expected)):
        c.warn(f'{cid}: new case with no expected result (outcome {run[cid]["outcome"]})')


def invariants(c, run, partial=False):
    if partial:
        # Only the invariants whose cases were actually run.
        wanted = {'L-0-JUMP', 'L-2-CADENCE', 'L-1-LANDING', 'L-4-JUMP-ON-T+0', 'L-4-JUMP-ON-T+1', 'L-6-JUMP-OUT-OF-SLIDE'}
        if not wanted & set(run):
            flaky = [cid for cid, r in run.items() if r['outcome'] == 'FLAKY']
            c.ok(not flaky, 'no flaky cases', ', '.join(flaky))
            return
    # Box audit: only the floor may move, and only upward, from the running box.
    audit = run.get('L-0-JUMP')
    if audit and audit.get('trace'):
        boxes = [s['box'] for s in audit['trace'] if s.get('box')]
        base = boxes[0]
        for key in ('top', 'back', 'front'):
            spread = max(abs(b[key] - base[key]) for b in boxes)
            c.ok(spread < 0.1, f'L-0 box {key} never moves', f'moved {spread:.2f}pt during the jump')
        lowest = min(b['floor'] for b in boxes)
        c.ok(lowest >= base['floor'] - 0.1, 'L-0 box floor never drops below the running floor',
             f'went to {lowest:.2f} from {base["floor"]:.2f}')
    else:
        if not partial:
            c.ok(False, 'L-0-JUMP', 'missing or has no trace')

    # Back-to-back jumps all reach the same height.
    cad = run.get('L-2-CADENCE')
    if cad and len(cad.get('apexes', [])) >= 5:
        apexes = cad['apexes']
        spread = max(apexes) - min(apexes)
        c.ok(spread <= 2.0, 'L-2 back-to-back jumps reach the same apex',
             'apexes ' + ', '.join(f'{a:.1f}' for a in apexes))
    else:
        if not partial:
            c.ok(False, 'L-2-CADENCE', 'missing or too few jumps')

    # Swiping up mid-air never buys a second jump.
    first_apex = None
    for cid, r in sorted(run.items()):
        if cid.startswith('L-3-') and r.get('apexes'):
            first_apex = first_apex or r['apexes'][0]
            c.ok(max(r['apexes']) <= r['apexes'][0] + 3, f'{cid} no double jump',
                 'apexes ' + ', '.join(f'{a:.1f}' for a in r['apexes']))

    # A jump keeps its jump poses until it lands — on the touchdown frame, one
    # frame after it, and straight out of a slide.
    for cid in ('L-4-JUMP-ON-T+0', 'L-4-JUMP-ON-T+1', 'L-6-JUMP-OUT-OF-SLIDE'):
        r = run.get(cid)
        if not r or not r.get('trace'):
            if not partial:
                c.ok(False, cid, 'missing or has no trace')
            continue
        trace = r['trace']
        # The second jump starts at the first jump_0 after the first touchdown
        # (L-4), or at the first jump_0 at all (L-6).
        start_after = (r.get('landingFrame') or 0) if cid.startswith('L-4') else 0
        starts = [s['frame'] for s in trace if s['pose'] == 'jump_0' and s['frame'] >= start_after]
        if not starts:
            c.ok(False, f'{cid} jump starts', 'no jump_0 pose after the input')
            continue
        start = starts[0]
        airborne = [s for s in trace if s['frame'] > start and not s['grounded']]
        # Stop at the next touchdown.
        lands = [s['frame'] for s in trace if s['frame'] > start + 3 and s['grounded']]
        stop = lands[0] if lands else trace[-1]['frame'] + 1
        flight = [s for s in airborne if s['frame'] < stop and s['paw'] > 15]
        bad = [f"f{s['frame']}:{s['pose']}" for s in flight if not s['pose'].startswith('jump_')]
        c.ok(not bad, f'{cid} keeps its jump poses in flight', ', '.join(bad[:6]))
        lifted = [s for s in flight if s.get('box') and s['box']['floor'] > 3]
        c.ok(bool(lifted), f'{cid} box lifts in flight', 'the box never lifted during this jump')

    # Landing: no deep sink, no big pop back up.
    land = run.get('L-1-LANDING')
    if land and land.get('trace') and land.get('landingFrame'):
        t = land['landingFrame']
        near = [s for s in land['trace'] if t - 2 <= s['frame'] <= t + 12]
        rest = land['trace'][-1]['paw']
        sink = min(s['paw'] for s in near)
        bounce = max(s['paw'] for s in near if s['frame'] > t) - rest
        c.ok(sink >= -3.0, 'L-1 landing sinks no more than 3pt into the turf', f'paw reached {sink:.1f}pt')
        c.ok(bounce <= 6.0, 'L-1 landing bounces no more than 6pt', f'rose {bounce:.1f}pt above rest')
    else:
        if not partial:
            c.ok(False, 'L-1-LANDING', 'missing, no trace or no landing')

    flaky = [cid for cid, r in run.items() if r['outcome'] == 'FLAKY']
    c.ok(not flaky, 'no flaky cases', ', '.join(flaky))


def pacing(c, results):
    """The run's own frame pacing, from device.json, if the lab wrote one."""
    folder = results if os.path.isdir(results) else os.path.dirname(results)
    path = os.path.join(folder, 'device.json')
    if not os.path.exists(path):
        return None
    with open(path) as fh:
        d = json.load(fh)
    want, got = d.get('requestedFPS', 60), d.get('measuredFPS', 0)
    frames, dropped = d.get('frames', 0) or 1, d.get('droppedFrames', 0)
    where = 'simulator' if d.get('simulator') else 'device'
    print(f"  {where} {d.get('model')} iOS {d.get('os')}: {got:.1f} of {want} fps, "
          f"{dropped} dropped of {frames} ({dropped / frames:.1%}), longest frame {d.get('longestFrameMs', 0):.0f} ms")
    # Below 90% of the asked-for rate the run is not testing what it says it is.
    c.ok(got >= 0.9 * want, f'ran at {want} fps', f'measured {got:.1f} fps')
    if dropped / frames > 0.01:
        c.warn(f'{dropped} dropped frames ({dropped / frames:.1%}); results near an edge may move by a frame')
    if d.get('lowPowerMode'):
        c.warn('Low Power Mode was on (caps the frame rate at 60)')
    if d.get('thermalState', 0) >= 2:
        c.warn(f"device was thermally throttled (state {d['thermalState']})")
    return d


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('results', help='folder with results.jsonl, or the file itself')
    ap.add_argument('--expected', default=os.path.join(HERE, 'expected.json'))
    ap.add_argument('--record', action='store_true', help='write this run as the expected results')
    ap.add_argument('--partial', action='store_true', help='only check the cases this run contains')
    ap.add_argument('--invariants-only', action='store_true', help='skip the golden outcomes')
    args = ap.parse_args()

    run = load_results(args.results)

    if args.record:
        expected = {cid: {'outcome': r['outcome'], 'hitFrame': r.get('hitFrame'), 'd': round(r.get('d') or 0, 3)}
                    for cid, r in sorted(run.items())}
        with open(args.expected, 'w') as fh:
            json.dump({'cases': expected}, fh, indent=1, sort_keys=True)
            fh.write('\n')
        print(f'Recorded {len(expected)} cases to {args.expected}')
        return 0

    c = Checks()
    pacing(c, args.results)
    if args.invariants_only:
        print('  (golden outcomes skipped: invariants only)')
    else:
        with open(args.expected) as fh:
            expected = json.load(fh)['cases']
        golden(c, run, expected, args.partial)
    invariants(c, run, args.partial)

    for w in c.warnings:
        print(f'  warn  {w}')
    for f in c.failures:
        print(f'  FAIL  {f}')
    total = c.passed + len(c.failures)
    if c.failures:
        print(f'\nHITBOX VALIDATION FAILED: {len(c.failures)} of {total} checks failed')
        return 1
    print(f'\nHITBOX VALIDATION PASSED: {total} checks, {len(c.warnings)} warnings')
    return 0


if __name__ == '__main__':
    sys.exit(main())
