//
//  GameScene.swift
//  Benny's Great Escape
//
//  Benny gallops, you tap to jump, the logs, bushes and stumps keep coming.
//
//  The world is drawn entirely in code — gradient sky, parallax clouds and
//  hills, scrolling turf. Everything you actually play against is painted and
//  lives in the asset catalogue: Benny himself (a gallop, a jump arc and a
//  slide), the three things he jumps, and the bench and swingset he ducks
//  under.
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
/// Authored landscape. `.aspectFill` crops a little off the top and bottom to
/// fill the screen, so nothing that matters sits near either: the painting runs
/// well below `groundTop`, and the live score is drawn by SwiftUI over the top
/// rather than inside the scene.
private enum Layout {
    static let sceneSize = CGSize(width: 800, height: 500)

    /// How much of the world every length below is drawn at, against the
    /// portrait numbers this was all tuned as.
    ///
    /// Landscape buys width and spends height: 500 units tall, of which
    /// `.aspectFill` shows only 368. At his portrait size Benny leaves the top
    /// of the frame at the apex of a jump, so the whole world comes down
    /// together rather than the jump alone being clipped — which would have
    /// broken the clearances every obstacle is sized by.
    ///
    /// One number, so the relationships the comments below describe all still
    /// hold and the spike is a single edit to reverse.
    static let worldScale: CGFloat = 0.8

    /// What the speeds scale by, which is deliberately not `worldScale`.
    ///
    /// A jump's airtime goes as the square root of its height, so a world scaled
    /// by `s` with its speeds scaled by `s` too would have every jump cover only
    /// `s^1.5` of the ground it used to — while the obstacle widths, which scale
    /// by `s`, carried on expecting the full share. Speed has to go as the
    /// square root for the distance a jump covers to scale with everything else,
    /// and it is the distance that binds. See `jumpHeight`.
    static let speedScale: CGFloat = sqrt(worldScale)

    /// Never a crop — landscape crops the other axis, see `visibleInsetY` — but
    /// the opening clip is framed against it anyway, because the scene is
    /// presented edge to edge (`.ignoresSafeArea()`) and a notch or Dynamic
    /// Island can land on this side of it even though the art itself never
    /// loses a pixel here: the scene is 1.60 wide against 2.17 on the phone, so
    /// `.aspectFill` fits the width exactly.
    ///
    /// Which side depends on which of the two supported landscape orientations
    /// is current — the notch flips with it — so this can't be a constant. Set
    /// once, live, in `didMove(to:)`, from `view.safeAreaInsets.left`: whichever
    /// orientation is current, that is the edge the notch actually lands on.
    static var visibleInset: CGFloat = 0

    /// The widest the scene can ever be shown, which is now always all of it.
    static let widestVisible: CGFloat = sceneSize.width

    /// What `.aspectFill` crops off the top and bottom on the tallest-ratio
    /// phone, leaving 66…434 of the 500 authored.
    ///
    /// The binding one is 874x402 — the 16 Pro, 17 and 17 Pro — at 2.174, with
    /// the Pro Max phones within a hair of it. This is the ceiling a jump has to
    /// stay under, and it is what caps `worldScale`.
    ///
    /// The SE is the exception here exactly as it was for the sides, and in the
    /// safe direction this time: at 1.78 it is squarer than the scene, so it
    /// crops 25 rather than 66 and shows more sky, not less.
    static let visibleInsetY: CGFloat = 66

    /// The top of what is actually shown, as against the top of what is
    /// authored. The line Benny's head is checked against at the apex.
    static var visibleTop: CGFloat { sceneSize.height - visibleInsetY }

    /// Where the dog and every obstacle stand.
    ///
    /// Just under a third of the way up what is actually shown — 109 above the
    /// visible bottom edge of 66, in a band 368 tall. Portrait had it at 35%,
    /// and the difference is sky that landscape can no longer afford: the
    /// headroom above this is what a jump has to fit inside.
    static let groundTop: CGFloat = 175

    /// Sized off the collar, which is the one part of the drawing that keeps a
    /// fixed size whatever Benny's doing — matching canvas widths would shrink
    /// him, because the gallop poses stretch the canvas without making the dog
    /// any bigger.
    static let dogWidth: CGFloat = 125 * worldScale

    /// Height follows the artwork's aspect so Benny is never stretched, and
    /// keeps following it if the drawing is ever replaced with one shaped
    /// differently.
    static var dogSize: CGSize {
        CGSize(width: dogWidth, height: dogWidth / DogArt.aspect)
    }

    /// Not scaled with the world, and the one length that isn't.
    ///
    /// Held near its portrait value in absolute terms, because against an
    /// 800-wide scene this is what sets the runway: 700 units of warning where
    /// portrait had 280. That is the whole point of the exercise.
    static let dogX: CGFloat = 100

    /// Where an obstacle is stood up, far enough past the right edge that it
    /// is never seen arriving. A cliff starts here too and is then nudged
    /// further right to land clear of the backdrop's turf sprigs — see
    /// `cliffSpawnX`, which measures its nudge from this.
    static var spawnX: CGFloat { sceneSize.width + 60 }

    /// Where a run starts. This is what caps the obstacle sizes in
    /// `ObstacleArt`: a jump lasts a fixed time, so the slowest the world ever
    /// moves is the least ground a jump ever covers, and everything has to be
    /// clearable there.
    ///
    /// It rose with Benny. The world scrolled at 220 when he was 80pt wide, and
    /// leaving it there while he grew made the game feel steadily more sluggish
    /// against him — and held the things he jumps down to toys beside him.
    static let openingSpeed: CGFloat = 280 * speedScale

    /// Where the ramp tops out. Held 160 above the opening, as it always has
    /// been, so a run still accelerates over its first 40 obstacles.
    static let topSpeed: CGFloat = 440 * speedScale

    /// Apex of a jump above `groundTop`. Obstacles top out around 78, so this is
    /// forgiving without feeling floaty.
    ///
    /// Height isn't the binding constraint, though — width is. A jump lasts a
    /// fixed time, so at the opening scroll speed it covers only ~231pt, and an
    /// obstacle's box plus Benny's own has to fit inside the stretch of that arc
    /// spent above it. That is what caps the obstacle sizes in `ObstacleArt`.
    ///
    /// Which is why this rises with `dogWidth`: a wider dog spends more of that
    /// stretch on himself, and left alone a full-height log goes from clearable
    /// to impossible. Every 25% on Benny has cost about 25pt here. It drags the
    /// spawn interval floor in `update` up with it, which the airtime has to
    /// stay under — and with the floor where it is, this is as high as it can
    /// go. Buying clearance beyond here means `Layout.openingSpeed`, not this.
    static let jumpHeight: CGFloat = 180 * worldScale

    /// How far a painted obstacle is pushed below the turf line by default.
    ///
    /// Has to clear the 8pt dark cut-turf edge drawn by `makeGround`, not just
    /// `groundTop`: obstacles draw over the ground, so a shallower sink leaves
    /// the pale highlight along the bottom of each drawing's grass sitting on
    /// top of that dark band, and the obstacle reads as resting on the ground
    /// rather than growing out of it. Individual pieces override it — how much
    /// painted grass there is to bury differs per drawing.
    static let obstacleSink: CGFloat = 12 * worldScale

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
    static let dogPlantDepth: CGFloat = 7 * worldScale

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
    static let duckClearance: CGFloat = 52 * worldScale

    /// A slide covers this much ground rather than lasting a fixed time — at
    /// the top scroll speed a fixed duration would end before the bench had
    /// finished passing. Bench plus dog is about 330, so this leaves margin.
    static let slideDistance: CGFloat = 400 * worldScale

    /// How flat a contact shadow is: its height as a fraction of its width.
    ///
    /// Low, because the turf is seen almost edge-on. A rounder one reads as a
    /// hole in the ground rather than something resting on it.
    static let shadowFlatness: CGFloat = 0.26

    /// How wide a shadow is against the footprint it's given. A little over
    /// one, so it shows past the thing standing on it — drawn narrower it
    /// vanishes entirely under anything with a wide base, like the stump.
    static let shadowWidthFraction: CGFloat = 1.06

    /// What a shadow shrinks to, and fades to, at the top of a jump.
    ///
    /// Height is the only thing a side-on runner can say about being off the
    /// ground, and this is what says it — without a shadow a jump reads as
    /// sliding up the screen rather than leaving it.
    static let shadowLiftScale: CGFloat = 0.45
    static let shadowLiftAlpha: CGFloat = 0.30

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
    /// him rather than quietly walking his foot off the edge. Lands around 61
    /// with no inset; further right on a notched phone, in whichever of the two
    /// landscape orientations puts the notch on this edge.
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

    /// The rabbit waits here — far enough ahead that Benny spotting him and
    /// giving chase reads as the beat, rather than a near miss the way a
    /// tighter gap once staged it.
    ///
    /// Landscape's wide, uncropped scene already broke the old staging this
    /// used to protect (see `stageIntro`'s "KNOWN LANDSCAPE REGRESSION": the
    /// camera-pan reveal it was tuned against doesn't happen any more, since
    /// he's in view from the first frame regardless of where this puts him),
    /// so there's no tight budget left to spend here. What sets this now is
    /// simply how far he has left to run once he breaks — see `rabbitAheadFraction`.
    static var rabbitX: CGFloat { manX + rabbitAheadFraction * walkerSize.width }

    /// How far ahead of the walker the rabbit sits, as a multiple of the
    /// walker's own width.
    ///
    /// Pushed well out past the old portrait-derived 0.820, so that the run
    /// he breaks into (see `handOff`) has meaningfully less ground to cover —
    /// raising this is the one lever for that, since his run-off distance is
    /// always measured live from wherever this actually places him.
    static let rabbitAheadFraction: CGFloat = 1.8

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

