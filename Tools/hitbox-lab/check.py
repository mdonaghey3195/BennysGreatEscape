#!/usr/bin/env python3
"""Check a Hitbox Lab run against the expected results.

    check.py RESULTS_DIR [--expected expected.json]
    check.py RESULTS_DIR --record [--expected expected.json]
    check.py RESULTS_DIR --partial     # a run of some cases only (-LabOnly)
    check.py RESULTS_DIR --invariants-only   # e.g. a 120 Hz run, which has no golden file yet
    check.py RESULTS_DIR --lenient-pacing --failed-cases FILE   # CI: see validate.sh --ci

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
        self.cases = set()     # the case IDs behind the failures, for a re-run

    def ok(self, cond, what, detail='', case=None):
        if cond:
            self.passed += 1
        else:
            self.failures.append(f'{what}: {detail}' if detail else what)
            if case:
                self.cases.add(case)

    def warn(self, what):
        self.warnings.append(what)


RULE_BASED = ('T-', 'H-', 'C-')


def golden(c, run, expected, partial=False):
    for cid, exp in sorted(expected.items()):
        if cid.startswith(RULE_BASED):
            continue
        got = run.get(cid)
        if got is None and partial:
            continue
        if got is None:
            c.ok(False, f'{cid}', 'missing from this run', case=cid)
            continue
        c.ok(got['outcome'] == exp['outcome'], cid,
             f"expected {exp['outcome']}, got {got['outcome']} (runs {'/'.join(got.get('runs', []))}, d {got.get('d', 0):.2f})", case=cid)
        if got['outcome'] == exp['outcome'] == 'HIT' and exp.get('hitFrame') is not None:
            drift = abs((got.get('hitFrame') or 0) - exp['hitFrame'])
            c.ok(drift <= 1, f'{cid} hit frame', f"expected f{exp['hitFrame']}, got f{got.get('hitFrame')}", case=cid)
            if drift == 1:
                c.warn(f"{cid}: hit one frame {'later' if got['hitFrame'] > exp['hitFrame'] else 'earlier'} than expected")
    for cid in sorted(set(run) - set(expected)):
        if not cid.startswith(RULE_BASED):
            c.warn(f'{cid}: new case with no expected result (outcome {run[cid]["outcome"]})')


def tiers(c, run, expected):
    """T cases: the clear window at every speed tier keeps its size."""
    for cid, r in sorted(run.items()):
        if not cid.startswith('T-') or r['outcome'] == 'N/A':
            continue
        edge = 'late' if '-LO-' in cid else 'early'
        if cid.endswith('-IN'):
            c.ok(r['outcome'] == 'CLEAR', f'{cid} clears',
                 f"{r['outcome']} one frame inside the {edge} edge (d {r['d']:.2f}): the window shrank by more than a frame", case=cid)
        elif cid.endswith('-OUT') and r['outcome'] == 'CLEAR':
            c.warn(f"{cid}: clears one frame outside the {edge} edge (d {r['d']:.2f}): the window grew by more than a frame")
        elif cid.endswith('-EDGE'):
            exp = expected.get(cid)
            if exp and exp['outcome'] != r['outcome']:
                c.warn(f"{cid}: {exp['outcome']} -> {r['outcome']} at the {edge} edge (moved by less than a frame)")


def hitches(c, run, partial=False):
    """H cases: a hitch never turns a clear into a hit."""
    for cid, r in sorted(run.items()):
        if not cid.startswith('H-') or r['outcome'] == 'N/A':
            continue
        base_id = cid[2:].split('@')[0]
        base = run.get(base_id)
        when = cid.split('@')[1]
        if base is None:
            if not partial:
                c.ok(False, cid, f'its base case {base_id} was not run', case=base_id)
            continue
        if base['outcome'] == 'CLEAR':
            c.ok(r['outcome'] == 'CLEAR', f'{cid} still clears',
                 f"a hitch at {when} turned a clear into a {r['outcome']} ({r.get('hitPose') or ''} f{r.get('hitFrame')})", case=cid)
        elif base['outcome'] == 'HIT' and r['outcome'] == 'CLEAR':
            c.warn(f'{cid}: a hitch at {when} turned a hit into a clear')


def courses(c, run):
    """C cases: a generated course, played at each window's centre, never fails."""
    for cid, r in sorted(run.items()):
        if not cid.startswith('C-'):
            continue
        notes = r.get('notes') or []
        summary = notes[0] if notes else ''
        print(f'  info  {cid}: {summary}')
        c.ok(r['outcome'] == 'CLEAR', f'{cid} plays through ({summary})',
             '; '.join(n for n in notes[1:]) or r['outcome'], case=cid)
        for n in notes[1:]:
            if r['outcome'] == 'CLEAR':
                c.warn(f'{cid}: {n}')


