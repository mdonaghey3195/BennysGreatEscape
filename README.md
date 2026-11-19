# Benny's Great Escape

A 2D IOS Game

## Checking performance on a phone

The game is tuned so nothing is decoded or handed to the GPU mid-run: every
animation is packed into a sprite atlas, and `ArtWarmer` loads each stage's
art before the stage arrives. If a run still stutters, check these in order.

1. **Build Release.** The scheme's Run action is a Debug build with Swift
   optimisation off. Test on the phone through TestFlight, or with Product →
   Profile, which builds Release. Only the Profile and Archive actions do.
2. **Low Power Mode off, phone cool.** Both throttle the CPU and GPU and look
   exactly like a slow game.
3. **Watch the frame rate in the game.** Add `-ShowStats` to the scheme's
   arguments (Edit Scheme → Run → Arguments) for SpriteKit's own frame rate,
   draw count and node count in the corner. Debug builds only.
4. **Log the hitches.** Add `-LogHitches` to the scheme's arguments and play
   from Xcode; works in Release too (Edit Scheme → Run → Build Configuration).
   Every frame over 50 ms prints a `HITCH` line to the console with the score,
   what Benny was doing, what had just happened (a jump, a landing, a spawn),
   which obstacles were on screen and which art stages had finished loading.
   `NOTE` lines give the timeline those sit in, and `PROBE` lines time the
   few calls that have stalled a frame before. That turns "it sometimes
   pauses" into a list.
5. **Let it play itself.** Add `-AutoPlay` as well (Debug builds) and the
   game taps Play, jumps and slides by a crude rule, and retries after a
   crash — so the whole opening can be watched for hitches in the simulator
   with nobody at the screen. The November 2026 pass used exactly this: the
   first landing's dust puff, the HUD's first layout, sound playback on the
   main thread and Game Center's sign-in each showed up as a `HITCH` line
   and were fixed one at a time.
6. **Instruments.** Product → Profile, then the Animation Hitches template, and
   play one run through to the dog house. A hitch that lines up with the first
   jump, first slide, a cliff or the launch means something is loading late —
   see `ArtWarmer` in `GameArt.swift` for what is loaded when.
7. **Memory.** Xcode's Debug navigator gauge should settle a little over
   100 MB during a run and climb once for the launch and once for the flight.

Benny's frames ship at 640 px wide, down from the 1259 px they are drawn at;
`Art/benny_fullres/README.md` has the originals and how to put them back.

## Testing hitboxes

`Tools/hitbox-lab/validate.sh` checks that collisions still behave the way they should. It builds the app, runs Benny through a few hundred staged jumps, slides and landings in the iOS simulator or on your iPhone, and compares the results with recorded expectations. It ends with `HITBOX VALIDATION PASSED` or `FAILED` and exits 0 or 1. Run it before merging anything that touches the hitbox, obstacle sizes, jump physics or the spawner.

### You'll need

- A Mac with Xcode, including its command-line tools (`xcode-select --install` if `xcodebuild` isn't found)
- The iPhone 17 Pro Max simulator, or another one named with `--device`
- For phone runs: an iPhone paired with this Mac over USB or Wi-Fi, unlocked, with Developer Mode on (Settings → Privacy & Security) and Low Power Mode off

### Run it

From the repo folder:

```bash
Tools/hitbox-lab/validate.sh              # everything in the simulator, about 20 minutes
Tools/hitbox-lab/validate.sh --quick      # the core 104 cases only, about 6 minutes
```

On a connected iPhone:

```bash
Tools/hitbox-lab/validate.sh --on-device              # at 60 fps, as the game runs
Tools/hitbox-lab/validate.sh --on-device --fps 120    # preview of 120 Hz (Debug builds only)
```

Leave the Mac alone while it runs. The lab counts frames, and a busy machine that drops frames can move a hit by one.

| Option | What it does |
| --- | --- |
| `--quick` | Only the core cases (J, D and L) |
| `--only J-LOG,T-log` | Only cases whose ID starts with one of these |
| `--device "iPhone 16 Pro"` | Use a different simulator |
| `--on-device [name]` | Run on a connected iPhone (the first one, or the one named) |
| `--fps 120` | Ask for 120 Hz; checks the always-true rules only until a 120 Hz baseline is recorded |
| `--screenshots` | On a phone, also copy the screenshots back (slow) |
| `--record` | Accept this run as the new expected results |
| `--timeout 3600` | Seconds to wait for the run before giving up |

### Read the result

Each `FAIL` line names a case and what went wrong. `warn` lines are worth a look but don't fail the run; a hit landing one frame from where it used to is normal timing noise. Results, screenshots and the build log go to `build/hitbox-lab/<timestamp>/`. The screenshots show Benny's physics box in cyan and the obstacle's in magenta at the moment that decided the case.

| Case family | What it covers |
| --- | --- |
| J | Every jump prop, hit on every side: early, late, over the top, barely hitting and barely missing |
| D | Bench, occupied bench and swingset: standing, sliding early or late, jumping out of a slide |
| L | Landing, back-to-back jumps, mid-air swipes, jumping on touchdown, crash and retry, cliffs |
| T | Each prop's clear window at every speed tier, one frame either side of each edge |
| H | Jumps and slides with the game frozen 50 or 100 ms partway through |
| C | Whole generated courses, from fixed seeds, played by a bot to score 50 |

### When a change is meant to move results

1. Run the script and read the failures.
2. Open the screenshots for the cases that changed.
3. If the new behaviour is right, run it again with `--record` and commit the updated `Tools/hitbox-lab/expected.json` with your change.

Then run `python3 Tools/hitbox-lab/gate.py --update-baseline` and commit `Tools/hitbox-lab/hitbox-baseline.json` as well.

### In CI

Every push and pull request runs the **Hitbox gate** on GitHub's Linux runners. It reads the hitbox numbers from the Swift source, checks the timing every obstacle gives, and fails on any change until `hitbox-baseline.json` is updated. To also run the simulator cases on a hosted Mac, add the `run-simulator` label to the pull request.

[Tools/hitbox-lab/README.md](Tools/hitbox-lab/README.md) has the details: every check, how the course bot plays, and how to re-derive the test distances from fresh sweeps.