    /// How fast he runs once he breaks, in the screen's own terms rather than
    /// the camera's — he's peeled off the stage at that point (see `handOff`),
    /// so this is his actual, literal ground speed, not a speed netted against
    /// a moving world.
    ///
    /// A speed forced to cross the remaining distance in some fixed short time
    /// looked wrong regardless of the number chosen: the gallop frames keep
    /// their own cadence (`timePerFrame: 0.07` in `handOff`), so pushing the
    /// translation speed up without it slides his legs against the ground —
    /// he reads as skating, not sprinting. This is close to a normal running
    /// pace instead, matched to the same gallop the rest of the game already
    /// runs Benny at (`Layout.topSpeed`), so his legs and his travel agree.
    static let rabbitRunSpeed: CGFloat = Layout.topSpeed

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

/// The painted world Benny runs through, and the handful of numbers it is
/// staged by.
///
/// One image, cut from a much longer painting by `Art/CropBackground.swift`.
/// The fractions below are what that script prints — measured off the crop
/// rather than typed in, so a repainted background is a rerun and a paste.
private enum BackdropArt {
    /// Probed rather than named directly, for the reason `ObstacleArt.load`
    /// gives: `SKTexture(imageNamed:)` hands back a placeholder for a missing
    /// name instead of admitting the art has gone.
    static let sheet: SKTexture? = UIImage(named: "bg_scroll").map(SKTexture.init(image:))

    /// The crop is exactly one repeat of the painting, so laying two of them end
    /// to end joins with nothing to see. Both the length of that repeat and
    /// where to take it from were found by sliding the source over itself —
    /// see the script, which prints how much better the join it chose is than
    /// the worst one available.
    static let aspect: CGFloat = 1.9174

    /// Down from the top of the crop: the near and far edges of the grass, and
    /// the band of flat sky the two scrolling layers are cut at.
    static let grassLineFraction: CGFloat = 0.5098
    static let earthLineFraction: CGFloat = 0.6152
    static let skySplitFraction: CGFloat = 0.3098

    /// How far down the grass everything stands. Nought is its near edge, one
    /// the lip of the cut earth.
    ///
    /// Half way, so there is field behind them and field in front — which is
    /// what standing in a field looks like. On the near edge, where this
    /// started, the bush line sits at Benny's heels and the whole flowered
    /// strip lies in front of him untouched, and he reads as pressed against a
    /// hedge rather than running through a park.
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

    /// How tall the whole crop is drawn, in scene points.
    ///
    /// Not picked — the larger of the two heights it has to reach. Above the
    /// line they stand on the painting has to fill the scene to its top, and
    /// below it, down to the bottom; whichever asks for more decides, and the
    /// other is covered with room to spare. Here it is the ground that asks:
    /// the painting carries far more sky than field, so the sky it doesn't need
    /// runs off the top of the scene and is never seen.
    ///
    /// Which is why standing them further down the grass makes the whole
    /// painting bigger — there is less of it left below them to reach the
    /// bottom of the scene with.
    static var height: CGFloat {
        max((Layout.sceneSize.height - Layout.groundTop) / anchorFraction,
            Layout.groundTop / (1 - anchorFraction))
    }

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

// MARK: - The obstacle artwork

/// Everything Benny meets on the path, painted and dropped into the catalogue:
/// a fallen log, a bush and a tree stump to jump, and a park bench and a
/// swingset to duck.
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

        /// How far the solid reaches above the drawing's foot, per unit of the
        /// drawing's height — how high Benny has to get.
        var topPerHeight: CGFloat {
            switch self {
            case let .box(_, height, base): base + height
            case let .disc(radius, centre): centre + radius
            }
        }

        /// How high Benny's feet have to be when the solid's centre is `gap`
        /// away from his, or `nil` where it can't touch him at all.
        ///
        /// Everything about the shape that matters to a jump, in one function.
        /// Both arguments and the result are in scene units, with `dogWidth`
        /// the width of his own body box, because what he has to clear is
        /// really the solid *grown by his own box* — slide a rectangle round a
        /// shape and the swept outline is what its corner traces.
        ///
        /// For a box that outline is another box, so this is a step: get above
        /// the top, stay there while the two overlap, and the width is the
        /// solid's plus his.
        ///
        /// For a disc it is a box with rounded ends, and that rounding is the
        /// whole reason this function exists. It used to report a disc as
        /// `2 * radius` wide at every height — a rectangle round a circle — and
        /// that is not what a jump meets. He crosses at the crown, which is the
        /// narrow part; the shoulders curve away beneath him and he never has
        /// to be above those at all. Sized as a rectangle, the bush came out
        /// asking for 150ms of timing and actually giving 268, nearly twice
        /// what every other obstacle allowed, and it was the one prop in the
        /// game that felt like a gift.
        /// Defined over `-reach ... +reach` and clamped inside it rather than
        /// refusing at the edge. Deliberately: the caller samples the ends of
        /// exactly that interval, and asking "is this gap within reach?" of a
        /// number that *is* the reach is a coin toss on the last bit of the
        /// mantissa. Losing that toss drops both end samples, and for a box the
        /// ends are the only samples that decide anything — it read 14ms easier
        /// than it was, on whichever props happened to round the wrong way.
        func clearance(at gap: CGFloat, height: CGFloat, aspect: CGFloat,
                       dogWidth: CGFloat) -> CGFloat {
            let reach = max(0, gap.magnitude - dogWidth / 2)
            switch self {
            case let .box(_, boxHeight, base):
                return height * (base + boxHeight)
            case let .disc(radius, centre):
                let r = height * radius
                // Flat across his own width, then the circle's own curve.
                return height * centre + max(0, r * r - reach * reach).squareRoot()
            }
        }

        /// How far either side of centre this solid can touch Benny at all,
        /// his own box included — the domain `clearance(at:)` is defined over.
        ///
        /// Exact rather than generous, which matters more than it sounds: a
        /// box's profile is a step, and the step is the only place its window is
        /// decided. Sample a span wider than the solid and the outermost sample
        /// sits inboard of the real edge, so the box comes out easier than it
        /// is — enough to disagree with the closed form this replaced. Landing
        /// the end samples on the edge makes a box exact at any sample count.
        func reach(height: CGFloat, aspect: CGFloat, dogWidth: CGFloat) -> CGFloat {
            switch self {
            case let .box(width, _, _): height * aspect * width / 2 + dogWidth / 2
            case let .disc(radius, _): height * radius + dogWidth / 2
            }
        }
    }

    /// Something hung off a drawing that moves on its own: the swingset's two
    /// swings, cut out of its frame by `Art/CutSwingset.swift` so that they can
    /// rock on the bar while the A-frame stands still.
    ///
    /// Stated in fractions of the drawing it hangs on, like everything else
    /// here, so a re-cut drawing carries its swings with it.
    struct Hang {
        let texture: SKTexture?

        /// The hanger, as a fraction of the drawing's width from its centre and
        /// of its height from its top. The sprite is pinned to the bar by its
        /// own top edge, which is where the cut was made.
        let pivotXFraction: CGFloat
        let pivotYFraction: CGFloat

        /// Width as a fraction of the drawing's; the height follows the swing's
        /// own aspect, so a swing is never stretched against its frame.
        let widthFraction: CGFloat

        /// How far into its first swing this one starts, 0 to 1. Two swings
        /// rocking in step read as one object with a hinge in it.
        let swayPhase: CGFloat

        /// How far a swing rocks, and how long it takes.
        ///
        /// Small, and not for the look of it: the physics box is measured with
        /// the seats at rest, so this is the amount they are allowed to disagree
        /// with it by. At six degrees a seat moves five points sideways and
        /// *rises* a quarter of one — and rising is the safe direction, since it
        /// can only ever open the gap Benny slides through, never close it.
        static let swayAngle: CGFloat = 6 * .pi / 180
        static let swayPeriod: TimeInterval = 2.2
    }

    /// One kind of obstacle: its drawing, how big it is allowed to be, and
    /// which part of the drawing is actually solid.
    struct Piece {
        let texture: SKTexture?

        /// How big this piece is allowed to get — a clamp, not a choice.
        ///
        /// The height itself comes from `obstacleHeight(_:at:)`, which solves
        /// for one shared timing window; this only has to be wide enough to
        /// hold every size the piece can take plus the `heightJitter` either
        /// side, and no wider. Anything wider is a lie about what appears.
        ///
        /// Which is now three sizes rather than one, since a prop is solved for
        /// whichever of `ObstacleArt.sizeTiers` the world has reached — so each
        /// of these spans from the smallest tier's jitter to the largest's, and
        /// is correspondingly loose. It cannot catch a mis-set tier on its own;
        /// `Art/CutJumpObstacles.swift` prints every tier against its clamp for
        /// that.
        ///
        /// What they are *not* is the ranges this had before any of that, which
        /// were picked by hand and drawn from with `.random(in:)`. Those are
        /// still in the commit history and are not somewhere to go back to: a
        /// bush rolled at its old upper bound is unclearable at the opening
        /// speed — a perfectly timed jump still clips it by 72ms — and only the
        /// solver ever caught that.
        ///
        /// They differ from each other because the solids do: a disc round the
        /// bush and a box stopping at the log's cylinder both shed lethal empty
        /// air, so those two carry more height for the same demand.
        ///
        /// Height is what's tuned; width follows the drawing's own aspect, so
        /// re-cropped art can never come out stretched — and it is the width
        /// that binds, since width comes along for the ride.
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

        /// Anything hung off the drawing. Empty for everything that is one
        /// picture standing still, which is everything but the swingset.
        var hangs: [Hang] = []

        /// Width over height of the drawing — what turns a height into a
        /// width, here and in `size(height:)`. Same fallback as that, for the
        /// same reason.
        var aspect: CGFloat {
            guard let texel = texture?.size(), texel.height > 0 else { return 2 }
            return texel.width / texel.height
        }

        /// The 2:1 fallback only matters if the art is missing, in which case
        /// the drawn block stands in for it.
        func size(height: CGFloat) -> CGSize {
            guard let texel = texture?.size(), texel.height > 0 else {
                return CGSize(width: height * 2, height: height)
            }
            return CGSize(width: height * texel.width / texel.height, height: height)
        }
    }

