//
//  GameLayout.swift
//  Benny's Great Escape
//
//  The space the game is played in: what size everything is, where the ground
//  sits, and the colours the scene paints in code.
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

    // MARK: - Physics categories

    enum PhysicsCategory {
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
    enum Layout {
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

        /// Where the dog and every obstacle stand — and, through
        /// `BackdropArt.bottomY`, where the painting behind them hangs from.
        ///
        /// That second job makes this the one place the whole scene can be slid up
        /// or down. Everything vertical in the game derives from it, the scenery
        /// included, so moving it moves the world and the countryside together and
        /// nothing comes off the plane it was staged on.
        ///
        /// Which is the hard-won part. `BackdropArt.standFraction` also moves the
        /// painting and looks like the same knob, and it is not: it slides the
        /// picture *underneath* a world that stays put. Reaching for it to drop the
        /// scene left the dog house, the obstacles and Benny standing seventeen
        /// units further back up the grass than they were drawn to sit, with the
        /// house's feet in the middle of the turf instead of at its front edge.
        ///
        /// A quarter of the way up what is actually shown — 91 above the visible
        /// bottom edge of 66, in a band 368 tall. It was 175 until the repainted
        /// sky arrived with clouds near the top of its lowest band; eighteen units
        /// down is what stops the screen's top edge slicing them, and it buys
        /// eighteen units of jump headroom on the way past. Portrait had this at
        /// 35%, and the difference is sky that landscape can no longer afford.
        static let groundTop: CGFloat = 157

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


    /// What is still drawn rather than painted. The sky, the hills and the turf
    /// used to be here too, and are in `bg_scroll` now.
    enum Palette {
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

}
