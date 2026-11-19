"""Report on the courses that were actually played.

    check_playthroughs.py RUN_DIR

Reads every results.jsonl under the run directory — one per simulator — and
says which courses the bot played through and which it died on. A course the
bot fails is not proof of an unfair course; it is a place to look, and the
note on the row says where.
"""
import glob
import json
import os
import sys


def main(run_dir):
    rows = []
    for path in sorted(glob.glob(os.path.join(run_dir, '*', 'results.jsonl'))):
        where = os.path.basename(os.path.dirname(path))
        for line in open(path):
            line = line.strip()
            if not line:
                continue
            r = json.loads(line)
            if r.get('id', '').startswith('C-'):
                r['where'] = where
                rows.append(r)
    if not rows:
        print('no course results under', run_dir)
        return 1

    cleared = [r for r in rows if r['outcome'] == 'CLEAR']
    failed = [r for r in rows if r['outcome'] != 'CLEAR']
    print(f'{len(rows)} courses played for real')
    print(f'  played through: {len(cleared)}')
    print(f'  ended early:    {len(failed)}')
    for r in rows[:3] + ([] if len(rows) <= 3 else []):
        notes = r.get('notes') or []
        if notes:
            print(f"  e.g. {r['id']}: {notes[0]}")
            break
    for r in failed:
        notes = r.get('notes') or []
        print(f"  {r['id']} ({r['where']}): {r['outcome']}" + (f" — {'; '.join(notes)}" if notes else ''))
    warnings = [(r['id'], n) for r in rows for n in (r.get('notes') or [])[1:]]
    if warnings:
        print(f'  {len(warnings)} notes worth a look:')
        for cid, n in warnings[:10]:
            print(f'    {cid}: {n}')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
