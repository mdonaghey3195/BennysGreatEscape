//
//  GameScene.swift
//  Benny's Great Escape
//
//  Benny gallops, you tap to jump, the logs, bushes and stumps keep coming.
//
//  The world is drawn entirely in code — gradient sky, parallax clouds and
//  hills, scrolling turf. Everything you actually play against is painted and
//  lives in the asset catalogue: Benny himself (a gallop, a jump arc and a
//  slide), the three things he jumps, and the bench he ducks under.
//

import SpriteKit
import SwiftUI
import UIKit

// MARK: - Physics categories

private enum PhysicsCategory {
    static let dog: UInt32 = 0x1 << 0
    static let obstacle: UInt32 = 0x1 << 1
    static let ground: UInt32 = 0x1 << 2
}

// MARK: - Layout

/// The scene runs in a fixed logical space and is scaled to fit whatever view
/// it lands in, so gravity, jump height and scroll speed are tuned once and
/// behave identically on every device rather than drifting with the size the
/// view happened to be handed.
///
/// Authored portrait, because that is how the app is held. `.aspectFill` crops
/// a little off the edges to fill the screen, so nothing that matters sits near
/// one: the ground slab runs well below `groundTop`, and the live score is drawn
/// by SwiftUI over the top rather than inside the scene.
private enum Layout {
    static let sceneSize = CGSize(width: 400, height: 800)

    /// What `.aspectFill` crops off each side on the tallest phone, leaving
    /// 16…384 of the 400 authored. The worst case of the shapes this is held
    /// in, and so the edge the opening clip is framed against.
    static let visibleInset: CGFloat = 16

    /// Where the dog and every obstacle stand. Set high enough that the action
    /// occupies the lower third rather than a thin strip under empty sky.
    static let groundTop: CGFloat = 280

    /// Sized off the collar, which is the one part of the drawing that keeps a
    /// fixed size whatever Benny's doing — matching canvas widths would shrink
    /// him, because the gallop poses stretch the canvas without making the dog
    /// any bigger.
    static let dogWidth: CGFloat = 125

    /// Height follows the artwork's aspect so Benny is never stretched, and
    /// keeps following it if the drawing is ever replaced with one shaped
    /// differently.
    static var dogSize: CGSize {
        CGSize(width: dogWidth, height: dogWidth / DogArt.aspect)
    }

    static let dogX: CGFloat = 120

    /// Where a run starts. This is what caps the obstacle sizes in
    /// `ObstacleArt`: a jump lasts a fixed time, so the slowest the world ever
    /// moves is the least ground a jump ever covers, and everything has to be
    /// clearable there.
    ///
    /// It rose with Benny. The world scrolled at 220 when he was 80pt wide, and
    /// leaving it there while he grew made the game feel steadily more sluggish
    /// against him — and held the things he jumps down to toys beside him.
    static let openingSpeed: CGFloat = 280

    /// Where the ramp tops out. Held 160 above the opening, as it always has
    /// been, so a run still accelerates over its first 40 obstacles.
    static let topSpeed: CGFloat = 440

    /// Apex of a jump above `groundTop`. Obstacles top out around 78, so this is
    /// forgiving without feeling floaty.
    ///
    /// Height isn't the binding constraint, though — width is. A jump lasts a
    /// fixed time, so at the opening scroll speed it covers only ~289pt, and an
    /// obstacle's box plus Benny's own has to fit inside the stretch of that arc
    /// spent above it. That is what caps the obstacle sizes in `ObstacleArt`.
    ///
    /// Which is why this rises with `dogWidth`: a wider dog spends more of that
    /// stretch on himself, and left alone a full-height log goes from clearable
    /// to impossible. Every 25% on Benny has cost about 25pt here. It drags the
    /// spawn interval floor in `update` up with it, which the airtime has to
    /// stay under — and with the floor where it is, this is as high as it can
    /// go. Buying clearance beyond here means `Layout.openingSpeed`, not this.
    static let jumpHeight: CGFloat = 180

    /// How far a painted obstacle is pushed below the turf line by default.
    ///
    /// Has to clear the 8pt dark cut-turf edge drawn by `makeGround`, not just
    /// `groundTop`: obstacles draw over the ground, so a shallower sink leaves
    /// the pale highlight along the bottom of each drawing's grass sitting on
    /// top of that dark band, and the obstacle reads as resting on the ground
    /// rather than growing out of it. Individual pieces override it — how much
    /// painted grass there is to bury differs per drawing.
    static let obstacleSink: CGFloat = 12

    /// The same idea for Benny, and the reason he isn't left standing on a
    /// ledge now that everything else is planted deeper.
    ///
    /// Shallower than `obstacleSink` because his paws *are* his contact point,
    /// where an obstacle's drawing carries a skirt of grass below its own. The
    /// 5pt difference between the two is the gap that has always existed here,
    /// back when it was 5 and 0 — this keeps it while moving both down.
    ///
    /// Unlike the obstacles' sink this moves his physics as well as his
    /// drawing: the ground edge he rests on comes down with him, so the art
    /// never disagrees with the box about where the floor is.
    static let dogPlantDepth: CGFloat = 7

    /// Where Benny's paws and every obstacle's base actually come to rest, as
    /// against `groundTop`, which is where the turf is *drawn*.
    static var dogGroundLine: CGFloat { groundTop - dogPlantDepth }

    /// How much room a sliding dog needs: the underside of the bench seat,
    /// above where Benny stands. Has to sit below the 68pt running box or Benny would
    /// stroll under it untouched, and above the 41pt ducked box or sliding
    /// wouldn't save him. 52 leaves margin both ways.
    ///
    /// The bench is sized *from* this rather than the other way round, so the
    /// one number that decides whether ducking works can be retuned on its own.
    static let duckClearance: CGFloat = 52

    /// A slide covers this much ground rather than lasting a fixed time — at
    /// the top scroll speed a fixed duration would end before the bench had
    /// finished passing. Bench plus dog is about 330, so this leaves margin.
    static let slideDistance: CGFloat = 400

    /// Thick dark outlines are most of what makes flat shapes read as cartoon.
    static let outline: CGFloat = 4
}

// MARK: - Artwork

/// Every animation in the game is a numbered run of images in the catalogue,
/// collected until one is missing — so adding a frame is a pure asset drop with
/// nothing here to change.
///
/// Probed with `UIImage(named:)` rather than `SKTexture(imageNamed:)` because
/// the latter hands back a placeholder for a missing name instead of nil, so it
/// can't tell you where the frames stop.
private func numberedTextures(_ prefix: String) -> [SKTexture] {
    var textures: [SKTexture] = []
    var index = 0
    while let image = UIImage(named: "\(prefix)_\(index)") {
        textures.append(SKTexture(image: image))
        index += 1
    }
    return textures
}

/// Benny, drawn side-on and facing right — the way he runs.
private enum DogArt {
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
    /// frame — the torso and head — found by intersecting all six silhouettes.
    /// The legs sweep through a much larger envelope during a gallop and the
    /// tail sweeps behind; catching an obstacle with a trailing paw or the tail
    /// shouldn't end a run, while hitting one body-on still does.
    ///
    /// The offset is large because the canvas is sized to the fully extended
    /// poses, whose rear legs reach a long way back, leaving the body sitting
    /// well right of centre.
    ///
    /// Re-derive these by running the frame-splitting script over a new sheet;
    /// it prints them.
    static let bodyWidthFraction: CGFloat = 0.729
    static let bodyHeightFraction: CGFloat = 0.599
    static let bodyOffsetXFraction: CGFloat = 0.091

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
private enum IntroArt {
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

/// How the clip is staged and paced.
private enum Intro {
    /// How big the drawing plays, against the size the game plays at.
    ///
    /// Only the drawing. The dog it hands over to is never scaled — he fades in
    /// at the size he runs at and stays there, which is the whole reason this
    /// number is no longer 0.66. At 0.66 Benny grew into his own size over the
    /// takeoff, and a dog inflating against turf that kept its size doesn't read
    /// as a camera closing in; it reads as a dog inflating.
    ///
    /// 0.76 because the two drawings disagree about what shape Benny is. At
    /// equal width the drawn dog stands about a fifth taller than the run
    /// sheet's gallop, so there is no size at which he matches on both — this is
    /// the one where his height does, which is the steadier of the two: the
    /// gallop swings 95…122pt through its own cycle but only 67…76pt tall.
    ///
    /// It is also as large as the shot can be staged. Every point of this eats
    /// the width the rabbit needs to be carried in on, and past about here he
    /// stops arriving before Benny lunges at him.
    static let scale: CGFloat = 0.76

    /// Sized so the drawn dog is `scale` of the dog you then play as. That one
    /// measurement is what lets the handoff be a cut rather than a trick: Benny
    /// fades in over a drawing of himself, at the drawing's size.
    static var walkerSize: CGSize {
        let width = Layout.dogWidth * scale / IntroArt.dogWidthFraction
        return CGSize(width: width, height: width / IntroArt.walkAspect)
    }

