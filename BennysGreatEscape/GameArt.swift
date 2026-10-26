//
//  GameArt.swift
//  Benny's Great Escape
//
//  What the artwork is, and the measurements taken off it.
//
//  Every one of these is a number read from a drawing rather than chosen, and
//  most name the script in `Art/` that prints it. Re-cut a sheet and the figures
//  here are what changes.
//
//  Nested inside `GameScene` rather than left at file scope. They were all
//  `private` when they lived in that file, and simply widening them would put
//  names as general as `Layout`, `Launch` and `Palette` into the module — where
//  `Palette` already means something else in `SettingsView`. Nested, the short
//  names still resolve everywhere they did before and nothing new is exported.
//

import SpriteKit
import SwiftUI
import UIKit

extension GameScene {


    // MARK: - Artwork

    /// Every animation in the game is a numbered run of images in the catalogue,
    /// collected until one is missing — so adding a frame is a pure asset drop with
    /// nothing here to change.
    ///
    /// Probed with `UIImage(named:)` rather than `SKTexture(imageNamed:)` because
    /// the latter hands back a placeholder for a missing name instead of nil, so it
    /// can't tell you where the frames stop.
    static func numberedTextures(_ prefix: String) -> [SKTexture] {
        var textures: [SKTexture] = []
        var index = 0
        while let image = UIImage(named: "\(prefix)_\(index)") {
            textures.append(SKTexture(image: image))
            index += 1
        }
        return textures
    }


    /// Benny, drawn side-on and facing right — the way he runs.
    enum DogArt {
        /// The run cycle: add `benny_run_6` and it joins the gallop on its own.
        static let frames: [SKTexture] = numberedTextures("benny_run")

        /// The jump arc — bound, rear up, two airborne poses, reach down, land.
        static let jumpFrames: [SKTexture] = numberedTextures("benny_jump")

        /// The slide — drop, slide, deep slide, recover.
        static let slideFrames: [SKTexture] = numberedTextures("benny_slide")

        /// Width / height of the drawing. The fallback only matters if the asset is
        /// missing entirely, in which case the placeholder block is drawn instead.
        static var aspect: CGFloat {
            guard let size = frames.first?.size(), size.height > 0 else { return 4.0 / 3.0 }
            return size.width / size.height
        }

        /// The physics body covers the part of the drawing that is Benny in *every*
        /// frame — the torso and head — found by intersecting the six **run**
        /// silhouettes. The legs sweep through a much larger envelope during a
        /// gallop and the tail sweeps behind; catching an obstacle with a trailing
        /// paw or the tail shouldn't end a run, while hitting one body-on still
        /// does.
        ///
        /// The offset is large because the canvas is sized to the fully extended
        /// poses, whose rear legs reach a long way back, leaving the body sitting
        /// well right of centre.
        ///
        /// **The run frames are not the whole story, and that is the limitation to
        /// understand before touching these.** There are six jump frames on the same
        /// canvas, and they throw the body diagonally: in the rising pose the box's
        /// leading edge sits hard against his front paw at the top and overhangs
        /// nothing but air at the bottom — 14 units of it three-quarters of the way
        /// down, 45 units at nine-tenths. Only 18% of this box is dog in all twelve
        /// poses.
        ///
        /// A better static shape can't fix that. Measured across all twelve poses
        /// together, the leading edge is already tight — within 0.3 units of what
        /// *some* pose reaches at almost every height. The box is not too big; one
        /// box cannot fit twelve silhouettes. The accurate fix is a body per pose,
        /// swapped with the animation, and that means replacing the physics body six
        /// times mid-flight with the velocity carried across each time.
        static let bodyWidthFraction: CGFloat = 0.729
        static let bodyHeightFraction: CGFloat = 0.599
        static let bodyOffsetXFraction: CGFloat = 0.091

