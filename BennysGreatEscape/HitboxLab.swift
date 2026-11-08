//
//  HitboxLab.swift
//  Benny's Great Escape
//
//  DEBUG-only test harness for comparing hitboxes between builds. Stages one
//  obstacle at an exact lead distance, fires the game's own jump or slide,
//  measures Benny's real physics box every frame by probing the physics world,
//  and saves annotated screenshots of the decisive frame.
//
//  Launch arguments:
//    -HitboxLab cases|sweep|all   run the lab instead of the game
//    -LabBuild before|after       label for the output folder and HUD
//    -LabOnly <prefix>            only cases / sweep targets with this prefix
//    -LabOut <path>               output folder (default: the host's
//                                 ~/Development/BGE-lab-results/<build>)
//    -ShowPhysics                 draw SpriteKit's physics outlines
//
//  Branch-agnostic on purpose: nothing here reads the hitbox's parameters, so
//  the same file runs unchanged on master and on feature/hitbox-improvements.
//

#if DEBUG
import SpriteKit
import UIKit

// MARK: - Configuration

enum LabPiece: String {
    case log, logStack, hedge, stump, bush, bench, occupiedBench, swingset, cliff, none

    var piece: GameScene.ObstacleArt.Piece? {
        switch self {
        case .log: GameScene.ObstacleArt.log
        case .logStack: GameScene.ObstacleArt.logStack
        case .hedge: GameScene.ObstacleArt.hedge
        case .stump: GameScene.ObstacleArt.stump
        case .bush: GameScene.ObstacleArt.bush
        case .bench: GameScene.ObstacleArt.bench
        case .occupiedBench: GameScene.ObstacleArt.occupiedBench
        case .swingset: GameScene.ObstacleArt.swingset
        case .cliff, .none: nil
        }
    }
}

enum LabAction: String { case jump, slide, none }

enum LabInput {
    /// Frames counted from the trigger; 0 is the trigger frame itself.
    case at(Int, LabAction)
    /// The first frame this pose is on screen.
    case onPose(String, LabAction)
    /// Touchdown frame plus an offset.
    case onLanding(Int, LabAction)
    /// Jump on the first grounded frame after every landing, this many times.
    case jumpOnEveryLanding(Int)
    /// When obstacle `index` has passed behind Benny's box.
    case whenCleared(Int, LabAction)
}

enum LabFreeze {
    /// HIT: the contact frame. CLEAR: the frame of closest approach.
    case outcome
    /// The frame the obstacle's centre crosses Benny's anchor.
    case top
    case frames([Int])
    case poses([String])
    case landing([Int])
    case none
}

enum LabDistance {
    case fixed(CGFloat)
    /// Key into plan.json for the case's target, with a model-predicted fallback.
    case plan(String, CGFloat)
    case planOffset(String, CGFloat, CGFloat)
}

struct LabCase {
    var id: String
    var piece: LabPiece = .none
    var speed: CGFloat = GameScene.Layout.openingSpeed
    /// Size tier for jump props. Nil: the piece's fixed height.
    var tier: CGFloat? = nil
    var target: String = ""
    var d: LabDistance = .fixed(150)
    var inputs: [LabInput] = []
    var freeze: LabFreeze = .outcome
    var repeats = 3
    var intercept = true
    var maxFrames = 150
    /// A second obstacle placed this far behind the first (pair spacing).
    var follower: LabPiece? = nil
    /// Let the real game-over happen, tap to retry, then jump once.
    var crashThenRetry = false
}

// MARK: - Measurements

struct LabBox: Codable {
    var floor: Double, top: Double, back: Double, front: Double
}

struct LabSample: Codable {
    var frame: Int
    var pose: String
    var paw: Double            // paw line above the ground line
    var box: LabBox?           // edges: floor/top above the paw line, back/front from dogX
    var sep: Double?           // signed separation to the nearest obstacle solid
    var grounded: Bool
    var obstacleX: Double?     // first obstacle's centre minus dogX
}

struct LabResult: Codable {
    var outcome = "CLEAR"
    var hitFrame: Int?
    var hitPose: String?
    var minSep: Double?
    var minSepFrame: Int?
    var minSepPose: String?
    var topFrame: Int?
    var landingFrame: Int?
    var apexes: [Double] = []
    var groundEvents: [String] = []
    var samples: [LabSample] = []
    var shots: [String] = []
    var note: String?
}

struct LabCaseRecord: Codable {
    var id: String
    var build: String
    var piece: String
    var speed: Double
    var height: Double?
    var d: Double
    var outcome: String
    var runs: [String]
    var hitFrame: Int?
    var hitPose: String?
    var minSep: Double?
    var minSepPose: String?
    var landingFrame: Int?
    var apexes: [Double]
    var groundEvents: [String]
    var shots: [String]
    var notes: [String]
    var trace: [LabSample]?
}

struct LabSweepRecord: Codable {
    var target: String
    var build: String
    var piece: String
    var action: String
    var speed: Double
    var height: Double
    var d: Double
    var outcome: String
    var minSep: Double?
    var minSepPose: String?
    var hitFrame: Int?
    var hitPose: String?
}

/// The solid of an obstacle, in scene coordinates.
enum LabShape {
    case rect(CGRect)
    case disc(CGPoint, CGFloat)

    var maxX: CGFloat {
        switch self {
        case .rect(let r): r.maxX
        case .disc(let c, let r): c.x + r
        }
    }