def touchdown(trace, t):
    """How far the paws went into the turf around touchdown frame `t`, and how
    far they popped back up above where they came to rest."""
    near = [s for s in trace if t - 2 <= s['frame'] <= t + 12]
    rest = trace[-1]['paw']
    sink = min((s['paw'] for s in near), default=rest)
    bounce = max((s['paw'] for s in near if s['frame'] > t), default=rest) - rest
    return sink, bounce


# The L-10 cases: a dive off each of these jump poses.
DIVES = [f'L-10-DIVE-jump_{f}' for f in (1, 3, 5, 7)]
DIVE_POSE = 'jump_7'


def dives(c, run, partial=False):
    """A swipe down in the air throws him at the turf. He holds the reaching
    pose to the ground, lands sooner than the jump would have and as cleanly
    as a jump does, and gets no second jump out of it. A second swipe made
    mid-dive slides on touchdown, a dive once a log is behind him clears it,
    and a dive over a cliff's gap goes into it. (A jump straight out of a
    dive's touchdown is held to the same poses and lifts as L-4, above.)"""
    def present(cid):
        r = run.get(cid)
        if r is None and not partial:
            c.ok(False, cid, 'missing from this run', case=cid)
        return r

    plain = run.get('L-1-LANDING') or {}
    plain_t = plain.get('landingFrame')

    for cid in DIVES:
        r = present(cid)
        if r is None:
            continue
        if not r.get('trace') or not r.get('landingFrame'):
            c.ok(False, cid, 'no trace or never landed', case=cid)
            continue
        trace, t = r['trace'], r['landingFrame']
        apexes = r.get('apexes') or [0.0]
        c.ok(max(apexes) <= apexes[0] + 3, f'{cid} no double jump',
             'apexes ' + ', '.join(f'{a:.1f}' for a in apexes), case=cid)
        if plain_t:
            c.ok(t < plain_t, f'{cid} lands sooner than a jump',
                 f'touched down at f{t}, a plain jump at f{plain_t}', case=cid)
        pose = cid.rsplit('-', 1)[1]
        trigger = next((s['frame'] for s in trace if s['frame'] > 0 and s['pose'] == pose), None)
        if trigger is None:
            c.ok(False, f'{cid} dives', f'{pose} was never shown, so the swipe never came', case=cid)
        else:
            off = [f"f{s['frame']}:{s['pose']}" for s in trace if trigger < s['frame'] < t and s['pose'] != DIVE_POSE]
            c.ok(not off, f'{cid} holds {DIVE_POSE} to the ground', ', '.join(off[:6]), case=cid)
        sink, bounce = touchdown(trace, t)
        c.ok(sink >= -3.0, f'{cid} sinks no more than 3pt into the turf', f'paw reached {sink:.1f}pt', case=cid)
        c.ok(bounce <= 6.0, f'{cid} bounces no more than 6pt', f'rose {bounce:.1f}pt above rest', case=cid)

    cid = 'L-11-DIVE-THEN-SLIDE'
    r = present(cid)
    if r is not None:
        t = r.get('landingFrame')
        slid = next((s['frame'] for s in r.get('trace') or [] if t is not None and s['frame'] >= t
                     and s['pose'].startswith('slide_')), None)
        c.ok(slid is not None and slid - t <= 3, 'L-11 a swipe saved mid-dive slides on touchdown',
             'never slid' if slid is None else f'slid {slid - t} frames after touching down', case=cid)

    cid = 'L-13-DIVE-PAST-LOG'
    r = present(cid)
    if r is not None:
        c.ok(r['outcome'] == 'CLEAR', 'L-13 a dive once the log is behind him clears it',
             f"{r['outcome']} at f{r.get('hitFrame')}", case=cid)
        if plain_t and r.get('landingFrame'):
            c.ok(r['landingFrame'] < plain_t, 'L-13 dives before the jump would have landed',
                 f"touched down at f{r['landingFrame']}, a plain jump at f{plain_t}", case=cid)

    cid = 'L-14-DIVE-INTO-CLIFF'
    r = present(cid)
    if r is not None:
        c.ok(r['outcome'] == 'GAMEOVER', "L-14 a dive into a cliff's gap ends the run",
             f"{r['outcome']}", case=cid)