    // Every piece below — art, solid and clamp alike — is measured and printed
    // by `Art/CutJumpObstacles.swift`. Repaint a prop, rerun it, paste. The
    // notes are about what each solid deliberately leaves *out*, because that
    // is the part a measurement can't tell you and the next repaint will need.

    /// The domed bush, and the only one of these that is really round.
    ///
    /// A least-squares circle through its upper silhouette comes out at radius
    /// 0.842, pulled in to sit inside the foliage rather than on its best-fit
    /// average. The loose leaves spilling either side of the base are left
    /// outside it, which is the whole reason this is a disc: a rectangle round
    /// the same drawing is four fifths empty air at the top corners, and the
    /// top corner is exactly where a descending jump arrives.
    ///
    /// Much the biggest prop in the set, at 68 x 121 against the stump's 70 x 69,
    /// and it earned that rather than being scaled up. Being round, it is the
    /// one obstacle whose width Benny doesn't have to clear all of — he passes
    /// over the crown while the shoulders curve away under him. The solver used
    /// to miss that and charge it for the full `2 x radius` anyway, so it came
    /// out a third too small and gave 268ms of timing where everything else gave
    /// 150. Now that `Solid.clearance` traces the real outline, the same bush at
    /// the same difficulty is simply bigger.
    static let bush = Piece(
        texture: load("obstacle_bush"),
        heightRange: (81 * Layout.worldScale)...(125 * Layout.worldScale),
        solid: .disc(radius: 0.808, centre: 0.102), offsetXFraction: 0
    )

    /// The squared-off hedge — the same shrub clipped flat, and a box.
    ///
    /// Not for want of a circle fitting it: one sits on its top arc to an
    /// average error of two hundredths, as good as the bush's. But it comes out
    /// radius 0.84 against a drawing only 1.29 wide, so the disc would be wider
    /// than the picture it is supposed to live inside. Fitting the top of
    /// something is not the same as it being round.
    static let hedge = Piece(
        texture: load("obstacle_hedge"),
        heightRange: (73 * Layout.worldScale)...(106 * Layout.worldScale),
        solid: .box(width: 0.947, height: 0.908, base: 0), offsetXFraction: -0.002
    )

    /// The single fallen log.
    ///
    /// The box stops at the top of the cylinder, leaving out the branch stub
    /// and its leaves. That exclusion is the one that matters most here: the
    /// stub is narrow and reaches a quarter again as high as the wood, so a box
    /// drawn round the whole drawing would be mostly nothing at the top and
    /// would kill Benny for passing through thin air.
    static let log = Piece(
        texture: load("obstacle_log"),
        heightRange: (59 * Layout.worldScale)...(91 * Layout.worldScale),
        solid: .box(width: 0.950, height: 0.758, base: 0), offsetXFraction: 0
    )

    /// Three logs stacked — two below, one across the top.
    ///
    /// The odd one out, and the reason the width rule is what it is. Its
    /// silhouette steps: only the lower course reaches the right-hand end. Ask
    /// how *filled* each column is and the stack reads as three quarters width,
    /// which cut the right-hand logs clean out of the solid. Ask instead how
    /// high each column reaches — whether there is anything there to hit at all
    /// — and it comes out at the 0.915 the picture plainly shows.
    static let logStack = Piece(
        texture: load("obstacle_log_stack"),
        heightRange: (70 * Layout.worldScale)...(102 * Layout.worldScale),
        solid: .box(width: 0.918, height: 0.911, base: 0), offsetXFraction: 0.009
    )

    /// The upright stump, and the tallest, narrowest thing in the game.
    ///
    /// At an aspect of 0.99 it renders very nearly square — 69 x 68 — where
    /// everything else here is half again as wide as it is tall. That is worth
    /// keeping rather than tidying away: a prop this narrow passes Benny
    /// quickly but has to be got properly over, which is a different demand
    /// from the long low ones, and the set had nothing like it before.
    ///
    /// The box takes the trunk. The cut face on top is an ellipse, so its outer
    /// corners fall outside — the taper at the foot likewise.
    static let stump = Piece(
        texture: load("obstacle_stump"),
        heightRange: (82 * Layout.worldScale)...(116 * Layout.worldScale),
        solid: .box(width: 0.950, height: 0.947, base: 0), offsetXFraction: 0
    )

    /// The jump rotation. The two you duck are deliberately not in here — they
    /// have a rotation of their own, in `ducks`.
    ///
    /// Flat, so a bush or a log turns up twice as often as the stump, there
    /// being two of each. Left that way on purpose: the variants exist to break
    /// up the repetition, and weighting them back down to a third each would
    /// undo most of what they were painted for.
    static let jumps = [bush, hedge, log, logStack, stump]

    /// How early a player may jump and still clear — the window every jump
    /// piece is sized for. The same knob `Cliff.clearance` is for the gap.
    ///
    /// Held by stepping each prop's size up as the world speeds up, rather than
    /// by growing it continuously — see `sizeTiers`, which is where that is
    /// actually done.
    ///
    /// Both halves of that mattered. A fixed prop against a fixed jump arc gets
    /// steadily easier the faster the world runs, so sizing everything once and
    /// leaving it made the late game the slack part: 149ms of margin at the
    /// opening against 394ms at top speed, two and a half times more forgiving
    /// exactly where it should have been hardest.
    ///
    /// Solving against the *live* speed fixes that and was tried first. It
    /// failed for a reason that has nothing to do with difficulty: width
    /// follows the drawing's aspect, so a prop sized for a faster world grows
    /// in both directions at once, and a log that ran 117 units early and 187
    /// by the end read as the artwork being wrong rather than the game being
    /// hard. Growth was never the problem; watching it happen was.
    static let clearance: TimeInterval = 0.15

    /// The speeds a jump prop may be *sized* for. A spawn takes the fastest of
    /// these at or below the live speed, so each drawing has three fixed sizes
    /// and steps between them instead of swelling.
    ///
    /// Quantising **down** is what keeps the game playable, and is not a detail:
    /// a prop's timing window only widens as the world gets faster, so one
    /// sized for a speed at or below the current one is always clearable, while
    /// one sized above it may not be. A prop solved for 320 units/s is already
    /// impossible in the opening seconds.
    ///
    /// The two upper figures were searched rather than chosen — the pair that
    /// minimises the worst drift anywhere in the speed range, at 5 unit
    /// resolution. Round-looking alternatives do measurably worse: 305 and 355
    /// leave 263ms where these leave 239ms.
    ///
    /// What this buys, and what it doesn't: the window now runs 149ms to 239ms
    /// across a whole run instead of 149ms to 394ms. It is a sawtooth, drifting
    /// up within a tier and snapping back at the next, not the flat line the
    /// live solve gave. That is the price of never changing a drawing's size
    /// while it is on screen.
    static let sizeTiers: [CGFloat] = [Layout.openingSpeed, 290, 335]

    /// The speed a prop spawning right now should be sized for.
    static func tier(for speed: CGFloat) -> CGFloat {
        sizeTiers.last { $0 <= speed } ?? sizeTiers[0]
    }

    /// How much a solved height is allowed to wander, so a rotation of three
    /// props doesn't come out as three fixed sizes marching past.
    static let heightJitter: CGFloat = 0.04

    /// How long the player gets to answer the second half of a pair, on top of
    /// any airtime the first half forced on them.
    static let pairRecovery: TimeInterval = 0.28

    /// From this score obstacles may arrive two at a time, and how many in ten
    /// spawns do. Late enough that both verbs are known, rare enough that the
    /// ordinary rhythm is still the ordinary rhythm.
    static let pairFromScore = 8
    static let pairInTen = 2

    /// Fraction of the bench drawing that is open air under the seat. High,
    /// because the seat was thinned to a plank: at the drawing's native
    /// chunkiness the slab came out as thick as the legs were tall, which left
    /// the bench towering over Benny's back rather than reading as something he
    /// could sit on.
    /// Fraction of the bench drawing that is open air under the seat, measured
    /// and printed by `Art/CutBench.swift`.
    ///
    /// It fell from 0.701 to 0.409 when the bench gained a back — the same seat
    /// and the same gap under it, but now only two fifths of the way up a much
    /// taller picture, which rendered the bench at 200x100 and had it dominate
    /// everything around it. The script answers that by taking material out of
    /// the drawing rather than scaling it, which is the only lever there is:
    /// this fraction is what `benchHeight` divides by to put the seat back on
    /// the clearance line, so the seat's height is never the thing that gives.
    private static let benchUnderseat: CGFloat = 0.494

    /// Shallower than the rest. The bench's feet are cast iron, not grass, so
    /// they only need to meet the turf rather than disappear into it — and
    /// every point of sink here makes the whole bench taller and wider, because
    /// the seat has to stay `duckClearance` above the turf regardless.
    private static let benchSink: CGFloat = 6 * Layout.worldScale

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
    ///
    /// Its box runs from the seat's underside to the top of the drawing, which
    /// since the repaint means to the top of the *backrest*. That settles what
    /// this obstacle is: the backless bench could be hurdled instead of ducked,
    /// though only at the top scroll speed, where a jump cleared its 59pt box
    /// with about 105ms in hand. The back puts the box at 101pt, and the 507ms
    /// a jump spends above that will not cover the 685ms the bench and Benny
    /// take to pass each other. So it is ducked, at every speed.
    static let bench = Piece(
        texture: load("obstacle_bench"), heightRange: benchHeight...benchHeight,
        solid: .box(width: 0.979, height: 1 - benchUnderseat, base: benchUnderseat),
        offsetXFraction: 0, sink: benchSink
    )

    /// Fraction of the swingset drawing that is open air under the seats, and
    /// the numbers that place the swings on the bar. All four are measured by
    /// `Art/CutSwingset.swift` and printed by it — the script is also what
    /// decides them, since it shortens the chains until the frame comes out at
    /// a size the scene has room for. Recut the art and it prints these again.
    private static let swingsetUnderbar: CGFloat = 0.393
    private static let swingsetPivotY: CGFloat = 0.101
    private static let swingsetSwingWidth: CGFloat = 0.146
    private static let swingsetHangers: [CGFloat] = [-0.250, 0.240]

