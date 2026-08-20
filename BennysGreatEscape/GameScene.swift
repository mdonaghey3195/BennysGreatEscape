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

// MARK: - The dog's artwork

/// Benny, drawn side-on and facing right — the way he runs.
private enum DogArt {
    /// Frames are collected until one is missing, so a real run cycle is a pure
    /// asset drop: add `benny_run_1`, `benny_run_2`, … to the catalogue and the
    /// animation starts on its own, with nothing here to change.
    ///
    /// Probed with `UIImage(named:)` rather than `SKTexture(imageNamed:)`
    /// because the latter hands back a placeholder for a missing name instead
    /// of nil, so it can't tell you where the frames stop.
    static let frames: [SKTexture] = load("benny_run")

    /// The jump arc — bound, rear up, two airborne poses, reach down, land.
    /// Loaded the same way, so extra frames are a pure asset drop here too.
    static let jumpFrames: [SKTexture] = load("benny_jump")

    /// The slide — drop, slide, deep slide, recover.
    static let slideFrames: [SKTexture] = load("benny_slide")

    private static func load(_ prefix: String) -> [SKTexture] {
        var textures: [SKTexture] = []
        var index = 0
        while let image = UIImage(named: "\(prefix)_\(index)") {
            textures.append(SKTexture(image: image))
            index += 1
        }
        return textures
    }

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
    private var hasSpawnedLowObstacle = false

    /// Driven by ground contacts rather than inferred from velocity. Velocity
    /// passes through zero at the apex of every jump, so testing `vy ≈ 0` would
    /// let you jump again in mid-air.
    private var groundContacts = 0
    private var isOnGround: Bool { groundContacts > 0 }

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
        guard !isGameOver else {
            restart()
            return
        }
        guard let touch = touches.first else { return }
        touchOrigin = touch.location(in: self)
        gestureResolved = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isGameOver, !gestureResolved,
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
    /// The old body's `didEnd` never arrives, so the ground contact count would
    /// creep up with every slide — and once it's above one, the count never
    /// reaches zero in mid-air and `isOnGround` stays true, handing out free
    /// double jumps. Since a swap only ever happens with his feet down, pinning
    /// the count back to exactly one is both safe and correct.
    private func setDucked(_ ducked: Bool) {
        dog.physicsBody = makeDogPhysics(ducked: ducked)
        groundContacts = 1
    }

    private func jump() {
        // Swiping up out of a slide cancels it — standing back up mid-air would
        // otherwise leave the ducked hitbox on while he's clearly upright.
        if isSliding { endSlide() }
        guard isOnGround else { return }
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

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver else { return }

        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        // Clamped so a stall — backgrounding, a slow first frame — can't advance
        // the spawner by a huge step and dump a wall of obstacles at once.
        let delta = min(currentTime - lastUpdateTime, 1.0 / 30)
        lastUpdateTime = currentTime

        scrollGroundDetail(by: gameSpeed * CGFloat(delta))

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
            groundContacts += 1
            // Not while sliding. Swapping in the ducked body makes the ground
            // report a fresh contact, and landing back into a gallop here would
            // wipe the slide a frame or two after it started — which is exactly
            // what made the slide impossible to see.
            if !isGameOver, !isSliding {
                squash(xScale: 1.2, yScale: 0.8)
                puffDust()
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
        if categories == (PhysicsCategory.dog | PhysicsCategory.ground) {
            groundContacts = max(0, groundContacts - 1)
        }
    }

    // MARK: - Game over / restart

    private func endGame() {
        guard !isGameOver else { return }
        isGameOver = true
        physicsWorld.speed = 0
        scenery.isPaused = true
        // Otherwise he keeps galloping on the spot in the frozen scene.
        dog.childNode(withName: "body")?.isPaused = true
        enumerateChildNodes(withName: "obstacle") { node, _ in node.removeAllActions() }

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
        messageLabel.run(.scale(to: 1, duration: 0.25))

        onGameOver?(score)
    }

    /// Begins play. `hasStarted` is deliberately not cleared by `restart`, so
    /// retrying after a crash drops straight back into the run rather than
    /// bouncing the player out to the title screen.
    func start() {
        hasStarted = true
    }

    /// Winds the world back to its opening state and stops play, so the title
    /// screen has a fresh run waiting behind it rather than a half-finished one.
    func returnToTitle() {
        restart()
        hasStarted = false
    }

    private func restart() {
        removeAllChildren()

        score = 0
        isGameOver = false
        isSliding = false
        touchOrigin = nil
        gestureResolved = false
        groundContacts = 0
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
