//
//  GameScene.swift
//  Benny's Great Escape
//
//  Benny gallops, you tap to jump, the logs and bushes keep coming.
//
//  The world is drawn entirely in code — gradient sky, parallax clouds and
//  hills, scrolling turf. The only artwork is Benny himself, a six-frame gallop
//  and a six-frame jump arc in the asset catalogue.
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
    static let dogWidth: CGFloat = 80

    /// Height follows the artwork's aspect so Benny is never stretched, and
    /// keeps following it if the drawing is ever replaced with one shaped
    /// differently.
    static var dogSize: CGSize {
        CGSize(width: dogWidth, height: dogWidth / DogArt.aspect)
    }

    static let dogX: CGFloat = 120

    /// Apex of a jump above `groundTop`. Obstacles top out around 85, so this is
    /// forgiving without feeling floaty.
    static let jumpHeight: CGFloat = 140

    /// Underside of a low rail, above the turf. Has to sit below the 44pt
    /// running box or Benny would stroll under it untouched, and above the 26pt
    /// ducked box or sliding wouldn't save him. 34 leaves margin both ways.
    static let railClearance: CGFloat = 34

    /// A slide covers this much ground rather than lasting a fixed time — at
    /// the top scroll speed a fixed duration would end before the rail had
    /// finished passing. Rail plus dog is about 150, so this leaves margin.
    static let slideDistance: CGFloat = 260

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
    /// 26pt tall against 44pt running, so a rail at `Layout.railClearance` is
    /// hit standing and cleared sliding. Slightly narrower than the drawing, so
    /// a trailing paw brushing an obstacle doesn't end the run.
    static let slideWidthFraction: CGFloat = 0.80
    static let slideHeightFraction: CGFloat = 0.362
    static let slideOffsetXFraction: CGFloat = 0.030
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
    static let bush = SKColor(red: 0.30, green: 0.66, blue: 0.34, alpha: 1)
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
    var onFirstRail: (() -> Void)?
    private var hasSpawnedRail = false

    /// Driven by ground contacts rather than inferred from velocity. Velocity
    /// passes through zero at the apex of every jump, so testing `vy ≈ 0` would
    /// let you jump again in mid-air.
    private var groundContacts = 0
    private var isOnGround: Bool { groundContacts > 0 }

    private var obstacleTimer: TimeInterval = 0
    private var obstacleInterval: TimeInterval = 1.8
    private var lastUpdateTime: TimeInterval = 0
    private var gameSpeed: CGFloat = 220

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
            edgeFrom: CGPoint(x: left, y: Layout.groundTop),
            to: CGPoint(x: left + span, y: Layout.groundTop)
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
        node.position = CGPoint(x: Layout.dogX, y: Layout.groundTop + size.height / 2)
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
            y: Layout.groundTop + 5
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
        // Rails stay the minority — they're the newer verb, and a run that's
        // mostly ducking loses the rhythm of jumping. They also hold off until
        // a few obstacles in, so the first thing anyone meets is a jump.
        let wantsRail = score >= 2 && DogArt.slideFrames.count > 1 && Int.random(in: 0..<10) < 3
        let obstacle: SKNode
        if wantsRail {
            obstacle = makeRail()
            if !hasSpawnedRail {
                hasSpawnedRail = true
                onFirstRail?()
            }
        } else {
            obstacle = Bool.random() ? makeLog() : makeBush()
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

    private func makeLog() -> SKNode {
        let node = SKNode()
        let size = CGSize(width: CGFloat.random(in: 42...60), height: CGFloat.random(in: 52...85))

        let log = SKShapeNode(
            rect: CGRect(x: -size.width / 2, y: 0, width: size.width, height: size.height),
            cornerRadius: 10
        )
        log.fillColor = Palette.log
        log.strokeColor = Palette.ink
        log.lineWidth = Layout.outline
        node.addChild(log)

        // A couple of rings so it reads as a cut log rather than a brown box.
        for offset in [size.height * 0.35, size.height * 0.65] {
            let ring = SKShapeNode(ellipseOf: CGSize(width: size.width * 0.42, height: 9))
            ring.fillColor = .clear
            ring.strokeColor = Palette.ink
            ring.lineWidth = 2.5
            ring.alpha = 0.5
            ring.position = CGPoint(x: 0, y: offset)
            node.addChild(ring)
        }

        node.physicsBody = Self.obstacleBody(size: size)
        return node
    }

    private func makeBush() -> SKNode {
        let node = SKNode()
        let size = CGSize(width: 66, height: CGFloat.random(in: 46...66))

        for (dx, r) in [(-18.0, 21.0), (0.0, 28.0), (18.0, 21.0)] {
            let clump = SKShapeNode(circleOfRadius: r)
            clump.fillColor = Palette.bush
            clump.strokeColor = Palette.ink
            clump.lineWidth = Layout.outline
            clump.position = CGPoint(x: dx, y: size.height - r)
            node.addChild(clump)
        }

        node.physicsBody = Self.obstacleBody(size: size)
        return node
    }

    /// A low rail on two posts — the obstacle you duck rather than jump.
    ///
    /// Placeholder, drawn in the same style as the logs and bushes until the
    /// painted fence art lands; swapping it for a sprite is a change to this
    /// function alone.
    private func makeRail() -> SKNode {
        let node = SKNode()
        let span: CGFloat = 96
        let railHeight: CGFloat = 20
        let postWidth: CGFloat = 16
        let postTop = Layout.railClearance + railHeight

        // Posts are decoration only. They stand on the turf either side, so
        // giving them bodies would make the rail impossible to get past —
        // letting Benny slide between them is the usual 2D shorthand.
        for dx in [-span / 2, span / 2] {
            let post = SKShapeNode(
                rect: CGRect(x: dx - postWidth / 2, y: 0, width: postWidth, height: postTop),
                cornerRadius: 5
            )
            post.fillColor = Palette.log
            post.strokeColor = Palette.ink
            post.lineWidth = Layout.outline
            node.addChild(post)
        }

        let rail = SKShapeNode(
            rect: CGRect(x: -span / 2 - 4, y: Layout.railClearance, width: span + 8, height: railHeight),
            cornerRadius: 6
        )
        rail.fillColor = Palette.log
        rail.strokeColor = Palette.ink
        rail.lineWidth = Layout.outline
        node.addChild(rail)

        let body = SKPhysicsBody(
            rectangleOf: CGSize(width: span + 8, height: railHeight),
            center: CGPoint(x: 0, y: Layout.railClearance + railHeight / 2)
        )
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.obstacle
        body.contactTestBitMask = PhysicsCategory.dog
        node.physicsBody = body

        return node
    }

    private static func obstacleBody(size: CGSize) -> SKPhysicsBody {
        let body = SKPhysicsBody(rectangleOf: size, center: CGPoint(x: 0, y: size.height / 2))
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
        dog.childNode(withName: "body")?.speed = (isOnGround && !isSliding) ? gameSpeed / 220 : 1

        // Everything above keeps the title screen alive; everything below is the
        // game proper and waits for the first tap.
        guard hasStarted else { return }

        obstacleTimer += delta
        if obstacleTimer >= obstacleInterval {
            obstacleTimer -= obstacleInterval
            spawnObstacle()
            obstacleInterval = max(0.95, obstacleInterval - 0.02)
            gameSpeed = min(380, gameSpeed + 4)
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
        gameSpeed = 220
        lastUpdateTime = 0
        physicsWorld.speed = 1

        onScoreChange?(0)
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