def invariants(c, run, partial=False):
    if partial:
        # Only the invariants whose cases were actually run.
        wanted = {'L-0-JUMP', 'L-2-CADENCE', 'L-1-LANDING', 'L-4-JUMP-ON-T+0', 'L-4-JUMP-ON-T+1', 'L-6-JUMP-OUT-OF-SLIDE'}
        wanted |= set(DIVES) | {'L-11-DIVE-THEN-SLIDE', 'L-12-JUMP-ON-DIVE-LANDING-T+0',
                                'L-12-JUMP-ON-DIVE-LANDING-T+1', 'L-13-DIVE-PAST-LOG', 'L-14-DIVE-INTO-CLIFF'}
        if not wanted & set(run):
            flaky = [cid for cid, r in run.items() if r['outcome'] == 'FLAKY']
            c.ok(not flaky, 'no flaky cases', ', '.join(flaky))
            c.cases.update(flaky)
            return
    # Box audit: only the floor may move, and only upward, from the running box.
    audit = run.get('L-0-JUMP')
    if audit and audit.get('trace'):
        boxes = [s['box'] for s in audit['trace'] if s.get('box')]
        base = boxes[0]
        for key in ('top', 'back', 'front'):
            spread = max(abs(b[key] - base[key]) for b in boxes)
            c.ok(spread < 0.1, f'L-0 box {key} never moves', f'moved {spread:.2f}pt during the jump', case='L-0-JUMP')
        lowest = min(b['floor'] for b in boxes)
        c.ok(lowest >= base['floor'] - 0.1, 'L-0 box floor never drops below the running floor',
             f'went to {lowest:.2f} from {base["floor"]:.2f}', case='L-0-JUMP')
    else:
        if not partial:
            c.ok(False, 'L-0-JUMP', 'missing or has no trace', case='L-0-JUMP')

    # Back-to-back jumps all reach the same height.
    cad = run.get('L-2-CADENCE')
    if cad and len(cad.get('apexes', [])) >= 5:
        apexes = cad['apexes']
        spread = max(apexes) - min(apexes)
        c.ok(spread <= 2.0, 'L-2 back-to-back jumps reach the same apex',
             'apexes ' + ', '.join(f'{a:.1f}' for a in apexes), case='L-2-CADENCE')
    else:
        if not partial:
            c.ok(False, 'L-2-CADENCE', 'missing or too few jumps', case='L-2-CADENCE')

    # Swiping up mid-air never buys a second jump.
    first_apex = None
    for cid, r in sorted(run.items()):
        if cid.startswith('L-3-') and r.get('apexes'):
            first_apex = first_apex or r['apexes'][0]
            c.ok(max(r['apexes']) <= r['apexes'][0] + 3, f'{cid} no double jump',
                 'apexes ' + ', '.join(f'{a:.1f}' for a in r['apexes']), case=cid)

    # A jump keeps its jump poses until it lands — on the touchdown frame, one
    # frame after it, straight out of a slide, and straight out of a dive's
    # touchdown.
    for cid in ('L-4-JUMP-ON-T+0', 'L-4-JUMP-ON-T+1', 'L-6-JUMP-OUT-OF-SLIDE',
                'L-12-JUMP-ON-DIVE-LANDING-T+0', 'L-12-JUMP-ON-DIVE-LANDING-T+1'):
        r = run.get(cid)
        if not r or not r.get('trace'):
            if not partial:
                c.ok(False, cid, 'missing or has no trace', case=cid)
            continue
        trace = r['trace']
        # The second jump starts at the first jump_0 after the first touchdown
        # (L-4, L-12), or at the first jump_0 at all (L-6).
        start_after = (r.get('landingFrame') or 0) if cid.startswith(('L-4', 'L-12')) else 0
        starts = [s['frame'] for s in trace if s['pose'] == 'jump_0' and s['frame'] >= start_after]
        if not starts:
            c.ok(False, f'{cid} jump starts', 'no jump_0 pose after the input', case=cid)
            continue
        start = starts[0]
        airborne = [s for s in trace if s['frame'] > start and not s['grounded']]
        # Stop at the next touchdown.
        lands = [s['frame'] for s in trace if s['frame'] > start + 3 and s['grounded']]
        stop = lands[0] if lands else trace[-1]['frame'] + 1
        flight = [s for s in airborne if s['frame'] < stop and s['paw'] > 15]
        bad = [f"f{s['frame']}:{s['pose']}" for s in flight if not s['pose'].startswith('jump_')]
        c.ok(not bad, f'{cid} keeps its jump poses in flight', ', '.join(bad[:6]), case=cid)
        lifted = [s for s in flight if s.get('box') and s['box']['floor'] > 3]
        c.ok(bool(lifted), f'{cid} box lifts in flight', 'the box never lifted during this jump', case=cid)

    # Landing: no deep sink, no big pop back up.
    land = run.get('L-1-LANDING')
    if land and land.get('trace') and land.get('landingFrame'):
        sink, bounce = touchdown(land['trace'], land['landingFrame'])
        c.ok(sink >= -3.0, 'L-1 landing sinks no more than 3pt into the turf', f'paw reached {sink:.1f}pt', case='L-1-LANDING')
        c.ok(bounce <= 6.0, 'L-1 landing bounces no more than 6pt', f'rose {bounce:.1f}pt above rest', case='L-1-LANDING')
    else:
        if not partial:
            c.ok(False, 'L-1-LANDING', 'missing, no trace or no landing', case='L-1-LANDING')

    dives(c, run, partial)

    flaky = [cid for cid, r in run.items() if r['outcome'] == 'FLAKY']
    c.ok(not flaky, 'no flaky cases', ', '.join(flaky))
    c.cases.update(flaky)