    var topY: CGFloat {
        switch self {
        case .rect(let r): r.maxY
        case .disc(let c, let r): c.y + r
        }
    }

    /// Positive: clear by that much. Negative: overlapping by that much.
    func separation(from box: CGRect) -> CGFloat {
        switch self {
        case .rect(let o):
            let sx = max(o.minX - box.maxX, box.minX - o.maxX)
            let sy = max(o.minY - box.maxY, box.minY - o.maxY)
            if sx > 0 && sy > 0 { return hypot(sx, sy) }
            return max(sx, sy)
        case .disc(let c, let r):
            if box.contains(c) {
                return -r - min(c.x - box.minX, box.maxX - c.x, c.y - box.minY, box.maxY - c.y)
            }
            let qx = min(max(c.x, box.minX), box.maxX)
            let qy = min(max(c.y, box.minY), box.maxY)
            return hypot(c.x - qx, c.y - qy) - r
        }
    }

    /// Where the two come closest, for the zoomed screenshot.
    func focus(with box: CGRect) -> CGPoint {
        switch self {
        case .rect(let o):
            return CGPoint(x: (max(box.minX, o.minX) + min(box.maxX, o.maxX)) / 2,
                           y: (max(box.minY, o.minY) + min(box.maxY, o.maxY)) / 2)
        case .disc(let c, let r):
            let qx = min(max(c.x, box.minX), box.maxX)
            let qy = min(max(c.y, box.minY), box.maxY)
            let dx = qx - c.x, dy = qy - c.y
            let len = max(0.001, hypot(dx, dy))
            return CGPoint(x: (qx + c.x + dx / len * r) / 2, y: (qy + c.y + dy / len * r) / 2)
        }
    }

    static func of(_ piece: GameScene.ObstacleArt.Piece, height: CGFloat, at position: CGPoint) -> LabShape {
        let size = piece.size(height: height)
        let x = position.x + size.width * piece.offsetXFraction
        guard piece.texture != nil else {
            return .rect(CGRect(x: position.x - size.width / 2, y: position.y,
                                width: size.width, height: size.height))
        }
        switch piece.solid {
        case let .box(w, h, base):
            return .rect(CGRect(x: x - size.width * w / 2,
                                y: position.y + size.height * base - piece.sink,
                                width: size.width * w, height: size.height * h))
        case let .disc(radius, centre):
            return .disc(CGPoint(x: x, y: position.y + size.height * centre - piece.sink),
                         size.height * radius)
        }
    }
}

// MARK: - The lab

final class HitboxLab {
    static var shared: HitboxLab?
    static var isActive: Bool { shared != nil }

