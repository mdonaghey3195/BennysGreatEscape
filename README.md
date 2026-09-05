# Benny's Great Escape

A one-thumb endless runner for iPhone. A man walks his beagle across the park, a
rabbit breaks cover, and the leash doesn't hold — after which Benny gallops, you
swipe to jump and duck, the logs and bushes keep coming, the swingsets keep
making you slide, and the world speeds up until you clip one.

Started life as a hidden easter egg inside PawTrack — triple-tapping the dog on
the welcome screen — and outgrew it.

## Building

```
xcodebuild -project BennysGreatEscape.xcodeproj -scheme BennysGreatEscape \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

iOS 17+, iPhone, portrait. No dependencies — SwiftUI and SpriteKit only.

## Game Center

The leaderboard is Game Center's, not ours — there is no server and no database
here. It needs setting up once in App Store Connect, and until that is done the
board screen says *"The leaderboard isn't open yet"*, which is
`Leaderboard.Failure.notConfigured` and means Game Center returned nothing for
our ID.

Under the app record for `donaghey.BennysGreatEscape`, in **Services > Game
Center**, add a single (classic) leaderboard:

| Field | Value |
| --- | --- |
| Leaderboard ID | `benny.bestrun` — must match `Leaderboard.id` exactly |
| Score Format Type | Integer |
| Sort Order | High to Low |
| Score Submission Type | Best Score |

Then **add a localization**. This is the step that gets missed: a leaderboard
with no localization is never published, and GameKit reports it as though it
does not exist — indistinguishable, from the client, from a typo in the ID.

Development builds talk to the Game Center sandbox, so test on a device with the
app freshly installed. New leaderboards take a few minutes to propagate.

When it fails, the raw error is logged — the one thing that says whether the ID
resolved to nothing or the app is unknown to Game Center entirely. Run from
Xcode and read the console, or off a plugged-in phone:

```
log stream --device --predicate 'subsystem == "donaghey.BennysGreatEscape"'
```

## How it's put together

| File | What it does |
| --- | --- |
| `BennysGreatEscapeApp.swift` | `@main`, hands off to `GameView` |
| `GameView.swift` | Hosts the scene, the score, and the title overlay |
| `TitleView.swift` | Title card; the live scene runs behind it |
| `GameScene.swift` | The game — the opening clip, world, physics, obstacles, scoring |
| `Leaderboard.swift` | Game Center behind one object; nothing else imports GameKit |
| `LeaderboardView.swift` | The top hundred, drawn to match the About page |
| `Art/SliceIntroSheets.swift` | Cuts the opening clip's three sheets into frames |
| `Art/CropBackground.swift` | Finds the loop in the painted background and cuts it |
| `Art/CutSwingset.swift` | Keys the swingset, shortens its chains and cuts its swings off it |

Everything you see is painted and lives in the asset catalogue — Benny, the
things he jumps, the opening clip, and the world itself. The world used to be
drawn in code, a gradient sky with circles for clouds and hills over a green
slab, and `Art/CropBackground.swift` is what replaced it: see below.

### The background

The world scrolls as one painted image, laid end to end with itself. Which only
works if the crop is exactly one repeat of the painting and taken from the right
place — so neither is typed in. `Art/CropBackground.swift` slides the source
over itself to find the length of its repeat (1624px, a clear minimum rather
than a tie), then asks which offset joins most cleanly at that length. It
matters: the best offset scores 0.86 and the worst 10.95, and the worst is a
hill with a notch in it that goes past every few seconds.

It draws in two layers, cut through a row of flat sky where the two edges match
to within three parts in 255 — so they can travel at different speeds with
nothing at the join to give it away. The land has to move at exactly the speed
of the world, because Benny's stride is tied to that speed and turf that
disagrees puts him on a treadmill. The sky is under no such obligation and
drifts.

The script prints the fractions the scene is staged by — where the grass line
falls, where the split is — so repainting the background is a rerun and a paste
rather than a re-measure.

### The opening

Play doesn't drop straight into a run. A ~3 second clip says why Benny is
running — a man out walking him, a rabbit up ahead, and the leash going — and it
plays *inside* the scene, same sky, same hills, same turf, so there is nothing
to cut to when it ends. What ends it is the artwork handing over: on the last
frame that still draws the dog, Benny fades up on top of that drawing, in the
same place and at the same size and both standing still, so the dissolve reads
as one dog rather than two; then the drawing goes, the world starts moving under
him, and he grows into his own size as the camera closes on him. A tap skips it.
It plays on every Play and never on a retry, which falls out of `hasStarted`
surviving `restart` and not `returnToTitle`.

The two source sheets live in `Art/`, and `swift Art/SliceIntroSheets.swift`
cuts them. Neither arrived usable: both have the background *painted* rather
than carried in an alpha channel, and the man-and-dog sheet only looks like a
row of cells — the pairs are drawn at their own spacing, and through the walk
each dog's nose reaches back past where the next man's trailing heel starts, so
no set of straight cuts separates all nineteen frames. The script finds them by
what is joined to what instead, and keys the background by flooding inward from
the border so that white *enclosed* by a drawing — Benny's chest, the man's
shirt — survives. Joined-to-what also decides what a frame *contains*: while the
leash is in the man's hand it joins him to the dog and the two come back as one
figure, and only once it slips are there a dog and a dropped leash to tell apart
from him. It prints the handful
of fractions `IntroArt` is built from, so re-cutting a redrawn sheet reprints
the numbers to paste back.

### The swingset

There are two obstacles you duck under and they are sized the same way, from
`Layout.duckClearance` rather than by eye: whatever else is true, the underside
of a bench seat and the underside of a swing seat both have to land 52pt above
the turf, which is below Benny's running box and above his ducked one. Retuning
the one number retunes both drawings.

Which is why `Art/CutSwingset.swift` exists. Sizing a duck obstacle from the
clearance means that where the seat sits *within the drawing* is what sets the
drawing's scale, and the swingset arrived with the seats 26% up it — enough to
render the frame at 446x198pt on a 400pt scene, wider than the screen and close
enough to the next obstacle at the spawn floor to touch it. Nothing was wrong
with the picture; there was just more chain in it than the game had room for. So
the script splices a band out of the free-hanging run until the frame comes out
at 110pt, which the join survives because a chain is the same all the way down.

It also keys the drawing — the only obstacle that arrived on a painted
background rather than on alpha — and cuts the swings off the frame as a second
sprite, hung back on at both hangers so they can rock while the A-frame stands
still. They rock six degrees, which is not a look but a limit: the physics box
is measured with the seats at rest, and six degrees moves a seat five points
sideways while *raising* it a quarter of one, and raising it can only ever open
the gap Benny slides through. As with the other scripts, the fractions
`ObstacleArt` needs are measured and printed rather than typed in.

### Animation

Three sets of frames — run, jump and slide — plus the clip's two, all loaded by
probing `benny_run_0…`, `intro_walk_0…` until a name is missing, so adding
frames is a pure asset drop with no code change.

Each set shares **one canvas**, which matters more than it sounds:

- The sprite renders every texture at one fixed size, so frames drawn at
  different scales would make Benny visibly change size mid-jump. Each source
  sheet is normalised against the run frames' median silhouette area.
- Every frame is aligned on Benny's **collar**, a fixed-size landmark visible in
  every pose, so his body doesn't wander between frames.
- The sprite anchors at `groundLineFraction` — where his paws are when
  *running*, not the bottom of the canvas. The rear-up jump pose dangles well
  below that line, and anchoring at the canvas floor would leave him hovering as
  he ran.

The jump arc is stretched to fit `airtime`, derived from the same gravity and
jump height as the launch velocity, so retuning the jump can't leave him landing
three frames early.

### Tuning

The numbers worth playing with all live at the top of `GameScene.swift`:
`jumpHeight`, `gravity` in `didMove`, `gameSpeed` and its ramp, and the obstacle
size ranges.

## Credit

Benny is a real dog.
