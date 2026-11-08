# Hitbox Lab

A DEBUG-only harness (`BennysGreatEscape/HitboxLab.swift`) that stages obstacles at exact lead distances, fires the game's own jump or slide, measures Benny's real physics box every frame, and saves annotated screenshots. These tools turn it into a regression check.

## Run the validation

```bash
Tools/hitbox-lab/validate.sh
```

Builds the app, boots the iPhone 17 Pro Max simulator, runs all 104 cases (about 6 minutes) and checks them against `expected.json`. Exits 0 on pass, 1 on a failed check, 2 if the run itself couldn't happen. Leave the Mac alone while it runs: the lab counts frames, and dropped frames can move a hit by one.

| Option | What it does |
| --- | --- |
| `--only J-LOG` | Run only cases whose ID starts with this; only those are checked |
| `--device "iPhone 16 Pro"` | Use another simulator |
| `--record` | Accept this run as the new `expected.json` |
| `--on-device [name]` | Run on a connected iPhone instead (the first one, or the one named) |
| `--fps 120` | Ask for 120 Hz (Debug builds only; checks invariants only until `expected-120hz.json` exists) |
| `--screenshots` | On a device, also copy the screenshots off the phone (slow) |
| `--expected FILE` | Check against a different expected file |
| `--timeout 1800` | Seconds to wait for the run (default 1200) |

Results, screenshots (`*_full.png`, `*_zoom.png`) and the build log go to `build/hitbox-lab/<timestamp>/`.

## On your iPhone

```bash
Tools/hitbox-lab/validate.sh --on-device              # 60 fps, as the game runs today
Tools/hitbox-lab/validate.sh --on-device --fps 120    # what 120 Hz would do to the hitboxes
```

The phone needs to be paired with this Mac (USB or the same Wi-Fi), unlocked, with Developer Mode on. Low Power Mode off and plugged in is best. The lab keeps the screen awake for the run. Results are copied back to `build/hitbox-lab/<timestamp>/validate/`; screenshots stay on the phone unless you pass `--screenshots`.

At 60 fps a phone should match the simulator's `expected.json` exactly. If it doesn't, that's the finding. The game doesn't ask for 120 Hz today (there's no `CADisableMinimumFrameDurationOnPhone`), so `--fps 120` is a preview. Debug builds carry that Info.plist key so the lab can ask for 120; normal play still runs at SpriteKit's default of 60. Every frame count the lab uses is scaled by the frame rate, so a 120 Hz trial waits the same real time as a 60 Hz one.

Every run writes `device.json`: model, iOS version, the frame rate asked for and measured, dropped frames, longest frame, Low Power Mode and thermal state. The check fails if the run achieved under 90% of the frame rate it asked for, and warns on more than 1% dropped frames, Low Power Mode, or thermal throttling.

## What is checked

- **Golden outcomes:** every case's outcome matches `expected.json`. A hit must land within one frame of where it used to; a one-frame drift is a warning, more is a failure. This keeps the fixed phantom hits fixed and the real hits real.
- **Invariants:**
  - only the box's floor ever moves, and only upward;
  - back-to-back jumps reach the same apex (within 2pt);
  - mid-air swipes never give a second jump;
  - a jump keeps its jump poses and box lifts in flight, including on the touchdown frame and out of a slide;
  - a landing sinks no more than 3pt and bounces no more than 6pt;
  - no flaky cases.

## Changing the hitbox on purpose

When a change is meant to move results:

1. Run `validate.sh` and read the failures.
2. Look at the screenshots for the cases that changed.
3. If the new behaviour is right, run `validate.sh --record` and commit the new `expected.json` with the change.

The cases run at the lead distances in `plan.json`, which came from sweeping master and `feature/hitbox-improvements`. To re-derive them, run sweeps on two builds (`-HitboxLab sweep -LabBuild before|after`) and use `plan.py`. `report.py` builds a side-by-side HTML report of two builds' runs.

## Files

| File | Purpose |
| --- | --- |
| `validate.sh` | Build, run and check, in one command |
| `check.py` | The checks; standard-library Python, runs anywhere |
| `expected.json` | Expected outcome and hit frame for every case |
| `plan.json` | The lead distances the boundary cases run at |
| `plan.py`, `report.py` | Re-derive `plan.json` from sweeps; compare two builds in HTML |