        /// How far the leading edge is pulled back, as a fraction of the canvas.
        ///
        /// Forgiveness, and named as such rather than folded into the fractions
        /// above, because it is not a measurement of the drawing — it is a decision
        /// about how close a near miss may be before it counts. The fractions stay
        /// honest about what they measure and this says what was traded.
        ///
        /// It exists because of a run that ended at 87 with the stump plainly
        /// uncleared only by the box: his front paws were above its top and his
        /// hind legs behind it, the drawings never touched, and the lower leading
        /// corner of the box — empty in that pose — caught it.
        ///
        /// The cost is the other direction: a nose-first hit now needs this much
        /// more overlap before it registers. Eight units against a stump some ninety
        /// wide, which is the smallest amount that clears the case above with
        /// margin.
        static let forgivenessFraction: CGFloat = 0.08

        /// Where Benny's paws are when he's *running*, as a fraction up from the
        /// bottom of the canvas — the sprite's anchor, and what sits on the turf.
        ///
        /// Not the bottom of the canvas, because run and jump share one canvas and
        /// the rear-up pose's hind legs dangle well below the running paw line.
        /// Anchoring at the canvas floor would leave him hovering as he ran; this
        /// way that dangle simply hangs below the anchor, which is exactly where it
        /// belongs once the physics has lifted him.
        static let groundLineFraction: CGFloat = 0.263

        /// The ducked box, measured off the slide poses the same way. Notably the
        /// slide frames are aligned on the *ground* rather than the collar — a
        /// sliding dog's head drops, and pinning his collar to the running collar
        /// would cancel exactly the crouch that makes ducking work.
        ///
        /// 33pt tall against 55pt running, so a rail at `Layout.duckClearance` is
        /// hit standing and cleared sliding. Slightly narrower than the drawing, so
        /// a trailing paw brushing an obstacle doesn't end the run.
        static let slideWidthFraction: CGFloat = 0.80
        static let slideHeightFraction: CGFloat = 0.362
        static let slideOffsetXFraction: CGFloat = 0.030
    }


    // MARK: - The opening clip's artwork

    /// The frames of the clip that plays before a run: a man out walking Benny, and
    /// the rabbit that ends it.
    ///
    /// The fractions are measured off the sheets rather than typed in — they are
    /// what `Art/SliceIntroSheets.swift` prints when it cuts them, so re-cutting a
    /// redrawn sheet reprints the numbers to paste back here.
    enum IntroArt {
        /// Man, leash and dog together in one drawing, all nineteen aligned on the
        /// man's head so he holds his ground while the dog pulls away from him.
        ///
        /// They fall into four beats: 0–7 out for a walk, 8–11 Benny leaning into
        /// the leash, 12–16 the lunge that takes it out of the man's hand, and
        /// 17–18 the man alone, reaching after him and then diving. From frame
        /// seventeen the dog isn't drawn at all — that is where the game's own
        /// Benny takes over — though the slipped leash lying in the grass still is.
        static let walkFrames: [SKTexture] = numberedTextures("intro_walk")

        /// A gallop cycle, facing right, the way he runs off.
        static let rabbitFrames: [SKTexture] = numberedTextures("intro_rabbit")

        /// The same rabbit before anything has startled him: six poses of him
        /// grazing, which is what he is doing while the walk comes towards him.
        ///
        /// He used to hold a single pose of the gallop through the whole approach,
        /// and a rabbit sitting perfectly still in the grass reads as scenery — the
        /// shot wants something for Benny to have noticed.
        ///
        /// His own sheet, drawn at its own scale, so the two rabbits are matched by
        /// what they draw rather than by their canvases — see `Intro.grazeSize`.
        static let grazeFrames: [SKTexture] = numberedTextures("intro_graze")

        /// The pose the graze opens on and comes back to: sitting up, head clear of
        /// the grass. Also what he is holding when the clip is staged behind the
        /// title card, which is why it is the first frame and not a nibble.
        static var grazeStill: SKTexture? { grazeFrames.first }

        static let walkAspect: CGFloat = 1.646
        static let rabbitAspect: CGFloat = 1.464
        static let grazeAspect: CGFloat = 1.087

