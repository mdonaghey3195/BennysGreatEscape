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

    /// Whether the dog house has been spawned and is still scrolling in.
    ///
    /// Held apart from `isLaunching` because the two want different answers.
    /// Once the house is on its way nothing more spawns behind it — it has to be
    /// the next thing you see — but the player is still running, may still have
    /// an obstacle to clear before it arrives, and should still be scored for
    /// it. Only when it lands does the scene stop being a run.
    private var launchIncoming = false

    /// Whether the clip is playing and the scene belongs to it.
    private var isLaunching = false
    private var launch: SKNode?

    /// The flying phase's backdrop, held on the camera rather than in the world.
    ///
    /// Which is the one design decision in here worth stating. The launch leaves
    /// the camera 1036 units above where it started, and anything parented to
    /// the scene has to know that to be drawn in the right place. Hang the sky
    /// off the camera instead and its altitude stops existing as a problem: the
    /// strips fill the frame wherever the frame happens to be, scroll sideways
    /// on their own, and the camera can be put back to the middle of the scene
    /// afterwards without a pixel of it moving.
    private var highSky: SKNode?

    /// Whether the flying phase has taken over.
    ///
    /// Not cosmetic. `update` is written against a world that exists — turf to
    /// scroll, a dog to read a shadow off, a spawner feeding obstacles onto the
    /// ground — and `beginPhaseTwo` takes all of that away. Left running it
    /// quietly carried on, and the first thing it did up there was spawn a log
    /// into the open sky.
    private var isFlying = false

    /// Whether the score has asked for the dog house but the spawner hasn't
    /// stood it up yet.
    private var launchPending = false

    /// Whether Benny has set off for the door. A latch, like `launchBraking`
    /// below, so the dash is started once and not restarted every frame it is
    /// inside the trip distance.
    private var launchDashed = false

    /// Whether the world has started winding down for the house's arrival. A
    /// latch, so the brake is applied once rather than re-applied every frame
    /// for as long as the house is inside stopping distance.
    private var launchBraking = false

    /// Whether this run has already reached the launch. Per-run, like
    /// `benchesSpawned` and unlike `hasSpawnedLowObstacle`: the trigger sits in
    /// `scoreClearedObstacles`, which can clear several obstacles in one frame,
    /// and without this the clip would be staged once for each of them.
    private var hasLaunched = false

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

    /// How many benches this run has stood up, because the second one is the
    /// occupied one. Per-run, unlike `hasSpawnedLowObstacle`, which teaches the
    /// swipe once and is meant never to teach it again — a joke you have already
    /// been told is worth less than a hint you have already taken.
    private var benchesSpawned = 0

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

        // The frame. At the centre of the authored scene it reproduces exactly
        // what no camera at all was doing, so ordinary play is untouched — it
        // exists so the launch has something to lift.
        //
        // Anything framed against the *screen* rather than the world has to hang
        // off this instead of off the scene, or it is left behind the moment the
        // camera moves: the retry message and the crash flash, both built later,
        // are added to it and not to `self`.
        let eye = SKCameraNode()
        eye.position = CGPoint(x: Layout.sceneSize.width / 2,
                               y: Layout.sceneSize.height / 2)
        addChild(eye)
        camera = eye

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
        // Pulled off the leading edge only — see `DogArt.forgivenessFraction`.
        // Half off the width and half off the centre, which moves the right edge
        // in and leaves the left where it is: the trailing edge is already
        // behind his tail and giving away ground there would buy nothing.
        let give = DogArt.forgivenessFraction
        let box = CGSize(
            width: size.width
                * ((ducked ? DogArt.slideWidthFraction : DogArt.bodyWidthFraction) - give),
            height: size.height * (ducked ? DogArt.slideHeightFraction : DogArt.bodyHeightFraction)
        )
        let body = SKPhysicsBody(
            rectangleOf: box,
            center: CGPoint(
                x: size.width
                    * ((ducked ? DogArt.slideOffsetXFraction : DogArt.bodyOffsetXFraction)
                       - give / 2),
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
        // A tap during the opening clip skips it. It is the same four seconds
        // every time Play is tapped, and there is no reason to sit through it
        // twice.
        guard !isIntro else {
            finishIntro()
            return
        }
        // Before anything that swallows a touch. Once the run is over the only
        // thing a tap can mean is "again", whichever phase it ended in — and
        // the two guards below used to sit above this one, which made the end
        // card a dead end: `isFlying` stays true until `restart` clears it, and
        // `restart` is only reachable from here. Every tap on "Tap to play
        // again" was being swallowed on its way to the branch that answers it.
        guard !isGameOver else {
            restart()
            return
        }
        // The launch is the other way about: it is what a hundred obstacles were
        // for, it happens once, and a stray tap is not a request to miss it. So
        // this swallows the touch rather than acting on it.
        guard !isLaunching else { return }
        // And nothing up here answers to a gesture yet. The dog these would
        // steer has been taken out of the scene by `beginPhaseTwo`, so without
        // this a swipe goes looking for a jump on a detached physics body.
        guard !isFlying else { return }
        guard let touch = touches.first else { return }
        touchOrigin = touch.location(in: self)
        gestureResolved = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isIntro, !isLaunching, !isGameOver, !gestureResolved,
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
            //
            // An even split between the two once both are in, which is what
            // drawing from a two-piece rotation came to. Written out rather than
            // drawn, because the bench half of it now has to know *which* bench:
            // the second one of a run has a pair of dogs sitting on it. Only the
            // second. A surprise that turns up every time is scenery.
            if score >= 6 && Bool.random() {
                piece = ObstacleArt.swingset
            } else {
                benchesSpawned += 1
                // The guard is on the dogs, not on the bench: the occupied
                // bench *is* the bench now, so a missing texture can't be what
                // tells you the art didn't arrive. Without the dogs it would
                // spend the one occupied bench of the run on a drawing
                // indistinguishable from the empty one.
                piece = benchesSpawned == 2 && ObstacleArt.occupiedBench.hasOverlayArt
                    ? ObstacleArt.occupiedBench
                    : ObstacleArt.bench
            }
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
        // The dog house first, before the cliff is even rolled for. The score
        // asked for it and it has to be the next thing over the edge — anything
        // else arriving in front of it would be one more obstacle between the
        // player and the ending they just earned.
        if launchPending {
            launchPending = false
            sendInDogHouse()
            return
        }

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

            for overlay in piece.overlays { stand(overlay, on: node, size: size, sink: piece.sink) }
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

    /// Stands a dog on its bench and sets it breathing.
    ///
    /// Pinned by its feet, which is what `Overlay.yFraction` names — the top of
    /// the seat — so the dog sits on the bench rather than at some height above
    /// its foot that would have to be re-derived every time either drawing
    /// changed. Width follows the dog's own aspect, so a re-cut dog is never
    /// stretched against the bench.
    ///
    /// In front of the drawing rather than behind it, because a dog on a bench
    /// hides the part of the backrest he is sitting against.
    ///
    /// The phase is applied by rotating the array rather than by delaying the
    /// action. A delay would leave the second dog holding pose one for most of a
    /// second while the first had already started, which is a stillness the eye
    /// picks out; rotating starts them both moving at once, from different
    /// points in the same breath.
    private func stand(_ overlay: ObstacleArt.Overlay, on node: SKNode, size: CGSize, sink: CGFloat) {
        guard let first = overlay.frames.first, first.size().height > 0 else { return }
        let height = size.height * overlay.heightFraction
        let sprite = SKSpriteNode(
            texture: first,
            size: CGSize(width: height * first.size().width / first.size().height, height: height)
        )
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.position = CGPoint(
            x: size.width * overlay.xFraction,
            y: size.height * overlay.yFraction - sink
        )
        sprite.zPosition = 1
        node.addChild(sprite)

        guard overlay.frames.count > 1 else { return }
        let start = overlay.phase % overlay.frames.count
        let cycle = Array(overlay.frames[start...] + overlay.frames[..<start])
        sprite.run(.repeatForever(.animate(with: cycle,
                                           timePerFrame: ObstacleArt.Overlay.frameTime)))
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

        // Everything below this line belongs to the world `beginPhaseTwo` takes
        // down. Nothing in the flying phase is stepped from here yet — the sky
        // drifts on an action and Benny bobs on one — so this is the whole of
        // what the flying phase asks of `update` for now.
        guard !isFlying else { return }

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

        // The dog house rides in on the same step everything else does, which is
        // the whole point of it: at this stage it is a prop on the turf and not
        // a cutscene.
        if launchIncoming, let stage = launch {
            stage.position.x -= step

            // The brake and the clip start on the same frame, and that is the
            // point: waiting out the wind-down and *then* playing the slide is
            // what made the game appear to stop and think about it.
            //
            // Winding down linearly covers half the ground that holding speed
            // would, so a brake of `2 x slide` carries the house exactly as far
            // as Benny walks across the drawing — which means the trip point is
            // simply his own travel, and from here to a standstill the two
            // cancel and he holds station on screen.
            // One slide-length before the brake: he sets off for the door, and
            // arrives exactly as the clip takes over. The two trip points are a
            // slide-length apart because the stage covers that in exactly the
            // time the dash is given.
            if !launchDashed, stage.position.x - launchMark <= 2 * Launch.stopping(at: gameSpeed) {
                launchDashed = true
                startLaunchDash()
            }

            if !launchBraking, stage.position.x - launchMark <= Launch.stopping(at: gameSpeed) {
                launchBraking = true
                let settle = Launch.settle(at: gameSpeed)
                ramp(worldScroll: 0, over: settle)
                scenery.run(.speed(to: 0, duration: settle))
                landLaunch()
                run(.sequence([
                    .wait(forDuration: settle),
                    .run { [weak self] in self?.launchIncoming = false },
                ]))
            }
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
        // `worldScroll` as well as `gameSpeed`, so his legs wind down with the
        // turf when the world brakes for the dog house instead of sprinting on
        // the spot through it. It is 1 for the whole of an ordinary run, so this
        // changes nothing anywhere else.
        dog.childNode(withName: "body")?.speed =
            (isOnGround && !isSliding) ? gameSpeed / Layout.openingSpeed * worldScroll : 1

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
        //
        // Stops once he sets off for the door. From there the shadow is being
        // faded out by `startLaunchDash`, and an alpha written every frame from
        // here would simply overwrite the fade.
        if !launchDashed {
            let lift = min(1, max(0, (dog.position.y - Layout.dogGroundLine) / Layout.jumpHeight))
            dogShadow.setScale(1 - (1 - Layout.shadowLiftScale) * lift)
            dogShadow.alpha = 1 - (1 - Layout.shadowLiftAlpha) * lift
        }

        // Falling through a cliff's gap is a fourth way to end a run,
        // alongside the physics contact `didBegin` already handles — there is
        // no contact here to catch it, so it's caught by how far down he's
        // gotten instead. Short on purpose: see `Cliff.fallDeath`.
        if !isGameOver, dog.position.y < Layout.dogGroundLine - Cliff.fallDeath {
            endGame()
        }

        obstacleTimer += delta
        if !isLaunching, !launchIncoming, obstacleTimer >= obstacleInterval {
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
        // Once the launch is playing the run is over, and anything still
        // drifting past the mark is scenery rather than an obstacle cleared.
        guard !isLaunching else { return }

        enumerateChildNodes(withName: "obstacle") { node, _ in
            guard node.userData?["scored"] == nil, node.position.x < Layout.dogX else { return }
            let data = node.userData ?? NSMutableDictionary()
            data["scored"] = true
            node.userData = data

            self.score += 1
            self.onScoreChange?(self.score)
        }

        // The end of the running, and the only place it can be: this is where
        // the score changes. `>=` rather than `==` because two obstacles can
        // clear in one frame and the exact number would be stepped over.
        //
        // It arms the spawner rather than starting the clip. The dog house is
        // meant to arrive like everything else does — over the right-hand edge,
        // on the turf, at the game's own cadence — so the score says *when* and
        // the spawner says *how*.
        if !hasLaunched, score >= Launch.trigger {
            hasLaunched = true
            launchPending = true
            holdBackDogHouse()
        }
    }

    // MARK: - The launch

    /// Keeps the dog house back until the turf in front of Benny is clear.
    ///
    /// Nothing more spawns once the launch is armed, so the last obstacle of
    /// the run is whatever was already in flight when the score tipped over —
    /// and on the ordinary cadence the house would follow it by one interval,
    /// arriving while the player was still landing. This waits for the
    /// furthest thing out there to go past him and then holds off for
    /// `Launch.runway` on top.
    ///
    /// Done by pushing the spawn timer negative, which is how the cliff buys
    /// itself clear ground either side — see `spawnObstacle`. A debt on the
    /// timer rather than a flag, so there is nothing extra to reset or forget.
    private func holdBackDogHouse() {
        var furthest = Layout.dogX
        enumerateChildNodes(withName: "obstacle") { node, _ in
            furthest = max(furthest, node.position.x)
        }
        let clearing = TimeInterval((furthest - Layout.dogX) / max(gameSpeed, 1))
        obstacleTimer -= clearing + Launch.runway
    }

    /// Where the dog house comes to rest, once the world has finished winding
    /// down: far enough right of `Layout.dogX` that the slide's first frame
    /// would draw its dog exactly on Benny's mark.
    ///
    /// *Would*, not does — the hand-over happens a slide-length before the house
    /// gets here, which is why `launchHandoff` exists and why Benny walks out to
    /// meet it. This is still the number everything is measured from, because it
    /// is the one the art defines; it is just not the point at which the swap
    /// occurs.
    ///
    /// `drawnDogX`'s trick run backwards. There the scene asks the drawing where
    /// its dog is so the real one can be put there; here it knows where its dog
    /// is and places the drawing to match.
    private var launchMark: CGFloat {
        let canvas = Launch.houseWidth / LaunchArt.slideHouseWidth
        return Layout.dogX - (LaunchArt.slideBennyCentre - LaunchArt.slideHouseLeft) * canvas
    }

    /// Where Benny is standing when the clip takes him over.
    ///
    /// Not `Layout.dogX`, which is where he has stood for the whole game. The
    /// clip's first frame draws him a slide-length further on than his mark, and
    /// the hand-over fires a slide-length before the house reaches `launchMark`
    /// — the same distance, which is not a coincidence but the reason the two
    /// can be made to meet at all. `startLaunchDash` walks him here so the
    /// drawn dog appears exactly on the real one.
    private var launchHandoff: CGFloat { Layout.dogX + Launch.stopping(at: gameSpeed) }

    /// The last few strides, off his mark and towards his own front door.
    ///
    /// He has stood still for the whole game while the world came to him, so
    /// this is the one time he moves, and it is worth saying why it has to
    /// happen at all. The clip draws him a slide-length ahead of his mark;
    /// something has to cover that ground before the clip starts, or he jumps
    /// it in a single frame the moment it does. Either the house travels the
    /// extra — which drags the launch hard against the left edge and under the
    /// notch — or he does. He does, and it reads as a burst for home.
    ///
    /// Eased at both ends. He is at the world's speed on his mark, and back at
    /// it once the clip has him, because the clip's own motion works out to
    /// exactly the world's speed. So the burst has to grow out of one and settle
    /// into the other, or the hand-over trades a jump in position for a jump in
    /// velocity and nothing is gained.
    ///
    /// Its length is the time the house takes to cover the ground between the
    /// two trip points, so it lands on the second one by construction rather
    /// than by a timer that has to be kept in step with one.
    private func startLaunchDash() {
        let dash = SKAction.moveTo(x: launchHandoff, duration: Launch.slide(at: gameSpeed))
        dash.timingMode = .easeInEaseOut
        dog.run(dash)

        // And the shadow goes, because this is the one moment it stops being
        // his. It is drawn once at `Layout.dogX` and never moved again — which
        // is right for every other second of the game, where Benny holds that
        // mark and the world travels past him. The dash is the only time he
        // leaves it, and the shadow stays behind: a dark ellipse sitting on
        // bare turf while he runs off to the right, still there through the
        // whole slide, still there with the door shut and nobody in shot.
        //
        // Faded rather than cut, over the dash he is already running. Cutting
        // it works too and is one line shorter, but it pops on a frame where
        // the eye is on him and nothing else is changing.
        dogShadow.run(.fadeOut(withDuration: Launch.slide(at: gameSpeed) * 0.6))
    }

    /// Stands the dog house up off the right-hand edge and lets the turf bring
    /// it in.
    ///
    /// Called from the spawner rather than from the score, so it arrives on the
    /// game's own cadence and is simply the next thing over the edge — which is
    /// the whole of what makes it feel like part of the run instead of an
    /// announcement. It carries no physics body, like the cliff and for the same
    /// reason: it is not something to be cleared.
    private func sendInDogHouse() {
        launchIncoming = true
        stageLaunch(atX: Layout.spawnX)
    }

    /// Builds the clip on one node, with every sprite at that node's origin, so
    /// that moving the node moves all of it. Starts showing nothing but the
    /// house, shut.
    private func stageLaunch(atX x: CGFloat) {
        let stage = SKNode()
        stage.zPosition = 9  // over the turf, under Benny — the intro's shelf
        stage.position = CGPoint(x: x, y: Layout.dogGroundLine)
        addChild(stage)
        launch = stage

        let houseWidth = Launch.houseWidth
        let canvas = houseWidth / LaunchArt.slideHouseWidth

        // What scrolls in. The same canvas as the slide's frames and the same
        // house drawn on it, so when the clip starts this is swapped for frame
        // zero and nothing whatever moves.
        let shut = sprite(LaunchArt.houseShut, width: canvas, anchorX: LaunchArt.slideHouseLeft)
        shut?.name = "shut"
        shut.map(stage.addChild)

        let slide = sprite(LaunchArt.slideFrames.first, width: canvas,
                           anchorX: LaunchArt.slideHouseLeft)
        slide?.name = "slide"
        slide?.isHidden = true
        slide.map(stage.addChild)

        // Everything after the slide is drawn on the roof's canvas, pinned by
        // the same corner of the same house. Its last frame is the open house
        // the rocket leaves from, so it is never swapped for anything — it just
        // stops animating.
        let roof = sprite(LaunchArt.roofFrames.first, width: houseWidth / LaunchArt.roofHouseWidth,
                          anchorX: LaunchArt.roofHouseLeft)
        roof?.name = "roof"
        roof?.alpha = 0
        roof?.isHidden = true
        roof.map(stage.addChild)

        // Behind the house, which is what makes it come *out* of it: the first
        // half of the climb is the rocket rising with the house drawn over it,
        // and that is all the rise sheet's early frames are.
        let rocket = sprite(LaunchArt.rocket, width: houseWidth * LaunchArt.rocketInHouses,
                            anchorX: 0)
        rocket?.name = "rocket"
        rocket?.zPosition = -1
        rocket?.position = CGPoint(x: LaunchArt.rocketFrom.x * houseWidth,
                                   y: LaunchArt.rocketFrom.y * houseWidth)
        rocket?.isHidden = true
        rocket.map(stage.addChild)

        // The turn from standing on its tail to flying level is drawn on its own
        // sheet at its own scale, so it gets its own sprite: animating the
        // rocket's would keep the rocket's size and squash every pose into it.
        // `flyInHouses` is picked so the first pose comes out exactly as tall as
        // the rocket, which is what makes the changeover invisible.
        let fly = sprite(LaunchArt.flyFrames.first, width: houseWidth * LaunchArt.flyInHouses,
                         anchorX: 0.5)
        fly?.name = "fly"
        fly?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        fly?.isHidden = true
        fly.map(stage.addChild)
    }

    /// The house has arrived. The scene stops being a run and becomes a clip.
    private func landLaunch() {
        guard launchIncoming, !isLaunching, !isGameOver else { return }
        isLaunching = true

        // `launchIncoming` deliberately stays set. The house is still moving —
        // it has the whole wind-down left to travel — and the clip has to keep
        // riding the turf through it, because that leftward travel is what
        // cancels the drawn Benny's rightward walk and holds him still. It
        // clears when the world does.
        //
        // Still at `launchHandoff`, not at `Layout.dogX`: the dash has just put
        // the real dog there and the clip's first frame draws its own on the
        // same spot, which is the whole point of the dash.
        //
        // Nor is the stage snapped to `launchMark`: it was, back when the house
        // arrived stationary, and it would now be yanking a moving thing to a
        // spot it is still a frame away from.

        // A slide the player started can't be left half-played under a clip that
        // has taken the scene over.
        if isSliding { endSlide() }

        runLaunch()
    }

    /// One sprite, sized by width off the texture's own aspect and anchored on
    /// the house's ground-left corner.
    private func sprite(_ texture: SKTexture?, width: CGFloat, anchorX: CGFloat) -> SKSpriteNode? {
        guard let texture, texture.size().width > 0 else { return nil }
        let node = SKSpriteNode(
            texture: texture,
            size: CGSize(width: width, height: width * texture.size().height / texture.size().width)
        )
        node.anchorPoint = CGPoint(x: anchorX, y: 0)
        return node
    }

    /// The clip: one sequence on the stage, each beat starting the next piece of
    /// it and then waiting out its length.
    ///
    /// On the stage rather than on a sprite because no one sprite is in all of
    /// it — the slide hands over to the roof and the roof to the rocket — and
    /// hanging the timeline off whichever happened to be on screen would mean
    /// stopping it to change what it was.
    private func runLaunch() {
        guard let stage = launch,
              let shut = stage.childNode(withName: "shut") as? SKSpriteNode,
              let slide = stage.childNode(withName: "slide") as? SKSpriteNode,
              let roof = stage.childNode(withName: "roof") as? SKSpriteNode,
              let rocket = stage.childNode(withName: "rocket") as? SKSpriteNode,
              let fly = stage.childNode(withName: "fly") as? SKSpriteNode,
              LaunchArt.slideFrames.count > 1, LaunchArt.roofFrames.count > 1,
              LaunchArt.flyFrames.count > 1
        else {
            // No artwork, no clip — `runIntro`'s stance, and for the same
            // reason. The run still ends properly.
            finishLaunch()
            return
        }

        // The drawn house becomes the drawn house-and-dog, and the real Benny
        // goes in the same frame. Both sprites carry the same house on the same
        // canvas at the same place, so the only thing that changes is that
        // there is now a beagle in the picture — standing exactly where the one
        // that just vanished was standing.
        shut.isHidden = true
        slide.isHidden = false
        dog.isHidden = true
        dog.physicsBody?.isDynamic = false

        // Taken once, from the speed the world was doing when the clip began,
        // so the frames and the wind-down are working off the same number. A
        // duration each rather than one for all of them — see `slideBeats`.
        let beats = Launch.slideBeats(at: gameSpeed)
        let sliding = beats.reduce(0) { $0 + $1.duration }
        let opening = Double(LaunchArt.roofFrames.count) * Launch.roofFrame
        let turning = Double(LaunchArt.flyFrames.count) * Launch.turnFrame

        // Stage-relative now, so the apex has to come back into the stage's
        // frame — it is the one measurement here that belongs to the world.
        let ascent = SKAction.move(to: CGPoint(
            x: rocket.position.x,
            y: Layout.groundTop + Launch.apex(forRocketOfHeight: rocket.size.height)
                - stage.position.y
        ), duration: Launch.climb)
        ascent.timingMode = .easeIn

        // The frame goes up with him, over the same beat and on the same curve,
        // so the two accelerate together and he simply pulls ahead. By the top
        // the turf is four hundred units below the bottom edge and there is
        // nothing in shot but sky — which is the shot the flying phase opens on.
        let lift = SKAction.moveBy(x: 0, y: Launch.cameraRise, duration: Launch.climb)
        lift.timingMode = .easeIn

        // And away to the right, level, far enough past the corner to be gone
        // rather than small. It only drifts up a little: by now it has finished
        // turning and is flying forward, which is the shot the flying phase
        // opens on.
        let exit = SKAction.moveBy(x: Layout.sceneSize.width * 1.2,
                                   y: Layout.sceneSize.height * 0.12, duration: Launch.away)
        exit.timingMode = .easeIn

        stage.run(.sequence([
            .run { slide.run(.sequence(beats)) },
            .wait(forDuration: sliding + Launch.beforeRoof),

            // Crossed rather than cut, and not for polish. The slide sheet and
            // the roof sheet draw *different* dog houses — same width, 12.5%
            // apart in aspect, with the doorway and the name plate redrawn — so
            // a straight cut between them pops. `Art/CutLaunch.swift` measures
            // the gap and says so every run. The real fix is one house across
            // all four sheets, at which point this can go back to a cut.
            .run {
                roof.isHidden = false
                roof.run(.fadeIn(withDuration: Launch.blend))
                slide.run(.fadeOut(withDuration: Launch.blend))
                roof.run(.sequence([
                    .wait(forDuration: Launch.blend),
                    .animate(with: LaunchArt.roofFrames, timePerFrame: Launch.roofFrame),
                ]))
            },
            .wait(forDuration: Launch.blend + opening + Launch.beforeLaunch),

            .run { [weak self] in
                rocket.isHidden = false
                rocket.run(ascent)
                self?.camera?.run(lift)
                self?.raiseHighSky()
            },
            .wait(forDuration: Launch.climb),

            .run {
                // Same centre, same height, different drawing — so the swap onto
                // the flight sheet is a change of pose and not of position.
                fly.position = CGPoint(x: rocket.position.x + rocket.size.width / 2,
                                       y: rocket.position.y + rocket.size.height / 2)
                rocket.isHidden = true
                fly.isHidden = false
                fly.run(.sequence([
                    .animate(with: LaunchArt.flyFrames, timePerFrame: Launch.turnFrame),
                    exit,
                ]))
            },
            .wait(forDuration: turning + Launch.away),

            .run { [weak self] in self?.beginPhaseTwo() },
        ]))
    }

    /// The one way out of the clip, whichever way it ended.
    private func finishLaunch() {
        guard isLaunching else { return }
        isLaunching = false

        launch?.removeFromParent()
        launch = nil

        // The frame stays where the shot left it, up in the sky. Snapping it
        // back here cut from open air to the turf a beat before the retry
        // message landed, which read as the game losing its place — and it
        // bought nothing, because the only ways on from here are `restart` and
        // `returnToTitle`, and both rebuild the world from scratch with a fresh
        // camera at the centre.
        camera?.removeAllActions()

        removeAction(forKey: "worldScroll")
        scenery.removeAllActions()
    }

    /// Brings the high sky up behind the climb.
    ///
    /// Built here rather than with the rest of the world because until the
    /// rocket is lit there is nothing up there to look at, and a second backdrop
    /// sitting at alpha nought through an entire run is a scrolling action and
    /// two sprites being paid for every frame of a game that never shows them.
    private func raiseHighSky() {
        guard highSky == nil, let camera, let texture = SkyArt.sheet else { return }

        let sky = SKNode()
        sky.zPosition = -200  // behind the painting it is replacing
        sky.alpha = 0
        camera.addChild(sky)
        highSky = sky

        // Centred on the camera, since that is where its origin now is.
        let size = CGSize(width: SkyArt.tileWidth, height: SkyArt.height)
        for index in 0..<SkyArt.stripCount {
            let strip = SKSpriteNode(texture: texture, size: size)
            strip.anchorPoint = .zero
            strip.position = CGPoint(x: CGFloat(index) * size.width - Layout.sceneSize.width / 2,
                                     y: -size.height / 2)
            sky.addChild(strip)
            drift(strip, speed: SkyArt.speed, width: SkyArt.tileWidth)
        }

        sky.run(.sequence([
            .wait(forDuration: Launch.skyFadeAfter),
            .fadeIn(withDuration: Launch.skyFade),
        ]))
    }

    /// Where the second phase of the game begins.
    ///
    /// The rocket has levelled off and flown out of shot, and the high sky came
    /// up behind it on the way. What is left to do is take down the world he has
    /// left — all of it, since none of it can be reached from up here — and fly
    /// him back in.
    ///
    /// The camera goes back to the middle of the scene in the same breath, and
    /// that move is free: the only thing on screen is the sky, and the sky is
    /// parented to the camera, so it cannot see the camera move. Everything the
    /// flying phase builds from here is in ordinary scene coordinates with the
    /// frame where it has always been — which is what keeps physics possible
    /// when there is finally something up here to hit.
    private func beginPhaseTwo() {
        finishLaunch()

        // The ground, and everything standing on it.
        scenery.removeFromParent()
        land?.removeFromParent()
        ground.removeFromParent()
        dog.removeFromParent()
        dogShadow.removeFromParent()
        enumerateChildNodes(withName: "obstacle") { node, _ in node.removeFromParent() }
        enumerateChildNodes(withName: "cliff") { node, _ in node.removeFromParent() }

        camera?.position = CGPoint(x: Layout.sceneSize.width / 2,
                                   y: Layout.sceneSize.height / 2)

        isFlying = true
        startFlying()
    }

    /// The flying phase, so far: Benny comes in from the left and flies.
    ///
    /// Deliberately only this much. There are no lanes yet and nothing to dodge,
    /// because the backdrop is what everything else will be judged against and
    /// it is worth looking at on its own first. The run still ends after a few
    /// seconds, the way `beginPhaseTwo` has ended it all along, so a launch can
    /// be played through without leaving the game somewhere it can't get out of.
    private func startFlying() {
        guard let pose = LaunchArt.flyFrames.last else { endGame(crashed: false); return }

        let width = Launch.houseWidth * LaunchArt.flyInHouses
        let flier = SKSpriteNode(
            texture: pose,
            size: CGSize(width: width, height: width * pose.size().height / pose.size().width)
        )
        flier.name = "flier"
        flier.zPosition = 10

        // Anchored on the rocket's nose, not the canvas centre — see
        // `LaunchArt.flyNose`. His position is therefore where the *nose* goes,
        // so the figures below are worked back from where the centred sprite
        // used to sit: he ends up in exactly the same place, and every later
        // texture swap hangs from the same point.
        flier.anchorPoint = LaunchArt.flyNose
        let noseX = Layout.dogX + (LaunchArt.flyNose.x - 0.5) * flier.size.width
        let noseY = Layout.sceneSize.height / 2
            + (LaunchArt.flyNose.y - 0.5) * flier.size.height
        flier.position = CGPoint(x: -flier.size.width, y: noseY)
        addChild(flier)

        let entry = SKAction.moveTo(x: noseX, duration: Flight.entry)
        entry.timingMode = .easeOut

        // A slow rise and fall on top of it, so he reads as flying rather than
        // as a sticker on a scrolling picture. It is the only motion he has
        // until the lanes arrive.
        let bob = SKAction.sequence([
            .moveBy(x: 0, y: Flight.bob, duration: Flight.bobTime),
            .moveBy(x: 0, y: -Flight.bob, duration: Flight.bobTime),
        ])
        bob.timingMode = .easeInEaseOut

        let arrive = SKAction.sequence([entry, .repeatForever(bob)])

        // No saucer, no clip — `runIntro`'s stance for missing art, and for the
        // same reason. Benny still flies in and the phase still starts.
        guard let ufo = makeUfo(nextTo: flier) else {
            flier.run(arrive)
            endFlightAfterLook()
            return
        }
        addChild(ufo)

        let hover = SKAction.sequence([
            .moveBy(x: 0, y: Rabbit.hover, duration: Rabbit.hoverTime),
            .moveBy(x: 0, y: -Rabbit.hover, duration: Rabbit.hoverTime),
        ])
        hover.timingMode = .easeInEaseOut

        let flyIn = SKAction.moveTo(x: Rabbit.stopX, duration: Rabbit.flyIn)
        flyIn.timingMode = .easeOut

        let away = SKAction.moveTo(x: Layout.sceneSize.width + ufo.size.width,
                                   duration: Rabbit.away)
        away.timingMode = .easeIn

        // Up through the poses and then back and forth across the top two —
        // see `Rabbit.laughOrder`. He is left on the calm pose for the flight
        // out, so he leaves composed.
        let laugh = SKAction.sequence([
            .animate(with: Rabbit.laughOrder.map { UfoArt.frames[$0] },
                     timePerFrame: Rabbit.laughFrame),
            .setTexture(UfoArt.frames[0]),
        ])

        ufo.run(.sequence([flyIn, .repeatForever(hover)]))

        run(.sequence([
            .wait(forDuration: Rabbit.flyIn + Rabbit.beforeBenny),
            .run { flier.run(arrive) },

            .wait(forDuration: Flight.entry + Rabbit.beforeLaugh),
            .run { ufo.run(laugh) },

            // The hover is a move and so is the exit; both write `position`, so
            // the hover is stopped rather than left to argue with the flight
            // out. Stopped here and not before, because it is what keeps the
            // saucer alive through the laugh.
            //
            // Benny starts fuming on the same frame, so the rabbit is bolting
            // while he is still gritting his teeth rather than after.
            .wait(forDuration: Rabbit.laughing),
            .run { [weak self] in
                ufo.removeAllActions()
                ufo.run(.sequence([away, .removeFromParent()]))
                self?.startAnger(flier)
            },

            .wait(forDuration: Rabbit.angry + Rabbit.hold),
            .run { [weak self] in
                self?.settle(flier)
                self?.endFlightAfterLook()
            },
        ]))
    }

    /// Benny watches the rabbit laugh and loses his temper.
    ///
    /// The bob is torn down first and deliberately. It is a `moveBy` repeating
    /// for ever and the recoil is a `moveBy` too — both write `position`, and
    /// left running they argue, which is the same trap the saucer's hover hit
    /// on its way out.
    ///
    /// Size and anchor are set along with the texture, never without it. These
    /// sheets are a different shape from the launch sheet — 1.71 against 0.99 —
    /// and carry the rocket somewhere else on the canvas, so setting a texture
    /// on its own would both squash him and jump him a sixth of his height.
    private func startAnger(_ flier: SKSpriteNode) {
        guard let first = AngerArt.frames.first else { return }
        flier.removeAllActions()
        wear(first, on: flier)

        // Sinks as he winds up, jerks back as the burst goes off — the drift
        // taken out of the sheet, put back with a shape.
        let down = SKAction.moveBy(x: 0, y: -Rabbit.recoil, duration: Rabbit.angry * 0.7)
        down.timingMode = .easeIn
        let up = SKAction.moveBy(x: 0, y: Rabbit.recoil, duration: Rabbit.angry * 0.3)
        up.timingMode = .easeOut

        flier.run(.animate(with: AngerArt.frames, timePerFrame: Rabbit.angryFrame))
        flier.run(.sequence([down, up]))
    }

    /// And composes himself. This is the face the flying phase is played on.
    private func settle(_ flier: SKSpriteNode) {
        guard let serious = AngerArt.serious else { return }
        flier.removeAllActions()
        wear(serious, on: flier)

        let bob = SKAction.sequence([
            .moveBy(x: 0, y: Flight.bob, duration: Flight.bobTime),
            .moveBy(x: 0, y: -Flight.bob, duration: Flight.bobTime),
        ])
        bob.timingMode = .easeInEaseOut
        flier.run(.repeatForever(bob))
    }

    /// Puts one of `AngerArt`'s poses on the flier without moving or resizing
    /// the rocket inside it.
    ///
    /// The one place the three sheets are reconciled: they are the same drawing
    /// at different resolutions and croppings, so the sprite is sized by
    /// `widthInFlyFrames` and hung from `AngerArt.nose`, both measured off the
    /// rocket's nose cone. Change one without the other and he changes size or
    /// jumps.
    private func wear(_ texture: SKTexture, on flier: SKSpriteNode) {
        let width = Launch.houseWidth * LaunchArt.flyInHouses * AngerArt.widthInFlyFrames
        flier.anchorPoint = AngerArt.nose
        flier.size = CGSize(width: width, height: width / AngerArt.aspect)
        flier.texture = texture
    }

    /// The saucer, sized against Benny and parked off the left-hand edge.
    ///
    /// `nil` when the sheet isn't there — `numberedTextures` comes back empty
    /// rather than handing out a placeholder, which is the point of it.
    private func makeUfo(nextTo flier: SKSpriteNode) -> SKSpriteNode? {
        guard let first = UfoArt.frames.first, UfoArt.frames.count > 1 else { return nil }

        let width = flier.size.width * Rabbit.widthInFliers
        let ufo = SKSpriteNode(
            texture: first,
            size: CGSize(width: width, height: width / UfoArt.aspect)
        )
        ufo.name = "ufo"
        ufo.zPosition = 11  // over Benny, who passes below him
        ufo.position = CGPoint(x: -width, y: Rabbit.height)
        return ufo
    }

    /// Lets the phase run for a while and then ends it, until there is
    /// something up here to play against.
    private func endFlightAfterLook() {
        run(.sequence([
            .wait(forDuration: Flight.look),
            .run { [weak self] in self?.endGame(crashed: false, finale: true) },
        ]))
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

    /// Ends the run.
    ///
    /// `crashed` is what separates hitting something from simply arriving at the
    /// end of what is built. The flying phase runs out rather than killing him,
    /// and giving that the full treatment — the crash sound, the haptic, the
    /// squash and the white flash — reads as a fault in a shot where nothing
    /// went wrong.
    ///
    /// `finale` is the other half of that: reaching the end of the story is not
    /// losing, and "Good boy! Tap to retry" is the wrong thing to say about it.
    /// Both default to the crash, so the twenty-odd other ways a run can end are
    /// untouched.
    private func endGame(crashed: Bool = true, finale: Bool = false) {
        guard !isGameOver else { return }
        isGameOver = true
        physicsWorld.speed = 0
        scenery.isPaused = true
        // He is still flying when the phase runs out, and a frozen scene with
        // one thing in it still moving reads as the game having lost track.
        childNode(withName: "flier")?.isPaused = true
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

        if crashed {
            Sfx.shared.play(.crash)
            Haptics.crash()
            // Harder than a landing, and the last thing he does. Actions still
            // run in a scene whose *physics* is stopped, which is what lets the
            // impact play out over a world that has already frozen.
            squash(xScale: 1.35, yScale: 0.68)
            flash()
        }

        if finale {
            showFinale()
        } else {
            messageLabel = SKLabelNode(fontNamed: "AvenirNextCondensed-Heavy")
            messageLabel.text = "Good boy! Tap to retry"
            messageLabel.fontSize = 30
            messageLabel.fontColor = Palette.ink
            messageLabel.horizontalAlignmentMode = .center
            // Centred vertically, the one part of the scene `.aspectFill` never
            // crops. On the camera, at its origin, which is the middle of the
            // frame wherever the frame happens to be. A crash can't move it, but
            // a launch can: end a run up in the sky and a scene-positioned label
            // would be 550 units below the bottom of the screen.
            messageLabel.position = .zero
            messageLabel.zPosition = 50
            messageLabel.setScale(0)
            (camera ?? self).addChild(messageLabel)
            messageLabel.run(.sequence([
                .wait(forDuration: Self.crashHold),
                .scale(to: 1, duration: 0.25),
            ]))
        }

        // On both paths. Reaching the end of the story means a score of at least
        // `Launch.atScore`, so leaving it out here would make the best run
        // anybody can have the one that never reaches the leaderboard.
        onGameOver?(score)
    }

    /// The card the game ends on — see `Finale`.
    ///
    /// One label per line, stacked and then shifted so the block as a whole sits
    /// on the camera's centre rather than hanging from its first line. Hung on
    /// the camera for the same reason the retry message is: the run ends a
    /// thousand points up in the sky, and anything positioned in the scene would
    /// be left behind on the ground.
    private func showFinale() {
        // Walk down the lines to find each centre, then recentre the block.
        var centres: [CGFloat] = []
        var cursor: CGFloat = 0
        for line in Finale.lines {
            cursor -= line.drop
            centres.append(cursor)
        }
        let shift = -((centres.first ?? 0) + (centres.last ?? 0)) / 2

        for (line, centre) in zip(Finale.lines, centres) {
            let isHeadline = line.size == Finale.lines.first?.size
            let label = SKLabelNode(
                fontNamed: isHeadline ? "AvenirNextCondensed-Heavy"
                                      : "AvenirNextCondensed-Medium")
            label.text = line.text
            label.fontSize = line.size
            label.fontColor = Palette.ink
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: centre + shift)
            label.zPosition = 50
            label.setScale(0)
            (camera ?? self).addChild(label)
            label.run(.sequence([
                .wait(forDuration: Self.crashHold),
                .scale(to: 1, duration: 0.25),
            ]))
            // Kept so the scene holds a reference to one of them, the way it
            // does for the retry message.
            if isHeadline { messageLabel = label }
        }
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
        sheet.position = .zero   // the camera's centre — see `messageLabel`
        sheet.zPosition = 45
        sheet.alpha = 0
        (camera ?? self).addChild(sheet)
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
        benchesSpawned = 0
        isLaunching = false
        launchIncoming = false
        launchPending = false
        launchDashed = false
        launchBraking = false
        hasLaunched = false
        launch = nil
        isFlying = false
        // `removeAllChildren` has already taken these; this is so the scene
        // isn't left holding references to them until `build` makes new ones.
        highSky = nil
        camera = nil
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
