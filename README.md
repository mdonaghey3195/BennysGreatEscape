# Benny's Great Escape

A one-thumb endless runner for iPhone. A man walks his beagle across the park, a
rabbit breaks cover, and the leash doesn't hold — after which Benny gallops, you
swipe to jump and duck, the logs and bushes keep coming and the world speeds up
until you clip one.

Started life as a hidden easter egg inside PawTrack — triple-tapping the dog on
the welcome screen — and outgrew it.

## Building

```
xcodebuild -project BennysGreatEscape.xcodeproj -scheme BennysGreatEscape \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

iOS 17+, iPhone, portrait. No dependencies — SwiftUI and SpriteKit only.

## How it's put together

| File | What it does |
| --- | --- |
| `BennysGreatEscapeApp.swift` | `@main`, hands off to `GameView` |
| `GameView.swift` | Hosts the scene, the score, and the title overlay |
| `TitleView.swift` | Title card; the live scene runs behind it |
| `GameScene.swift` | The game — the opening clip, world, physics, obstacles, scoring |
| `Art/SliceIntroSheets.swift` | Cuts the opening clip's two sheets into frames |

The world is drawn in code: the gradient sky, the parallax clouds and hills, the
scrolling turf. Everything you actually play against is painted and lives in the
asset catalogue — Benny, the things he jumps, and the opening clip.

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