        /// Where the man's head sits across the drawing — the sprite's anchor, and
        /// so the point that stays put as the frames change under it.
        static let manCentreXFraction: CGFloat = 0.334

        /// Where his feet are, as a fraction up from the bottom of the canvas. Zero
        /// on this sheet: every pose is pinned by its own lowest foot, and no frame
        /// draws anything below the one it is pinned by.
        static let groundLineFraction: CGFloat = 0.000

        /// The drawn dog, measured on the handoff frame: how wide he is, and where
        /// he stands. The first sets the whole clip's scale, the second is where
        /// Benny is put when he takes the drawing's place.
        static let dogWidthFraction: CGFloat = 0.340
        static let dogCentreXFraction: CGFloat = 0.830

        /// The leftmost the drawing reaches while the man is still on his mark —
        /// his trailing foot at full stride. `Intro.manX` is set against it, which
        /// is the only way to put him as far left as the crop allows without
        /// guessing.
        ///
        /// Measured over the walk and the lunge only. The dive reaches the canvas
        /// edge itself, but it plays after the handoff, with the turf already
        /// carrying him out of shot.
        static let walkLeftFraction: CGFloat = 0.188

        /// How much of the rabbit's canvas the still pose actually fills.
        ///
        /// The canvas is the union of all six poses and the gallop stretches it a
        /// third wider than the sitting rabbit is, so sizing him by the canvas is
        /// sizing him by a pose he isn't in. The same trap `Layout.dogWidth`
        /// sidesteps by measuring Benny off his collar.
        static let rabbitStillWidthFraction: CGFloat = 0.616

        /// How tall the sitting rabbit stands in the graze canvas, and how tall the
        /// still pose stands in the gallop's. Between them they make one rabbit of
        /// two sheets drawn at two scales: `Intro.grazeSize` stretches the graze
        /// canvas until those two poses come out the same height.
        ///
        /// Height and not width, because he is the same animal in two attitudes —
        /// sitting up he is short and deep, stretched down into the grass he is long
        /// and low — and his height is the one of the two that survives the change.
        static let rabbitStillHeightFraction: CGFloat = 0.863
        static let grazeSitHeightFraction: CGFloat = 0.948

        /// Where the sitting rabbit's own centre falls across the graze canvas.
        ///
        /// Not the middle of it: the canvas is stretched rightwards by the poses
        /// that reach down into the grass, so the sitting pose sits left of centre
        /// in it. Anchoring on this is what keeps `Intro.rabbitX` meaning the same
        /// place when the sheet under him changes.
        static let grazeSitCentreXFraction: CGFloat = 0.396
    }


    /// The painted world Benny runs through, and the handful of numbers it is
    /// staged by.
    ///
    /// One image, cut from a much longer painting by `Art/CropBackground.swift`.
    /// The fractions below are what that script prints — measured off the crop
    /// rather than typed in, so a repainted background is a rerun and a paste.
    enum BackdropArt {
        /// Probed rather than named directly, for the reason `ObstacleArt.load`
        /// gives: `SKTexture(imageNamed:)` hands back a placeholder for a missing
        /// name instead of admitting the art has gone.
        static let sheet: SKTexture? = UIImage(named: "bg_scroll").map(SKTexture.init(image:))

        /// The crop is exactly one repeat of the painting, so laying two of them end
        /// to end joins with nothing to see. Both the length of that repeat and
        /// where to take it from were found by sliding the source over itself —
        /// see the script, which prints how much better the join it chose is than
        /// the worst one available.
        static let aspect: CGFloat = 0.5880

        /// Down from the top of the crop: the top of the weather.
        ///
        /// Measured, like everything else here, and printed by the cutter —
        /// `cloudLine` in `Art/CropBackground.swift` reports the highest row
        /// carrying cloud every time the backdrop is cut. The launch climbs to this
        /// and stops, so a repainted sky moves the top of the shot with it instead
        /// of leaving the rocket hanging wherever a number typed in last year
        /// happened to put it.
        ///
        /// It is printed rather than measured by hand because it moves further than
        /// anyone expects. The painting this came from was handed over as a tweak to
        /// one cloud and shifted the ceiling ninety-one rows, which is about forty
        /// units of climb.
        static let cloudCeilingFraction: CGFloat = 0.3960

