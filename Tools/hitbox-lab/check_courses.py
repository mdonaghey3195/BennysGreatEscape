"""Check the courses the spawner generated.

    check_courses.py courses.jsonl

Reads the audit's record of every obstacle in every course — see
`HitboxLab.auditCourses` — and asks of each one the questions a player would:
can it be jumped, can it be ducked under, and is there room to recover between
it and the next. The constants come from the Swift source through
`hitbox_source`, so the thresholds follow the game rather than a copy of it.

Exits 1 if any course fails.
"""
import json
import os
import sys
from collections import Counter, defaultdict

from hitbox_source import load_world

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))


def main(path):
    world = load_world(ROOT)
    c = world.const
    airtime = world.airtime
    dog_w, dog_h = world.dog_size
    duck_box = dog_h * c('DogArt.slideHeightFraction')
    # What `obstacleHeight` solves for, and what a jump needs to be worth
    # taking at all. A spawn under the floor is one the player cannot time.
    wanted_slack = c('ObstacleArt.clearance')
    floor_slack = 0.5 * wanted_slack
    # The ground an obstacle must leave the next: land, find the feet, act.
    recovery = c('ObstacleArt.pairRecovery')

    courses = [json.loads(line) for line in open(path) if line.strip()]
    if not courses:
        print('no courses in', path)
        return 1

    failures = []          # (seed, message)
    warnings = []
    slacks = []
    gaps = []
    pieces = Counter()
    verbs = Counter()
    worst = {}

    for course in courses:
        seed = course['seed']
        spawns = course['spawns']
        if course['stalled']:
            failures.append((seed, f"stalled at score {course['score']} after {course['frames']} frames"))
        if not spawns:
            failures.append((seed, 'no obstacles at all'))
            continue

        for s in spawns:
            pieces[s['piece']] += 1
            verbs[s['verb']] += 1
            if s['verb'] == 'jump':
                slacks.append(s['slack'])
                if s['slack'] < floor_slack:
                    failures.append((seed, f"{s['piece']} at score {s['score']} gives only "
                                           f"{1000 * s['slack']:.0f} ms to jump it"))
                elif s['slack'] < wanted_slack * 0.95:
                    warnings.append((seed, f"{s['piece']} at score {s['score']} gives "
                                           f"{1000 * s['slack']:.0f} ms"))
            elif s['verb'] == 'duck':
                if s['underGap'] <= duck_box:
                    failures.append((seed, f"{s['piece']} at score {s['score']} leaves "
                                           f"{s['underGap']:.1f}pt under it, less than Benny ducked "
                                           f"({duck_box:.1f}pt)"))
            elif s['verb'] == 'cliff':
                if s['slack'] < floor_slack:
                    failures.append((seed, f"cliff at score {s['score']} is {s['width']:.0f}pt wide, "
                                           f"{1000 * s['slack']:.0f} ms of airtime to spare"))

        # Back-to-back spacing. Obstacles are nearly all spawned at the same
        # x and separated by the time between spawns, so where a piece sits on
        # the ground is `x + scroll` — see `LabSpawn.scroll`.
        for a, b in zip(spawns, spawns[1:]):
            ground = ((b['x'] + b['scroll']) - b['width'] / 2) - ((a['x'] + a['scroll']) + a['width'] / 2)
            seconds = ground / b['speed']
            gaps.append(seconds)
            if ground < 0:
                failures.append((seed, f"{a['piece']} and {b['piece']} overlap at score {b['score']}"))
            elif seconds < recovery:
                failures.append((seed, f"{a['piece']} into {b['piece']} at score {b['score']}: "
                                       f"{1000 * seconds:.0f} ms between them, under the "
                                       f"{1000 * recovery:.0f} ms the game allows a pair"))
            if seconds < worst.get('gap', (1e9,))[0]:
                worst['gap'] = (seconds, seed, f"{a['piece']} into {b['piece']}")

    jump_slacks = sorted(slacks)
    gaps_sorted = sorted(gaps)

    def pct(xs, p):
        return xs[min(len(xs) - 1, int(p * len(xs)))] if xs else 0

    print(f'{len(courses)} courses, {sum(len(x["spawns"]) for x in courses)} obstacles')
    print(f'  scores reached: {min(x["score"] for x in courses)}–{max(x["score"] for x in courses)}')
    print('  pieces: ' + ', '.join(f'{n} {k}' for k, n in pieces.most_common()))
    print('  verbs:  ' + ', '.join(f'{n} {k}' for k, n in verbs.most_common()))
    if jump_slacks:
        print(f'  jump timing, ms:  min {1000 * jump_slacks[0]:.0f}  '
              f'1% {1000 * pct(jump_slacks, 0.01):.0f}  '
              f'median {1000 * pct(jump_slacks, 0.5):.0f}  '
              f'(solved for {1000 * wanted_slack:.0f})')
    if gaps_sorted:
        print(f'  gap to the next, ms:  min {1000 * gaps_sorted[0]:.0f}  '
              f'1% {1000 * pct(gaps_sorted, 0.01):.0f}  '
              f'median {1000 * pct(gaps_sorted, 0.5):.0f}  '
              f'(floor {1000 * recovery:.0f})')
    if 'gap' in worst:
        s, seed, what = worst['gap']
        print(f'  tightest pair: {what} at {1000 * s:.0f} ms, seed {seed}')

    if warnings:
        by_seed = defaultdict(list)
        for seed, msg in warnings:
            by_seed[seed].append(msg)
        print(f'\n  {len(warnings)} warnings across {len(by_seed)} courses (timing under what the solve aims for)')
        for seed, msgs in list(by_seed.items())[:5]:
            print(f'    seed {seed}: {msgs[0]}')

    if failures:
        by_seed = defaultdict(list)
        for seed, msg in failures:
            by_seed[seed].append(msg)
        print(f'\nCOURSE AUDIT FAILED: {len(failures)} problems in {len(by_seed)} of {len(courses)} courses')
        for seed, msgs in list(by_seed.items())[:20]:
            print(f'  seed {seed}: {msgs[0]}' + (f' (and {len(msgs) - 1} more)' if len(msgs) > 1 else ''))
        return 1

    print(f'\nCOURSE AUDIT PASSED: {len(courses)} courses, no unfair spawns')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else 'courses.jsonl'))