    /// A rabbit against a beagle. Half his length, which is about right and,
    /// more to the point, small enough to read as prey.
    static let rabbitLength: CGFloat = 0.5

    /// Stated against the pose he is actually sitting in, not the canvas that
    /// has to hold the gallop as well.
    ///
    /// Those differ by a third, which is how a rabbit asked for at half a
    /// beagle's length came out at a third of one for the entire approach — the
    /// only stretch of the clip he is sitting still for.
    static var rabbitSize: CGSize {
        let width = Layout.dogWidth * scale * rabbitLength / IntroArt.rabbitStillWidthFraction
        return CGSize(width: width, height: width / IntroArt.rabbitAspect)
    }

    /// The graze canvas, scaled until the rabbit sitting up in it stands exactly
    /// as tall as the rabbit that runs off — the only way two sheets drawn at
    /// two scales end up the same animal.
    ///
    /// Stated against `rabbitSize` rather than against Benny, so the pair can
    /// only move together: restage the clip and both follow.
    static var grazeSize: CGSize {
        let height = rabbitSize.height
            * IntroArt.rabbitStillHeightFraction / IntroArt.grazeSitHeightFraction
        return CGSize(width: height * IntroArt.grazeAspect, height: height)
    }

    /// How long he holds each pose of the graze.
    ///
    /// Six poses at this is one cycle in a little over a second — head down,
    /// three of nibbling, and up again — which is about as long as he is on
    /// screen for. He is clear of the right edge at 1.06s and gone at
    /// `toHandoff`, so a slower graze would show him eating without ever
    /// finishing a mouthful.
    static let grazeFrame: TimeInterval = 0.18

    /// The man's head, and so the man. As far left as the crop allows, which is
    /// where he has to be: everything else in the shot stands to the right of
    /// him, and the room the rabbit is carried in on is whatever is left.
    ///
    /// Placed by his trailing leg at full stride rather than picked — four
    /// points inside what `.aspectFill` actually leaves, so a re-cut sheet moves
    /// him rather than quietly walking his foot off the edge. Lands around 61.
    ///
    /// He stays on it for the whole walk now that the ground moves instead of
    /// him, so the clearance no longer has to hold against a slide as well.
    ///
    /// Only his walk. The dive on the last frame reaches further left than any
    /// of this and is cropped by it, but by then the ground is moving and he is
    /// being carried out of shot anyway, which is the point of it.
    static var manX: CGFloat {
        Layout.visibleInset + 4
            + (IntroArt.manCentreXFraction - IntroArt.walkLeftFraction) * walkerSize.width
    }

    /// The rabbit waits here: a clear nose ahead of the dog, which is where he
    /// has to be for the moment to read as Benny spotting him rather than
    /// tripping over him.
    ///
    /// Far enough out that the drawn dog's nose at full stretch still doesn't
    /// reach him — the sheet has Benny pulling a long way ahead of the man
    /// before the leash goes, which puts that nose around 213 with the man
    /// holding his mark.
    ///
    /// Twenty points of air between him and the drawn dog's nose at full
    /// stretch, which the sheet puts around 246 with the man on his mark. That
    /// stretch is the handoff frame alone; the lunge he is actually reacting to
    /// only reaches about 182, so through the approach the gap is four times
    /// this.
    ///
    /// Which is the whole budget spent. Left of here and Benny's drawing runs
    /// into him at the cut; right of here and the turf hasn't finished carrying
    /// him into frame by the time Benny pulls. At 291 he is clear of the right
    /// edge at 1.07s against the pull at 0.88s — a fifth of a second late, and
    /// he has always been a little late.
    static let rabbitX: CGFloat = 291

    /// The first two of the three beats: out for a walk, then Benny leaning into
    /// the leash until it comes out of the man's hand. Eight frames, then nine.
    ///
    /// The eight are one whole stride, so `walkFrame` is that stride's length
    /// divided by eight, and a stride is the thing to set it by: at 0.11 he
    /// covers one in 0.88s, which is a walk with somewhere to be. The two are
    /// set together because between them they fix `scrollSpeed`, and so how
    /// fast the whole shot travels.
    static let walkFrame: TimeInterval = 0.11
    static let lungeFrame: TimeInterval = 0.14

    /// How much ground one stride of the drawn walk covers.
    ///
    /// He used to be slid forward by this against a world held still, which is
    /// the one thing a walk cycle can't survive: the turf was the only reference
    /// and it wasn't moving, so the travel had to be faked and any amount of it
    /// read as a treadmill. Now the turf moves instead, and this is what sets how
    /// fast — his legs and the grass are tied to the same number, so his feet
    /// only slip if this disagrees with what the sheet actually draws.
    ///
    /// A fraction of the drawing rather than a distance, because that is what a
    /// stride is: restage the clip at a different size and the same drawn legs
    /// cover more ground, so a fixed number here would put him straight back on
    /// a treadmill. 0.206 is the 50pt this used to be, against the 243pt-wide
    /// drawing it was measured on.
    ///
    /// Short of a real stride even so. Raising it speeds the whole shot up,
    /// because everything below is measured off it.
    static let strideFraction: CGFloat = 0.206
    static var walkTravel: CGFloat { walkerSize.width * strideFraction }

    /// The pace the world rolls at through the clip, as a speed and as the
    /// fraction of `gameSpeed` that `worldScroll` actually holds.
    ///
    /// Not chosen — divided out of the walk. One stride is `walkTravel` long and
    /// takes eight frames, so this is the speed at which the ground passes under
    /// a man whose legs are drawing that stride at that cadence.
    static var scrollSpeed: CGFloat { walkTravel / CGFloat(8 * walkFrame) }
    static var scrollFraction: CGFloat { scrollSpeed / Layout.openingSpeed }

    /// How long the clip takes to reach the handoff: the walk, the lunge, and the
    /// single frame the handover is made across. The rabbit's whole approach is
    /// timed against this, so it is derived here rather than counted twice.
    static var toHandoff: TimeInterval { 8 * walkFrame + 8 * lungeFrame + lungeFrame }

    /// Slower than the rest, because there are only two of them and they are the
    /// beat that has to land: the man reaching after Benny, and the man diving.
    static let aloneFrame: TimeInterval = 0.20

    /// Where the rabbit is planted, off the right of the scene, so that the turf
    /// delivers him to `rabbitX` exactly as the leash goes.
    ///
    /// There is no cue and no fade any more: he is sitting in the grass from the
    /// first frame, and the shot travelling towards him is what brings him on.
    /// He starts around 431, well off the right of the scene; his nose crosses
    /// what is actually shown a third of a second in, and he is clear of it and
    /// full in frame at about 1.06s — just after Benny starts pulling at 0.88s,
    /// so the pull still reads as a reaction to seeing him.
    static var rabbitStartX: CGFloat { rabbitX + scrollSpeed * CGFloat(toHandoff) }

    /// How fast he goes when he breaks, and for how long.
    ///
    /// Against the camera, not the ground — which is the whole difference from
    /// the old clip, where the world was standing still and any speed at all took
    /// him off the edge. By the end of `pickUp` the shot is moving at
    /// `openingSpeed` itself, so a rabbit at that speed would hang exactly where
    /// he is and one below it would slide backwards into Benny's teeth. The
    /// margin over it is what "getting away" is.
    static var rabbitRunSpeed: CGFloat { Layout.openingSpeed * 1.3 }
    static let rabbitBolt: TimeInterval = 1.05

    /// Benny fading in over the drawing of himself, and then how long he takes
    /// to settle into the place he runs from.
    ///
    /// The fade is a shade shorter than `lungeFrame`, which is how long that
    /// drawing is up for: he wants to be fully opaque by the time it goes, or
    /// the cut lands on a half-faded dog.
    static let handoff: TimeInterval = 0.12
    static let takeoff: TimeInterval = 0.9

    /// How long the world takes to get up to speed once he goes.
    static let pickUp: TimeInterval = 0.6

    /// A beat on Benny running, the man already carried out of frame behind
    /// him, before the score comes up over the top.
    static let hold: TimeInterval = 0.55
}

// MARK: - The obstacle artwork

/// Everything Benny meets on the path, painted and dropped into the catalogue:
/// a fallen log, a bush and a tree stump to jump, and a park bench to duck.
private enum ObstacleArt {

    /// The shape a drawing's solid mass is modelled with.
    ///
    /// A box for anything square-shouldered, a disc for anything domed. The
    /// distinction earns its keep: a rectangle laid over the bush is 81% empty
    /// air at its top corners, and the top corner is precisely where a jump
    /// coming down clips it.
    enum Solid {
        /// Width as a fraction of the sprite's width; height and base as
        /// fractions of its height, the base measured up from the drawing's
        /// bottom edge.
        case box(width: CGFloat, height: CGFloat, base: CGFloat)

