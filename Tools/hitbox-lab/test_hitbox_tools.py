#!/usr/bin/env python3
"""Tests for the hitbox tools themselves: check.py, the source reader and the gate.

    python3 Tools/hitbox-lab/test_hitbox_tools.py

check.py is fed synthetic lab records, so a broken checker is caught without
a simulator. The gate is fed the real source with one number changed at a
time, to prove each rule actually fires. Standard library only.
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)

import check  # noqa: E402
import gate  # noqa: E402
from hitbox_source import SourceError, load_world  # noqa: E402
from timing_model import report  # noqa: E402


# --- check.py -----------------------------------------------------------------------

def case(cid, outcome='CLEAR', **kw):
    r = {'id': cid, 'outcome': outcome, 'runs': [outcome], 'd': 100.0, 'notes': [], 'shots': []}
    r.update(kw)
    return r


def frame(n, pose='run_0', paw=0.0, grounded=True, floor=0.0):
    return {'frame': n, 'pose': pose, 'paw': paw, 'grounded': grounded,
            'box': {'top': 56.8, 'back': -33.9, 'front': 36.7, 'floor': floor}}


def good_jump_trace(start=0, landing=None):
    """A clean jump: jump_0..jump_9 airborne with the box lifted, then grounded."""
    trace = [frame(start, 'run_0')]
    for i in range(10):
        trace.append(frame(start + 1 + i * 6, f'jump_{i}', paw=40.0, grounded=False, floor=8.0))
    end = start + 62
    trace.append(frame(end, 'run_0'))
    return trace, end


def healthy_run():
    """Every case the invariants need, all well behaved."""
    run = {}
    audit, _ = good_jump_trace()
    run['L-0-JUMP'] = case('L-0-JUMP', 'DONE', trace=audit)
    run['L-2-CADENCE'] = case('L-2-CADENCE', 'DONE', apexes=[144.0, 144.5, 143.8, 144.2, 144.1])
    run['L-3-MIDAIR-jump_2'] = case('L-3-MIDAIR-jump_2', 'DONE', apexes=[144.0])
    land = [frame(n, paw=0.0) for n in range(55, 75)]
    land[3]['paw'] = -1.5
    run['L-1-LANDING'] = case('L-1-LANDING', 'DONE', trace=land, landingFrame=57)
    for cid in ('L-4-JUMP-ON-T+0', 'L-4-JUMP-ON-T+1'):
        first, end = good_jump_trace()
        second, _ = good_jump_trace(end)
        run[cid] = case(cid, 'DONE', trace=first + second[1:], landingFrame=end)
    slide, _ = good_jump_trace()
    run['L-6-JUMP-OUT-OF-SLIDE'] = case('L-6-JUMP-OUT-OF-SLIDE', 'DONE', trace=slide)
    run['J-LOG-TOP'] = case('J-LOG-TOP')
    run['J-LOG-LC-H'] = case('J-LOG-LC-H', 'HIT', hitFrame=4)
    return run


def expected_for(run):
    return {cid: {'outcome': r['outcome'], 'hitFrame': r.get('hitFrame'), 'd': r['d']} for cid, r in run.items()}


def checked(run, expected=None, partial=False):
    c = check.Checks()
    with contextlib.redirect_stdout(io.StringIO()):
        if expected is not None:
            check.golden(c, run, expected, partial)
            check.tiers(c, run, expected)
        check.hitches(c, run, partial)
        check.courses(c, run)
        check.invariants(c, run, partial)
    return c


class CheckPy(unittest.TestCase):
    def test_healthy_run_passes(self):
        run = healthy_run()
        c = checked(run, expected_for(run))
        self.assertEqual(c.failures, [])

    def test_changed_outcome_fails(self):
        run = healthy_run()
        exp = expected_for(run)
        run['J-LOG-TOP'] = case('J-LOG-TOP', 'HIT', hitFrame=9)
        self.assertTrue(any('J-LOG-TOP' in f for f in checked(run, exp).failures))

    def test_hit_frame_drift(self):
        run = healthy_run()
        exp = expected_for(run)
        run['J-LOG-LC-H']['hitFrame'] = 5
        c = checked(run, exp)
        self.assertEqual(c.failures, [])
        self.assertTrue(any('one frame later' in w for w in c.warnings))
        run['J-LOG-LC-H']['hitFrame'] = 7
        self.assertTrue(any('hit frame' in f for f in checked(run, exp).failures))

    def test_missing_case_fails_unless_partial(self):
        run = healthy_run()
        exp = expected_for(run)
        del run['J-LOG-TOP']
        self.assertTrue(any('missing' in f for f in checked(run, exp).failures))
        self.assertEqual(checked(run, exp, partial=True).failures, [])

    def test_box_top_moving_fails(self):
        run = healthy_run()
        run['L-0-JUMP']['trace'][4]['box']['top'] = 50.0
        self.assertTrue(any('L-0 box top' in f for f in checked(run).failures))

    def test_double_jump_fails(self):
        run = healthy_run()
        run['L-3-MIDAIR-jump_2']['apexes'] = [144.0, 190.0]
        self.assertTrue(any('no double jump' in f for f in checked(run).failures))

    def test_uneven_apexes_fail(self):
        run = healthy_run()
        run['L-2-CADENCE']['apexes'][2] = 130.0
        self.assertTrue(any('same apex' in f for f in checked(run).failures))

    def test_landing_sink_and_bounce(self):
        run = healthy_run()
        run['L-1-LANDING']['trace'][3]['paw'] = -6.0
        self.assertTrue(any('sinks' in f for f in checked(run).failures))
        run = healthy_run()
        run['L-1-LANDING']['trace'][8]['paw'] = 9.0
        self.assertTrue(any('bounces' in f for f in checked(run).failures))

    def test_run_pose_mid_flight_fails(self):
        run = healthy_run()
        run['L-4-JUMP-ON-T+0']['trace'][-4]['pose'] = 'run_2'
        self.assertTrue(any('keeps its jump poses' in f for f in checked(run).failures))

    def test_flaky_fails(self):
        run = healthy_run()
        run['J-LOG-TOP']['outcome'] = 'FLAKY'
        self.assertTrue(any('flaky' in f for f in checked(run).failures))

    def test_tier_rules(self):
        run = healthy_run()
        run['T-log@250-LO-IN'] = case('T-log@250-LO-IN', 'HIT', hitFrame=3)
        run['T-log@250-HI-OUT'] = case('T-log@250-HI-OUT', 'CLEAR')
        c = checked(run, {})
        self.assertTrue(any('T-log@250-LO-IN' in f for f in c.failures))
        self.assertTrue(any('T-log@250-HI-OUT' in w for w in c.warnings))

    def test_hitch_turning_clear_into_hit_fails(self):
        run = healthy_run()
        run['H-J-LOG-TOP@f10+50ms'] = case('H-J-LOG-TOP@f10+50ms', 'HIT', hitFrame=20)
        self.assertTrue(any('H-J-LOG-TOP' in f for f in checked(run).failures))
        run['H-J-LOG-TOP@f10+50ms'] = case('H-J-LOG-TOP@f10+50ms', 'CLEAR')
        self.assertEqual(checked(run).failures, [])

    def test_course_must_clear(self):
        run = healthy_run()
        run['C-SEED-1'] = case('C-SEED-1', 'HIT', notes=['score 12', 'hit a log at 300'])
        self.assertTrue(any('C-SEED-1' in f for f in checked(run).failures))

    def test_pacing(self):
        with tempfile.TemporaryDirectory() as tmp:
            with open(os.path.join(tmp, 'device.json'), 'w') as fh:
                json.dump({'requestedFPS': 120, 'measuredFPS': 57.2, 'frames': 1000, 'droppedFrames': 30,
                           'simulator': False, 'model': 'iPhone', 'os': '26'}, fh)
            c = check.Checks()
            with contextlib.redirect_stdout(io.StringIO()):
                check.pacing(c, tmp)
            self.assertTrue(any('ran at 120 fps' in f for f in c.failures))
            self.assertTrue(any('dropped' in w for w in c.warnings))
            c = check.Checks()
            with contextlib.redirect_stdout(io.StringIO()):
                check.pacing(c, tmp, lenient=True)
            self.assertEqual(c.failures, [])
            self.assertTrue(any('ran at' in w for w in c.warnings))

    def test_failed_case_ids(self):
        run = healthy_run()
        exp = expected_for(run)
        run['J-LOG-TOP'] = case('J-LOG-TOP', 'HIT', hitFrame=9)
        run['L-2-CADENCE']['apexes'][2] = 130.0
        c = checked(run, exp)
        self.assertEqual(sorted(c.cases), ['J-LOG-TOP', 'L-2-CADENCE'])

    def test_expected_files_are_clean(self):
        for name in ('expected.json',):
            with open(os.path.join(HERE, name)) as fh:
                cases = json.load(fh)['cases']
            self.assertTrue(cases)
            self.assertFalse([k for k, v in cases.items() if v['outcome'] in ('FLAKY', 'NOSCENE', 'NOGROUND')])


# --- The source reader and the gate ---------------------------------------------------

def world_with(file, old, new, count=1):
    def edit(f, text):
        if f != file:
            return text
        if text.count(old) < 1:
            raise AssertionError(f'{old!r} not in {file}')
        return text.replace(old, new, count)
    return load_world(ROOT, edit)


def gate_on(world):
    g = gate.Gate()
    now = gate.snapshot(world)
    gate.safety(g, world, now['timing'])
    changes = gate.baseline(g, now, gate.BASELINE)
    return g, changes


class Source(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.world = load_world(ROOT)

    def test_reads_known_numbers(self):
        w = self.world
        self.assertAlmostEqual(w.const('Layout.worldScale'), 0.8)
        self.assertAlmostEqual(w.const('Layout.jumpHeight'), 144.0)
        self.assertEqual(len(w.const('DogArt.jumpLifts')), w.jump_frames)
        self.assertAlmostEqual(w.gravity, 1350.0)
        self.assertAlmostEqual(w.airtime, 0.9238, places=3)
        self.assertEqual(w.pieces['bush'].shape, 'disc')
        self.assertEqual(w.pieces['occupiedBench'].image, w.pieces['bench'].image)
        # Same-named constants in different types stay apart.
        self.assertNotEqual(w.const('ObstacleArt.clearance'), w.const('Cliff.clearance'))

    def test_bench_is_sized_from_duck_clearance(self):
        w = self.world
        bench = w.pieces['bench']
        underside = bench.low * bench.solid['base'] - (bench.sink - w.const('Layout.dogPlantDepth'))
        self.assertAlmostEqual(underside, w.const('Layout.duckClearance'), places=3)

    def test_renamed_constant_is_named(self):
        with self.assertRaises(SourceError) as e:
            world_with('GameArt.swift', 'static let jumpLifts', 'static let jumpFloorLifts')
        self.assertIn('DogArt.jumpLifts', str(e.exception))

    def test_unreadable_expression_is_named(self):
        with self.assertRaises(SourceError):
            world_with('GameLayout.swift', 'static let jumpHeight: CGFloat = 180 * worldScale',
                       'static let jumpHeight: CGFloat = someFunction(180)')


class Gate(unittest.TestCase):
    def test_current_source_passes(self):
        g, changes = gate_on(load_world(ROOT))
        self.assertEqual(g.failures, [])
        self.assertEqual(changes, [])

    def test_any_number_change_fails_the_baseline(self):
        g, changes = gate_on(world_with('ObstacleArt.swift', 'static let heightJitter: CGFloat = 0.04',
                                        'static let heightJitter: CGFloat = 0.05'))
        self.assertTrue(any('baseline' in f for f in g.failures))
        self.assertEqual([k for k, _, _ in changes], ['source.constants.ObstacleArt.heightJitter'])

    def test_a_lift_out_of_the_body_fails(self):
        g, _ = gate_on(world_with('GameArt.swift', '0.213', '0.900'))
        self.assertTrue(any('box lifts stay' in f for f in g.failures))

    def test_missing_lift_fails(self):
        g, _ = gate_on(world_with('GameArt.swift', '            0.067,   // jump_9  settling      4.8pt\n', ''))
        self.assertTrue(any('one box lift per jump frame' in f for f in g.failures))

    def test_tall_slide_box_fails(self):
        g, _ = gate_on(world_with('GameArt.swift', '0.391', '0.560'))
        self.assertTrue(any('ducked box' in f for f in g.failures))

    def test_shrunk_window_is_called_out(self):
        # Less clearance: every prop is solved taller, every window tighter.
        g, _ = gate_on(world_with('ObstacleArt.swift', 'static let clearance: TimeInterval = 0.15',
                                  'static let clearance: TimeInterval = 0.08'))
        self.assertTrue(any('shrank by more than a frame' in f for f in g.failures))
        self.assertTrue(any('at least 130 ms to jump' in f for f in g.failures))

    def test_cliff_rule(self):
        # Today the 170pt cap binds at every speed; lift it and ask for less
        # clearance, and the gaps grow until the rule fires.
        def edit(f, text):
            if f == 'ObstacleArt.swift':
                text = text.replace('static let clearance: TimeInterval = 0.21', 'static let clearance: TimeInterval = 0.10')
                text = text.replace('static let maxGapWidth: CGFloat = 170', 'static let maxGapWidth: CGFloat = 400')
            return text
        g, _ = gate_on(load_world(ROOT, edit))
        self.assertTrue(any('cliff' in f for f in g.failures))

    def test_model_matches_lab_within_a_few_points(self):
        """The model's windows sit within ~8pt of what the lab measured on a
        simulator (plan.json), so it is modelling the same thing."""
        with open(os.path.join(HERE, 'plan.json')) as fh:
            plan = json.load(fh)
        jumps = report(load_world(ROOT))['jumps']
        for key, row in jumps.items():
            lab = plan[key]
            self.assertLess(abs(row['lo'] - lab['winLo']), 8, key)
            self.assertLess(abs(row['hi'] - lab['winHi']), 8, key)


if __name__ == '__main__':
    unittest.main(verbosity=1)