    /// The bench's reasoning, and for the same reason: the foot plates are
    /// bolted metal rather than a skirt of grass, so they meet the turf instead
    /// of growing out of it, and every point of sink here would otherwise make
    /// the whole swingset taller and wider.
    private static let swingsetSink: CGFloat = 6 * Layout.worldScale

    /// Sized so the underside of the seats lands on the clearance line, exactly
    /// as `benchHeight` is. Comes out at 110pt tall and 247 wide — half again
    /// the bench's height, which is what makes the two read as different things
    /// to duck rather than the same thing twice.
    private static let swingsetHeight =
        (Layout.duckClearance + swingsetSink - Layout.dogPlantDepth) / swingsetUnderbar

    private static let swingsetSwing = load("obstacle_swingset_swing")

    /// The other one you slide under, and the one that all but insists on it:
    /// its box runs to the top of the drawing rather than stopping at a seat
    /// low enough to hurdle, as the bench's does. A jump spends 180pt above
    /// 110 at the opening speed and 283 at the top one, against the 273 the box
    /// and Benny need together — so hurdling this is impossible for most of a
    /// run and a ten-point window at the end of one.
    ///
    /// The box spans both seats and the air between them, because a piece gets
    /// one physics body and two would be a lie anyway — the gap passes in a
    /// fifth of a second at full tilt, and a slide covers the lot. Its width is
    /// the seats and their hooks, pulled in a little in Benny's favour; the
    /// legs, like the bench's, carry no physics and are simply run through.
    static let swingset = Piece(
        texture: load("obstacle_swingset_frame"), heightRange: swingsetHeight...swingsetHeight,
        solid: .box(width: 0.629, height: 1 - swingsetUnderbar, base: swingsetUnderbar),
        offsetXFraction: -0.002, sink: swingsetSink,
        hangs: swingsetHangers.enumerated().map { index, hanger in
            Hang(
                texture: swingsetSwing, pivotXFraction: hanger,
                pivotYFraction: swingsetPivotY, widthFraction: swingsetSwingWidth,
                swayPhase: index == 0 ? 0 : 0.45
            )
        }
    )

    /// The duck rotation, held apart from `jumps` because the two verbs are
    /// weighted against each other in `spawnObstacle` rather than drawn from
    /// one bag.
    static let ducks = [bench, swingset]

    /// Optional, and probed with `UIImage(named:)` for the same reason `DogArt`
    /// does it: `SKTexture(imageNamed:)` hands back a placeholder for a name
    /// that isn't there, so it can't tell you the art has gone missing. A nil
    /// here falls back to a drawn block rather than an invisible obstacle.
    private static func load(_ name: String) -> SKTexture? {
        UIImage(named: name).map(SKTexture.init(image:))
    }
}

/// Where the cliff's three pieces come from. The one obstacle drawn from a
/// cropped scene rather than an isolated sprite — the source mockup was a
/// full background (two ledges, the drop between them, distant hills), not a
/// cutout — so this holds three textures rather than `ObstacleArt.Piece`'s
/// one. See `Cliff` for how they're sized and placed, and `makeCliff` for why
/// this doesn't go through `ObstacleArt` at all.
/// How the rare cliff set-piece is staged and gated. Not an obstacle with a
/// physics box, unlike everything in `ObstacleArt` — the hazard is the
/// ground itself going away for a beat, tracked here and enforced in
/// `update`.
///
/// The gap is one painted sprite, `cliff_gap` — a crop of the notch out of
/// the reference art, drawn in the same style and palette as `bg_scroll`
/// itself (sampled both: bushes, turf and dirt match to within a few values
/// each). Everything it's sized and placed by is measured off that crop, so
/// a re-crop means updating the pixel figures below and nothing else.
///
/// Earlier versions built the gap out of live `BackdropArt.sheet` samples
/// instead — hills glimpsed through it, then a darkened version of the same,
/// then plain dirt, then dirt under a grass cap. All of them were trying to
/// *add* something at turf height. What the art shows is the opposite: in a
/// real gap the turf strip is simply **missing**, and what you see through it
/// is the background bushes, with the dirt continuing across underneath.
/// Covering grass with more grass is why the last version had no visible gap
/// at all.
private enum Cliff {
    /// `cliff_gap.png` (247×135), measured: how wide the crop is, how wide
    /// the opening inside it is, the turf band's thickness beside it, and
    /// the crop's full height. Printed by `Art/CutCliffGap.swift`, which cuts
    /// the asset as well — so a repainted gap is a rerun and a paste. It finds
    /// the rows with the same detectors `Art/CropBackground.swift` uses for
    /// `bg_scroll` itself, so the two sets of figures are comparable.
    ///
    /// The crop is cut to the game's proportions, not the art's own. Its top
    /// edge is the turf line exactly — deliberately not a pixel higher.
    /// An earlier version reached ~29 units further up to cover the real
    /// ground's tuft rise, and in doing so painted a flat, static patch over
    /// the live scrolling bushes, which is what kept reading as wrong
    /// through every attempt at this. Above the turf line the real
    /// background now shows through the gap, which matches by definition
    /// because it *is* the background. It stops as far below the dirt line
    /// as the real dirt band is deep (~28 units) — the reference art draws a
    /// far thicker dirt layer than this game's ground has, and cropping its
    /// full depth left the pit hanging well past where the real dirt ends.
    ///
    /// Its sides reach *past* the opening on purpose, and this is the whole
    /// difference between reading as a cliff and reading as a notch. The
    /// art's turf rolls over each lip and drops into a shaded cut face, and
    /// the crop reaches past both faces to carry them. An earlier crop trimmed
    /// to just inside the turf to avoid bringing foreign grass in — which cut
    /// off both lips exactly, leaving a turf notch with flat dirt behind it
    /// and no cliff at all.
    static let spritePx: CGFloat = 537
    static let gapPx: CGFloat = 445
    static let turfBandPx: CGFloat = 97
    static let cropHeightPx: CGFloat = 463

    /// Scene units per pixel of that crop, fixed by making its turf band
    /// land exactly on the game's own — which is what keeps the art's turf
    /// line and dirt line flush with the real ground either side of it.
    static var artScale: CGFloat { (grassRise - pitRise) / turfBandPx }

    /// How much of each end of the crop is lip and cut face, and so has to be
    /// drawn at native scale however wide the opening is — see `makeCliffPit`,
    /// which slices the sprite into these two caps and a stretched middle.
    ///
    /// Found by `Art/CutCliffGap.swift` rather than eyed: the first column, in
    /// from each end, whose colour above the dirt line has settled onto the
    /// interior's own, plus a few pixels of margin.
    static let capPx: CGFloat = 52

    /// How many rows at the top of the crop fade in rather than starting
    /// opaque, and so how far above the turf line the sprite's top edge sits.
    ///
    /// The sprite still covers the ground's turf from the turf line down; it
    /// just arrives gradually. Stopping flat on the line put its first painted
    /// row against an unrelated stretch of the backdrop's bush line and drew a
    /// straight edge across the scenery. See `Art/CutCliffGap.swift`.
    static let fadePx: CGFloat = 12

    /// Where the sprite's top edge goes: the turf line, raised by the fade.
    static var fadeRise: CGFloat { grassRise + fadePx * artScale }

    /// How far the sprite reaches *past* the opening, total — the ledge it
    /// carries on each side, which overlaps the real ground. Fixed by the art
    /// and so unaffected by how wide the opening is made.
    static var lipOverhang: CGFloat { (spritePx - gapPx) * artScale }

    /// How early a player may jump and still land clear.
    ///
    /// This is the difficulty knob: the gap is sized from it rather than the
    /// other way round. The gap used to follow the art at 1:1 — 113 units,
    /// against the 259 a jump covers at the speed cliffs used to unlock at,
    /// which left over half a second of slack and meant an early jump could
    /// never actually fall short.
    static let clearance: TimeInterval = 0.21

    /// The widest opening `bg_scroll` can hold. Not chosen — measured.
    ///
    /// The sprite stops on the turf line, so the real ground shows above it and
    /// the turf's own sprigs would otherwise stand over the hole with nothing
    /// under them. `cliffSpawnX` puts the gap where they don't, and this is as
    /// wide as the stretches it has to choose from allow — with room to spare
    /// inside them rather than filling them exactly, since a gap that only just
    /// fits leaves a window a few pixels wide to aim at.
    ///
    /// It was briefly 280, the width at which the timing stays constant at every
    /// speed, bought by covering the sprigs with a band of the gap painting's
    /// own haze. That band read as a patch laid over the scenery, worst of all
    /// mid-jump with Benny up beside it, so the width went back to what
    /// placement alone can keep clean.
    static let maxGapWidth: CGFloat = 170

    /// The sprite's drawn height. Its top edge goes straight on the turf
    /// line, since that's exactly where the crop starts.
    static var pitHeight: CGFloat { cropHeightPx * artScale }

    /// How far above `Layout.groundTop` the turf line sits, and so where the
    /// sprite's own top edge goes.
    ///
    /// Not a guess: `Layout.groundTop` isn't the top of the grass, it's
    /// `BackdropArt.standFraction` (half) of the way *through* it — the same
    /// derivation `BackdropArt.anchorFraction` itself uses — so the true
    /// grass line sits this far above it:
    static let grassRise: CGFloat = BackdropArt.landSize.height
        * (BackdropArt.anchorFraction - BackdropArt.grassLineFraction) / (1 - BackdropArt.skySplitFraction)

    /// How far above `Layout.groundTop` the dirt begins — negative, since
    /// this is below the grass, not at it. Same derivation as `grassRise`,
    /// off the earth line instead of the grass line. Only used to size
    /// `artScale`; the sprite itself is placed from `grassRise`.
    static let pitRise: CGFloat = BackdropArt.landSize.height
        * (BackdropArt.anchorFraction - BackdropArt.earthLineFraction) / (1 - BackdropArt.skySplitFraction)