        /// Radius and centre height, both as fractions of the sprite's height —
        /// height rather than width, because height is what `heightRange` sets
        /// and width merely follows the drawing's aspect.
        case disc(radius: CGFloat, centre: CGFloat)
    }

    /// One kind of obstacle: its drawing, how big it is allowed to be, and
    /// which part of the drawing is actually solid.
    struct Piece {
        let texture: SKTexture?

        /// The three ranges differ because they were each solved for the same
        /// timing window rather than set to the same number: at max height all
        /// three give a 33pt launch window at the opening speed. They diverged
        /// once the shapes were made honest — a disc round the bush and a box
        /// that stops at the log's cylinder both shed lethal empty air, so
        /// those two had to grow to stay as demanding as they read.
        ///
        /// Height is what's tuned; width follows the drawing's own aspect, so
        /// re-cropped art can never come out stretched. Both ends of the range
        /// are held down by the jump arc — see `Layout.jumpHeight`, and note it
        /// is the width that binds, since width comes along for the ride.
        let heightRange: ClosedRange<CGFloat>

        /// The solid mass within the drawing.
        ///
        /// Every one of these carries a fringe of loose grass along its base,
        /// and the stump has leaves sprouting either side. Nobody reads those as
        /// part of the obstacle, so brushing one shouldn't end a run — the same
        /// reasoning that keeps Benny's trailing paws out of his own body box.
        ///
        /// Measured off the alpha channel, then trimmed a little in Benny's
        /// favour.
        let solid: Solid

        /// The log's cylinder sits right of centre, because its grass tuft
        /// spills further out to the left than the wood does.
        let offsetXFraction: CGFloat

        /// How far this drawing sinks below the turf line. Defaults to
        /// `Layout.obstacleSink`; the bench takes less, because its cast-iron
        /// feet are the bottom of the drawing rather than a skirt of grass, and
        /// because its height is derived from this — see `benchHeight`.
        var sink: CGFloat = Layout.obstacleSink

        /// The 2:1 fallback only matters if the art is missing, in which case
        /// the drawn block stands in for it.
        func size(height: CGFloat) -> CGSize {
            guard let texel = texture?.size(), texel.height > 0 else {
                return CGSize(width: height * 2, height: height)
            }
            return CGSize(width: height * texel.width / texel.height, height: height)
        }
    }

    static let log = Piece(
        texture: load("obstacle_log"), heightRange: 59...76,
        // Stops at the top of the cylinder, measured at 0.754 of the drawing.
        // It used to run to 0.94 because the sprig of leaves dragged the
        // measurement up with it, leaving a full-width slab of nothing above
        // the wood — 88% empty at the top-left corner, which is the corner a
        // descending jump meets first.
        solid: .box(width: 0.75, height: 0.534, base: 0.22), offsetXFraction: 0.06
    )

    static let bush = Piece(
        texture: load("obstacle_bush"), heightRange: 70...92,
        // The one genuinely round obstacle. Least-squares fit over the
        // silhouette's upper edge gives radius 0.830 / centre 0.120; the radius
        // is pulled in to 0.80 so the disc sits inside the foliage rather than
        // on its best-fit average.
        solid: .disc(radius: 0.80, centre: 0.12), offsetXFraction: 0
    )

    /// Sized to the bush, so the three read as one family rather than the
    /// stump looming over the other two.
    ///
    /// Its box is the crown rather than the flared base, which is both narrower
    /// and the only part Benny's box can meet — he passes over the top, where
    /// the stump has already tapered in. Taking the flare instead costs a good
    /// 15pt of the clearance a jump has to spare at the opening scroll speed.
    static let stump = Piece(
        texture: load("obstacle_stump"), heightRange: 66...87,
        solid: .box(width: 0.64, height: 0.94, base: 0.02), offsetXFraction: 0
    )

    /// The jump rotation. The bench is deliberately not in here — it's the
    /// obstacle you duck, and `spawnObstacle` reaches for it by name.
    static let jumps = [log, bush, stump]

    /// Fraction of the bench drawing that is open air under the seat. High,
    /// because the seat was thinned to a plank: at the drawing's native
    /// chunkiness the slab came out as thick as the legs were tall, which left
    /// the bench towering over Benny's back rather than reading as something he
    /// could sit on.
    private static let benchUnderseat: CGFloat = 0.701

    /// Shallower than the rest. The bench's feet are cast iron, not grass, so
    /// they only need to meet the turf rather than disappear into it — and
    /// every point of sink here makes the whole bench taller and wider, because
    /// the seat has to stay `duckClearance` above the turf regardless.
    private static let benchSink: CGFloat = 6

    /// Sized so the underside of the seat lands exactly on the clearance line,
    /// the sink into the turf included. The bench scales off the one number
    /// that says how much room a sliding dog needs, so resizing Benny again
    /// can't quietly leave the seat too low to duck under.
    /// `duckClearance` is measured from where Benny stands, so both depths go
    /// in: the bench's own sink pushes the seat down, and Benny being planted
    /// deeper than the bench pulls it back up relative to him.
    private static let benchHeight =
        (Layout.duckClearance + benchSink - Layout.dogPlantDepth) / benchUnderseat

    /// The one you slide under. The legs fall below the seat's box and carry no
    /// physics of their own — Benny passing between them is the same shorthand
    /// the old drawn rail used for its posts.
    static let bench = Piece(
        texture: load("obstacle_bench"), heightRange: benchHeight...benchHeight,
        solid: .box(width: 0.95, height: 1 - benchUnderseat, base: benchUnderseat),
        offsetXFraction: 0, sink: benchSink
    )

    /// Optional, and probed with `UIImage(named:)` for the same reason `DogArt`
    /// does it: `SKTexture(imageNamed:)` hands back a placeholder for a name
    /// that isn't there, so it can't tell you the art has gone missing. A nil
    /// here falls back to a drawn block rather than an invisible obstacle.
    private static func load(_ name: String) -> SKTexture? {
        UIImage(named: name).map(SKTexture.init(image:))
    }
}

private enum Palette {
    static let skyTop = SKColor(red: 0.35, green: 0.72, blue: 0.97, alpha: 1)
    static let skyBottom = SKColor(red: 0.76, green: 0.92, blue: 1.00, alpha: 1)
    static let grass = SKColor(red: 0.44, green: 0.80, blue: 0.36, alpha: 1)
    static let grassDark = SKColor(red: 0.26, green: 0.60, blue: 0.24, alpha: 1)
    static let hillNear = SKColor(red: 0.55, green: 0.85, blue: 0.45, alpha: 1)
    static let hillFar = SKColor(red: 0.68, green: 0.89, blue: 0.62, alpha: 1)
    static let ink = SKColor(red: 0.16, green: 0.20, blue: 0.24, alpha: 1)
    static let cloud = SKColor(white: 1, alpha: 0.95)
    static let sun = SKColor(red: 1.0, green: 0.87, blue: 0.35, alpha: 1)
    static let log = SKColor(red: 0.60, green: 0.40, blue: 0.24, alpha: 1)
    static let hound = SKColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1)
}

// MARK: - Scene

final class GameScene: SKScene, SKPhysicsContactDelegate {

    // Nodes
    private var dog: SKNode!
    private var messageLabel: SKLabelNode!
    private var scenery: SKNode!
    private var groundDetail: SKNode!

    // State
    private(set) var score = 0
    private var isGameOver = false

    /// The world runs behind the title screen — scenery scrolling, Benny
    /// galloping — but nothing is thrown at him and nothing is scored until the
    /// player taps to begin. A live backdrop makes a far better first frame
    /// than a still, and it costs nothing since the scene is already built.
    private var hasStarted = false

    /// Whether Benny has left the ground since the last time he was on it.
    ///
    /// The one thing that separates a landing from the ground contact the
    /// physics reports when the world is first built, or rebuilt on a retry.
    /// Both of those raise `didBegin` with his paws already down, and neither
    /// should thud.
    private var hasLeftGround = false

    /// The opening clip, between the title screen and the first obstacle. It
    /// runs inside the scene rather than over it, so the park it is played in is
    /// the same park the game is played in and the handoff at the end is a cut
    /// between two things standing in one place.
    private var isIntro = false
    private var intro: SKNode?

    /// The rabbit, held separately because he is the one thing in the clip that
    /// moves with the turf *before* the stage does — see `update`.
    private weak var introRabbit: SKSpriteNode?

    /// Whether the clip is being carried along by the turf yet.
    ///
    /// It isn't while the man is walking. The turf is moving by then, but at the
    /// pace his own stride sets — riding it would take him backwards out of shot
    /// while he is still the thing being watched. From the handoff on, when the
    /// world winds up to Benny's speed, it is exactly what leaves him behind.
    private var introRidesAlong = false

