#!/usr/bin/env python3
"""The hitbox gate: what can be checked about the hitboxes without a Mac.

    gate.py                      # check the source against hitbox-baseline.json
    gate.py --update-baseline    # accept the source's numbers as the new baseline
    gate.py --summary FILE       # also write a Markdown report (CI: $GITHUB_STEP_SUMMARY)

Reads every collision number straight from the Swift source (hitbox_source.py),
works out the timing each obstacle gives (timing_model.py), and checks three
things:

* Safety rules that must always hold: the box lifts fit the jump frames and
  stay inside the body, the ducked box fits under every bench, every jump prop
  and slide leaves at least 130 ms of timing, cliffs are clearable, the spawn
  interval never undercuts a jump.
* The baseline: any change to a hitbox number fails until hitbox-baseline.json
  is updated in the same commit. A timing window that shrank by more than one
  frame of travel is called out, since that is what a player feels.
* The lab's own data: plan.json and expected.json parse and agree.

Exits 0 on pass, 1 on a failed check, 2 if the source couldn't be read.
Standard library only.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from hitbox_source import SourceError, load_world, JUMP_PIECES, DUCK_PIECES  # noqa: E402
from timing_model import report  # noqa: E402

BASELINE = os.path.join(HERE, 'hitbox-baseline.json')
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))

MIN_WINDOW_MS = 130     # least timing any jump or slide may give
MIN_CLIFF_MS = 150      # least slack a cliff may give
DUCK_MARGIN = 4.0       # points between the ducked box and a seat's underside
FRAME = 1 / 60
SETTLED = ('CLEAR', 'HIT', 'DONE', 'GAMEOVER', 'N/A')


class Gate:
    def __init__(self):
        self.failures, self.warnings, self.passed = [], [], 0

    def ok(self, cond, what, detail=''):
        if cond:
            self.passed += 1
        else:
            self.failures.append(f'{what}: {detail}' if detail else what)
        return cond

    def warn(self, what):
        self.warnings.append(what)


def snapshot(world):
    return {'source': world.as_dict(), 'timing': report(world)}


# --- Safety rules ---------------------------------------------------------------

def safety(g, world, timing):
    c = world.const
    lifts = c('DogArt.jumpLifts')
    body_h = c('DogArt.bodyHeightFraction')
    g.ok(len(lifts) == world.jump_frames, 'one box lift per jump frame',
         f'{len(lifts)} lifts for {world.jump_frames} benny_jump images')
    g.ok(len(world.jump_weights) == world.jump_frames, 'one arc weight per jump frame',
         f'{len(world.jump_weights)} weights for {world.jump_frames} frames')
    bad = [f'jump_{i}={v}' for i, v in enumerate(lifts) if not 0 <= v < body_h]
    g.ok(not bad, 'box lifts stay between the paws and the top of the body', ', '.join(bad))
    g.ok(0 <= c('DogArt.forgivenessFraction') < min(c('DogArt.bodyWidthFraction'), c('DogArt.slideWidthFraction')),
         'forgiveness is smaller than the box it trims', str(c('DogArt.forgivenessFraction')))
    for f in ('bodyWidthFraction', 'bodyHeightFraction', 'slideWidthFraction', 'slideHeightFraction'):
        v = c(f'DogArt.{f}')
        g.ok(0 < v <= 1, f'DogArt.{f} is a fraction of the drawing', str(v))
    g.ok(c('DogArt.slideHeightFraction') < c('DogArt.bodyHeightFraction'), 'the slide box is lower than the standing box')

    ducked, standing, clearance = timing['duckedTop'], timing['standingTop'], c('Layout.duckClearance')
    g.ok(ducked + DUCK_MARGIN <= clearance, 'the ducked box fits under duckClearance',
         f'ducked box top {ducked:.1f}pt, clearance {clearance:.1f}pt (needs {DUCK_MARGIN:.0f}pt spare)')
    if standing <= clearance:
        g.warn(f'the standing box ({standing:.1f}pt) fits under duckClearance ({clearance:.1f}pt): benches no longer need a slide')
    for name in DUCK_PIECES:
        under = timing['slides'].get(f'{name}:underside')
        if under is not None:
            g.ok(under >= ducked + DUCK_MARGIN, f'{name}: the ducked box passes under it',
                 f'underside {under:.1f}pt, ducked box top {ducked:.1f}pt')

    for name in JUMP_PIECES + DUCK_PIECES:
        p = world.pieces[name]
        g.ok(0 < p.low <= p.high, f'{name}: heightRange runs low to high', f'{p.low:.1f}...{p.high:.1f}')

    for key, row in timing['jumps'].items():
        g.ok(row['ms'] >= MIN_WINDOW_MS, f'{key} gives at least {MIN_WINDOW_MS} ms to jump',
             f"{row['ms']:.0f} ms (lead {row['lo']}–{row['hi']}pt)" if row['lo'] is not None else 'no jump clears it')
        if row['clampedLow']:
            g.warn(f"{key}: held at its smallest height ({row['height']}pt) and gives {row['solverSlackMs']:.0f} ms by the game's own measure, under ObstacleArt.clearance")
        if row['clampedHigh']:
            g.warn(f"{key}: held at its largest height ({row['height']}pt); easier than ObstacleArt.clearance asks")
    for key, row in timing['slides'].items():
        if ':' in key:
            continue
        g.ok(row is not None and row['ms'] >= MIN_WINDOW_MS, f'{key} gives at least {MIN_WINDOW_MS} ms to slide',
             f"{row['ms']:.0f} ms" if row else 'no slide passes under it')
    cl = timing['cliffs']
    g.ok(cl['tightestSlackMs'] >= MIN_CLIFF_MS, f'every cliff leaves at least {MIN_CLIFF_MS} ms',
         f"{cl['tightestSlackMs']:.0f} ms with a {cl['gapThere']:.0f}pt gap")
    if 'spawnFloorVsAirtimeMs' in timing:
        g.ok(timing['spawnFloorVsAirtimeMs'] >= 0, 'the quickest spawn interval outlasts a jump',
             f"{timing['spawnFloorVsAirtimeMs']:.0f} ms to spare")
    else:
        g.warn('spawn interval constants not found in GameScene.swift; skipped that check')


# --- Baseline -------------------------------------------------------------------

def flatten(d, prefix=''):
    out = {}
    if isinstance(d, dict):
        for k, v in d.items():
            out.update(flatten(v, f'{prefix}.{k}' if prefix else k))
    elif isinstance(d, list) and d and not isinstance(d[0], (dict, list)):
        out[prefix] = d
    elif isinstance(d, list):
        for i, v in enumerate(d):
            out.update(flatten(v, f'{prefix}[{i}]'))
    else:
        out[prefix] = d
    return out


def same(a, b, tolerance=1e-9):
    """Source numbers must match exactly (as rounded); the model's outputs may
    wobble in their last printed digit."""
    if isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool):
        return abs(a - b) <= tolerance
    if isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
        return all(same(x, y, tolerance) for x, y in zip(a, b))
    return a == b


def baseline(g, now, path):
    if not os.path.exists(path):
        g.ok(False, 'hitbox-baseline.json exists', 'run gate.py --update-baseline and commit it')
        return []
    with open(path) as fh:
        base = json.load(fh)
    old, new = flatten(base), flatten(now)
    changes = []
    for key in sorted(set(old) | set(new)):
        a, b = old.get(key, '(absent)'), new.get(key, '(absent)')
        if not same(a, b, 0.15 if key.startswith('timing.') else 1e-9):
            changes.append((key, a, b))
    # Windows that shrank by more than a frame of travel are the ones a player feels.
    for key, row in now['timing']['jumps'].items():
        was = base.get('timing', {}).get('jumps', {}).get(key)
        if was and was.get('ms') and row['ms'] < was['ms'] - 1000 * FRAME:
            g.failures.append(f"{key}: jump window shrank by more than a frame, {was['ms']:.0f} -> {row['ms']:.0f} ms")
    g.ok(not changes, 'hitbox numbers match hitbox-baseline.json',
         f'{len(changes)} changed; if intended, run Tools/hitbox-lab/gate.py --update-baseline and commit it with the change')
    return changes


# --- The lab's data files ---------------------------------------------------------

def lab_data(g, world):
    plan_path, exp_path = os.path.join(HERE, 'plan.json'), os.path.join(HERE, 'expected.json')
    try:
        with open(plan_path) as fh:
            plan = json.load(fh)
        g.ok(True, 'plan.json parses')
    except (OSError, ValueError) as e:
        g.ok(False, 'plan.json parses', str(e))
        plan = {}
    for name in JUMP_PIECES:
        for tier in world.const('ObstacleArt.sizeTiers'):
            key = f'{name}@{round(tier)}'
            entry = plan.get(key)
            g.ok(bool(entry) and 'winLo' in entry and 'winHi' in entry and entry['winLo'] < entry['winHi'],
                 f'plan.json has the window for {key}', 'missing or out of order; re-derive with plan.py')
    for name in ('bench', 'swingset'):
        entry = plan.get(f'{name}/slide')
        g.ok(bool(entry) and 'winHi' in entry, f'plan.json has the slide window for {name}')
    try:
        with open(exp_path) as fh:
            text = fh.read()
        pairs = json.loads(text, object_pairs_hook=lambda kv: kv)
        cases = dict(pairs)['cases']
        ids = [k for k, _ in cases]
        dupes = sorted({i for i in ids if ids.count(i) > 1})
        g.ok(not dupes, 'expected.json has no duplicate case IDs', ', '.join(dupes))
        # What a settled run can record; FLAKY, NOSCENE and NOGROUND never belong here.
        bad = [k for k, v in cases if dict(v).get('outcome') not in SETTLED]
        g.ok(not bad, 'expected.json holds only settled outcomes', ', '.join(bad[:8]))
    except (OSError, ValueError, KeyError, TypeError) as e:
        g.ok(False, 'expected.json parses', str(e))


# --- Output -----------------------------------------------------------------------

def markdown(g, timing, changes):
    lines = ['## Hitbox gate', '']
    lines.append(f"**{'Failed' if g.failures else 'Passed'}**: {g.passed + len(g.failures)} checks, "
                 f"{len(g.failures)} failed, {len(g.warnings)} warnings.")
    lines.append('')
    if g.failures:
        lines += ['### Failures', ''] + [f'- {f}' for f in g.failures] + ['']
    if changes:
        lines += ['### Changed numbers', '', '| Number | Baseline | Now |', '| --- | --- | --- |']
        for key, a, b in changes[:60]:
            lines.append(f'| `{key}` | {a} | {b} |')
        if len(changes) > 60:
            lines.append(f'| … {len(changes) - 60} more | | |')
        lines.append('')
    if g.warnings:
        lines += ['### Warnings', ''] + [f'- {w}' for w in g.warnings] + ['']
    lines += ['### Timing windows (model)', '', '| Prop @ tier | Height | Lead (pt) | Window |', '| --- | --- | --- | --- |']
    for key, row in timing['jumps'].items():
        lead = f"{row['lo']:.1f}–{row['hi']:.1f}" if row['lo'] is not None else '—'
        lines.append(f"| {key} | {row['height']:.1f} | {lead} | {row['ms']:.0f} ms |")
    for key, row in timing['slides'].items():
        if ':' not in key and row:
            lines.append(f"| {key} (slide) | | {row['lo']:.1f}–{row['hi']:.1f} | {row['ms']:.0f} ms |")
    lines += ['', '_From the source alone: no frames, no Box2D skin, so windows run a little wider than the simulator measures._', '']
    return '\n'.join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--root', default=ROOT, help='the repository (default: two folders up)')
    ap.add_argument('--baseline', default=BASELINE)
    ap.add_argument('--update-baseline', action='store_true', help='write the current numbers as the baseline')
    ap.add_argument('--summary', help='also write a Markdown report here (appends)')
    args = ap.parse_args()

    try:
        world = load_world(args.root)
        now = snapshot(world)
    except (SourceError, OSError) as e:
        print(f'error: could not read the hitbox numbers from the source: {e}', file=sys.stderr)
        print('If the Swift moved on purpose, update Tools/hitbox-lab/hitbox_source.py to match.', file=sys.stderr)
        if args.summary:
            with open(args.summary, 'a') as fh:
                fh.write(f'## Hitbox gate\n\n**Error**: could not read the source: {e}\n')
        return 2

    if args.update_baseline:
        with open(args.baseline, 'w') as fh:
            json.dump(now, fh, indent=1, sort_keys=True)
            fh.write('\n')
        print(f'Wrote {args.baseline}')

    g = Gate()
    safety(g, world, now['timing'])
    changes = [] if args.update_baseline else baseline(g, now, args.baseline)
    lab_data(g, world)

    for key, a, b in changes:
        print(f'  changed  {key}: {a} -> {b}')
    for w in g.warnings:
        print(f'  warn  {w}')
    for f in g.failures:
        print(f'  FAIL  {f}')
    if args.summary:
        with open(args.summary, 'a') as fh:
            fh.write(markdown(g, now['timing'], changes))
    total = g.passed + len(g.failures)
    if g.failures:
        print(f'\nHITBOX GATE FAILED: {len(g.failures)} of {total} checks failed')
        return 1
    print(f'\nHITBOX GATE PASSED: {total} checks, {len(g.warnings)} warnings')
    return 0


if __name__ == '__main__':
    sys.exit(main())