    /// Spawns a cliff at every opportunity instead of rarely, for looking at
    /// the gap without having to play for one.
    ///
    /// Ships `false`. One switch rather than the handful of scattered edits
    /// this used to take — those had to be hunted down and undone by hand
    /// every time, and once shipped a run where cliffs never spawned again.
    ///
    /// It lifts the two gates that make a cliff *rare*, and deliberately not
    /// the one that keeps the feature honest: `activeCliff` still allows only
    /// one at a time, and the gap is still sized from the speed it spawns at,
    /// so what turns up is a real cliff and not a debug approximation of one.
    static let debugSpawnAlways = false

    /// How many points of score have to pass between cliffs, so they read as
    /// a rare event rather than clustering.
    ///
    /// This is the only thing pacing them now. There used to be a `gameSpeed`
    /// floor as well, to keep a gap from spawning at a speed that couldn't
    /// clear it — `cliffGapWidth(at:)` guarantees that by construction now,
    /// and leaving the floor in would have pinned every gap to `maxGapWidth`
    /// and made the sizing inert.
    static let scoreCooldown = 5

    /// The clean beat after a cliff, on top of the time the gap itself takes
    /// to pass. Nothing should spawn crowding a gap — it needs a clear
    /// sightline, not a log stacked against it. See `spawnObstacle`, which
    /// adds the gap's own crossing time and the spawn nudge to this.
    static let postSpacing: TimeInterval = 0.9

    /// How far below the ground line counts as having fallen through, rather
    /// than mid-jump. Short on purpose: at top speed there's barely more time
    /// to cross the gap than to fall this far, so it has to resolve before
    /// the ground would otherwise reconnect underneath him.
    static let fallDeath: CGFloat = 40
}

/// What is still drawn rather than painted. The sky, the hills and the turf
/// used to be here too, and are in `bg_scroll` now.
private enum Palette {
    static let ink = SKColor(red: 0.16, green: 0.20, blue: 0.24, alpha: 1)
    static let log = SKColor(red: 0.60, green: 0.40, blue: 0.24, alpha: 1)
    static let hound = SKColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1)

    /// Sampled from the bottom of the painting, so anything showing behind it
    /// is the same ground it is.
    ///
    /// Dirt, not grass. The painting this was named for ended in a green apron
    /// below the cut earth; the one that replaced it runs dirt all the way down,
    /// which is what lets the cliff gap fall away instead of stopping at a
    /// depth someone had to choose.
    static let field = SKColor(red: 0.34, green: 0.19, blue: 0.08, alpha: 1)
}

// MARK: - Scene

final class GameScene: SKScene, SKPhysicsContactDelegate {

    // Nodes
    private var dog: SKNode!

    /// Benny's contact shadow. Not a child of him: it has to stay on the turf
    /// while he leaves it, which is the whole of what it's for.
    private var dogShadow: SKSpriteNode!
    private var messageLabel: SKLabelNode!
    private var scenery: SKNode!
    /// The painted land, in strips that wrap round each other as they scroll.
    /// Distinct from what `makeGround` returns, which is the floor's physics and
    /// nothing else — one is what you see, the other is what Benny stands on.
    private var land: SKNode!
    /// The floor's physics, and nothing else — see `land`. Held onto so a
    /// cliff can switch it off for the width of its gap; `build()` used to
    /// hand this straight to `addChild` and let it go.
    private var ground: SKNode!

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

    /// The one cliff on screen, if any — there is never more than one, being
    /// rare. `update` reads its live position every frame to know whether
    /// `Layout.dogX` currently sits inside the gap; `spawnObstacle` uses this
    /// to keep from spawning a second one before the first has scrolled off.
    private weak var activeCliff: SKNode?
    /// How wide `activeCliff`'s opening came out. Cliffs aren't all the same
    /// width any more — each is sized from the speed it spawned at, by
    /// `cliffGapWidth(at:)` — so the number `update` tests `Layout.dogX`
    /// against has to travel with the cliff rather than being a constant.
    private var activeCliffGap: CGFloat = 0
    /// The score the last cliff was spawned at, so `Cliff.scoreCooldown`
    /// has something to measure from.
    private var lastCliffScore = 0

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
        // Read once, before `build()` stages the opening clip against it. The
        // scene fills the view's width exactly (see `Layout.visibleInset`), so
        // that same ratio converts the device's own safe-area inset into scene
        // units — the `> 0` guard is only for a view handed to us before it has
        // a real width, and falls back to the old, un-inset answer.
        let insetPoints = view.safeAreaInsets.left
        let scale = view.bounds.width / Layout.sceneSize.width
        Layout.visibleInset = scale > 0 ? insetPoints / scale : 0