        /// That row in scene coordinates — the height at which the sky runs out of
        /// weather.
        static var cloudCeiling: CGFloat { bottomY + height * (1 - cloudCeilingFraction) }

        /// Down from the top of the crop: the near and far edges of the grass, and
        /// the band of flat sky the two scrolling layers are cut at.
        static let grassLineFraction: CGFloat = 0.8497
        static let earthLineFraction: CGFloat = 0.8820
        static let skySplitFraction: CGFloat = 0.7910

        /// How far down the grass everything stands. Nought is its near edge, one
        /// the lip of the cut earth.
        ///
        /// Half way, so there is field behind them and field in front — which is
        /// what standing in a field looks like. On the near edge, where this
        /// started, the bush line sits at Benny's heels and the whole flowered
        /// strip lies in front of him untouched, and he reads as pressed against a
        /// hedge rather than running through a park.
        ///
        /// **Not** the way to slide the scene up or down, however much it looks
        /// like it. This moves the painting *relative to* everything standing on
        /// it: Benny and the obstacles are staged against `Layout.groundTop`, which
        /// does not follow, so turning this down drops the countryside and leaves
        /// the whole cast planted further back up the grass — the dog house ends up
        /// mid-turf with a band of field in front of its feet. `Layout.groundTop`
        /// is the knob that moves both at once; this one only ever changes where in
        /// the grass they stand.
        static let standFraction: CGFloat = 0.5

        /// The row of the painting the game is played on, and so the row that has
        /// to land on `Layout.groundTop`.
        ///
        /// Everything in the world is staged against that line and nothing against
        /// the artwork, so this is the only place the two meet: move it and Benny,
        /// the obstacles and the whole opening cast move together, while the
        /// physics, the jump and the bench's clearance never know anything
        /// happened.
        static var anchorFraction: CGFloat {
            grassLineFraction + standFraction * (earthLineFraction - grassLineFraction)
        }

        /// How much field there is to stand on, in scene points — the strip between
        /// the near edge of the grass and the lip of the cut earth.
        ///
        /// This is what sets the whole painting's scale now, and it is the number to
        /// hold if the backdrop is ever repainted: everything the game is staged
        /// against hangs off it, and it has been 60.9 since the world went
        /// landscape.
        static let turfBand: CGFloat = 60.9

        /// How tall the whole crop is drawn, in scene points — whatever it takes to
        /// give `turfBand` the size it has always had.
        ///
        /// It used to be the larger of two demands: fill the scene above the line
        /// they stand on, or fill it below. That worked for exactly as long as the
        /// painting's sky was the short side, because then the sky was the one
        /// asking and the ground came along with room to spare.
        ///
        /// The tall painting inverts it. Give the scene three times the sky and the
        /// *ground* becomes the binding term, and the picture is scaled to whatever
        /// makes a ground-height of field reach the bottom — which came out a third
        /// smaller, shrinking the turf, the hills, the repeat and Benny's footing
        /// with it. Nothing about the game had changed; only which way round the
        /// `max` fell.
        ///
        /// So the band is pinned and the sky is allowed to come out as tall as it is
        /// drawn, which is the whole point of the new painting. At the figures above
        /// that is 1885 points, of which 1632 stand above the ground line — against
        /// 325 before, and none of it reachable.
        static var height: CGFloat { turfBand / (earthLineFraction - grassLineFraction) }

        /// One repeat, in scene points — and so how far the world travels before it
        /// comes round again.
        static var tileWidth: CGFloat { height * aspect }

