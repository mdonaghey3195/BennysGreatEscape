# Hitbox Lab

A DEBUG-only harness (`BennysGreatEscape/HitboxLab.swift`) that stages obstacles at exact lead distances, fires the game's own jump or slide, measures Benny's real physics box every frame, and saves annotated screenshots. These tools turn it into a regression check.

## Run the validation

```bash
Tools/hitbox-lab/validate.sh
```

Builds the app, boots the iPhone 17 Pro Max simulator, runs every case (about 20 minutes; `--quick` runs the original 104 in about 6) and checks them. Exits 0 on pass, 1 on a failed check, 2 if the run itself couldn't happen. Leave the Mac alone while it runs: the lab counts frames, and dropped frames can move a hit by one.

| Option | What it does |
| --- | --- |
| `--quick` | Only the J, D and L families, about 6 minutes |
| `--only J-LOG,T-log` | Run only cases whose ID starts with one of these; only those are checked |
| `--device "iPhone 16 Pro"` | Use another simulator |
| `--record` | Accept this run as the new `expected.json` |
| `--on-device [name]` | Run on a connected iPhone instead (the first one, or the one named) |
| `--fps 120` | Ask for 120 Hz (Debug builds only; checks invariants only until `expected-120hz.json` exists) |
| `--screenshots` | On a device, also copy the screenshots off the phone (slow) |
| `--expected FILE` | Check against a different expected file |
| `--seeds 7,42` | Course seeds for the C cases instead of 1, 2 and 3 (replay a failure, or try new courses) |
| `--score 100` | Play each course to this score instead of 50 |
| `--ci` | As GitHub Actions runs it: a slow frame rate warns, and failed cases get one re-run before they count |
| `--timeout 1800` | Seconds to wait for each run (default 3600) |

Results, screenshots (`*_full.png`, `*_zoom.png`) and the build log go to `build/hitbox-lab/<timestamp>/`.

## On your iPhone

```bash
Tools/hitbox-lab/validate.sh --on-device              # 60 fps, as the game runs today
Tools/hitbox-lab/validate.sh --on-device --fps 120    # what 120 Hz would do to the hitboxes
```

The phone needs to be paired with this Mac (USB or the same Wi-Fi), unlocked, with Developer Mode on. Low Power Mode off and plugged in is best. The lab keeps the screen awake for the run. Results are copied back to `build/hitbox-lab/<timestamp>/validate/`; screenshots stay on the phone unless you pass `--screenshots`.

