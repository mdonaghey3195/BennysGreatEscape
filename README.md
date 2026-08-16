# Benny's Great Escape

A one-thumb endless runner for iPhone. Benny gallops, you tap to jump, the logs
and bushes keep coming and the world speeds up until you clip one.

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
| `GameScene.swift` | The game — world, physics, obstacles, scoring |

Everything except Benny is drawn in code: the gradient sky, the parallax clouds
and hills, the scrolling turf, the logs and bushes. The only artwork in the
asset catalogue is Benny himself.

### Animation

Two sets of frames, both loaded by probing `benny_run_0…`, `benny_jump_0…`
until a name is missing — so adding frames is a pure asset drop with no code
change.

Both sets share **one canvas**, which matters more than it sounds:

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