    /// How much of `gameSpeed` the turf is actually moving at. One, except
    /// during the clip: nothing at all behind the title card, a fifth of it while
    /// the man walks his dog — a walking pace, and the pace that brings the
    /// rabbit into shot — and then all of it as Benny goes.
    ///
    /// Kept apart from `gameSpeed` itself, which also sets how fast Benny's legs
    /// turn over — winding *that* down to nothing would freeze his gallop at
    /// exactly the moment he is supposed to bolt.
    private var worldScroll: CGFloat = 1

    // Swipe tracking
    private var touchOrigin: CGPoint?
    private var gestureResolved = false

    /// Sliding is a timed action rather than a hold, so it can end itself.
    private var isSliding = false

    /// Reported so the SwiftUI layer can show the "swipe down" hint the first
    /// time a rail actually appears, rather than up front where it means little.
    var onFirstLowObstacle: (() -> Void)?

    /// Fires when a fresh run begins after a crash. The counterpart to
    /// `onGameOver`, so anything that reacted to the run ending can undo it.
    var onRetry: (() -> Void)?

    /// Fires when the opening clip is over — however it ended — and play is
    /// actually beginning. What used to happen the instant Play was tapped
    /// hangs off this instead, so the music and the score arrive with Benny
    /// rather than four seconds ahead of him.
    var onIntroFinished: (() -> Void)?
    private var hasSpawnedLowObstacle = false

    /// Driven by ground contacts rather than inferred from velocity. Velocity
    /// passes through zero at the apex of every jump, so testing `vy ≈ 0` would
    /// let you jump again in mid-air.
    ///
    /// A flag and not a tally, which it used to be. There is one ground body —
    /// a single edge across the world, see `makeGround` — so there is only ever
    /// one contact to be in, and a count of it can only ever be 0 or 1. What
    /// counting did buy was drift: every place that had to *correct* the tally
    /// after a body swap had to know exactly how many contacts were in flight,
    /// and two of them guessed one too few. Both left him permanently airborne
    /// in the game's eyes and handed out free jumps for the rest of the run.
    ///
    /// A flag can't drift. Setting it true twice is setting it true.
    private var isOnGround = false

    private var obstacleTimer: TimeInterval = 0
    private var obstacleInterval: TimeInterval = 1.8
    private var lastUpdateTime: TimeInterval = 0
    private var gameSpeed: CGFloat = Layout.openingSpeed

    /// Reported so SwiftUI can draw the score and persist a best.
    var onScoreChange: ((Int) -> Void)?
    var onGameOver: ((Int) -> Void)?

    /// Built through here rather than an overloaded `init(size:)`, which would
    /// collide with `SKScene`'s own designated initialiser.
    static func make() -> GameScene {
        let scene = GameScene(size: Layout.sceneSize)
        scene.scaleMode = .aspectFill
        return scene
    }