        /// How many copies of the repeat it takes to cover the scene at every point
        /// in the scroll, rather than at most of them.
        ///
        /// Two was right in portrait and is wrong here, and the precondition the
        /// old comment stated — "given a repeat wider than the screen" — is exactly
        /// what landscape broke. The copies are laid end to end and wrap round each
        /// other, so the pair reach only `tileWidth` right of the origin at the
        /// moment before one wraps, never `2 * tileWidth`. Portrait had 1067
        /// against a 400-wide scene and a repeat to spare; landscape has 667
        /// against 800, so for a fifth of every cycle the last 133 units of the
        /// scene had nothing painted over them and showed `Palette.field` — a flat
        /// green slab down the right-hand edge, blinking in and out as the world
        /// came round.
        ///
        /// Derived rather than bumped to three, because it follows `tileWidth`,
        /// which follows `height`, which follows the scene and `groundTop`. Retune
        /// either and this keeps up.
        static var stripCount: Int {
            max(2, Int((Layout.sceneSize.width / tileWidth).rounded(.up)) + 1)
        }

        /// The bottom of the painting, and the seam between its two layers, in
        /// scene coordinates. Both fall out of standing the grass line on
        /// `Layout.groundTop`, which is the whole of how this is positioned: the
        /// painted turf lands where the code used to draw its own, so nothing
        /// physical moves.
        static var bottomY: CGFloat { Layout.groundTop - height * (1 - anchorFraction) }
        static var splitY: CGFloat { bottomY + height * (1 - skySplitFraction) }

        /// Everything above the split, and everything below it. Two rectangles of
        /// one texture rather than two images: the split is a measurement, and a
        /// measurement is better kept as a number than baked into a second file.
        ///
        /// Texture coordinates count up from the bottom where the crop's fractions
        /// count down from the top, hence the inversion.
        static var sky: SKTexture? {
            sheet.map { SKTexture(rect: CGRect(x: 0, y: 1 - skySplitFraction, width: 1, height: skySplitFraction), in: $0) }
        }

        static var land: SKTexture? {
            sheet.map { SKTexture(rect: CGRect(x: 0, y: 0, width: 1, height: 1 - skySplitFraction), in: $0) }
        }

        static var skySize: CGSize { CGSize(width: tileWidth, height: height * skySplitFraction) }
        static var landSize: CGSize { CGSize(width: tileWidth, height: height * (1 - skySplitFraction)) }

        /// How fast the sky drifts. Its own speed, and a slow one: the land travels
        /// at whatever the world is doing, and clouds keeping pace with the grass
        /// under Benny's feet is exactly the flat painted wall that having two
        /// layers is for.
        static let skySpeed: CGFloat = 16
    }


    /// The sky the flying phase is played against.
    ///
    /// A single painting rather than the running game's pair of layers, because up
    /// here there is nothing to be in front of anything else: no ground to travel at
    /// the world's speed and no hills to lag behind it. One texture, tiled sideways,
    /// and that is the whole backdrop.
    ///
    /// Cut by `Art/CropSky.swift`, which exists because `CropBackground` cannot do
    /// this one — that script's job is to find the grass line, the lip of the cut
    /// earth and the band of flat sky the layers split at, and this painting has no
    /// ground in it to find them in.
    enum SkyArt {
        /// Same stance as `BackdropArt.sheet` and for the same reason:
        /// `SKTexture(imageNamed:)` hands back a placeholder for a name that isn't
        /// there, so it can't tell you the art has gone missing.
        static let sheet: SKTexture? = UIImage(named: "bg_sky").map(SKTexture.init(image:))

        /// Printed by the cutter. One repeat of the painting.
        static let aspect: CGFloat = 2.6741

        /// Drawn to the *authored* height, not the visible one.
        ///
        /// `.aspectFill` crops the scene vertically by between nothing and
        /// `Layout.visibleInsetY` depending on how square the device is, so a sky
        /// sized to the 368 units a phone shows would come up short on an iPad and
        /// leave `Palette.field` along the top and bottom. Sized to all 500, the
        /// narrow case simply sees the middle of it.
        static var height: CGFloat { Layout.sceneSize.height }
        static var tileWidth: CGFloat { height * aspect }

        /// Same derivation as `BackdropArt.stripCount`, same reason: enough copies
        /// to cover the scene at every point in the scroll rather than at most of
        /// them.
        static var stripCount: Int {
            max(2, Int((Layout.sceneSize.width / tileWidth).rounded(.up)) + 1)
        }