def pacing(c, results, lenient=False):
    """The run's own frame pacing, from device.json, if the lab wrote one.
    Lenient (CI's shared, virtualised Macs): a slow run warns instead of failing."""
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
    if lenient:
        if got < 0.9 * want:
            c.warn(f'ran at {got:.1f} of {want} fps; hits near a window edge may land a frame or two off')
    else:
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
    ap.add_argument('--lenient-pacing', action='store_true', help='a slow frame rate warns rather than fails (CI)')
    ap.add_argument('--failed-cases', metavar='FILE', help='write the IDs of the cases behind any failure here')
    ap.add_argument('--flaky-ok', metavar='IDS', default='',
                    help='comma-separated cases that failed once and passed on a re-run: warn, not fail (CI)')
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
    pacing(c, args.results, args.lenient_pacing)
    if args.invariants_only:
        print('  (golden outcomes skipped: invariants only)')
    else:
        with open(args.expected) as fh:
            expected = json.load(fh)['cases']
        golden(c, run, expected, args.partial)
        tiers(c, run, expected)
    if args.invariants_only:
        tiers(c, run, {})
    hitches(c, run, args.partial)
    courses(c, run)
    invariants(c, run, args.partial)

    for cid in filter(None, args.flaky_ok.split(',')):
        c.warn(f'{cid}: failed on the first try and passed on a re-run (flaky on CI)')
    if args.failed_cases:
        with open(args.failed_cases, 'w') as fh:
            fh.write(''.join(f'{cid}\n' for cid in sorted(c.cases)))
            # A failure with no case behind it can't be settled by a re-run.
            if len(c.cases) == 0 and c.failures:
                fh.write('')
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
