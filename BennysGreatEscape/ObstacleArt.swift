//
//  ObstacleArt.swift
//  Benny's Great Escape
//
//  The things Benny has to get past: what each one is, how big it stands, and
//  the solid shape inside its drawing that actually stops him.
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


    // MARK: - The obstacle artwork

    /// Everything Benny meets on the path, painted and dropped into the catalogue:
    /// a fallen log, a bush and a tree stump to jump, and a park bench and a
    /// swingset to duck.
    enum ObstacleArt {

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

        /// Something standing on a drawing that has a life of its own: the two dogs
        /// sitting on the second bench of a run.
        ///
        /// `Hang`'s idea — a sprite pinned to another drawing at fractions of it —
        /// with a run of textures instead of a rotation. Stated in fractions for the
        /// same reason everything here is, so that a re-cut bench carries its
        /// passengers with it.
        ///
        /// Its being a *layer* rather than part of the picture is the whole lesson
        /// of the attempt before it. The dogs used to be drawn onto the bench —
        /// five separate drawings of bench-and-dogs — and a prop whose bench is
        /// redrawn five times is a prop whose bench moves: the five never agreed
        /// about it to the pixel, and the eye catches a bench that shifts even by
        /// one. Here the bench is `bench`'s own texture and is never animated at
        /// all, so the only thing that can move is a dog. It also settles the other
        /// complaint for nothing: the occupied bench is exactly the size of the
        /// empty one, because it *is* the empty one.
        struct Overlay {
            let frames: [SKTexture]

            /// Where its feet stand: x as a fraction of the drawing's width out
            /// from the centre, y as a fraction of the drawing's height up from its
            /// foot — which for these is the top of the bench's seat.
            let xFraction: CGFloat
            let yFraction: CGFloat

            /// How tall, as a fraction of the drawing's height. Over 1 for both of
            /// these, and rightly: a sitting dog is taller than the bench he is
            /// sitting on. Width follows the drawing's own aspect, so a re-cut dog
            /// can never come out stretched.
            let heightFraction: CGFloat

            /// Which pose it starts on. The two are offset for the reason
            /// `Hang.swayPhase` gives: two dogs breathing in step read as one
            /// two-headed animal rather than as two animals.
            let phase: Int

            /// Slow, and slow on purpose. Two dogs sitting still are the point; this
            /// only has to keep them from looking stuffed. Five poses at this rate
            /// is a breath every two and a quarter seconds, about what a resting dog
            /// does.
            static let frameTime: TimeInterval = 0.45
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

            /// Anything standing on the drawing under its own steam: the two dogs
            /// on the occupied bench, and nothing else.
            var overlays: [Overlay] = []

            /// Whether every overlay actually found its art. `numberedTextures`
            /// hands back an empty run for a name that isn't in the catalogue, and
            /// an overlay with no frames draws nothing at all.
            var hasOverlayArt: Bool { !overlays.isEmpty && overlays.allSatisfy { !$0.frames.isEmpty } }

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

        /// The jump rotation. The ones you duck are deliberately not in here — they
        /// are picked by hand in `spawnObstacle`.
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

        /// Where the dogs stand, as a fraction of the bench drawing's height up from
        /// its foot.
        ///
        /// Not the top of the seat, which is what this said at first and is how both
        /// dogs came to be hovering. The bench is drawn in perspective and its seat
        /// is a band 85 rows deep, not a line: "the top" is its *far* edge, and a
        /// dog standing on the far edge has the whole seat showing under its paws.
        /// This is 88% of the way forward across that band, near the front lip,
        /// which is where a dog actually sits. `Art/CutDogs.swift` measures both
        /// edges and prints it, so a re-cut bench moves them with it.
        private static let dogSeat: CGFloat = 0.564

        /// The two of them. Sizes and places are a composition rather than a
        /// measurement — the dogs and the bench were drawn apart, so how they meet
        /// is a choice — and `Art/CutDogs.swift` prints these from the same
        /// constants its preview is built with, so the preview is what settles them.
        private static let blackDog = Overlay(
            frames: numberedTextures("dog_black"),
            xFraction: -0.170, yFraction: dogSeat, heightFraction: 0.910, phase: 0
        )

        private static let goldenDog = Overlay(
            frames: numberedTextures("dog_golden"),
            xFraction: 0.140, yFraction: dogSeat, heightFraction: 1.080, phase: 2
        )

        /// The bench you meet second, with two dogs on it.
        ///
        /// The *same* bench — `bench`'s texture, clamp, solid and sink, passed
        /// straight through. Not a second drawing sized to agree with the first, but
        /// the first one with passengers, which is why there is nothing to measure
        /// here and nothing that can drift out of agreement later. It renders 170 x
        /// 83 because the empty bench does, and the duck is the same duck because it
        /// is the same box.
        ///
        /// It got here the long way. An earlier version drew the dogs into the
        /// bench and had to be a whole second obstacle: its own underseat fraction,
        /// its own box, its own quarrel with being two fifths too long. All of that
        /// is gone, and with it the bench that moved.
        static let occupiedBench = Piece(
            texture: bench.texture, heightRange: bench.heightRange, solid: bench.solid,
            offsetXFraction: bench.offsetXFraction, sink: bench.sink,
            overlays: [blackDog, goldenDog]
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

        // There is no `ducks` array to match `jumps`. The two verbs are weighted
        // against each other in `spawnObstacle` rather than drawn from one bag, and
        // the duck side of that now has to pick between three drawings on a rule
        // rather than two at random — so it is written out there instead.

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
    enum Cliff {
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
        /// `BackdropArt.standFraction` of the way *through* it — the same
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

}