    /// Launch arguments, plus any in `lab.args` in the host's results folder —
    /// so the lab can be driven without editing the scheme. Delete that file
    /// and an ordinary Run is an ordinary game again.
    static let arguments: [String] = {
        var args = ProcessInfo.processInfo.arguments
        if let host = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] {
            let file = URL(fileURLWithPath: host).appendingPathComponent("Development/BGE-lab-results/lab.args")
            if let text = try? String(contentsOf: file, encoding: .utf8) {
                args += text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
            }
        }
        return args
    }()
    static func argument(_ name: String) -> String? {
        guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
        let value = arguments[i + 1]
        return value.hasPrefix("-") ? nil : value
    }
    static var showPhysics: Bool { arguments.contains("-ShowPhysics") || arguments.contains("-HitboxLab") }

    /// Creates the lab if the launch arguments ask for it.
    static func configure(scene: GameScene) -> HitboxLab? {
        if let shared { shared.scene = scene; return shared }
        guard let mode = argument("-HitboxLab") else { return nil }
        let lab = HitboxLab(mode: mode, scene: scene)
        shared = lab
        return lab
    }

    weak var scene: GameScene?
    let mode: String
    let build: String
    let only: String?
    let root: URL
    let out: URL
    var plan: [String: [String: Double]] = [:]

    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var frameCount = 0
    private var started = false

    // Per-trial contact state, written by `observe`.
    private var intercepting = true
    private var pendingHit = false
    private var groundLog: [String] = []
    private var trialFrame = 0

    init(mode: String, scene: GameScene) {
        self.mode = mode
        self.scene = scene
        build = HitboxLab.argument("-LabBuild") ?? "unlabelled"
        only = HitboxLab.argument("-LabOnly")
        if let custom = HitboxLab.argument("-LabOut") {
            root = URL(fileURLWithPath: custom)
        } else if let host = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] {
            root = URL(fileURLWithPath: host).appendingPathComponent("Development/BGE-lab-results")
        } else {
            root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("HitboxLab")
        }
        out = root.appendingPathComponent(build)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    // MARK: Frame clock

    /// Called from `GameScene.didFinishUpdate`, after physics, every frame.
    func tick() {
        frameCount += 1
        scene?.labHoldWorld()
        if !started, frameCount > 30 {
            started = true
            Task { @MainActor in await self.runAll() }
        }
        let ready = waiters
        waiters = []
        for waiter in ready { waiter.resume() }
    }

    func nextFrame() async {
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Contacts, from the scene's delegate. Returns true to swallow one.
    func observe(_ contact: SKPhysicsContact, began: Bool) -> Bool {
        let categories = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if categories == (GameScene.PhysicsCategory.dog | GameScene.PhysicsCategory.ground) {
            groundLog.append("\(trialFrame + 1):\(began ? "begin" : "end")")
            return false
        }
        if began, categories == (GameScene.PhysicsCategory.dog | GameScene.PhysicsCategory.obstacle) {
            pendingHit = true
            return intercepting
        }
        return false
    }

    // MARK: Output

    private func append(_ line: some Encodable, to file: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(line) else { return }
        data.append(0x0A)
        let url = out.appendingPathComponent(file)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private func status(_ text: String) {
        print("LAB \(build): \(text)")
        try? "\(Date()) \(text)\n".data(using: .utf8)?.write(to: out.appendingPathComponent("STATUS.txt"))
    }

    // MARK: Running

    @MainActor
    func runAll() async {
        Music.shared.isEnabled = false
        Sfx.shared.isEnabled = false
        for name in ["results.jsonl", "sweep.jsonl", "DONE"] where mode != "cases" || name != "sweep.jsonl" {
            try? FileManager.default.removeItem(at: out.appendingPathComponent(name))
        }
        if let data = try? Data(contentsOf: root.appendingPathComponent("plan.json")),
           let decoded = try? JSONDecoder().decode([String: [String: Double]].self, from: data) {
            plan = decoded
        }
        status("started mode=\(mode) only=\(only ?? "-") plan=\(plan.isEmpty ? "none" : "loaded")")

        // Warm-up: the first trials after launch run while textures and audio
        // are still loading, and a hitch there shifts the physics against the
        // scroll. Two throwaway jumps over a log settle it.
        var warmup = LabCase(id: "warmup")
        warmup.piece = .log
        warmup.tier = GameScene.Layout.openingSpeed
        warmup.inputs = [.at(0, .jump)]
        for _ in 0..<2 { _ = await trial(warmup, d: 117, stopAt: nil, captureHit: nil) }

        if mode == "sweep" || mode == "all" { await runSweeps() }
        if mode == "cases" || mode == "all" {
            let cases = HitboxLab.catalogue().filter { only == nil || $0.id.hasPrefix(only!) }
            for (i, c) in cases.enumerated() {
                status("case \(i + 1)/\(cases.count) \(c.id)")
                await runCase(c)
            }
        }
        status("done")
        try? "done\n".data(using: .utf8)?.write(to: out.appendingPathComponent("DONE"))
        print("LAB DONE")
    }

    // MARK: Cases

    func distance(_ c: LabCase) -> CGFloat {
        switch c.d {
        case .fixed(let d): return d
        case .plan(let key, let fallback): return CGFloat(plan[c.target]?[key] ?? Double(fallback))
        case .planOffset(let key, let fallback, let offset):
            return CGFloat(plan[c.target]?[key] ?? Double(fallback)) + offset
        }
    }

    @MainActor
    func runCase(_ c: LabCase) async {
        guard let scene else { return }
        // A boundary the sweep found no such thing for (no phantom zone at this
        // size, say) is recorded as not applicable rather than run at a guess.
        if !plan.isEmpty {
            var key: String?
            switch c.d {
            case .plan(let k, _), .planOffset(let k, _, _): key = k
            case .fixed: key = nil
            }
            if let key, plan[c.target]?[key] == nil {
                append(LabCaseRecord(
                    id: c.id, build: build, piece: c.piece.rawValue, speed: Double(c.speed), height: nil,
                    d: 0, outcome: "N/A", runs: [], hitFrame: nil, hitPose: nil, minSep: nil,
                    minSepPose: nil, landingFrame: nil, apexes: [], groundEvents: [], shots: [],
                    notes: ["no \(key) boundary for \(c.target) in the sweep"], trace: nil
                ), to: "results.jsonl")
                return
            }
        }
        let d = distance(c)
        var runs: [LabResult] = []
        for r in 0..<max(1, c.repeats) {
            runs.append(await trial(c, d: d, stopAt: nil, captureHit: r == 0 && c.freeze != LabFreeze.none ? c.id : nil))
        }
        let outcomes = runs.map(\.outcome)
        let first = runs[0]
        var outcome = Set(outcomes).count == 1 ? first.outcome : "FLAKY"
        var shots = first.shots
        var notes: [String] = []
        if let n = first.note { notes.append(n) }

        // Captures that need a second pass at a known frame.
        var stops: [(Int, String)] = []
        switch c.freeze {
        case .outcome:
            if first.outcome != "HIT", let f = first.minSepFrame { stops.append((f, c.id)) }
        case .top:
            if let f = first.topFrame { stops.append((f, c.id)) }
        case .frames(let list):
            for f in list { stops.append((f, "\(c.id)_f\(f)")) }
        case .poses(let poses):
            for pose in poses {
                if let s = first.samples.first(where: { $0.pose == pose && $0.frame > 0 }) ?? first.samples.first(where: { $0.pose == pose }) {
                    stops.append((s.frame, "\(c.id)_\(pose)"))
                } else {
                    notes.append("pose \(pose) never shown")
                }
            }
        case .landing(let offsets):
            if let t = first.landingFrame {
                for o in offsets { stops.append((t + o, "\(c.id)_T\(o >= 0 ? "+" : "")\(o)")) }
            } else {
                notes.append("no landing seen")
            }
        case .none:
            break
        }
        for (frame, label) in stops {
            let shot = await trial(c, d: d, stopAt: frame, captureHit: nil, label: label)
            shots += shot.shots
            if let n = shot.note { notes.append(n) }
            if c.freeze == .outcome || c.freeze == .top, shot.outcome == "HIT", first.outcome != "HIT" {
                outcome = "FLAKY"
                notes.append("capture pass hit at frame \(shot.hitFrame ?? -1)")
            }
        }

        let height = c.piece.piece.map { piece in c.tier.map { scene.labHeight(piece, tier: $0) } ?? piece.heightRange.lowerBound }
        let keepTrace = true
        append(LabCaseRecord(
            id: c.id, build: build, piece: c.piece.rawValue, speed: Double(c.speed),
            height: height.map(Double.init), d: Double(d), outcome: outcome, runs: outcomes,
            hitFrame: first.hitFrame, hitPose: first.hitPose, minSep: first.minSep,
            minSepPose: first.minSepPose, landingFrame: first.landingFrame, apexes: first.apexes,
            groundEvents: first.groundEvents, shots: shots, notes: notes,
            trace: keepTrace ? first.samples : nil
        ), to: "results.jsonl")
    }

    // MARK: Sweeps

    struct SweepTarget {
        let id: String
        let piece: LabPiece
        let speed: CGFloat
        let tier: CGFloat?
        let action: LabAction
        let range: ClosedRange<CGFloat>
        let step: CGFloat
    }

    static func sweepTargets() -> [SweepTarget] {
        var targets: [SweepTarget] = []
        let jumps: [LabPiece] = [.log, .logStack, .hedge, .stump, .bush]
        for piece in jumps {
            for tier in GameScene.ObstacleArt.sizeTiers {
                targets.append(SweepTarget(
                    id: "\(piece.rawValue)@\(Int(tier.rounded()))", piece: piece, speed: tier, tier: tier,
                    action: .jump, range: (tier * 0.30)...(tier * 0.62), step: 2))
            }
        }
        let top = GameScene.Layout.topSpeed
        for piece in [LabPiece.bench, .swingset] {
            targets.append(SweepTarget(id: "\(piece.rawValue)/hurdle", piece: piece, speed: top, tier: nil,
                                       action: .jump, range: 140...240, step: 2))
        }
        for piece in [LabPiece.bench, .swingset] {
            targets.append(SweepTarget(id: "\(piece.rawValue)/slide", piece: piece,
                                       speed: GameScene.Layout.openingSpeed, tier: nil,
                                       action: .slide, range: 60...280, step: 4))
        }
        return targets
    }

    @MainActor
    func runSweeps() async {
        guard let scene else { return }
        let targets = HitboxLab.sweepTargets().filter { only == nil || $0.id.hasPrefix(only!) || "S-\($0.id)".hasPrefix(only!) }
        for (i, t) in targets.enumerated() {
            status("sweep \(i + 1)/\(targets.count) \(t.id)")
            var c = LabCase(id: "S-\(t.id)")
            c.piece = t.piece
            c.speed = t.speed
            c.tier = t.tier
            c.inputs = t.action == .none ? [] : [.at(0, t.action)]
            c.maxFrames = 200
            let height = t.tier.map { scene.labHeight(t.piece.piece!, tier: $0) } ?? t.piece.piece!.heightRange.lowerBound

            var results: [CGFloat: String] = [:]
            func record(_ d: CGFloat) async -> String {
                let r = await trial(c, d: d, stopAt: nil, captureHit: nil)
                append(LabSweepRecord(
                    target: t.id, build: build, piece: t.piece.rawValue, action: t.action.rawValue,
                    speed: Double(t.speed), height: Double(height), d: Double(d), outcome: r.outcome,
                    minSep: r.minSep, minSepPose: r.minSepPose, hitFrame: r.hitFrame, hitPose: r.hitPose
                ), to: "sweep.jsonl")
                return r.outcome
            }

            var d = t.range.lowerBound
            var grid: [CGFloat] = []
            while d <= t.range.upperBound + 0.001 { grid.append(d); d += t.step }
            for d in grid { results[d] = await record(d) }

            // Refine every outcome change down to a quarter point, then repeat the
            // two points either side of it.
            for (a, b) in zip(grid, grid.dropFirst()) where results[a] != results[b] {
                var lo = a, hi = b
                let loOutcome = results[a]
                while hi - lo > 0.26 {
                    let mid = ((lo + hi) / 2 * 4).rounded() / 4
                    if mid <= lo || mid >= hi { break }
                    let o = await record(mid)
                    if o == loOutcome { lo = mid } else { hi = mid }
                }
                for _ in 0..<2 {
                    _ = await record(lo)
                    _ = await record(hi)
                }
            }
        }
    }

    // MARK: One trial

    @MainActor
    func trial(_ c: LabCase, d: CGFloat, stopAt: Int?, captureHit: String?, label: String? = nil) async -> LabResult {
        var result = LabResult()
        guard let scene else { result.outcome = "NOSCENE"; return result }

        // Reset through the game's own path, then wait for Benny to settle.
        intercepting = true
        pendingHit = false
        scene.labRestart()
        scene.labSpeed = c.speed
        var grounded = 0
        var waited = 0
        while grounded < 10 {
            await nextFrame()
            waited += 1
            grounded = scene.labGrounded && !scene.labSliding ? grounded + 1 : 0
            if waited > 400 { result.outcome = "NOGROUND"; return result }
        }

        // L-7: crash for real first, retry, and only then run the case.
        if c.crashThenRetry {
            intercepting = false
            let crashPiece = GameScene.ObstacleArt.log
            let crashHeight = scene.labHeight(crashPiece, tier: GameScene.Layout.openingSpeed)
            _ = scene.labPlace(crashPiece, height: crashHeight, centreX: GameScene.Layout.dogX + d)
            scene.labJump()
            var waitedCrash = 0
            while !scene.labGameOver, waitedCrash < 200 { await nextFrame(); waitedCrash += 1 }
            result.note = scene.labGameOver ? "crashed at +\(waitedCrash), retried" : "did not crash"
            for _ in 0..<20 { await nextFrame() }
            scene.labTapToRetry()
            scene.labSpeed = c.speed
            grounded = 0
            while grounded < 10 {
                await nextFrame()
                grounded = scene.labGrounded ? grounded + 1 : 0
            }
        }

        intercepting = c.intercept
        pendingHit = false
        groundLog = []
        trialFrame = 0

        // Trigger.
        let groundLine = GameScene.Layout.dogGroundLine
        let dogX = GameScene.Layout.dogX
        var obstacles: [(node: SKNode, piece: GameScene.ObstacleArt.Piece, height: CGFloat)] = []
        var cliffGap: CGFloat?
        if c.piece == .cliff {
            cliffGap = scene.labPlaceCliff(centreX: dogX + d)
        } else if let piece = c.piece.piece {
            let h = c.tier.map { scene.labHeight(piece, tier: $0) } ?? piece.heightRange.lowerBound
            let node = scene.labPlace(piece, height: h, centreX: dogX + d)
            obstacles.append((node, piece, h))
            if let followerKind = c.follower, let fp = followerKind.piece {
                let fh = scene.labHeight(fp, tier: c.speed)
                let gap = scene.labPairSeparation(lead: piece, leadHeight: h, follower: fp, followerHeight: fh)
                let f = scene.labPlace(fp, height: fh, centreX: dogX + d + gap)
                obstacles.append((f, fp, fh))
            }
        }
        if let cliffGap { result.note = "cliff gap \(String(format: "%.1f", cliffGap))" }

        var fired = Set<Int>()
        var jumpsOnLanding = 0
        var airborne = false
        var apex: CGFloat = 0
        var landing: Int?
        var poseSeen = Set<String>()
        var cleared = Set<Int>()

        func apply(_ action: LabAction) {
            switch action {
            case .jump: scene.labJump()
            case .slide: scene.labSlide()
            case .none: break
            }
        }

        func inputs(frame: Int, pose: String, newlyLanded: Bool) {
            for (i, input) in c.inputs.enumerated() where !fired.contains(i) {
                switch input {
                case let .at(f, action) where f == frame:
                    fired.insert(i); apply(action)
                case let .onPose(p, action) where frame > 0 && p == pose:
                    fired.insert(i); apply(action)
                case let .onLanding(o, action):
                    if let t = landing, frame == t + o { fired.insert(i); apply(action) }
                case let .jumpOnEveryLanding(count):
                    if frame == 0 || newlyLanded, jumpsOnLanding < count {
                        jumpsOnLanding += 1
                        apply(.jump)
                    }
                case let .whenCleared(index, action):
                    if cleared.contains(index) { fired.insert(i); apply(action) }
                default:
                    break
                }
            }
        }

        func measure(frame: Int) -> (LabSample, CGRect?, [LabShape]) {
            let paw = scene.labPawY
            let box = scene.labProbeBox()
            let shapes = obstacles.map { LabShape.of($0.piece, height: $0.height, at: $0.node.position) }
            let sep = box.flatMap { b in shapes.map { $0.separation(from: b) }.min() }
            let sample = LabSample(
                frame: frame, pose: scene.labPose, paw: Double(paw - groundLine),
                box: box.map { LabBox(floor: Double($0.minY - paw), top: Double($0.maxY - paw),
                                      back: Double($0.minX - dogX), front: Double($0.maxX - dogX)) },
                sep: sep.map(Double.init), grounded: scene.labGrounded,
                obstacleX: obstacles.first.map { Double($0.node.position.x - dogX) }
            )
            return (sample, box, shapes)
        }

        func hud(_ s: LabSample, outcome: String) -> String {
            let floor = s.box.map { String(format: "%+.1f", $0.floor) } ?? "?"
            let sep = s.sep.map { String(format: "%+.1f", $0) } ?? "-"
            return "\(label ?? captureHit ?? c.id) · \(build.uppercased()) · \(String(format: "%.1f", c.speed)) pt/s · d \(String(format: "%.2f", d)) · f\(s.frame) \(s.pose) · floor \(floor) · sep \(sep) · \(outcome)"
        }

        // Frame 0 is the trigger: state before the first step, inputs fire now.
        var frame = 0
        let (s0, _, _) = measure(frame: 0)
        result.samples.append(s0)
        poseSeen.insert(s0.pose)
        inputs(frame: 0, pose: s0.pose, newlyLanded: false)
        if stopAt == 0 {
            let (s, box, shapes) = measure(frame: 0)
            result.shots += await capture(name: label ?? c.id, sample: s, box: box, shapes: shapes, text: hud(s, outcome: "FRAME"))
            return result
        }

        while true {
            await nextFrame()
            frame += 1
            trialFrame = frame
            scene.labSpeed = c.speed

            let (s, box, shapes) = measure(frame: frame)
            result.samples.append(s)
            let newPose = !poseSeen.contains(s.pose)
            poseSeen.insert(s.pose)

            // Airborne bookkeeping: touchdown frame and apexes.
            var newlyLanded = false
            if !s.grounded { airborne = true; apex = max(apex, CGFloat(s.paw)) }
            if airborne && s.grounded {
                airborne = false
                newlyLanded = true
                if landing == nil { landing = frame; result.landingFrame = frame }
                result.apexes.append(Double(apex))
                apex = 0
            }
            _ = newPose

            if let sep = s.sep, result.minSep == nil || sep < result.minSep! {
                result.minSep = sep
                result.minSepFrame = frame
                result.minSepPose = s.pose
            }
            if result.topFrame == nil, let x = s.obstacleX, x <= 0 { result.topFrame = frame }
            if let box {
                for (i, shape) in shapes.enumerated() where shape.maxX < box.minX { cleared.insert(i) }
            }

            if pendingHit, result.hitFrame == nil {
                result.outcome = "HIT"
                result.hitFrame = frame
                result.hitPose = s.pose
                if intercepting {
                    if let name = captureHit ?? label {
                        result.shots += await capture(name: name, sample: s, box: box, shapes: shapes, text: hud(s, outcome: "HIT"))
                    }
                    break
                }
            }
            if scene.labGameOver {
                if result.hitFrame == nil { result.outcome = "GAMEOVER"; result.hitFrame = frame; result.hitPose = s.pose }
                break
            }
            if let stopAt, frame >= stopAt {
                let state = result.hitFrame == nil ? "CLEAR" : "HIT"
                result.shots += await capture(name: label ?? c.id, sample: s, box: box, shapes: shapes, text: hud(s, outcome: state))
                break
            }

            inputs(frame: frame, pose: s.pose, newlyLanded: newlyLanded)

            let allCleared = !obstacles.isEmpty && cleared.count == obstacles.count
            let landedAndSettled = landing.map { frame > $0 + 20 } ?? false
            var waitingOnInput = false
            for (i, input) in c.inputs.enumerated() {
                if case .jumpOnEveryLanding(let n) = input {
                    if jumpsOnLanding < n || airborne { waitingOnInput = true }
                } else if !fired.contains(i) {
                    waitingOnInput = true
                }
            }
            if stopAt == nil, allCleared, !airborne || landedAndSettled, !waitingOnInput { break }
            if stopAt == nil, obstacles.isEmpty, c.piece != .cliff, landedAndSettled, !waitingOnInput { break }
            if frame >= (stopAt.map { max($0 + 5, c.maxFrames) } ?? c.maxFrames) { break }
        }
        result.groundEvents = groundLog
        if c.piece == .none || c.piece == .cliff, result.hitFrame == nil { result.outcome = "DONE" }
        return result
    }

    // MARK: Screenshots

    @MainActor
    func capture(name: String, sample: LabSample, box: CGRect?, shapes: [LabShape], text: String) async -> [String] {
        guard let scene, let view = scene.view else { return [] }
        view.isPaused = true
        defer { view.isPaused = false }

        let layer = SKNode()
        layer.zPosition = 900
        scene.addChild(layer)
        defer { layer.removeFromParent() }

        let cyan = SKColor(red: 0, green: 0.9, blue: 1, alpha: 1)
        let magenta = SKColor(red: 1, green: 0.1, blue: 0.85, alpha: 1)
        if let box {
            let node = SKShapeNode(rect: box)
            node.strokeColor = cyan
            node.lineWidth = 1.5
            node.fillColor = cyan.withAlphaComponent(0.12)
            layer.addChild(node)
        }
        for shape in shapes {
            let node: SKShapeNode
            switch shape {
            case .rect(let r): node = SKShapeNode(rect: r)
            case .disc(let c, let r):
                node = SKShapeNode(circleOfRadius: r)
                node.position = c
            }
            node.strokeColor = magenta
            node.lineWidth = 1.5
            node.fillColor = .clear
            layer.addChild(node)

            let line = CGMutablePath()
            line.move(to: CGPoint(x: 0, y: shape.topY))
            line.addLine(to: CGPoint(x: 800, y: shape.topY))
            let dashed = SKShapeNode(path: line.copy(dashingWithPhase: 0, lengths: [6, 4]))
            dashed.strokeColor = magenta.withAlphaComponent(0.8)
            dashed.lineWidth = 1
            layer.addChild(dashed)
        }

        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text
        label.fontSize = 11
        label.fontColor = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 400, y: 418)
        let width = min(790, label.frame.width + 16)
        let plate = SKShapeNode(rect: CGRect(x: 400 - width / 2, y: 408, width: width, height: 20), cornerRadius: 4)
        plate.fillColor = SKColor(white: 0, alpha: 0.72)
        plate.strokeColor = .clear
        layer.addChild(plate)
        layer.addChild(label)

        await Task.yield()

        var files: [String] = []
        let visible = CGRect(x: 0, y: GameScene.Layout.visibleInsetY, width: GameScene.Layout.sceneSize.width,
                             height: GameScene.Layout.sceneSize.height - 2 * GameScene.Layout.visibleInsetY)
        if let data = png(view.texture(from: scene, crop: visible), width: 1600) {
            let file = "\(name)_full.png"
            try? data.write(to: out.appendingPathComponent(file))
            files.append(file)
        }
        let focus: CGPoint
        if let box, let nearest = shapes.min(by: { $0.separation(from: box) < $1.separation(from: box) }) {
            focus = nearest.focus(with: box)
        } else if let box {
            focus = CGPoint(x: box.midX, y: box.minY)
        } else {
            focus = CGPoint(x: GameScene.Layout.dogX, y: GameScene.Layout.dogGroundLine)
        }
        // The HUD is redrawn into the zoom so every picture carries its label.
        label.position = CGPoint(x: focus.x, y: focus.y + 52)
        label.fontSize = 4
        plate.removeFromParent()
        if let data = png(view.texture(from: scene, crop: CGRect(x: focus.x - 100, y: focus.y - 60, width: 200, height: 120)), width: 1600) {
            let file = "\(name)_zoom.png"
            try? data.write(to: out.appendingPathComponent(file))
            files.append(file)
        }
        return files
    }

    private func png(_ texture: SKTexture?, width: CGFloat) -> Data? {
        guard let cg = texture?.cgImage() else { return nil }
        let scale = width / CGFloat(cg.width)
        let size = CGSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.interpolationQuality = scale > 1.5 ? .none : .high
            UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size))
        }
        return image.pngData()
    }
}