    // MARK: - Setup

    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: -9)
        physicsWorld.contactDelegate = self
        // Input is handled by `touchesBegan` rather than a gesture recognizer
        // hung on the view — the scene owns it, so it can't outlive the scene
        // or stack up if the scene is presented more than once.
        build()
    }

    private func build() {
        addChild(makeSky())
        addChild(makeSun())

        scenery = SKNode()
        addChild(scenery)
        addParallax()

        addChild(makeGround())
        addGroundDetail()
        dog = makeDog()
        addChild(dog)

        // The clip is what stands behind the title card, so it is built with the
        // rest of the world rather than swapped in when Play is tapped. Not on a
        // retry, though — `hasStarted` survives `restart` precisely so that a
        // crash drops straight back into the run.
        if !hasStarted { stageIntro() }
    }

    /// Tufts scattered over the turf. Without them the ground is an unbroken
    /// slab of one colour and the dog reads as running on the spot — these are
    /// the only cue that the world is moving, so they scroll at `gameSpeed`
    /// rather than a fixed rate and speed up as the game does.
    private func addGroundDetail() {
        groundDetail = SKNode()
        groundDetail.zPosition = 6
        addChild(groundDetail)

        let spacing: CGFloat = 70
        let count = Int((Layout.sceneSize.width + spacing * 2) / spacing)
        for i in 0...count {
            let tuft = makeTuft()
            tuft.position = CGPoint(
                x: CGFloat(i) * spacing + CGFloat.random(in: -18...18),
                y: Layout.groundTop - CGFloat.random(in: 16...54)
            )
            groundDetail.addChild(tuft)
        }
    }

    private func makeTuft() -> SKNode {
        let tuft = SKShapeNode(rect: CGRect(x: -9, y: 0, width: 18, height: 5), cornerRadius: 2.5)
        tuft.fillColor = Palette.grassDark
        tuft.strokeColor = .clear
        tuft.alpha = 0.55
        return tuft
    }

    // MARK: - Backdrop

    private func makeSky() -> SKNode {
        let sky = SKSpriteNode(texture: Self.gradientTexture(
            from: Palette.skyBottom,
            to: Palette.skyTop,
            size: Layout.sceneSize
        ))
        sky.position = CGPoint(x: Layout.sceneSize.width / 2, y: Layout.sceneSize.height / 2)
        sky.zPosition = -100
        return sky
    }

    /// Added to the scene rather than to the sky sprite. A sprite's children are
    /// positioned from its centre, so scene coordinates would land it off-frame.
    private func makeSun() -> SKNode {
        let sun = SKShapeNode(circleOfRadius: 42)
        sun.fillColor = Palette.sun
        sun.strokeColor = Palette.ink
        sun.lineWidth = Layout.outline
        // Kept clear of the top strip, where SwiftUI draws the score — dark text
        // over the sun's yellow reads badly.
        sun.position = CGPoint(x: 300, y: 555)
        sun.zPosition = -90
        return sun
    }

    /// Clouds drift slowly and hills faster, so the backdrop reads as depth
    /// rather than a flat painted wall.
    private func addParallax() {
        let width = Layout.sceneSize.width

        for i in 0..<4 {
            let cloud = makeCloud()
            cloud.position = CGPoint(x: CGFloat(i) * 150 + 40, y: CGFloat.random(in: 420...700))
            cloud.zPosition = -80
            scenery.addChild(cloud)
            drift(cloud, speed: CGFloat.random(in: 10...18), width: width + 200)
        }

        for i in 0..<5 {
            let hill = makeHill(radius: CGFloat.random(in: 80...120), color: Palette.hillFar)
            hill.position = CGPoint(x: CGFloat(i) * 150 - 40, y: Layout.groundTop - 20)
            hill.zPosition = -60
            scenery.addChild(hill)
            drift(hill, speed: 35, width: width + 350)
        }

        for i in 0..<4 {
            let hill = makeHill(radius: CGFloat.random(in: 55...85), color: Palette.hillNear)
            hill.position = CGPoint(x: CGFloat(i) * 170 + 60, y: Layout.groundTop - 14)
            hill.zPosition = -40
            scenery.addChild(hill)
            drift(hill, speed: 60, width: width + 300)
        }
    }

    /// Scrolls a node left forever, wrapping it round by `width`.
    private func drift(_ node: SKNode, speed: CGFloat, width: CGFloat) {
        let step = SKAction.moveBy(x: -width, y: 0, duration: TimeInterval(width / speed))
        let wrap = SKAction.moveBy(x: width, y: 0, duration: 0)
        node.run(.repeatForever(.sequence([step, wrap])))
    }

    private func makeCloud() -> SKNode {
        let cloud = SKNode()
        // Three overlapping circles — the classic cartoon cloud.
        for (dx, dy, r) in [(-24.0, 0.0, 18.0), (0.0, 7.0, 24.0), (24.0, 0.0, 16.0)] {
            let puff = SKShapeNode(circleOfRadius: r)
            puff.fillColor = Palette.cloud
            puff.strokeColor = .clear
            puff.position = CGPoint(x: dx, y: dy)
            cloud.addChild(puff)
        }
        return cloud
    }

    private func makeHill(radius: CGFloat, color: SKColor) -> SKShapeNode {
        let hill = SKShapeNode(circleOfRadius: radius)
        hill.fillColor = color
        hill.strokeColor = .clear
        return hill
    }

    private func makeGround() -> SKNode {
        let ground = SKNode()
        ground.zPosition = 5

        let left = -Layout.sceneSize.width
        let span = Layout.sceneSize.width * 3

        // Runs far below `groundTop` so `.aspectFill` cropping the bottom of the
        // scene on a shorter screen can never open a gap under the grass.
        let slab = SKShapeNode(rect: CGRect(x: left, y: -300, width: span, height: Layout.groundTop + 300))
        slab.fillColor = Palette.grass
        slab.strokeColor = .clear
        ground.addChild(slab)

        // Bold top edge, the cartoon "cut turf" line.
        let edge = SKShapeNode(rect: CGRect(x: left, y: Layout.groundTop - 8, width: span, height: 8))
        edge.fillColor = Palette.grassDark
        edge.strokeColor = .clear
        ground.addChild(edge)

        let body = SKPhysicsBody(
            edgeFrom: CGPoint(x: left, y: Layout.dogGroundLine),
            to: CGPoint(x: left + span, y: Layout.dogGroundLine)
        )
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.ground
        ground.physicsBody = body

        return ground
    }

    // MARK: - The dog

    /// Everything about the hound lives here, so replacing the artwork is a
    /// change to this one function — the physics and the rest of the scene
    /// don't care.
    private func makeDog() -> SKNode {
        let size = Layout.dogSize
        let node = SKNode()
        node.position = CGPoint(x: Layout.dogX, y: Layout.dogGroundLine + size.height / 2)
        node.zPosition = 10

        let body = makeDogBody(size: size)
        body.name = "body"
        node.addChild(body)

        // An inset torso box rather than the drawing's full bounds, which would
        // include the tail, the snout and the empty sky above his back. Offset
        // so the box's *bottom* lands on the drawing's bottom — otherwise Benny
        // floats above the turf or sinks into it.
        node.physicsBody = makeDogPhysics(ducked: false)

        return node
    }

    /// Standing and ducked share a shape: a box whose bottom sits on the paw
    /// line. A fresh body inherits none of the masks, so they're reapplied here
    /// rather than at each call site.
    private func makeDogPhysics(ducked: Bool) -> SKPhysicsBody {
        let size = Layout.dogSize
        let box = CGSize(
            width: size.width * (ducked ? DogArt.slideWidthFraction : DogArt.bodyWidthFraction),
            height: size.height * (ducked ? DogArt.slideHeightFraction : DogArt.bodyHeightFraction)
        )
        let body = SKPhysicsBody(
            rectangleOf: box,
            center: CGPoint(
                x: size.width * (ducked ? DogArt.slideOffsetXFraction : DogArt.bodyOffsetXFraction),
                y: (box.height - size.height) / 2
            )
        )
        body.categoryBitMask = PhysicsCategory.dog
        body.contactTestBitMask = PhysicsCategory.obstacle | PhysicsCategory.ground
        body.collisionBitMask = PhysicsCategory.ground
        body.restitution = 0
        body.allowsRotation = false
        body.friction = 0
        return body
    }

    /// The drawing, anchored at its feet. Squash and stretch then pivots from
    /// the paws, which is the only pivot that looks right — scaling about the
    /// centre drives his feet through the turf on landing.
    private func makeDogBody(size: CGSize) -> SKNode {
        guard let first = DogArt.frames.first else { return placeholderDogBody(size: size) }

        let sprite = SKSpriteNode(texture: first, size: size)
        sprite.anchorPoint = CGPoint(x: 0.5, y: DogArt.groundLineFraction)
        sprite.position = CGPoint(x: 0, y: -size.height / 2)

        if DogArt.frames.count > 1 {
            sprite.run(gallop, withKey: "gait")
        } else {
            // One drawing, so the run is sold with a bob and a slight tilt
            // instead. Harmless to leave in once real frames exist.
            sprite.run(.repeatForever(.sequence([
                .group([
                    .moveBy(x: 0, y: 2.5, duration: 0.18),
                    .rotate(toAngle: -0.025, duration: 0.18),
                ]),
                .group([
                    .moveBy(x: 0, y: -2.5, duration: 0.18),
                    .rotate(toAngle: 0.015, duration: 0.18),
                ]),
            ])), withKey: "gait")
        }
        return sprite
    }

    /// A full gallop cycle in ~0.42s, near two strides a second. Set from how far
    /// a paw travels relative to the body against how fast the ground moves — get
    /// this wrong and planted feet slide, which is what makes a run cycle read as
    /// a moonwalk. `update` then scales it with `gameSpeed`.
    private var gallop: SKAction {
        .repeatForever(.animate(with: DogArt.frames, timePerFrame: 0.07))
    }

    /// The jump arc, stretched to fit however long Benny is actually airborne,
    /// so retuning `jumpHeight` or gravity can't leave him landing three frames
    /// early. Weighted rather than evenly spaced: the two airborne poses hold
    /// longest, because that's where the flight spends its time.
    private var jumpArc: SKAction {
        let weights: [CGFloat] = [0.12, 0.18, 0.22, 0.22, 0.16, 0.10]
        let frames = DogArt.jumpFrames
        guard !frames.isEmpty else { return gallop }

        var steps: [SKAction] = []
        for (i, texture) in frames.enumerated() {
            let share = i < weights.count ? weights[i] : 1 / CGFloat(frames.count)
            steps.append(.setTexture(texture))
            steps.append(.wait(forDuration: TimeInterval(airtime * share)))
        }
        // Runs once and leaves the landing pose showing — if he's somehow still
        // in the air, holding it beats snapping back to a gallop mid-flight.
        return .sequence(steps)
    }

    /// Only reached if the artwork is missing from the bundle.
    private func placeholderDogBody(size: CGSize) -> SKNode {
        let body = SKShapeNode(rectOf: size, cornerRadius: 10)
        body.fillColor = Palette.hound
        body.strokeColor = Palette.ink
        body.lineWidth = Layout.outline
        return body
    }

    // MARK: - Input

    /// Swipe up to jump, swipe down to slide.
    ///
    /// The direction is resolved as soon as the finger crosses a small
    /// threshold rather than on lift-off — waiting for touch-up would put about
    /// a tenth of a second on the game's core verb.
    ///
    /// A plain tap does nothing on purpose. Falling back to a jump would mean a
    /// short or lazy down-swipe launches Benny into the very rail he was trying
    /// to duck, which is the worst way to lose a run.
    private static let swipeThreshold: CGFloat = 24

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // A tap during the clip skips it. It is the same four seconds every
        // time Play is tapped, and there is no reason to sit through it twice.
        guard !isIntro else {
            finishIntro()
            return
        }
        guard !isGameOver else {
            restart()
            return
        }
        guard let touch = touches.first else { return }
        touchOrigin = touch.location(in: self)
        gestureResolved = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isIntro, !isGameOver, !gestureResolved,
              let touch = touches.first, let origin = touchOrigin else { return }

        let dy = touch.location(in: self).y - origin.y
        guard abs(dy) >= Self.swipeThreshold else { return }

        gestureResolved = true
        if dy > 0 {
            jump()
        } else {
            slide()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchOrigin = nil
        gestureResolved = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchOrigin = nil
        gestureResolved = false
    }

    /// Drops Benny flat for a fixed *distance* of ground. A fixed duration
    /// would clear a rail at the opening speed and fall short at the top one.
    private func slide() {
        guard isOnGround, !isSliding, !DogArt.slideFrames.isEmpty else { return }
        isSliding = true
        Sfx.shared.play(.slide)
        Haptics.slide()

        setDucked(true)

        // Dirt kicking up for the whole slide. The pose change alone is hard to
        // read at this size — the dust is what actually says "sliding".
        dog.run(
            .repeatForever(.sequence([
                .run { [weak self] in self?.puffDust(behind: 6, scale: 1.5) },
                .wait(forDuration: 0.1),
            ])),
            withKey: "slideDust"
        )

        let frames = DogArt.slideFrames
        let total = TimeInterval(Layout.slideDistance / gameSpeed)
        let entry: TimeInterval = 0.06
        let recover: TimeInterval = 0.10
        let hold = max(0.08, total - entry * 2 - recover)

        var steps: [SKAction] = []
        for texture in frames.prefix(2) {
            steps.append(.setTexture(texture))
            steps.append(.wait(forDuration: entry))
        }
        if frames.count > 2 {
            steps.append(.setTexture(frames[2]))
            steps.append(.wait(forDuration: hold))
        }
        if frames.count > 3 {
            steps.append(.setTexture(frames[3]))
            steps.append(.wait(forDuration: recover))
        }
        steps.append(.run { [weak self] in self?.endSlide() })

        dog.childNode(withName: "body")?.removeAction(forKey: "gait")
        dog.childNode(withName: "body")?.run(.sequence(steps), withKey: "gait")
    }

    private func endSlide() {
        guard isSliding else { return }
        isSliding = false
        dog.removeAction(forKey: "slideDust")
        setDucked(false)
        guard let body = dog.childNode(withName: "body"), DogArt.frames.count > 1 else { return }
        body.removeAction(forKey: "gait")
        body.run(gallop, withKey: "gait")
    }

    /// Swaps the hitbox between standing and ducked.
    ///
    /// Nothing is done about `isOnGround` here, deliberately. Swapping a hitbox
    /// doesn't change whether Benny is standing on the ground, and the state
    /// says whether he is standing on the ground.
    ///
    /// It used to pin the old ground-contact tally back to 1 to make up for the
    /// destroyed body never reporting its contact ended — which was one too
    /// many, because the replacement body then announced itself with a `didBegin`
    /// of its own. That is the whole of what made a slide hand out free jumps
    /// for the rest of a run.
    private func setDucked(_ ducked: Bool) {
        dog.physicsBody = makeDogPhysics(ducked: ducked)
    }

    private func jump() {
        // Swiping up out of a slide cancels it — standing back up mid-air would
        // otherwise leave the ducked hitbox on while he's clearly upright.
        if isSliding { endSlide() }
        guard isOnGround else { return }
        hasLeftGround = true
        Sfx.shared.play(.jump)
        // Velocity is set directly from the desired apex rather than applying an
        // impulse, which would depend on the body's mass — and therefore on the
        // dog's size, which is placeholder art due to change.
        dog.physicsBody?.velocity = CGVector(dx: 0, dy: launchVelocity)

        // No squash on takeoff: the leap poses already draw that stretch, and
        // scaling on top of them reads as rubbery.
        if let body = dog.childNode(withName: "body"), !DogArt.jumpFrames.isEmpty {
            body.speed = 1
            body.removeAction(forKey: "gait")
            body.run(jumpArc, withKey: "gait")
        }
    }

    /// `v = sqrt(2·a·h)`. SpriteKit gravity is in m/s² against a 150 points-per-
    /// metre world, and velocity is in points/s.
    private var launchVelocity: CGFloat {
        sqrt(2 * gravityAcceleration * Layout.jumpHeight)
    }

    /// SpriteKit gravity is in m/s² against a 150 points-per-metre world.
    private var gravityAcceleration: CGFloat {
        abs(physicsWorld.gravity.dy) * 150
    }

    /// How long a jump lasts, up and back down. Derived from the same numbers as
    /// `launchVelocity`, so the jump animation stays in step if the height or
    /// gravity is retuned.
    private var airtime: CGFloat {
        2 * launchVelocity / gravityAcceleration
    }

    /// Squash and stretch. Cheap, and it does more for the cartoon feel than any
    /// amount of detail in the shapes themselves.
    private func squash(xScale: CGFloat, yScale: CGFloat) {
        guard let body = dog.childNode(withName: "body") else { return }
        // Keyed, so this replaces only a previous squash. `removeAllActions`
        // here would also kill the gait loop, and Benny would freeze mid-stride
        // after his first jump.
        body.removeAction(forKey: "squash")
        body.run(.sequence([
            .group([.scaleX(to: xScale, duration: 0.08), .scaleY(to: yScale, duration: 0.08)]),
            .group([.scaleX(to: 1, duration: 0.16), .scaleY(to: 1, duration: 0.16)]),
        ]), withKey: "squash")
    }

    private func puffDust(behind: CGFloat = 20, scale: CGFloat = 1) {
        let puff = SKShapeNode(circleOfRadius: 6 * scale)
        puff.fillColor = .white
        puff.strokeColor = .clear
        puff.alpha = 0.9
        puff.position = CGPoint(
            x: Layout.dogX - behind + CGFloat.random(in: -4...4),
            y: Layout.dogGroundLine + 5
        )
        puff.zPosition = 9
        addChild(puff)
        puff.run(.sequence([
            .group([
                .scale(to: 2.2, duration: 0.32),
                .fadeOut(withDuration: 0.32),
                .moveBy(x: -24, y: 6, duration: 0.32),
            ]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Obstacles

    private func spawnObstacle() {
        // Benches stay the minority — ducking is the newer verb, and a run
        // that's mostly ducking loses the rhythm of jumping. They also hold off
        // until a few obstacles in, so the first thing anyone meets is a jump.
        let wantsBench = score >= 2 && DogArt.slideFrames.count > 1 && Int.random(in: 0..<10) < 3
        let obstacle: SKNode
        if wantsBench {
            obstacle = makeObstacle(ObstacleArt.bench)
            if !hasSpawnedLowObstacle {
                hasSpawnedLowObstacle = true
                onFirstLowObstacle?()
            }
        } else {
            obstacle = makeObstacle(ObstacleArt.jumps.randomElement() ?? ObstacleArt.log)
        }
        obstacle.position = CGPoint(x: Layout.sceneSize.width + 60, y: Layout.groundTop)
        obstacle.zPosition = 8
        obstacle.name = "obstacle"
        addChild(obstacle)

        let travel = Layout.sceneSize.width + 160
        obstacle.run(.sequence([
            .moveBy(x: -travel, y: 0, duration: TimeInterval(travel / gameSpeed)),
            .removeFromParent(),
        ]))
    }

    /// One of the painted jump obstacles, at a random height within its own
    /// range, standing on the turf with its physics box hugging the solid part
    /// of the drawing.
    ///
    /// The node's origin is on the ground line rather than at the middle of the
    /// sprite, so `spawnObstacle` can stand every obstacle at `Layout.groundTop`
    /// without knowing how tall this one came out.
    private func makeObstacle(_ piece: ObstacleArt.Piece) -> SKNode {
        let node = SKNode()
        let size = piece.size(height: .random(in: piece.heightRange))

        let body: SKPhysicsBody

        if let texture = piece.texture {
            let sprite = SKSpriteNode(texture: texture, size: size)
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
            sprite.position = CGPoint(x: 0, y: -piece.sink)
            node.addChild(sprite)

            let x = size.width * piece.offsetXFraction
            switch piece.solid {
            case let .box(width, height, base):
                body = SKPhysicsBody(
                    rectangleOf: CGSize(width: size.width * width, height: size.height * height),
                    center: CGPoint(x: x, y: size.height * (base + height / 2) - piece.sink)
                )
            case let .disc(radius, centre):
                body = SKPhysicsBody(
                    circleOfRadius: size.height * radius,
                    center: CGPoint(x: x, y: size.height * centre - piece.sink)
                )
            }
        } else {
            // Missing art. A plain block keeps the game playable and obvious
            // rather than putting an invisible obstacle in Benny's way.
            let block = SKShapeNode(
                rect: CGRect(x: -size.width / 2, y: 0, width: size.width, height: size.height),
                cornerRadius: 10
            )
            block.fillColor = Palette.log
            block.strokeColor = Palette.ink
            block.lineWidth = Layout.outline
            node.addChild(block)

            // The block is solid all the way through — `solid` describes a
            // drawing that isn't here.
            body = SKPhysicsBody(rectangleOf: size, center: CGPoint(x: 0, y: size.height / 2))
        }

        node.physicsBody = Self.obstacleBody(body)
        return node
    }

    /// The masks every obstacle shares, whatever shape it came out as.
    private static func obstacleBody(_ body: SKPhysicsBody) -> SKPhysicsBody {
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.obstacle
        body.contactTestBitMask = PhysicsCategory.dog
        return body
    }

    // MARK: - The opening clip

    /// Why Benny is running: a man walks him across the park, a rabbit breaks
    /// cover in front of them, and the leash doesn't hold.
    ///
    /// It plays inside the scene rather than over it — same sky, same hills,
    /// same turf — so there is nothing to cut to when it ends. What ends it is
    /// the artwork handing over: the sheet stops drawing the dog, Benny fades in
    /// where the drawing left him, and the world starts moving under him.
    /// Sets the clip up, still and silent, as the thing standing behind the
    /// title card.
    ///
    /// Which sounds like a detail and isn't. `SpriteView` draws on its own clock
    /// and the SwiftUI card over it on another, and there is no turn in which
    /// both change together — so a scene that swaps as the card lifts gets the
    /// card taken off it over whatever it last drew, and what that is, on the
    /// frame Play is tapped, is the galloping dog the clip exists to explain.
    /// Fades and delays only move which frame it is.
    ///
    /// Staged up front there is nothing to swap. Play starts the beats, and the
    /// card comes off a scene that has had the man standing in it all along.
    private func stageIntro() {
        guard IntroArt.walkFrames.count >= 19,
              !IntroArt.rabbitFrames.isEmpty, !IntroArt.grazeFrames.isEmpty
        else { return }

        // Nothing moves behind the title card. The man is standing in it, and a
        // world rolling under a man standing still is the one thing that would
        // give the drawing away.
        worldScroll = 0
        scenery.speed = 0

        // Benny is in the artwork for now, drawn rather than simulated. Left
        // dynamic, gravity would drag him off the ground line the moment an
        // action took his position over.
        dog.isHidden = true
        dog.physicsBody?.isDynamic = false

        let stage = SKNode()
        stage.zPosition = 9  // over the turf, under Benny
        addChild(stage)
        intro = stage

        let walker = SKSpriteNode(texture: IntroArt.walkFrames[0], size: Intro.walkerSize)
        walker.name = "walker"
        walker.anchorPoint = CGPoint(x: IntroArt.manCentreXFraction, y: IntroArt.groundLineFraction)
        walker.position = CGPoint(x: Intro.manX, y: Layout.dogGroundLine)
        stage.addChild(walker)

        // Grazing in the grass off the right of the shot. He is drawn from the
        // first frame — the walk travelling towards him is what brings him on,
        // so there is nothing to fade in and nothing to cue — but he holds the
        // sitting pose until the clip actually starts, because nothing moves
        // behind the title card.
        let rabbit = SKSpriteNode(texture: IntroArt.grazeStill, size: Intro.grazeSize)
        rabbit.name = "rabbit"
        // Every pose on the graze sheet is pinned to the floor of its canvas, so
        // the floor is the ground; across it he is anchored on the sitting
        // rabbit rather than on the canvas, which is stretched by the poses that
        // reach down into the grass.
        rabbit.anchorPoint = CGPoint(x: IntroArt.grazeSitCentreXFraction, y: 0)
        rabbit.position = CGPoint(x: Intro.rabbitStartX, y: Layout.dogGroundLine)
        stage.addChild(rabbit)
        introRabbit = rabbit
    }

    /// Starts the clip running. Everything it moves is already on screen; this
    /// is only the beats.
    private func runIntro() {
        isIntro = true

        // The shot starts moving with him. Stepped rather than ramped: at 57pt/s
        // there is nothing to ease into, and an ease would cost the rabbit a
        // tenth of a second of travel that his arrival on the mark is measured
        // against.
        worldScroll = Intro.scrollFraction
        scenery.speed = Intro.scrollFraction

        let frames = IntroArt.walkFrames
        guard let stage = intro,
              let walker = stage.childNode(withName: "walker") as? SKSpriteNode,
              stage.childNode(withName: "rabbit") != nil
        else {
            // No artwork, no clip — the same stance `makeDog` takes with its
            // placeholder. The game still starts.
            finishIntro()
            return
        }

        // One turn of the walk; then the lunge and the leash going; then the two
        // frames with no dog drawn in them, over which he reaches after Benny,
        // dives, and misses.
        //
        // Frame sixteen is split out of the lunge because it is the one the
        // handover happens across: Benny fades up over the drawing of himself
        // while it is still on screen, and only once it goes does he leave.
        //
        // He holds his ground while he does it. The turf moving under him at the
        // pace his own stride sets is what carries him now, and adding a slide on
        // top would be that travel counted twice.
        walker.run(.sequence([
            .animate(with: Array(frames[0...7]), timePerFrame: Intro.walkFrame),
            .animate(with: Array(frames[8...15]), timePerFrame: Intro.lungeFrame),
            .run { [weak self] in self?.bennyAppears() },
            .animate(with: Array(frames[16...16]), timePerFrame: Intro.lungeFrame),
            .run { [weak self] in self?.handOff() },
            .animate(with: Array(frames[17...]), timePerFrame: Intro.aloneFrame),
            .wait(forDuration: Intro.hold),
            .run { [weak self] in self?.finishIntro() },
        ]))

        // The rabbit's one beat: he grazes. Started here rather than in
        // `stageIntro` because the clip is staged behind the title card and a
        // rabbit chewing away behind it would be the one thing moving.
        //
        // Everything else about him is somebody else's beat. He is carried in by
        // the turf — `update` walks him — and he breaks in `handOff`, which is
        // the moment the leash goes, because those are the same moment.
        introRabbit?.run(.repeatForever(
            .animate(with: IntroArt.grazeFrames, timePerFrame: Intro.grazeFrame)
        ))
    }

    /// Benny fades up on top of the last drawing of himself, still standing on
    /// the spot, while that drawing is still on screen.
    ///
    /// The overlap is the whole point, and it is why this is separate from
    /// `handOff`. Fade him in on the frame *after* the drawing has gone and
    /// there is an instant with no dog on screen at all — half of a very short
    /// beat in which the man is reaching after nothing. Fade him in while the
    /// drawing is still there and the two are the same dog, in the same place,
    /// at the same size, one dissolving into the other. Which also means he must
    /// not move yet: a dissolve between two things standing still reads as one
    /// thing, and the moment he starts pulling away it reads as two.
    private func bennyAppears() {
        dog.removeAllActions()
        dog.position = CGPoint(x: drawnDogX, y: Layout.dogGroundLine + Layout.dogSize.height / 2)
        // At the size he runs at, which is the size the drawing has him — and
        // the size he stays. He used to come in at the drawing's 0.66 and grow
        // into his own over the takeoff; a dog swelling against turf that keeps
        // its size doesn't read as a camera closing in, it reads as a dog
        // swelling.
        dog.setScale(1)
        dog.isHidden = false
        dog.alpha = 0
        dog.run(.fadeIn(withDuration: Intro.handoff))
    }

    /// The drawing stops drawing the dog, and the dog `bennyAppears` left
    /// standing in its place goes.
    private func handOff() {
        // The real dog, once a run, on the beat the whole clip exists to reach.
        // Not on jumps: a bark on every jump is the fastest way to wear out the
        // best sound in the game.
        Sfx.shared.bark()

        // The camera goes with Benny: the turf starts moving, the hills pick up,
        // and the man — pinned to the turf by `update` — is carried backwards
        // out of frame.
        ramp(worldScroll: 1, over: Intro.pickUp)
        scenery.run(.speed(to: 1, duration: Intro.pickUp))
        introRidesAlong = true

        // He drifts left against the screen while the ground goes left faster,
        // which nets out as him pulling away — and lands him on the mark he runs
        // from for the rest of the game. Travel only: he is already the size he
        // plays at, and nothing about him changes again.
        let settle = SKAction.moveTo(x: Layout.dogX, duration: Intro.takeoff)
        settle.timingMode = .easeOut
        dog.run(settle)

        // The man gets a step or two after him before the fight goes out of it.
        intro?.childNode(withName: "walker")?
            .run(.moveBy(x: 24, y: 0, duration: Intro.aloneFrame * 2))

        // And the rabbit, who has been sitting on the mark waiting for exactly
        // this, breaks. He is inside the stage, and the stage now rides the turf,
        // so the distance he is given here is ground covered rather than screen
        // crossed — which is what lets `rabbitRunSpeed` be stated against the
        // speed of the chase.
        if let rabbit = introRabbit {
            // A different sheet, so the size and the anchor go with the frames:
            // the gallop is drawn longer and lower than the rabbit sitting up in
            // the grass, and `grazeSize` and `rabbitSize` are what keep the two
            // the same animal across the change.
            rabbit.removeAllActions()
            rabbit.size = Intro.rabbitSize
            rabbit.anchorPoint = CGPoint(x: 0.5, y: 0)
            rabbit.run(.repeatForever(.animate(with: IntroArt.rabbitFrames, timePerFrame: 0.07)))
            let bolt = SKAction.moveBy(
                x: Intro.rabbitRunSpeed * CGFloat(Intro.rabbitBolt), y: 0,
                duration: Intro.rabbitBolt
            )
            // A standing start, but only just: the ground is accelerating under
            // him from this frame, and a longer ease would have it out-run him
            // for the first tenth and drag him backwards as he sets off.
            bolt.timingMode = .easeIn
            rabbit.run(.sequence([bolt, .removeFromParent()]))
        }
    }

    /// Where the sheet last drew the dog, in scene coordinates.
    private var drawnDogX: CGFloat {
        guard let stage = intro,
              let walker = stage.childNode(withName: "walker") as? SKSpriteNode
        else { return Layout.dogX }
        let left = walker.position.x - walker.size.width * walker.anchorPoint.x
        return stage.position.x + left + walker.size.width * IntroArt.dogCentreXFraction
    }

    /// The one way out of the clip, taken whether it played through or was
    /// tapped away, so the two can't drift apart.
    private func finishIntro() {
        guard isIntro else { return }
        isIntro = false
        introRidesAlong = false

        intro?.removeFromParent()
        intro = nil
        introRabbit = nil

        removeAction(forKey: "worldScroll")
        worldScroll = 1
        scenery.removeAllActions()
        scenery.speed = 1

        dog.removeAllActions()
        dog.isHidden = false
        dog.alpha = 1
        dog.setScale(1)
        dog.position = CGPoint(x: Layout.dogX, y: Layout.dogGroundLine + Layout.dogSize.height / 2)
        dog.physicsBody?.velocity = .zero
        dog.physicsBody?.isDynamic = true
        // Put back on the ground rather than dropped onto it, so the first jump
        // doesn't have to wait for a landing contact to arrive. The contact then
        // arrives anyway and says the same thing, which is exactly why this is a
        // flag: as a tally, this line and that contact came to two, and two
        // never counted back down to nothing.
        isOnGround = true

        hasStarted = true
        onIntroFinished?()
    }

    /// Eases `worldScroll` to a value. It isn't a node property, so it can't
    /// simply be animated — but it is the thing the whole clip hands over with,
    /// and handing it over in one step is a visible jolt.
    private func ramp(worldScroll target: CGFloat, over duration: TimeInterval) {
        let from = worldScroll
        removeAction(forKey: "worldScroll")
        run(.customAction(withDuration: duration) { [weak self] _, elapsed in
            let progress = duration > 0 ? min(1, elapsed / CGFloat(duration)) : 1
            self?.worldScroll = from + (target - from) * progress
        }, withKey: "worldScroll")
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver else { return }

        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        // Clamped so a stall — backgrounding, a slow first frame — can't advance
        // the spawner by a huge step and dump a wall of obstacles at once.
        let delta = min(currentTime - lastUpdateTime, 1.0 / 30)
        lastUpdateTime = currentTime

        // The man is pinned to the turf rather than given a slide of his own, so
        // that when the world does start moving he can't moonwalk against it.
        let step = gameSpeed * worldScroll * CGFloat(delta)
        scrollGroundDetail(by: step)
        if introRidesAlong {
            intro?.position.x -= step
        } else if isIntro {
            // The rabbit is out in the world rather than part of the shot, so he
            // is walked by the same step the grass is: whatever the scroll does,
            // he cannot slide against the ground he is sitting on. Once the stage
            // rides along it carries him, and stepping him here as well would
            // move him twice.
            introRabbit?.position.x -= step
        }

        // Benny's legs keep pace with the ground. Without this the gait stays
        // fixed while the world accelerates, and by the top speed he looks like
        // he's being dragged along rather than running.
        //
        // Grounded only. The jump arc is already timed to the airtime, so
        // scaling it too would run it ~1.7x fast at the top scroll speed and
        // leave him holding the landing pose for most of the flight.
        // Grounded and running only. The jump arc is timed to the airtime and
        // the slide to a distance, so both already account for `gameSpeed` —
        // scaling them again here would cut them short at the top speed.
        dog.childNode(withName: "body")?.speed =
            (isOnGround && !isSliding) ? gameSpeed / Layout.openingSpeed : 1

        // Everything above keeps the title screen alive; everything below is the
        // game proper and waits for the first tap.
        guard hasStarted else { return }

        obstacleTimer += delta
        if obstacleTimer >= obstacleInterval {
            obstacleTimer -= obstacleInterval
            spawnObstacle()
            // The floor is held above both the airtime and the slide, not
            // chosen for pacing: at the top scroll speed a jump covers 454pt
            // and a slide 400pt, so a tighter gap than this would run one
            // obstacle into the next with no ground time to react in between.
            // It has had to climb every time Benny has grown.
            obstacleInterval = max(1.30, obstacleInterval - 0.02)
            gameSpeed = min(Layout.topSpeed, gameSpeed + 4)
        }

        scoreClearedObstacles()
    }

    private func scrollGroundDetail(by distance: CGFloat) {
        let wrap = Layout.sceneSize.width + 140
        for tuft in groundDetail.children {
            tuft.position.x -= distance
            if tuft.position.x < -70 { tuft.position.x += wrap }
        }
    }

    /// One point per obstacle cleared. Counting frames instead would score twice
    /// as fast on a 120Hz display as on a 60Hz one.
    private func scoreClearedObstacles() {
        enumerateChildNodes(withName: "obstacle") { node, _ in
            guard node.userData?["scored"] == nil, node.position.x < Layout.dogX else { return }
            let data = node.userData ?? NSMutableDictionary()
            data["scored"] = true
            node.userData = data

            self.score += 1
            self.onScoreChange?(self.score)
        }
    }

    // MARK: - Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        let categories = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if categories == (PhysicsCategory.dog | PhysicsCategory.ground) {
            isOnGround = true
            // Not while sliding. Swapping in the ducked body makes the ground
            // report a fresh contact, and landing back into a gallop here would
            // wipe the slide a frame or two after it started — which is exactly
            // what made the slide impossible to see.
            if !isGameOver, !isSliding {
                squash(xScale: 1.2, yScale: 0.8)
                puffDust()
                // Only if he was actually in the air. A contact also arrives the
                // moment the world is built and again on every retry, with him
                // standing still on the ground both times.
                if hasLeftGround {
                    hasLeftGround = false
                    Sfx.shared.play(.land)
                    Haptics.land()
                }
                // Back to running. The jump arc is a one-shot, so without this
                // he'd hold the landing pose and skate along in it.
                if let body = dog.childNode(withName: "body"), DogArt.frames.count > 1 {
                    body.removeAction(forKey: "gait")
                    body.run(gallop, withKey: "gait")
                }
            }
        }

        if categories == (PhysicsCategory.dog | PhysicsCategory.obstacle) {
            endGame()
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let categories = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        guard categories == (PhysicsCategory.dog | PhysicsCategory.ground) else { return }

        // Only from the body he currently has. Swapping his hitbox destroys the
        // old one, and everything here says a destroyed body never reports its
        // contact ended — but if one ever did, and arrived after its
        // replacement had already reported the same contact beginning, this
        // would read as him leaving ground he is plainly standing on, and he
        // would never jump again.
        guard contact.bodyA === dog.physicsBody || contact.bodyB === dog.physicsBody else { return }

        isOnGround = false
    }

    // MARK: - Game over / restart

    /// How long the frozen scene is left alone before the message arrives.
    ///
    /// The freeze was always there; what was missing was any time to read it.
    /// The label used to appear on the same frame as the impact, which reads as
    /// a cut rather than as a stop — the run doesn't end, it is simply replaced
    /// by a label. Three or four frames of nothing is all it takes.
    private static let crashHold: TimeInterval = 0.09

    private func endGame() {
        guard !isGameOver else { return }
        isGameOver = true
        physicsWorld.speed = 0
        scenery.isPaused = true
        // Otherwise he keeps galloping on the spot in the frozen scene.
        dog.childNode(withName: "body")?.isPaused = true
        enumerateChildNodes(withName: "obstacle") { node, _ in node.removeAllActions() }

        Sfx.shared.play(.crash)
        Haptics.crash()
        // Harder than a landing, and the last thing he does. Actions still run
        // in a scene whose *physics* is stopped, which is what lets the impact
        // play out over a world that has already frozen.
        squash(xScale: 1.35, yScale: 0.68)
        flash()

        messageLabel = SKLabelNode(fontNamed: "AvenirNextCondensed-Heavy")
        messageLabel.text = "Good boy! Tap to retry"
        messageLabel.fontSize = 30
        messageLabel.fontColor = Palette.ink
        messageLabel.horizontalAlignmentMode = .center
        // Centred vertically, the one part of the scene `.aspectFill` never crops.
        messageLabel.position = CGPoint(x: Layout.sceneSize.width / 2, y: Layout.sceneSize.height / 2)
        messageLabel.zPosition = 50
        messageLabel.setScale(0)
        addChild(messageLabel)
        messageLabel.run(.sequence([
            .wait(forDuration: Self.crashHold),
            .scale(to: 1, duration: 0.25),
        ]))

        onGameOver?(score)
    }

    /// A frame or two of white over the whole scene.
    ///
    /// Kept faint and kept short. The artwork is already bright, and a flash
    /// that actually whites it out reads as a rendering fault rather than as an
    /// impact — this is only here to put a hard edge on the frame Benny stops.
    ///
    /// Under the message rather than over it, so it is finished with by the time
    /// there is anything to read.
    private func flash() {
        let sheet = SKSpriteNode(color: .white, size: Layout.sceneSize)
        sheet.position = CGPoint(x: Layout.sceneSize.width / 2, y: Layout.sceneSize.height / 2)
        sheet.zPosition = 45
        sheet.alpha = 0
        addChild(sheet)
        sheet.run(.sequence([
            .fadeAlpha(to: 0.3, duration: 0.03),
            .fadeOut(withDuration: 0.12),
            .removeFromParent(),
        ]))
    }

    /// Rolls the opening clip, and then begins play.
    ///
    /// `hasStarted` is deliberately not cleared by `restart`, so retrying after
    /// a crash drops straight back into the run rather than bouncing the player
    /// out to the title screen — and, now, without sitting through the clip
    /// again. Backing out to the title does clear it, so the next Play plays it.
    func start() {
        runIntro()
    }

    /// Winds the world back to its opening state and stops play, so the title
    /// screen has a fresh run waiting behind it rather than a half-finished one.
    func returnToTitle() {
        // Cleared first: `restart` rebuilds the world, and whether that world
        // has the opening clip standing in it turns on this.
        hasStarted = false
        restart()
    }

    private func restart() {
        removeAllChildren()
        removeAllActions()

        intro = nil
        isIntro = false
        introRidesAlong = false
        worldScroll = 1
        score = 0
        isGameOver = false
        isSliding = false
        hasLeftGround = false
        touchOrigin = nil
        gestureResolved = false
        isOnGround = false
        obstacleTimer = 0
        obstacleInterval = 1.8
        gameSpeed = Layout.openingSpeed
        lastUpdateTime = 0
        physicsWorld.speed = 1

        onScoreChange?(0)
        onRetry?()
        build()
    }

    // MARK: - Helpers

    /// A vertical two-stop gradient. `SKShapeNode` can't fill with one, so it is
    /// drawn once into a texture.
    private static func gradientTexture(from bottom: SKColor, to top: SKColor, size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let colors = [bottom.cgColor, top.cgColor] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size.height),
                end: CGPoint(x: 0, y: 0),
                options: []
            )
        }
        return SKTexture(image: image)
    }
}