        /// Faster than the running game's clouds, which drift at 16 against a world
        /// doing 300-odd. Up here the sky *is* the ground — it is the only thing
        /// telling the player they are moving at all — so it travels at something
        /// like flying speed.
        static let speed: CGFloat = 150
    }


    /// The drawings the launch is made of, and where they sit against each other.
    ///
    /// All of it measured off the five sheets and printed by `Art/CutLaunch.swift`,
    /// in the same arrangement `IntroArt` uses: this enum holds nothing but
    /// fractions read off the art, and `Launch` next door turns them into positions
    /// and pacing.
    ///
    /// Four clips arrived and only two of them are clips. The climb sheet's every
    /// frame separates into a house and a rocket of *exactly* 345,414 pixels — the
    /// same number five times over, which is one drawing being moved rather than
    /// five drawings. So the rocket is a single sprite flown up from inside the
    /// house, and the house's own drawing does the occluding that the rise sheet's
    /// early frames are a picture of. See the script's header.
    enum LaunchArt {
        static let slideFrames = numberedTextures("launch_slide")
        static let roofFrames = numberedTextures("launch_roof")
        static let flyFrames = numberedTextures("launch_fly")
        static let rocket = load("launch_rocket")

        /// The house alone, for the run in. Cut from the slide sheet's first frame
        /// and onto the slide's own canvas, so the changeover into the clip moves
        /// nothing. Not from its last frame, which looks like the obvious choice and
        /// has Benny's tail still hanging out of the door.
        static let houseShut = load("launch_house_shut")

        /// The slide's canvas, in fractions of itself: where the house stands on it,
        /// how wide the house is across it, and where the drawn Benny starts —
        /// which is the mark the real one is swapped at. Its ground line is the
        /// canvas's own bottom row, so an anchor of 0 puts it on the turf.
        static let slideHouseLeft: CGFloat = 0.448
        static let slideHouseWidth: CGFloat = 0.546
        static let slideBennyCentre: CGFloat = 0.174

        /// How far each frame of the slide moves him, across the canvas, and the
        /// sum of them.
        ///
        /// The steps are what the clip is timed off, because the art does not space
        /// him quite evenly — his longest frame covers more than twice his shortest.
        /// Played at a flat frame time that becomes a lurch; see
        /// `Launch.slideBeats(at:)`.
        ///
        /// They used to read as far more uneven than this, and most of that was a
        /// bug rather than the drawing: the frames were being registered backwards,
        /// so the house slid about underneath him and his measured travel went with
        /// it. These come off art that is actually lined up.
        ///
        /// Measured off his tail rather than his centre, because from the third
        /// frame on he overlaps the house and only his trailing edge can be told
        /// from it; `Art/CutLaunch.swift` explains why.
        static let slideSteps: [CGFloat] = [0.093, 0.077, 0.072, 0.086, 0.042, 0.100, 0.067, 0.002]
        static let slideSpan: CGFloat = 0.538

        /// The roof's canvas, stated the same way. Its last frame is also the house
        /// the rocket climbs out of — there is no separate drawing of that, on
        /// purpose: a second copy would be a second thing to keep in agreement, and
        /// the swap onto it would be exactly where they disagreed.
        static let roofHouseLeft: CGFloat = 0.009
        static let roofHouseWidth: CGFloat = 0.887

        /// The climb, in house widths from the house's ground-left corner.
        ///
        /// It starts on the floor of the house — the one place "inside" can mean
        /// without guessing. Sideways it barely moves: 0.18 to 0.23 across the climb
        /// sheet's five frames, so the ascent is vertical and that spread is just
        /// drawing.
        ///
        /// Where it *stops* is not taken from the art — see `Launch.apex`. The climb
        /// sheet carries the rocket 2.29 house widths up, which was once a taller
        /// shot than this game had sky for; now the sky goes to 1807 and the limit
        /// is the shot rather than the frame.
        static let rocketFrom = CGPoint(x: 0.215, y: 0.000)