extension LabFreeze: Equatable {
    static func == (a: LabFreeze, b: LabFreeze) -> Bool {
        switch (a, b) {
        case (.outcome, .outcome), (.top, .top), (.none, .none): true
        default: false
        }
    }
}

// MARK: - The catalogue (sections J, D and L of the test plan)

extension HitboxLab {
    /// Model-predicted edges at the opening speed, used until plan.json exists:
    /// late edge, master's early edge, the branch's early edge.
    static let predicted: [LabPiece: (late: CGFloat, earlyBefore: CGFloat, earlyAfter: CGFloat)] = [
        .log: (94.23, 139.91, 142.04),
        .logStack: (93.54, 139.16, 141.48),
        .hedge: (94.42, 140.02, 142.40),
        .stump: (94.29, 139.86, 142.55),
        .bush: (94.57, 139.58, 141.65),
    ]

    static func catalogue() -> [LabCase] {
        var cases: [LabCase] = []
        let opening = GameScene.Layout.openingSpeed
        let openTier = Int(opening.rounded())
        let jumpPieces: [(LabPiece, String)] = [(.log, "LOG"), (.logStack, "STACK"), (.hedge, "HEDGE"), (.stump, "STUMP"), (.bush, "BUSH")]

        // J — jump obstacles, every side.
        for (piece, name) in jumpPieces {
            let p = predicted[piece]!
            func make(_ suffix: String, _ d: LabDistance, input: Bool = true, freeze: LabFreeze = .outcome) -> LabCase {
                var c = LabCase(id: "J-\(name)-\(suffix)")
                c.piece = piece
                c.tier = opening
                c.target = "\(piece.rawValue)@\(openTier)"
                c.d = d
                c.inputs = input ? [.at(0, .jump)] : []
                c.freeze = freeze
                return c
            }
            cases.append(make("LF", .fixed(150), input: false))
            cases.append(make("LF-J", .planOffset("lateHit", p.late - 0.5, -15)))
            cases.append(make("LC-H", .plan("lateHit", p.late - 0.5)))
            cases.append(make("LC-M", .plan("lateMiss", p.late + 0.5)))
            cases.append(make("TOP", .plan("centre", (p.late + p.earlyBefore) / 2), freeze: .top))
            cases.append(make("RC-M", .plan("earlyMissBoth", p.earlyBefore - 0.5)))
            cases.append(make("RC-P", .plan("phantom", (p.earlyBefore + p.earlyAfter) / 2)))
            cases.append(make("LC-P", .plan("latePhantom", p.late - 1)))
            cases.append(make("RC-H", .plan("earlyHitAfter", p.earlyAfter + 0.5)))
            cases.append(make("TOP-H", .planOffset("earlyHitAfter", p.earlyAfter + 0.5, 15)))
        }
        for (suffix, key, fallback) in [("T3-LP", "latePhantom", CGFloat(126.0)), ("T3-RC-P", "phantom", CGFloat(187.3))] {
            var c = LabCase(id: "J-STUMP-\(suffix)")
            c.piece = .stump
            c.tier = 335
            c.speed = 335
            c.target = "stump@335"
            c.d = .plan(key, fallback)
            c.inputs = [.at(0, .jump)]
            cases.append(c)
        }

        // D — duck obstacles.
        let duckPieces: [(LabPiece, String, String, CGFloat, CGFloat, CGFloat)] = [
            // piece, name, plan target, slide window low, high, hurdle d
            (.bench, "BENCH", "bench", 120.0, 202.8, 184.5),
            (.occupiedBench, "OCC", "bench", 120.0, 202.8, 184.5),
            (.swingset, "SWING", "swingset", 110.5, 213.2, 195.0),
        ]
        for (piece, name, target, low, high, hurdle) in duckPieces {
            func make(_ suffix: String, _ d: LabDistance, _ inputs: [LabInput], plan: String = "slide") -> LabCase {
                var c = LabCase(id: "D-\(name)-\(suffix)")
                c.piece = piece
                c.target = "\(target)/\(plan)"
                c.d = d
                c.inputs = inputs
                c.maxFrames = 220
                return c
            }
            cases.append(make("1-STAND", .fixed(200), []))
            cases.append(make("2-SL-OK", .plan("centre", (low + high) / 2), [.at(0, .slide)]))
            cases.append(make("3-SL-LATE-M", .plan("lateMiss", low + 0.5), [.at(0, .slide)]))
            cases.append(make("4-SL-LATE-H", .plan("lateHit", low - 0.5), [.at(0, .slide)]))
            cases.append(make("5-SL-EARLY-M", .plan("earlyMiss", high - 0.5), [.at(0, .slide)]))
            cases.append(make("6-SL-EARLY-H", .plan("earlyHit", high + 0.5), [.at(0, .slide)]))
            cases.append(make("7-JUMP-IN", .fixed(170), [.at(0, .jump)]))
            cases.append(make("8-SL-JUMP", .plan("centre", (low + high) / 2), [.at(0, .slide), .at(10, .jump)]))
            var top = make("9-HURDLE-TOP", .plan("d", hurdle), [.at(0, .jump)], plan: "hurdle")
            top.speed = GameScene.Layout.topSpeed
            cases.append(top)
        }

        // L — landing, double jumps and state.
        var audit = LabCase(id: "L-0-RUN")
        audit.freeze = .frames([0]); audit.repeats = 1; audit.maxFrames = 5
        cases.append(audit)
        var auditJump = LabCase(id: "L-0-JUMP")
        auditJump.inputs = [.at(0, .jump)]
        auditJump.freeze = .poses((0..<10).map { "jump_\($0)" })
        auditJump.repeats = 1
        auditJump.maxFrames = 90
        cases.append(auditJump)
        var auditSlide = LabCase(id: "L-0-SLIDE")
        auditSlide.inputs = [.at(0, .slide)]
        auditSlide.freeze = .poses(["slide_\(max(0, GameScene.DogArt.slideFrames.count - 1))"])
        auditSlide.repeats = 1
        auditSlide.maxFrames = 90
        cases.append(auditSlide)

        var landing = LabCase(id: "L-1-LANDING")
        landing.inputs = [.at(0, .jump)]
        landing.freeze = .landing([-1, 0, 1, 2, 4])
        landing.maxFrames = 100
        cases.append(landing)

        var cadence = LabCase(id: "L-2-CADENCE")
        cadence.inputs = [.jumpOnEveryLanding(10)]
        cadence.freeze = .none
        cadence.repeats = 1
        cadence.maxFrames = 700
        cases.append(cadence)

        for f in 1...9 {
            var c = LabCase(id: "L-3-MIDAIR-jump_\(f)")
            c.inputs = [.at(0, .jump), .onPose("jump_\(f)", .jump)]
            c.freeze = .none
            c.repeats = 1
            c.maxFrames = 100
            cases.append(c)
        }
        for o in [0, 1] {
            var j = LabCase(id: "L-4-JUMP-ON-T+\(o)")
            j.inputs = [.at(0, .jump), .onLanding(o, .jump)]
            j.freeze = .none
            j.repeats = 2
            j.maxFrames = 160
            cases.append(j)
            var s = LabCase(id: "L-5-SLIDE-ON-T+\(o)")
            s.inputs = [.at(0, .jump), .onLanding(o, .slide)]
            s.freeze = .poses(["slide_\(max(0, GameScene.DogArt.slideFrames.count - 1))"])
            s.repeats = 1
            s.maxFrames = 160
            cases.append(s)
        }
        var outOfSlide = LabCase(id: "L-6-JUMP-OUT-OF-SLIDE")
        outOfSlide.inputs = [.at(0, .slide), .at(10, .jump)]
        outOfSlide.freeze = .poses(["jump_5"])
        outOfSlide.repeats = 1
        outOfSlide.maxFrames = 100
        cases.append(outOfSlide)

        var retry = LabCase(id: "L-7-CRASH-RETRY")
        retry.piece = .none
        retry.target = "log@\(openTier)"
        retry.d = .plan("earlyHitAfter", predicted[.log]!.earlyAfter + 0.5)
        retry.crashThenRetry = true
        retry.inputs = []
        retry.freeze = .frames([0])
        retry.repeats = 1
        cases.append(retry)
        var retryJump = retry
        retryJump.id = "L-7-CRASH-RETRY-JUMP"
        retryJump.crashThenRetry = true
        retryJump.inputs = [.at(0, .jump)]
        retryJump.freeze = .poses(["jump_5"])
        retryJump.maxFrames = 90
        cases.append(retryJump)

        let airtimeDistance = opening * 0.924
        for (suffix, d, jump, freeze) in [
            ("JUMP", airtimeDistance / 2, true, LabFreeze.landing([0, 1])),
            ("NOJUMP", CGFloat(40), false, LabFreeze.none),
            ("EARLY", airtimeDistance, true, LabFreeze.none),
        ] {
            var c = LabCase(id: "L-8-CLIFF-\(suffix)")
            c.piece = .cliff
            c.d = .fixed(d)
            c.inputs = jump ? [.at(0, .jump)] : []
            c.intercept = false
            c.freeze = freeze
            c.repeats = 1
            c.maxFrames = 120
            cases.append(c)
        }

        var pair = LabCase(id: "L-9-PAIR")
        pair.piece = .bench
        pair.follower = .log
        pair.target = "bench/slide"
        pair.d = .plan("centre", 161.4)
        pair.inputs = [.at(0, .slide), .whenCleared(0, .jump)]
        pair.maxFrames = 300
        cases.append(pair)

        return cases
    }
}
#endif