At 60 fps a phone should match the simulator's `expected.json` exactly. If it doesn't, that's the finding. The game doesn't ask for 120 Hz today (there's no `CADisableMinimumFrameDurationOnPhone`), so `--fps 120` is a preview. Debug builds merge that key in from `Debug-Info.plist` (it is not a build setting Xcode recognises) so the lab can ask for 120; normal play still runs at SpriteKit's default of 60. Every frame count the lab uses is scaled by the frame rate, so a 120 Hz trial waits the same real time as a 60 Hz one.

Every run writes `device.json`: model, iOS version, the frame rate asked for and measured, dropped frames, longest frame, Low Power Mode and thermal state. The check fails if the run achieved under 90% of the frame rate it asked for, and warns on more than 1% dropped frames, Low Power Mode, or thermal throttling.

## The cases

| Family | What it stages | Count |
| --- | --- | --- |
| J | Each jump prop at the opening speed, hit on every side: late, early, over the top, barely hitting and barely missing | 50 |
| D | Bench, occupied bench and swingset: standing, sliding early or late, jumping in, jumping out of a slide | 27 |
| L | Box audit, landing, back-to-back jumps, mid-air swipes, jumping or sliding on touchdown, crash and retry, cliffs | 27 |
| T | Each prop's clear window at every speed tier: one frame inside each edge, one outside, and the edge itself | 102 |
| H | Jumps and slides from J and D with the main thread stalled 50 or 100 ms partway through | 114 |
| C | Whole generated courses from seeds 1, 2 and 3, played by a bot to score 50 (past top speed) | 3 |

The course bot answers each obstacle at the middle of its window in seconds: 0.47 s out for a jump prop, 0.54 s for a slide, half a jump for a cliff. A jump waits until any bench Benny is under has gone by. The spawner's rolls come from `SpawnDice`, which is the system's randomness in normal play and a fixed sequence only when the lab seeds it, so a failing seed replays the identical course.

## What is checked

- **Golden outcomes:** every case's outcome matches `expected.json`. A hit must land within one frame of where it used to; a one-frame drift is a warning, more is a failure. This keeps the fixed phantom hits fixed and the real hits real.
- **Invariants:**
  - only the box's floor ever moves, and only upward;
  - back-to-back jumps reach the same apex (within 2pt);
  - mid-air swipes never give a second jump;
  - a jump keeps its jump poses and box lifts in flight, including on the touchdown frame and out of a slide;
  - a landing sinks no more than 3pt and bounces no more than 6pt;
  - no flaky cases.
- **Speed tiers (T):** one frame inside either edge of a window must clear, or the window has shrunk. Clearing one frame outside warns that it grew; the edge itself only warns if it changes.
- **Hitches (H):** a stall must never turn a clear into a hit. Each H case is compared with the J or D case it copies.
- **Courses (C):** every course plays through to score 50 with no hit and no fall. The summary line lists what came up and how fast it got.

## In GitHub Actions

Two workflows, in `.github/workflows/`:

| Workflow | Runs | What it does |
| --- | --- | --- |
| Hitbox gate (`ci-linux.yml`) | Every push and pull request, on Linux, about a minute | Tests these tools, then `gate.py` |
| Hitbox lab (`ci-simulator.yml`) | Pull requests labelled `run-simulator`, or by hand | `validate.sh --quick --ci` on a hosted Mac (Xcode 26.6, iPhone 17 Pro Max simulator), plus a Release build |

**The gate** needs no Mac. `hitbox_source.py` reads every collision number straight from the Swift source (box fractions, jump lifts, prop solids and height clamps, gravity, the jump arc's weights, cliff and spawn constants) and the image sizes from `Assets.xcassets`. `timing_model.py` solves each prop's height the way `obstacleHeight` does and works out the lead distances a jump or slide clears it from. `gate.py` then fails if:

- a box lift is missing, negative or taller than the body, or there isn't one per jump frame;
- the ducked box doesn't fit under a bench or swingset with 4pt to spare;
- any prop at any speed tier, or any slide, gives under 130 ms of timing;
- a cliff gives under 150 ms, or the quickest spawn interval is shorter than a jump;
- **any hitbox number differs from `hitbox-baseline.json`**. A window that shrank by more than a frame is called out separately.

The model has no frames and no Box2D skin, so its windows run a few points wider than the lab measures; the tests hold it within 8pt of `plan.json`. It can't see changes to how the Swift *uses* those numbers. That's what the simulator run is for.

```bash
python3 Tools/hitbox-lab/gate.py                     # what CI runs
python3 Tools/hitbox-lab/gate.py --update-baseline   # accept a deliberate change
python3 Tools/hitbox-lab/test_hitbox_tools.py        # the tools' own tests
```

**The simulator run** is on trial: label a pull request `run-simulator` to run it. Hosted Macs are shared and virtualised, so `--ci` doesn't fail on a low frame rate (frame counts stay exact; only hitches and pacing notice) and re-runs any failed case once on its own; one that passes the second time is reported as flaky on CI. Results, screenshots and logs are attached to the run as the `hitbox-lab` artifact.

## Changing the hitbox on purpose

When a change is meant to move results:

1. Run `validate.sh` and read the failures.
2. Look at the screenshots for the cases that changed.
3. If the new behaviour is right, run `validate.sh --record` and commit the new `expected.json` with the change.
4. Run `gate.py --update-baseline` and commit `hitbox-baseline.json` too, or the Linux gate fails.

The cases run at the lead distances in `plan.json`, which came from sweeping master and `feature/hitbox-improvements`. To re-derive them, run sweeps on two builds (`-HitboxLab sweep -LabBuild before|after`) and use `plan.py`. `report.py` builds a side-by-side HTML report of two builds' runs.

## Files

| File | Purpose |
| --- | --- |
| `validate.sh` | Build, run and check, in one command |
| `check.py` | The checks; standard-library Python, runs anywhere |
| `expected.json` | Expected outcome and hit frame for every case |
| `plan.json` | The lead distances the boundary cases run at |
| `plan.py`, `report.py` | Re-derive `plan.json` from sweeps; compare two builds in HTML |
| `gate.py` | The Linux CI gate |
| `hitbox_source.py` | Reads the collision numbers from the Swift source |
| `timing_model.py` | Works out each obstacle's timing window from those numbers |
| `hitbox-baseline.json` | The numbers and windows the gate compares against |
| `test_hitbox_tools.py` | Tests for `check.py`, the source reader and the gate |