        physicsWorld.gravity = CGVector(dx: 0, dy: -9)
        physicsWorld.contactDelegate = self
        // Input is handled by `touchesBegan` rather than a gesture recognizer
        // hung on the view — the scene owns it, so it can't outlive the scene
        // or stack up if the scene is presented more than once.
        build()
    }

    private func build() {
        // Whatever the painting doesn't reach. `.aspectFill` can only ever crop
        // the scene, never show past it, so this should be impossible to see —
        // but if it ever is, a field is a better thing to glimpse than black.
        backgroundColor = Palette.field

        scenery = SKNode()
        addChild(scenery)
        addBackdrop()

        ground = makeGround()
        addChild(ground)
        // His solid box, not the drawing: the canvas is sized to the extended
        // gallop poses and is far wider than the dog standing in it.
        dogShadow = Self.shadowSprite(width: Layout.dogSize.width * DogArt.bodyWidthFraction)
        dogShadow.position = CGPoint(x: Layout.dogX, y: Layout.dogGroundLine)
        dogShadow.zPosition = 6  // over the turf, under the obstacles and Benny
        addChild(dogShadow)

        dog = makeDog()
        addChild(dog)

        // The clip is what stands behind the title card, so it is built with the
        // rest of the world rather than swapped in when Play is tapped. Not on a
        // retry, though — `hasStarted` survives `restart` precisely so that a
        // crash drops straight back into the run.
        if !hasStarted { stageIntro() }
    }

    // MARK: - Backdrop

    /// The painted world, in two layers that travel at different speeds.
    ///
    /// The split is cut through a row of flat sky, which is what lets them: the
    /// two edges are the same colour to within three parts in 255, so there is
    /// nothing at the join to slide against itself and draw a line across the
    /// sky. Anywhere lower in the picture — through the hills, the bushes, the
    /// grass — and the cut would show the moment the layers disagreed.
    ///
    /// The land is stepped by `update` at exactly the speed of the world, and
    /// not by an action, because Benny's stride is tied to that speed and turf
    /// that disagrees with it puts him on a treadmill. The sky is a backdrop and
    /// has no such obligation, so it drifts on an action inside `scenery` and
    /// ramps with everything else there.
    private func addBackdrop() {
        guard let sky = BackdropArt.sky, let texture = BackdropArt.land else { return }

        for strip in strips(sky, size: BackdropArt.skySize, y: BackdropArt.splitY) {
            strip.zPosition = -100
            scenery.addChild(strip)
            drift(strip, speed: BackdropArt.skySpeed, width: BackdropArt.tileWidth)
        }

        land = SKNode()
        land.zPosition = 5  // over the sky, under the obstacles and the dog
        addChild(land)
        for strip in strips(texture, size: BackdropArt.landSize, y: BackdropArt.bottomY) {
            land.addChild(strip)
        }
    }

    /// Copies of one repeat, laid end to end — as many as it takes to cover the
    /// scene however they happen to have wrapped. See `BackdropArt.stripCount`.
    private func strips(_ texture: SKTexture, size: CGSize, y: CGFloat) -> [SKSpriteNode] {
        (0..<BackdropArt.stripCount).map { index in
            let strip = SKSpriteNode(texture: texture, size: size)
            strip.anchorPoint = .zero
            strip.position = CGPoint(x: CGFloat(index) * size.width, y: y)
            return strip
        }
    }

    /// Scrolls a node left forever, wrapping it round by `width`.
    private func drift(_ node: SKNode, speed: CGFloat, width: CGFloat) {
        let step = SKAction.moveBy(x: -width, y: 0, duration: TimeInterval(width / speed))
        let wrap = SKAction.moveBy(x: width, y: 0, duration: 0)
        node.run(.repeatForever(.sequence([step, wrap])))
    }

    /// The floor Benny stands on — the box only. What it used to draw as well, a
    /// green slab with a darker strip along the top, is painted now.
    private func makeGround() -> SKNode {
        let ground = SKNode()

        let left = -Layout.sceneSize.width
        let span = Layout.sceneSize.width * 3

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

    /// How wide a cliff spawning right now should be.
    ///
    /// Crossing a gap of width `w` at speed `s` takes `w / s` of the jump, so
    /// what's left over — `airtime - w / s` — is how early a player may leave
    /// the ground and still land clear. Sizing the gap to hold that at
    /// `Cliff.clearance` is what makes every cliff both clearable by
    /// construction and worth timing, at whatever speed it turns up.
    ///
    /// It caps rather than growing forever: `maxGapWidth` is as wide an
    /// opening as the backdrop can hold. Past roughly 280 the cap binds and
    /// the slack starts widening again — a fixed jump arc against a fixed gap
    /// is always easier the faster you're going, and the cap is where that
    /// takes back over.
    private func cliffGapWidth(at speed: CGFloat) -> CGFloat {
        min(Cliff.maxGapWidth, speed * (airtime - Cliff.clearance))
    }

    /// How tall to draw a jump obstacle so clearing it leaves
    /// `ObstacleArt.clearance` to spare at this speed.
    ///
    /// Every caller passes `Layout.openingSpeed`, so in practice this returns
    /// one number per piece and the argument is there to be honest about what
    /// the answer depends on. It stays a solve rather than three constants
    /// because the props are then still *derived*: retune `jumpHeight`, the
    /// clearance, or a solid box, and they follow — and all three stay equally
    /// demanding as each other, which hand-picked sizes never managed.
    ///
    /// The gap gets the same treatment one line above, but arithmetic there and
    /// a search here, because a prop is harder to solve than a hole. Growing it
    /// costs on both counts at once — it reaches higher, so there is less of
    /// the jump spent above it, *and* it grows wider with its own aspect, so
    /// there is more of it to clear. Those pull against each other through a
    /// square root. The slack still falls as the height rises, though, which is
    /// all a bisection needs.
    ///
    /// **How the window is found.** Walk the solid's outline — `Solid.clearance`
    /// gives the height Benny's feet need at each point of the crossing — and
    /// ask of each point when he could have jumped and still been above it. The
    /// parabola is above a given height for one stretch of its flight, so each
    /// point allows an interval of launch times; clearing the whole obstacle
    /// means being inside all of them at once, and the window is what their
    /// overlap leaves. One `min` and one `max` over a single pass.
    ///
    /// Which is the same arithmetic as before for anything box-shaped — every
    /// point shares one height, so the overlap collapses to *time above the top,
    /// less time to pass* — and it agrees with the old closed form to the
    /// millisecond. What it no longer does is flatten a disc into a rectangle.
    /// See `Solid.clearance` for what that cost.
    private func obstacleHeight(_ piece: ObstacleArt.Piece, at speed: CGFloat) -> CGFloat {
        let gravity = gravityAcceleration
        let launch = launchVelocity
        let dogSolid = Layout.dogSize.width * DogArt.bodyWidthFraction
        // Obstacles sink further into the turf than Benny's paws do, so their
        // feet start below his — that much of their height he never has to
        // clear.
        let underfoot = piece.sink - Layout.dogPlantDepth
        let aspect = piece.aspect

        /// Enough to trace a curve without the sampling itself costing timing.
        /// At this count the widest solid in the game is read every couple of
        /// units, which is worth well under a millisecond of window.
        let samples = 96

        func slack(_ height: CGFloat) -> TimeInterval {
            // Half the ground over which the solid, grown by Benny's own box,
            // can touch him at all — exactly, so the end samples land on the
            // edge rather than inside it.
            let span = piece.solid.reach(height: height, aspect: aspect, dogWidth: dogSolid)
            var earliest = -CGFloat.greatestFiniteMagnitude
            var latest = CGFloat.greatestFiniteMagnitude
            var touches = false
            for step in 0...samples {
                let gap = -span + 2 * span * CGFloat(step) / CGFloat(samples)
                let need = piece.solid.clearance(
                    at: gap, height: height, aspect: aspect, dogWidth: dogSolid
                ) - underfoot
                guard need > 0 else { continue }
                touches = true
                let remaining = launch * launch - 2 * gravity * need
                guard remaining > 0 else { return -1 }  // taller than the jump goes
                // He is above `need` from `rising` to `falling` after launch, so
                // to be above it when this point arrives he must have launched
                // somewhere in between.
                let rising = (launch - sqrt(remaining)) / gravity
                let falling = (launch + sqrt(remaining)) / gravity
                let arrives = -gap / speed
                latest = min(latest, arrives - rising)
                earliest = max(earliest, arrives - falling)
            }
            guard touches else { return .greatestFiniteMagnitude }
            return TimeInterval(latest - earliest)
        }

        var low = piece.heightRange.lowerBound
        var high = piece.heightRange.upperBound
        guard slack(low) > ObstacleArt.clearance else { return low }
        guard slack(high) < ObstacleArt.clearance else { return high }
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if slack(middle) > ObstacleArt.clearance { low = middle } else { high = middle }
        }

        let jitter = CGFloat.random(in: -ObstacleArt.heightJitter...ObstacleArt.heightJitter)
        return min(high, max(piece.heightRange.lowerBound, low * (1 + jitter)))
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

    // MARK: - Contact shadows

    /// One soft ellipse, drawn once and shared by everything that needs
    /// grounding — Benny and every obstacle.
    ///
    /// A texture rather than an `SKShapeNode` each: a shape node per obstacle
    /// would be a fresh path to rasterise for something that is the same blur
    /// every time, and this way a shadow costs one sprite.
    ///
    /// Drawn square and squashed at the point of use, so `Layout.shadowFlatness`
    /// stays the one place that decides how flat they sit.
    private static let shadowTexture: SKTexture = {
        let side = 128
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let centre = CGPoint(x: side / 2, y: side / 2)
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                // A solid core with the falloff held to the outer half. A
                // plain centre-to-edge ramp averages out to almost nothing and
                // reads as a smudge on turf this bright.
                colors: [SKColor.black.withAlphaComponent(0.50).cgColor,
                         SKColor.black.withAlphaComponent(0.44).cgColor,
                         SKColor.black.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 0.45, 1]
            )!
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: centre, startRadius: 0,
                // Stops short of the edge, leaving a band of clear pixels all
                // the way round. Run to the edge exactly and the sampler has
                // nothing beyond it to blend with, so it clamps the last texel
                // outwards and draws a hard rim round every shadow.
                endCenter: centre, endRadius: CGFloat(side) * 0.45,
                options: []
            )
        }
        return SKTexture(image: image)
    }()

    /// A shadow to sit under something `width` wide.
    ///
    /// Behind its caster but in front of the turf: children are ordered by
    /// their own `zPosition` within the parent, so a negative one here puts it
    /// under the drawing without lifting it out of the node it belongs to.
    private static func shadowSprite(width: CGFloat) -> SKSpriteNode {
        let drawn = width * Layout.shadowWidthFraction
        let sprite = SKSpriteNode(
            texture: shadowTexture,
            size: CGSize(width: drawn, height: drawn * Layout.shadowFlatness)
        )
        sprite.zPosition = -1
        return sprite
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

    /// What an obstacle asks of the player. The two rotations are held apart
    /// in `ObstacleArt` because the verbs are weighted against each other, and
    /// pairing them needs to name which is which.
    private enum Verb { case jump, duck }

    /// What an obstacle came out as, which is what pairing has to reason about:
    /// two of them must not overlap, and the second must be answerable once the
    /// first has gone by.
    private struct Spawned {
        let node: SKNode
        let width: CGFloat

        /// How high Benny has to get above his own feet to clear it. Nought for
        /// a duck piece, which is not cleared by getting over it.
        let clearHeight: CGFloat
    }

    /// Stands one obstacle up at `x`.
    @discardableResult
    private func spawn(_ verb: Verb, at x: CGFloat) -> Spawned {
        let piece: ObstacleArt.Piece
        let height: CGFloat
        switch verb {
        case .duck:
            // The bench is the only one of these for a while yet. The hint that
            // teaches the swipe fires on the first low obstacle of a run, so it
            // should always be teaching it on the same one — and meeting the
            // swingset before you have the verb is a harsher lesson, since it's
            // the one you can't jump instead.
            piece = (score >= 6 ? ObstacleArt.ducks : [ObstacleArt.bench]).randomElement()
                ?? ObstacleArt.bench
            // Not sized from the speed, unlike the jumps: a duck piece's height
            // *is* the mechanic — derived from `duckClearance` so that sliding
            // works and standing doesn't — so there is nothing to solve for.
            height = piece.heightRange.lowerBound
            if !hasSpawnedLowObstacle {
                hasSpawnedLowObstacle = true
                onFirstLowObstacle?()
            }
        case .jump:
            piece = ObstacleArt.jumps.randomElement() ?? ObstacleArt.log
            // Sized for the tier the world has reached rather than for the
            // speed it is actually doing — see `ObstacleArt.sizeTiers` for why
            // it is quantised, and quantised downwards.
            height = obstacleHeight(piece, at: ObstacleArt.tier(for: gameSpeed))
        }

        let node = makeObstacle(piece, height: height)
        node.position = CGPoint(x: x, y: Layout.groundTop)
        node.zPosition = 8
        node.name = "obstacle"
        addChild(node)
        return Spawned(
            node: node,
            width: piece.size(height: height).width,
            clearHeight: verb == .jump
                ? height * piece.solid.topPerHeight - (piece.sink - Layout.dogPlantDepth)
                : 0
        )
    }

    /// The least ground that may separate a duck from the jump that follows it.
    ///
    /// The first version of this said a duck owed nothing, because `jump()`
    /// cuts a slide short — so the next thing only had to be far enough off to
    /// see coming. That is wrong, and wrong in a way that made every pair
    /// unclearable by about 150ms: jumping does cut the slide short, but it
    /// also *stands him up*, and standing up while the bench is still over him
    /// is the collision the slide was avoiding. He cannot leave the ground
    /// until the thing he ducked has gone past him entirely.
    ///
    /// So three things have to fit between the two, and only the last was ever
    /// counted:
    ///
    /// * the lead clearing his box — half of each of their widths,
    /// * `pairRecovery`, for seeing it and answering,
    /// * and the climb, because being off the ground is not enough: he has to
    ///   be above the follower before it reaches him.
    ///
    /// Even with all three it stays a burst — about a fifth tighter than the
    /// ordinary cadence at every speed, where before it was merely impossible.
    private func pairSeparation(from lead: Spawned, to follower: Spawned) -> CGFloat {
        let box = Layout.dogSize.width * DogArt.bodyWidthFraction
        let remaining = launchVelocity * launchVelocity - 2 * gravityAcceleration * follower.clearHeight
        let climb = remaining > 0
            ? (launchVelocity - sqrt(remaining)) / gravityAcceleration
            : airtime / 2
        return (lead.width + follower.width) / 2
            + box
            + gameSpeed * (CGFloat(ObstacleArt.pairRecovery) + climb)
    }

    private func spawnObstacle() {
        // The rare one: a gap Benny has to clear by jumping across rather than
        // over — see `Cliff`. There's no speed gate, because it doesn't need
        // one: the gap is *sized* from the speed it spawns at
        // (`cliffGapWidth(at:)`), so one can never turn up too wide to clear.
        // Up to the speed where `maxGapWidth` takes over it also arrives with
        // the same slack every time; past that the cap binds and a fast run
        // gets an easier gap than a slow one.
        //
        // `activeCliff` keeps a second one from spawning before the first has
        // scrolled off, and `lastCliffScore` keeps them from clustering.
        let wantsCliff = activeCliff == nil
            && (Cliff.debugSpawnAlways
                || (score - lastCliffScore >= Cliff.scoreCooldown && Int.random(in: 0..<10) < 1))
        if wantsCliff {
            let gap = cliffGapWidth(at: gameSpeed)
            let spawnX = cliffSpawnX()
            let cliff = makeCliff(gap: gap)
            cliff.position = CGPoint(x: spawnX, y: Layout.groundTop)
            cliff.zPosition = 8
            cliff.name = "obstacle"
            addChild(cliff)
            activeCliff = cliff
            activeCliffGap = gap
            lastCliffScore = score
            // Three parts: how long the gap itself takes to pass, how long the
            // spawn nudge delays its arrival, and the clean beat after it.
            obstacleTimer -= (gap + spawnX - Layout.spawnX) / gameSpeed + Cliff.postSpacing
            return
        }

        // Ducks stay the minority — ducking is the newer verb, and a run that's
        // mostly ducking loses the rhythm of jumping. They also hold off until a
        // few obstacles in, so the first thing anyone meets is a jump.
        func rollVerb() -> Verb {
            score >= 2 && DogArt.slideFrames.count > 1 && Int.random(in: 0..<10) < 3 ? .duck : .jump
        }

        let first = rollVerb()

        // Once in a while, two at once: slide under, then straight back up and
        // over. Everything else arrives alone on a metronome, which is steady
        // but never asks for two different things in a row.
        //
        // Always that way round, and it has to be. A jump commits Benny to a
        // fixed airtime in which he can do nothing at all — not jump again, and
        // not duck either, since a duck piece is a bar to go under and meeting
        // one mid-jump is a crash however high he is. Costing that out, a pair
        // *after* a jump comes to 554 units against an ordinary cadence of 512
        // at speed: wider than the rhythm it was meant to interrupt.
        //
        // A duck owes less, though not nothing — `pairSeparation` has the
        // reckoning. It comes to roughly a fifth tighter than the cadence,
        // which is the moment worth having.
        let wantsPair = score >= ObstacleArt.pairFromScore
            && DogArt.slideFrames.count > 1
            && Int.random(in: 0..<10) < ObstacleArt.pairInTen
        if wantsPair {
            let lead = spawn(.duck, at: Layout.spawnX)
            // Stood up alongside it and then moved back, because how far back
            // depends on how big it came out — and that is settled inside
            // `spawn`. Both are off screen throughout, so the shuffle is free.
            let follower = spawn(.jump, at: Layout.spawnX)
            let separation = pairSeparation(from: lead, to: follower)
            follower.node.position.x = Layout.spawnX + separation
            // The pair is two obstacles' worth of screen, so the next one waits
            // the extra out rather than landing on the second one's heels.
            obstacleTimer -= separation / gameSpeed
            return
        }

        spawn(first, at: Layout.spawnX)

        // Moved and eventually removed by `update`, on the same per-frame step
        // the ground scrolls by — see the comment there for why this isn't a
        // one-shot action timed to `gameSpeed` at spawn.
    }

    /// The one obstacle that isn't a solid prop: a gap in the ground, with no
    /// physics body at all. Deliberately not routed through
    /// `makeObstacle`/`Self.obstacleBody` — that would give it a real
    /// `obstacle` contact and end the run just for scrolling past it. The
    /// actual hazard lives in `update`, which pulls the ground itself out
    /// from under Benny while `Layout.dogX` sits inside the gap.
    ///
    /// No ledge sprites either, on either side — an earlier version drew
    /// two, cropped from the user's mockup, and they never stopped looking
    /// like a seam against the real ground either side of them, because
    /// they're a different painting. The real scrolling `land` layer already
    /// renders correct, matching ground everywhere on screen, including
    /// exactly where those ledges sat — so the fix is to draw nothing there
    /// and let it show through. All that's actually missing, that the real
    /// ground has no art for, is the gap itself — see `makeCliffPit`.
    private func makeCliff(gap: CGFloat) -> SKNode {
        let node = SKNode()
        for piece in makeCliffPit(gap: gap) { node.addChild(piece) }
        return node
    }

    /// Where to put a cliff so the ground's own turf sprigs don't end up
    /// standing inside the gap with nothing under them.
    ///
    /// Since the sprite stops at the turf line, the real background shows
    /// through the opening — sprigs included, and a sprig hanging in mid-air
    /// over the hole reads as a glitch. But the sprigs sit at fixed places in
    /// `bg_scroll`, and a cliff holds its position against the backdrop for
    /// life (both are moved by the same per-frame `step`), so where the gap
    /// lands in the repeat at spawn is where it stays. Picking that spot is
    /// enough to avoid them entirely.
    ///
    /// Rather than wait for the backdrop to come round to a clear stretch —
    /// which would make cliffs rarer and bunch them at the same scenery — this
    /// nudges the spawn point right until the gap lands in one. It spawns off
    /// screen either way, so the only effect is arriving up to half a repeat
    /// later.
    private func cliffSpawnX() -> CGFloat {
        let tile = BackdropArt.tileWidth
        guard let strip = land.children.first else { return Layout.spawnX }

        /// Where a scene-x falls in the backdrop's repeat, as a fraction.
        /// Any strip serves — `scrollLand` keeps them a whole `tile` apart.
        func phase(_ sceneX: CGFloat) -> CGFloat {
            let raw = (sceneX - strip.position.x) / tile
            let mod = raw.truncatingRemainder(dividingBy: 1)
            return mod < 0 ? mod + 1 : mod
        }

        // Measured off `bg_scroll.png` by `Art/MeasureTurfWindows.swift`: for
        // each column, how far turf reaches above the turf line, then every
        // window a `Cliff.maxGapWidth` opening fits into holding nothing
        // taller than 4px (~2.5 units). Each is about 12 units wide.
        //
        // However many the painting happens to have, at whatever spacing. This
        // used to be a single number taken mod half a repeat, which worked only
        // because this particular painting has two windows exactly half a
        // repeat apart — nothing makes that true of the next one.
        //
        // Measured at the *widest* gap on purpose, and used for every gap. A
        // narrower one centred on the same spot sits strictly inside the span
        // that was checked, so these cover the whole range of widths
        // `cliffGapWidth(at:)` produces.
        //
        // Nine units of window means the nominal spawn point is almost never
        // already in one, so this snaps to the nearest ahead rather than
        // testing first. The nudge is off screen either way, and paid back into
        // `obstacleTimer` by `spawnObstacle`.
        let clearCentres: [CGFloat] = [0.0760, 0.5760]

        let here = phase(Layout.spawnX)
        let ahead = clearCentres
            .map { centre -> CGFloat in
                let d = centre - here
                return d < 0 ? d + 1 : d
            }
            .min() ?? 0
        return Layout.spawnX + ahead * tile
    }

    /// The gap itself: the `cliff_gap` crop — turf missing, background bushes
    /// showing through where it was, dirt carrying on underneath, and the cut
    /// edges the real ground has no art for.
    ///
    /// Its *height* is 1:1 and has to be: the crop's turf band is scaled to
    /// match the game's (see `Cliff.artScale`), which is what lands its turf
    /// line and its dirt line flush on the real ground's own either side.
    ///
    /// Its width isn't, because the opening is sized from the jump rather than
    /// from the art — so it comes out in three pieces. The lip and cut face at
    /// each end stay at native scale, since those are the shapes that read as a
    /// cliff and a stretched one reads as a smear; only the middle takes up the
    /// slack. That is safe here, and it's the art that makes it safe rather
    /// than luck: across the middle, the shadow above the dirt line is flat to
    /// within a couple of levels and the dirt below it is a soft gradient, so
    /// there's no brushwork in there to distort. Stretch is about 1.9x at the
    /// widest.
    private func makeCliffPit(gap: CGFloat) -> [SKNode] {
        guard let sheet = UIImage(named: "cliff_gap").map(SKTexture.init(image:)) else { return [] }

        let capU = Cliff.capPx / Cliff.spritePx
        let capWidth = Cliff.capPx * Cliff.artScale
        let half = (gap + Cliff.lipOverhang) / 2
        let height = Cliff.pitHeight

        /// One slice, cut from `sheet` and stood with its top edge on the turf
        /// line. `anchorX` places it by whichever of its own edges has to land
        /// exactly: the outside edge for the caps, the centre for the middle.
        func slice(u: CGFloat, width uWidth: CGFloat, drawn: CGFloat, anchorX: CGFloat, at x: CGFloat) -> SKSpriteNode {
            let texture = SKTexture(rect: CGRect(x: u, y: 0, width: uWidth, height: 1), in: sheet)
            let sprite = SKSpriteNode(texture: texture, size: CGSize(width: drawn, height: height))
            sprite.anchorPoint = CGPoint(x: anchorX, y: 1)
            sprite.position = CGPoint(x: x, y: Cliff.fadeRise)
            return sprite
        }

        return [
            slice(u: 0, width: capU, drawn: capWidth, anchorX: 0, at: -half),
            slice(u: capU, width: 1 - 2 * capU, drawn: 2 * (half - capWidth), anchorX: 0.5, at: 0),
            slice(u: 1 - capU, width: capU, drawn: capWidth, anchorX: 1, at: half),
        ]
    }

    /// One of the painted jump obstacles, at a random height within its own
    /// range, standing on the turf with its physics box hugging the solid part
    /// of the drawing.
    ///
    /// The node's origin is on the ground line rather than at the middle of the
    /// sprite, so `spawnObstacle` can stand every obstacle at `Layout.groundTop`
    /// without knowing how tall this one came out.
    private func makeObstacle(_ piece: ObstacleArt.Piece, height: CGFloat) -> SKNode {
        let node = SKNode()
        let size = piece.size(height: height)

        // On the node, so it travels and is removed with the obstacle rather
        // than having to be tracked separately. At the drawing's own foot,
        // which is sunk into the turf by the same amount the sprite is.
        let shadow = Self.shadowSprite(width: size.width)
        shadow.position = CGPoint(x: size.width * piece.offsetXFraction, y: -piece.sink)
        node.addChild(shadow)

        let body: SKPhysicsBody

        if let texture = piece.texture {
            let sprite = SKSpriteNode(texture: texture, size: size)
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
            sprite.position = CGPoint(x: 0, y: -piece.sink)
            node.addChild(sprite)

            for hang in piece.hangs { hangFromDrawing(hang, on: node, size: size, sink: piece.sink) }

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

    /// Hangs a swing on its drawing and sets it rocking.
    ///
    /// Pinned by its top edge, which is the line the art was cut on, so putting
    /// that edge on the bar puts the pivot where the chains meet it — and means
    /// the whole sprite turning is the swing turning about its hanger.
    ///
    /// It turns as one piece, so the seat tilts with the chains where a real
    /// one would stay level under them. At six degrees that is a couple of
    /// points across the seat, and the alternative is a third sprite and a
    /// linkage to keep it upright.
    private func hangFromDrawing(_ hang: ObstacleArt.Hang, on node: SKNode, size: CGSize, sink: CGFloat) {
        guard let texture = hang.texture, texture.size().width > 0 else { return }
        let width = size.width * hang.widthFraction
        let swing = SKSpriteNode(
            texture: texture,
            size: CGSize(width: width, height: width * texture.size().height / texture.size().width)
        )
        swing.anchorPoint = CGPoint(x: 0.5, y: 1)
        swing.position = CGPoint(
            x: size.width * hang.pivotXFraction,
            y: size.height * (1 - hang.pivotYFraction) - sink
        )
        swing.zPosition = 1  // the chains hang in front of the bar they hang from
        node.addChild(swing)

        let half = ObstacleArt.Hang.swayPeriod / 2
        func turn(to angle: CGFloat, over duration: TimeInterval) -> SKAction {
            let action = SKAction.rotate(toAngle: angle, duration: duration)
            action.timingMode = .easeInEaseOut  // a pendulum, not a metronome
            return action
        }
        swing.zRotation = ObstacleArt.Hang.swayAngle
        swing.run(.sequence([
            turn(to: -ObstacleArt.Hang.swayAngle, over: half * (1 - TimeInterval(hang.swayPhase))),
            .repeatForever(.sequence([
                turn(to: ObstacleArt.Hang.swayAngle, over: half),
                turn(to: -ObstacleArt.Hang.swayAngle, over: half),
            ])),
        ]))
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

        // KNOWN LANDSCAPE REGRESSION — he now starts in view.
        //
        // In portrait he began off the right of the scene and the travelling
        // shot carried him in. That cannot happen at 800 wide: his mark is at
        // 220 and the walk only travels 112 before the leash goes, so starting
        // him past the edge would need five times the ground the drawn stride
        // actually covers. He is simply sitting in the grass from the first
        // frame, in frame.
        //
        // The beat still reads — he grazes, Benny notices him, the leash goes —
        // but the reveal is gone, and the clip wants restaging for the wider
        // shot: a longer walk, or a composition that opens on him.
        //
        // The assertion that guarded the off-stage start is removed rather than
        // weakened, because it guarded an invariant this spike knowingly
        // breaks, and an assert that cannot hold is worse than none.
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
        // this, breaks. He is peeled off the stage first — see below — so his
        // sprint is real screen distance, run to completion on his own clock,
        // rather than ground covered while riding along with a clip that tears
        // itself down out from under him.
        if let rabbit = introRabbit, let stage = intro {
            // A different sheet, so the size and the anchor go with the frames:
            // the gallop is drawn longer and lower than the rabbit sitting up in
            // the grass, and `grazeSize` and `rabbitSize` are what keep the two
            // the same animal across the change.
            rabbit.removeAllActions()
            rabbit.size = Intro.rabbitSize
            rabbit.anchorPoint = CGPoint(x: 0.5, y: 0)
            rabbit.run(.repeatForever(.animate(with: IntroArt.rabbitFrames, timePerFrame: 0.07)))

            // Handed from the stage to the scene itself, at the same spot he
            // already occupies. `finishIntro` only tears down `intro` — once
            // he's no longer inside it, that cut can't reach him, and he's free
            // to finish his own sprint on his own schedule, on or off screen,
            // whether the clip ends around him or is skipped out from under him.
            let scenePosition = stage.convert(rabbit.position, to: self)
            rabbit.removeFromParent()
            rabbit.position = scenePosition
            rabbit.zPosition = stage.zPosition  // "over the turf, under Benny" — lost by leaving the stage otherwise
            addChild(rabbit)

            // However far is actually left to clear the edge, plus his own
            // width so it's his trailing edge that clears it, not his centre —
            // the same reasoning the scrolling obstacles use for their own
            // `+160` margin. Measured live rather than assumed, so a wider
            // notch inset (which starts him further right) doesn't leave him
            // clipped mid-screen.
            let clearRight = Layout.sceneSize.width - scenePosition.x + rabbit.size.width
            let bolt = SKAction.moveBy(
                x: clearRight, y: 0,
                duration: TimeInterval(clearRight / Intro.rabbitRunSpeed)
            )
            // A standing start: anything bolting from rest accelerates rather
            // than snapping straight to top speed.
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
        scrollLand(by: step)
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

        // The same step the ground moves by, not a one-shot action timed to
        // whatever `gameSpeed` was at spawn — `gameSpeed` climbs over the
        // course of a run, and an obstacle that kept its spawn-time pace for
        // its whole life would drift out of sync with the ground (and with
        // every obstacle spawned after it) as the run sped up around it.
        // -200 clears the scene's left edge with room to spare, the same
        // margin `spawnObstacle` used to travel before removing itself.
        enumerateChildNodes(withName: "obstacle") { node, _ in
            node.position.x -= step
            if node.position.x < -200 { node.removeFromParent() }
        }

        // The one hazard that isn't a contact. A cliff carries no physics
        // body — see `makeCliff` — so whether Benny is over its gap is worked
        // out fresh every frame from its live position, and the ground
        // itself is what answers: switched off for the width of the gap,
        // switched back on once it's scrolled past. Forced rather than left
        // to `didBegin`/`didEnd`, both of which key off contacts that a
        // category mutated out from under them isn't guaranteed to report
        // cleanly.
        if let cliff = activeCliff {
            let halfGap = activeCliffGap / 2
            if Layout.dogX > cliff.position.x - halfGap && Layout.dogX < cliff.position.x + halfGap {
                ground.physicsBody?.categoryBitMask = 0
                isOnGround = false
                // A duck in progress would otherwise keep sliding through
                // turf that is no longer there to slide on.
                if isSliding { endSlide() }
            } else {
                ground.physicsBody?.categoryBitMask = PhysicsCategory.ground
            }
        }

        // How far off the turf he is, as a fraction of a full jump — the one
        // thing the shadow has to say. Clamped because a fall through a gap
        // goes below the line and the apex can be passed on a retry frame.
        let lift = min(1, max(0, (dog.position.y - Layout.dogGroundLine) / Layout.jumpHeight))
        dogShadow.setScale(1 - (1 - Layout.shadowLiftScale) * lift)
        dogShadow.alpha = 1 - (1 - Layout.shadowLiftAlpha) * lift

        // Falling through a cliff's gap is a fourth way to end a run,
        // alongside the physics contact `didBegin` already handles — there is
        // no contact here to catch it, so it's caught by how far down he's
        // gotten instead. Short on purpose: see `Cliff.fallDeath`.
        if !isGameOver, dog.position.y < Layout.dogGroundLine - Cliff.fallDeath {
            endGame()
        }

        obstacleTimer += delta
        if obstacleTimer >= obstacleInterval {
            obstacleTimer -= obstacleInterval
            spawnObstacle()
            // The floor is held above both the airtime and the slide, not
            // chosen for pacing: at the top scroll speed a jump covers ~364pt
            // and a slide 400pt, so a tighter gap than this would run one
            // obstacle into the next with no ground time to react in between.
            // It has had to climb every time Benny has grown.
            obstacleInterval = max(1.30, obstacleInterval - 0.02)
            gameSpeed = min(Layout.topSpeed, gameSpeed + 4)
        }

        scoreClearedObstacles()
    }

    /// Walks the painted land left, wrapping each repeat round behind the other
    /// as it leaves.
    private func scrollLand(by distance: CGFloat) {
        let tile = BackdropArt.tileWidth
        for strip in land.children {
            strip.position.x -= distance
            if strip.position.x <= -tile {
                strip.position.x += tile * CGFloat(BackdropArt.stripCount)
            }
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
        // Paused as well as stopped: removing the actions holds the obstacle
        // still, but the swingset's swings carry actions of their own and would
        // otherwise keep rocking in the frozen scene, exactly as Benny would
        // keep galloping in it.
        enumerateChildNodes(withName: "obstacle") { node, _ in
            node.removeAllActions()
            node.isPaused = true
        }

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

        // Both of these are what `spawnObstacle` gates cliffs on, and a run
        // that ends having spawned one leaves them saying so. Without the
        // reset, `score - lastCliffScore` starts the next run negative — by
        // however far the last run got — and no cliff can spawn until the
        // score climbs back past it, which for a good run is the whole of the
        // next one. `activeCliff` is weak and would clear itself once
        // `removeAllChildren` let the node go, but that leans on when ARC
        // happens to release it rather than saying what's meant.
        lastCliffScore = 0
        activeCliff = nil
        activeCliffGap = 0

        onScoreChange?(0)
        onRetry?()
        build()
    }
}
