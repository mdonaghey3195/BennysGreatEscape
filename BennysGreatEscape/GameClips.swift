//
//  GameClips.swift
//  Benny's Great Escape
//
//  How the three clips are paced — the opening walk, the launch into the sky,
//  and the rabbit's send-off. Beats rather than one duration each, because every
//  beat waits on the one before it.
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


    /// How the clip is staged and paced.
    enum Intro {
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


    /// How the launch is staged and paced — `Intro`'s job for the other clip.
    enum Launch {
        /// Where the running stops and the flying starts.
        static let atScore = 100

        /// Testing. Set to something small to reach the launch without playing a
        /// hundred obstacles first; ships `nil`, the way `Cliff.debugSpawnAlways`
        /// ships `false`. It moves the trigger and nothing else, so what you get is
        /// the real launch and not a debug approximation of one.
        ///
        /// Set to 5 while the clip is being worked on. Put it back to `nil` before
        /// this ships — `atScore` below is the real figure and is deliberately left
        /// alone, so turning the knob back is the only thing that has to happen.
        static let debugAtScore: Int? = nil
        static var trigger: Int { debugAtScore ?? atScore }

        /// How big the dog house stands, from Benny's own length.
        static var houseWidth: CGFloat { Layout.dogWidth * LaunchArt.houseInDogs }

        /// How far the house still has to come when the wind-down begins.
        ///
        /// The one distance the whole hand-over is built on, and everything else is
        /// set equal to it: it is how far Benny dashes, how far the clip carries
        /// him, and how far apart the two trip points are. Winding down linearly
        /// covers half what holding speed would, so a brake of `2 x slide` travels
        /// exactly `speed x slide` — and the drawn dog lands on the real one only
        /// if his dash covered the same ground. Deriving all three from this rather
        /// than from the art's own travel is what keeps them equal when the floor
        /// in `slideBeats` nudges the timing.
        static func stopping(at speed: CGFloat) -> CGFloat {
            speed * CGFloat(slide(at: speed))
        }

        /// The shortest a frame of the slide may be held.
        ///
        /// The art's last step is nothing at all — two of its frames put him in the
        /// same place — and timing purely by distance would give that frame no
        /// duration and nobody would ever see it. The floor costs a few percent of
        /// drift on frames that barely move him, which is invisible; dropping a
        /// drawing is not.
        static let slideFloor: TimeInterval = 0.04

        /// The slide, a texture and a duration at a time.
        ///
        /// Not `.animate(with:timePerFrame:)`, and this is the third and last thing
        /// that was wrong with this clip. The frames are unevenly *drawn* — his step
        /// runs 0.113, 0.100, 0.055, 0.051, 0.066, 0.094, 0.030, 0.000 — so timing
        /// them evenly makes his speed swing by a factor of three against a house
        /// arriving at a steady rate. On screen that came out as a lurch forward
        /// fifteen units, forward eleven, back, back, forward ten, back twenty, at
        /// about fourteen a second. A vibration, not a slide.
        ///
        /// Worse, it was front-loaded: the first two frames carry two fifths of his
        /// travel in a fifth of the time, so the clip opened at roughly twice the
        /// speed of the ground. That is the part that read as *fast*, and it is why
        /// two rounds of measuring the total came out right while the thing still
        /// looked wrong. The average was never the problem.
        ///
        /// Timing each frame by the ground it covers makes his velocity the world's
        /// velocity at every instant, not just on aggregate, so the house's leftward
        /// travel cancels it exactly and he holds still while it comes to him. The
        /// frames that move him least are on screen least, which is the right way
        /// round however odd it looks written down.
        ///
        /// `jumpArc` hand-rolls its frames for a closely related reason: that clip
        /// is timed to an airtime, this one to a ground speed, and neither can be
        /// said with one number.
        static func slideBeats(at speed: CGFloat) -> [SKAction] {
            let canvas = houseWidth / LaunchArt.slideHouseWidth
            return LaunchArt.slideFrames.enumerated().map { index, texture in
                // The last frame has no step after it; it is held by the beat that
                // follows the clip.
                let step = index < LaunchArt.slideSteps.count ? LaunchArt.slideSteps[index] : 0
                let hold = max(slideFloor, TimeInterval(step * canvas / max(speed, 1)))
                return .sequence([.setTexture(texture), .wait(forDuration: hold)])
            }
        }

        /// How long the slide takes altogether — the sum of its own beats, so that
        /// the wind-down can't drift out of step with it when the floor nudges one.
        ///
        /// Derived rather than declared, which was the fix before last. The clip
        /// used to run on a fixed frame time *after* the world had been brought to
        /// a stop for it, so the player watched the game halt, wait, and then play a
        /// little film.
        ///
        /// It is `Intro.scrollSpeed`'s trick upside down. There the world's speed is
        /// taken from the walk cycle so the man can't moonwalk against the grass;
        /// here the cycle's speed is taken from the world so Benny can't.
        static func slide(at speed: CGFloat) -> TimeInterval {
            slideBeats(at: speed).reduce(0) { $0 + $1.duration }
        }

        /// And the wind-down is exactly twice that.
        ///
        /// Winding down linearly covers half the ground that holding speed would, so
        /// a brake of `2 x slide` carries the house exactly as far as Benny walks
        /// across the drawing — and the two cancel. He holds station on screen while
        /// the house comes to him, which is what the game has always shown and what
        /// the clip, left to itself, would contradict.
        static func settle(at speed: CGFloat) -> TimeInterval { 2 * slide(at: speed) }

        static let roofFrame: TimeInterval = 0.09

        /// How much empty turf there is between the last obstacle and the dog
        /// house, on top of whatever is still out there getting past Benny.
        ///
        /// The house used to arrive on the ordinary spawn beat, which meant it
        /// could come over the right-hand edge while the player was still coming
        /// down from jumping the thing before it. That reads as one more obstacle,
        /// and the ending needs to read as the opposite — a clear stretch of
        /// ground is what says the run is over before the house says it.
        static let runway: TimeInterval = 1.1

        /// A beat after he is inside and before the roof moves, so the two read as
        /// cause and effect rather than one continuous shuffle.
        static let beforeRoof: TimeInterval = 0.25

        /// How long the slide takes to become the roof.
        ///
        /// A cross-fade covering a mismatch rather than a flourish: the two sheets
        /// draw different dog houses and a straight cut between them pops. Short
        /// enough to read as a beat, long enough to hide the change of shape.
        static let blend: TimeInterval = 0.18

        /// And another before the engine lights, which is the joke landing.
        static let beforeLaunch: TimeInterval = 0.45

        /// The climb out of the house. Eased in: the rocket is heaviest at the
        /// bottom of it.
        ///
        /// It was 1.35 when the ceiling was the top of the screen and the whole
        /// ascent was 250 units. At 1150 it needs to be an ascent rather than a
        /// flick — and a touch faster per unit than it was at 700, which is what a
        /// rocket that has been burning for three seconds should look like.
        static let climb: TimeInterval = 3.0

        /// How much clear air is left under the frame when the climb stops.
        ///
        /// The whole of what decides how high he goes. Thirty units is enough that
        /// the last cloud has visibly gone rather than being half out of shot, and
        /// little enough that it leaves on the frame the turn begins on.
        static let cloudClearance: CGFloat = 30

        /// Half of what the player can actually see, which is what the frame's edges
        /// are measured from.
        private static var halfFrame: CGFloat { Layout.visibleTop - Layout.sceneSize.height / 2 }

        /// How much clear air is left over the rocket's nose at the top of the
        /// climb, so the shot ends in open sky rather than against a ceiling.
        static let noseMargin: CGFloat = 24

        /// How far the camera rises: until its bottom edge has just cleared the top
        /// of the painted weather, and not a unit further.
        ///
        /// This is the direction the derivation runs now, and it used to run the
        /// other way — a chosen apex, with the camera worked out from it. That put
        /// the frame seventy-three units above the last cloud instead of thirty, and
        /// those extra units cost about half a second. They were worse than they
        /// sound, because the high sky has faded up by then and is parented to the
        /// camera: with the clouds gone and the new sky moving with the frame, there
        /// is nothing on screen that can show the camera moving at all. The rocket
        /// simply hung upright in flat blue until the turn came.
        ///
        /// So the shot's real constraint — be above the weather — decides the
        /// camera, and the rocket is then placed inside the frame rather than the
        /// frame around the rocket.
        static var cameraRise: CGFloat {
            BackdropArt.cloudCeiling + cloudClearance + halfFrame - Layout.sceneSize.height / 2
        }

        /// How far above the turf the rocket climbs, given a rocket that tall:
        /// nose `noseMargin` under the top of the frame the camera has just reached.
        ///
        /// Its height has to be asked for rather than assumed, and that is the
        /// lesson of the first attempt at this. The rocket is 139 units tall and
        /// drawn from its foot; treating it as a point put the nose thirty units
        /// past the top edge and sliced the dog's head off at the one moment of the
        /// clip anybody is looking at him.
        static func apex(forRocketOfHeight height: CGFloat) -> CGFloat {
            Layout.sceneSize.height / 2 + cameraRise + halfFrame - noseMargin - height - Layout.groundTop
        }

        /// When in the climb the high sky starts coming up, and how long it takes.
        ///
        /// Tied to the one moment in the shot worth tying it to: the rocket's foot
        /// passes the cloud ceiling at about 2.6 seconds of the climb — it is eased
        /// in, so most of the distance is covered late — and that is when the air is
        /// meant to change. Any earlier and the new sky is washing over cloud that
        /// is still in frame.
        ///
        /// A cross-fade rather than a cut, and rather than a join. Stacking the two
        /// paintings was the first thought and the measurement killed it: the
        /// running sky's top row is (120, 202, 250) and the high sky's bottom row is
        /// (164, 220, 252), a step of 44 out of 255 — and the wrong way round, since
        /// the new one lightens as it descends. It is a complete sky in its own
        /// right, not a continuation. Faded, though, both are blue and the change
        /// reads as the air thinning.
        /// Timed to *finish* at the top of the climb rather than to start at a
        /// chosen moment. Landing it early was the other half of the dead beat: the
        /// clouds were being covered over while they still had a way to fall, so
        /// they vanished instead of leaving, and what was left was flat blue with
        /// nothing happening in it.
        static var skyFadeAfter: TimeInterval { max(0, climb - skyFade) }
        static let skyFade: TimeInterval = 0.6

        /// The turn from standing on its tail to flying level.
        static let turnFrame: TimeInterval = 0.09

        /// And away. Brisk: he has turned, the shot is over, and the flying phase
        /// is what everyone is waiting for.
        static let away: TimeInterval = 0.8
    }


    /// How the flying phase is paced.
    ///
    /// One place for its numbers from the start, the way `Intro` and `Launch` each
    /// have one, so that when lanes and obstacles arrive they have somewhere to go
    /// that isn't the middle of a function.
    enum Flight {
        /// How long Benny takes to come in from off the left and settle at
        /// `Layout.dogX`, where he runs on the ground. Eased out, so he arrives
        /// rather than stops.
        static let entry: TimeInterval = 0.7

        /// A slow rise and fall while he flies, and how long each half takes.
        /// Small: this is the difference between flying and being a sticker on a
        /// moving picture, not a manoeuvre.
        static let bob: CGFloat = 14
        static let bobTime: TimeInterval = 1.3

        /// How long Benny flies on after the rabbit has gone, before the card.
        ///
        /// It was six seconds, which was padding from when this phase had nothing in
        /// it at all. Now the card is what it was waiting for, and six seconds of a
        /// dog flying at nothing in particular is six seconds of the player
        /// wondering whether the game has stopped working. Long enough to let the
        /// serious pose land, and no longer.
        static let look: TimeInterval = 1.8
    }


    /// The clip the flying phase opens on.
    ///
    /// Beats rather than one duration, because each waits on the one before it and
    /// the whole thing is read in order — the same arrangement `Intro` and `Launch`
    /// use for the other two clips in the game.
    enum Rabbit {
        /// How big the saucer is, in Bennys-on-a-rocket. Hung off him rather than
        /// typed in points so the two keep their relative size if he is ever
        /// resized — the same stance `LaunchArt` takes with the dog house.
        ///
        /// A matched pair: 135 units against his 136, so neither craft outranks the
        /// other. It was 1.6, which put the saucer at 1.66x his drawn width and
        /// read even larger than that — his canvas is only 56% full vertically
        /// where the saucer's is 100% full, so comparing canvases flatters it and
        /// comparing drawings is the only honest measure.
        static let widthInFliers: CGFloat = 0.95

        /// How high he hangs, in scene points. Above the middle, where Benny
        /// arrives, so the rabbit is looking *down* at him.
        static let height: CGFloat = 300

        /// In from off the left, and where he stops.
        static let flyIn: TimeInterval = 1.4
        static var stopX: CGFloat { Layout.sceneSize.width / 2 }

        /// A beat with the rabbit alone on screen before Benny turns up, so the
        /// shot reads as the rabbit being here first and Benny arriving — which is
        /// the order the joke needs.
        static let beforeBenny: TimeInterval = 0.25

        /// And another after Benny has settled, before the laugh. This one is the
        /// rabbit noticing him.
        static let beforeLaugh: TimeInterval = 0.5

        /// The laugh, as an order to play the poses in.
        ///
        /// Up through all of them and then back and forth across the top two,
        /// rather than all of them and then the last few on repeat. The repeat is
        /// what it was, and it sawtoothed: the sheet draws his muzzle at four
        /// different widths — 193, 210, 202, 218, a 13% spread, where his ears and
        /// skull are pixel-identical — so cycling the last three snapped him from
        /// the widest pose back to a narrow one three times over, and the face read
        /// as pulsing rather than laughing.
        ///
        /// A ping-pong matches every rise with the same fall back down. The muzzle
        /// still moves, because it is drawn that way and no amount of ordering can
        /// rescale part of a sprite, but it walks instead of snapping.
        ///
        /// Built from the sheet rather than typed, so a redraw with a different
        /// number of poses can't index off the end of it.
        static var laughOrder: [Int] {
            let last = UfoArt.frames.count - 1
            guard last >= 2 else { return Array(0...max(0, last)) }
            // 0,1,…,last, then (last-1, last) twice — up, and back and forth.
            return Array(0...last) + [last - 1, last, last - 1, last, last - 1]
        }

        static let laughFrame: TimeInterval = 0.12
        static var laughing: TimeInterval { TimeInterval(laughOrder.count) * laughFrame }

        /// And away to the right. He came in from the left and carries on rather
        /// than turning round, which keeps him going the way the world goes.
        static let away: TimeInterval = 1.0

        /// Benny's temper, which starts the instant the laugh ends — so the rabbit
        /// is bolting while he is still gritting his teeth, rather than waiting
        /// politely for him to finish.
        static let angryFrame: TimeInterval = 0.13
        static var angry: TimeInterval { TimeInterval(AngerArt.frames.count) * angryFrame }

        /// And a beat held on the burst before he composes himself.
        ///
        /// Longer than the wind-up that gets him there, deliberately. It was 0.45 —
        /// shorter than the six frames it followed — and he looked like he got over
        /// it the moment he arrived. Anger that takes 0.78s to build and 0.45s to
        /// drop reads as a flinch; holding it past the build is what makes it a
        /// grudge.
        ///
        /// He is motionless through this, and that is fine rather than frozen: the
        /// high sky is scrolling past him at `SkyArt.speed` the whole time, so the
        /// shot still moves even though he doesn't.
        static let hold: TimeInterval = 1.0

        /// How far the rocket sinks as he winds up, and jerks back as the burst
        /// goes off. This is the drift the cutter took out of the sheet, put back
        /// deliberately: twenty-four pixels of a 371-pixel drawing is about five
        /// points at the size he flies.
        static let recoil: CGFloat = 5

        /// A slow rise and fall while he waits and laughs, so the saucer reads as
        /// hanging in the air rather than pinned to the glass.
        static let hover: CGFloat = 9
        static let hoverTime: TimeInterval = 0.9
    }


    /// The card the game ends on, now that there is an end to reach.
    ///
    /// V1 ships one story beat: the run, the launch, and the cutscene where the
    /// rabbit laughs and gets away. Someone who reaches it has finished everything
    /// there is, and used to be told "Good boy! Tap to retry" — the crash message,
    /// which says nothing about why the game stopped.
    ///
    /// The cutscene has already done the work: the rabbit escaped and Benny is
    /// furious. That is a cliffhanger whether or not it is labelled one, so the card
    /// names it rather than reading like release notes.
    enum Finale {
        /// Every line of the card, with the size it is drawn at and how far its
        /// centre sits below the line before it.
        ///
        /// A node per line, which is not the obvious way to build this and is the
        /// only way that works. `SKLabelNode` will happily hold all four lines, but
        /// it left-aligns them inside the block whatever `horizontalAlignmentMode`
        /// is set to — measured on screen, the headline landed centred at 400 while
        /// "is coming soon" and "Tap to play again" sat at 369 and 374. It also
        /// draws every line at one size, where the headline wants to be nearly
        /// twice the rest.
        ///
        /// Laying the lines out here also makes the spacing a number rather than a
        /// consequence. The first attempt left three points between the headline's
        /// bottom and the body's top, which on screen read as one crowded block.
        static let lines: [(text: String, size: CGFloat, drop: CGFloat)] = [
            ("To be continued…", 38, 0),
            ("More of Benny's escape", 20, 48),
            ("is coming soon", 20, 26),
            ("Tap to play again", 20, 48),
        ]
    }

}