        /// Sizes, each against the thing it hangs off, so the whole clip follows
        /// Benny — the one thing in it the game already decides the size of.
        static let houseInDogs: CGFloat = 1.617
        static let rocketInHouses: CGFloat = 0.503

        /// The flight sheet is drawn at its own scale, so its canvas is sized to put
        /// the first pose — the same upright rocket the climb ends on — at exactly
        /// the height `rocket` renders. Swapping between the two then doesn't resize
        /// the rocket in the middle of the shot.
        static let flyInHouses: CGFloat = 0.878

        /// Where the rocket's nose cone sits on this sheet's canvas, as a fraction
        /// across and up.
        ///
        /// The flier is anchored here rather than at its centre, because the clip
        /// swaps him onto `AngerArt`'s sheets, and those put the nose somewhere
        /// else entirely — 0.87 across and 0.22 up, against 0.91 and 0.38 here. A
        /// centred anchor would jump the rocket by a sixth of its height on the
        /// swap, which is about fourteen points and plainly visible. Anchored on
        /// the nose, every pose hangs from the same point and nothing moves.
        static let flyNose = CGPoint(x: 0.9050, y: 0.3830)

        /// Same reasoning as `ObstacleArt.load` and `DogArt`: `SKTexture(imageNamed:)`
        /// hands back a placeholder for a name that isn't there, so it can't tell you
        /// the art has gone missing. A nil here means the clip doesn't play.
        private static func load(_ name: String) -> SKTexture? {
            UIImage(named: name).map(SKTexture.init(image:))
        }
    }


    /// The rabbit's saucer, four frames of him laughing.
    ///
    /// The same rabbit from the opening clip, which is the whole joke: Benny chased
    /// him across a park, lost him, got into a rocket, and the rabbit is already up
    /// here and finds it funny.
    ///
    /// Cut by `Art/CutRabbit.swift`, which hangs every frame from the saucer's rim.
    /// The sheet draws them at four different heights, and a sprite swapping between
    /// them in place would jump forty-three pixels — not a subtle fault on a craft
    /// meant to hang in the air.
    enum UfoArt {
        /// `ufo_0` is the calm pose he flies in on; 1 to 3 are the laugh.
        static let frames: [SKTexture] = numberedTextures("ufo")

        /// Printed by the cutter.
        static let aspect: CGFloat = 1.3848
    }


    /// Benny losing his temper, and the face he settles into afterwards.
    ///
    /// Cut by `Art/CutAngry.swift`, which hangs all seven poses — six angry frames
    /// and the serious one — from the rocket's nose cone. The sheet draws the craft
    /// sinking twenty-four pixels across the six and snapping back eighteen on the
    /// last, which is both a visible fault and exactly the shape a registration bug
    /// takes; it is taken out there and a recoil is put back here, where it can be
    /// shaped.
    enum AngerArt {
        /// Six frames: tongue-out happy, through gritted teeth, to a burst of anger
        /// over his head.
        static let frames: [SKTexture] = numberedTextures("benny_angry")

        /// Mouth closed, eyes forward. What the flying phase is played on.
        static let serious: SKTexture? = UIImage(named: "benny_serious").map(SKTexture.init(image:))

        /// Printed by the cutter, and shared by all seven — they are installed on
        /// one common canvas, which is the whole point of registering them.
        static let aspect: CGFloat = 1.7090
        static let nose = CGPoint(x: 608.0 / 699.0, y: 1 - 321.0 / 409.0)

        /// How wide these are drawn against the launch sheet's flight pose.
        ///
        /// Measured on the nose cone, the one feature that is the same object in
        /// all of them: it is 0.13947 of the launch canvas and 0.13877 of this one.
        /// Half a percent, so this changes almost nothing — but it is the number
        /// that would matter if either sheet were ever recropped, and guessing it
        /// is how Benny ends up a different size mid-shot.
        static let widthInFlyFrames: CGFloat = 1.0050
    }

}
