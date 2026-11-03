#!/usr/bin/env swift
//
//  CutDogFrames.swift
//  Benny's Great Escape
//
//  Cuts Benny's three phase-one animations — the gallop, the jump arc and the
//  slide — out of the sheets in this directory, and writes them straight into
//  the asset catalogue.
//
//      swift Art/CutDogFrames.swift
//
//  Run from the repository root. Rerunning overwrites the assets in place.
//
//  Four things make this more than a copy.
//
//  **The run frames arrive on solid black.** Unlike the jump and the slide they
//  carry no alpha at all, so they have to be keyed — and the key has to be a
//  flood inwards from the canvas edges rather than a brightness threshold.
//  Benny's own ink is as dark as the background he is sitting on: measured on
//  the first frame, better than six thousand pixels of it are *enclosed* by his
//  silhouette, and a threshold punches every one of them into a hole. A flood
//  only ever reaches the background, because the ink it would eat is walled off
//  behind his outline.
//
//  **A flood cannot reach everything, either.** In four of the ten run frames
//  the hind legs close around the gap between them, and the background trapped
//  in there is left behind as a solid black wedge — 8,640px at its worst, a
//  fifth of Benny's length. Nothing about the pixels themselves distinguishes
//  that from his eye, so `clearEnclosedBackground` asks the atlas copy of the
//  same frame, which ships a real alpha channel. The atlas is far too small to
//  draw from, which is why the frames come from the loose files, but it answers
//  a yes-or-no question about one pocket at a time perfectly well.
//
//  **All three animations have to share one canvas.** The game gives Benny a
//  single size and a single `groundLineFraction`, so if the gallop and the slide
//  were trimmed to different canvases they would disagree about where the floor
//  is and he would hop between them. Every frame here is placed on one canvas
//  measured across all twenty-eight.
//
//  **The slide needs pinning and the other two do not.** The paw line is allowed
//  to move during a gallop — that is the legs working — and during a jump, where
//  it is the whole point. But the slide's drawn ground contact climbs steadily
//  as he goes down, which on screen is Benny floating upward while he ducks. The
//  frames that ship today hold it to nothing. So the slide is registered on its
//  own ground line and the guard at the end refuses to install if that failed.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tuning

/// How opaque a pixel has to be to count as drawn.
private let drawn: UInt8 = 40

/// How dark a pixel has to be for the flood to treat it as the run sheet's
/// background. Measured: the background is pure black with a dusting of 1-level
/// noise, and nothing else in the frame comes close.
private let blackCeiling = 24

/// How far apart the slide's paw lines may sit after registration, in pixels,
/// before this refuses to install. The art that ships today holds them to zero.
private let slideTolerance = 2

/// How big a pocket of unreachable background has to be before it is worth
/// asking the atlas about. Below this it is a speck no one can see at 100pt and
/// the vote has too few pixels to be worth trusting.
private let smallestPocket = 300

/// How much of a pocket the atlas has to call transparent for it to count as
/// background rather than ink. Measured across the ten frames: every pocket
/// scores 56% or more and every piece of real ink scores 0%, so this sits in the
/// middle of a gap with nothing in it.
private let pocketVote = 0.25

// MARK: - Bitmap

private struct Bitmap {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }
    func isDrawn(_ x: Int, _ y: Int) -> Bool { pixels[offset(x, y) + 3] > drawn }
}

private func load(_ path: String) -> Bitmap {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("can't read \(path) — run this from the repository root")
    }
    var bitmap = Bitmap(width: image.width, height: image.height)
    bitmap.pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bitmap
}

private func write(_ bitmap: Bitmap, to path: String) {
    var pixels = bitmap.pixels
    let image: CGImage = pixels.withUnsafeMutableBytes { buffer in
        CGContext(
            data: buffer.baseAddress, width: bitmap.width, height: bitmap.height,
            bitsPerComponent: 8, bytesPerRow: bitmap.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!.makeImage()!
    }
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("can't write \(path)") }
}

private func install(_ frame: Bitmap, named name: String) {
    let directory = "BennysGreatEscape/Assets.xcassets/\(name).imageset"
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    write(frame, to: "\(directory)/\(name).png")
    try! """
    {
      "images" : [
        {
          "filename" : "\(name).png",
          "idiom" : "universal"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """.write(toFile: "\(directory)/Contents.json", atomically: true, encoding: .utf8)
}

// MARK: - Keying

/// Clears the run sheet's black background, flooding inward from the edges.
///
/// See the header for why this is a flood and not a threshold. Everything the
/// flood cannot reach stays, which is exactly the rule that keeps the ink inside
/// Benny's outline while taking the identical black outside it.
private func clearBlack(_ sheet: inout Bitmap) -> Int {
    func isBackground(_ x: Int, _ y: Int) -> Bool {
        let o = sheet.offset(x, y)
        return Int(sheet.pixels[o]) + Int(sheet.pixels[o + 1]) + Int(sheet.pixels[o + 2]) <= blackCeiling
    }
    var seen = [Bool](repeating: false, count: sheet.width * sheet.height)
    var stack: [Int] = []
    for x in 0..<sheet.width {
        for y in [0, sheet.height - 1] where isBackground(x, y) && !seen[y * sheet.width + x] {
            seen[y * sheet.width + x] = true
            stack.append(y * sheet.width + x)
        }
    }
    for y in 0..<sheet.height {
        for x in [0, sheet.width - 1] where isBackground(x, y) && !seen[y * sheet.width + x] {
            seen[y * sheet.width + x] = true
            stack.append(y * sheet.width + x)
        }
    }
    var cleared = 0
    while let pixel = stack.popLast() {
        let px = pixel % sheet.width, py = pixel / sheet.width
        sheet.pixels[sheet.offset(px, py) + 3] = 0
        cleared += 1
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let nx = px + dx, ny = py + dy
            guard nx >= 0, nx < sheet.width, ny >= 0, ny < sheet.height else { continue }
            let next = ny * sheet.width + nx
            guard !seen[next], isBackground(nx, ny) else { continue }
            seen[next] = true
            stack.append(next)
        }
    }
    return cleared
}

/// Clears the pockets of background that the edge flood cannot reach.
///
/// The gap between Benny's hind legs is background like any other, but in four
/// of the ten run frames the legs close around it and the flood, coming in from
/// the canvas edges, never gets there. What it leaves is a solid black wedge up
/// to 8,640px across — on screen, a fifth of his length painted black.
///
/// **They cannot be told from his own ink by colour or by size.** Both are the
/// same near-black; the biggest pocket is 8,640px and his eye is 800, but a
/// pocket in frame eight is 1,397px and the muzzle in frame one is 805, so the
/// ranges overlap and neither measure decides it.
///
/// What does decide it is the atlas copy of the same frame, which ships a real
/// alpha channel with the gap already transparent. It is far too small to draw
/// from — 305px of dog against the loose file's 1,008, which is why the frames
/// themselves come from the loose files — but here it is only being asked a yes
/// or no question, one pocket at a time, deep inside the silhouette where a few
/// pixels of registration error cost nothing. The two crops agree to within
/// 0.3% of aspect on all ten frames, so the drawn bounding box of each maps one
/// onto the other.
private func clearEnclosedBackground(_ sheet: inout Bitmap, against alphaPath: String) -> Int {
    func isBackground(_ x: Int, _ y: Int) -> Bool {
        let o = sheet.offset(x, y)
        return Int(sheet.pixels[o]) + Int(sheet.pixels[o + 1]) + Int(sheet.pixels[o + 2])
            <= blackCeiling
    }
    // What the flood already took is transparent, so anything still opaque and
    // still background-coloured is by definition a pocket it couldn't reach.
    func enclosed(_ x: Int, _ y: Int) -> Bool {
        sheet.pixels[sheet.offset(x, y) + 3] > 0 && isBackground(x, y)
    }

    let reference = load(alphaPath)
    var alphaBox = Box(left: reference.width, right: -1, top: reference.height, bottom: -1)
    for y in 0..<reference.height {
        for x in 0..<reference.width where reference.isDrawn(x, y) {
            alphaBox.left = min(alphaBox.left, x); alphaBox.right = max(alphaBox.right, x)
            alphaBox.top = min(alphaBox.top, y); alphaBox.bottom = max(alphaBox.bottom, y)
        }
    }
    // The drawing itself, which is every pixel the background test rejects —
    // pockets included, and they are interior, so they don't move the bounds.
    var here = Box(left: sheet.width, right: -1, top: sheet.height, bottom: -1)
    for y in 0..<sheet.height {
        for x in 0..<sheet.width where !isBackground(x, y) {
            here.left = min(here.left, x); here.right = max(here.right, x)
            here.top = min(here.top, y); here.bottom = max(here.bottom, y)
        }
    }
    guard here.width > 0, alphaBox.width > 0 else {
        fatalError("\(alphaPath): nothing drawn in one of the two crops to line them up by.")
    }
    let scaleX = Double(alphaBox.width) / Double(here.width)
    let scaleY = Double(alphaBox.height) / Double(here.height)

    var seen = [Bool](repeating: false, count: sheet.width * sheet.height)
    var cleared = 0
    for startY in 0..<sheet.height {
        for startX in 0..<sheet.width where enclosed(startX, startY)
            && !seen[startY * sheet.width + startX] {
            var stack = [startY * sheet.width + startX]
            seen[startY * sheet.width + startX] = true
            var pocket: [Int] = []
            while let pixel = stack.popLast() {
                pocket.append(pixel)
                let px = pixel % sheet.width, py = pixel / sheet.width
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = px + dx, ny = py + dy
                    guard nx >= 0, nx < sheet.width, ny >= 0, ny < sheet.height else { continue }
                    let next = ny * sheet.width + nx
                    guard !seen[next], enclosed(nx, ny) else { continue }
                    seen[next] = true
                    stack.append(next)
                }
            }
            guard pocket.count >= smallestPocket else { continue }

            var transparent = 0
            for pixel in pocket {
                let px = pixel % sheet.width, py = pixel / sheet.width
                let ax = alphaBox.left + Int(Double(px - here.left) * scaleX)
                let ay = alphaBox.top + Int(Double(py - here.top) * scaleY)
                guard ax >= 0, ax < reference.width, ay >= 0, ay < reference.height else { continue }
                if !reference.isDrawn(ax, ay) { transparent += 1 }
            }
            guard Double(transparent) / Double(pocket.count) >= pocketVote else { continue }
            for pixel in pocket {
                sheet.pixels[(pixel * 4) + 3] = 0
            }
            cleared += pocket.count
        }
    }
    return cleared
}

// MARK: - Measuring

private struct Box {
    var left: Int, right: Int, top: Int, bottom: Int
    var width: Int { right - left + 1 }
    var height: Int { bottom - top + 1 }
}

private func drawnBox(_ sheet: Bitmap) -> Box {
    var box = Box(left: sheet.width, right: -1, top: sheet.height, bottom: -1)
    for y in 0..<sheet.height {
        for x in 0..<sheet.width where sheet.isDrawn(x, y) {
            box.left = min(box.left, x); box.right = max(box.right, x)
            box.top = min(box.top, y); box.bottom = max(box.bottom, y)
        }
    }
    return box
}

/// Where a run of drawn pixels actually meets the floor.
///
/// The lowest drawn row alone is too eager: a single trailing hair or a stray
/// pixel of anti-aliasing sits a long way below the paw and would drag the
/// measurement with it. A row has to carry a real run of the drawing to count.
private func pawLine(_ sheet: Bitmap, minimumRun: Int = 6) -> Int {
    for y in (0..<sheet.height).reversed() {
        var run = 0
        for x in 0..<sheet.width where sheet.isDrawn(x, y) { run += 1 }
        if run >= minimumRun { return y }
    }
    return sheet.height - 1
}

// MARK: - Cutting

print("Benny's phase-one animations")

private struct Clip {
    let folder: String, asset: String, count: Int, keyBlack: Bool, pinPaws: Bool
    /// The atlas copies of the same frames, which carry a real alpha channel and
    /// are consulted only about enclosed pockets. Only the keyed clip needs one:
    /// the jump and slide sheets arrive with their own alpha and have no pockets
    /// to resolve.
    var alphaFolder: String? = nil
}

private let clips = [
    Clip(folder: "benny_run_source", asset: "benny_run", count: 10,
         keyBlack: true, pinPaws: false, alphaFolder: "benny_run_alpha"),
    Clip(folder: "benny_jump_source", asset: "benny_jump", count: 10,
         keyBlack: false, pinPaws: false),
    Clip(folder: "benny_slide_source", asset: "benny_slide", count: 8,
         keyBlack: false, pinPaws: true),
]

private var loaded: [(clip: Clip, index: Int, sheet: Bitmap, box: Box, paws: Int)] = []

for clip in clips {
    print("  \(clip.asset)")
    var keyed = 0
    var pockets: [(frame: Int, pixels: Int)] = []
    for index in 1...clip.count {
        let name = clip.asset.replacingOccurrences(of: "benny_", with: "Benny_")
        var sheet = load("Art/\(clip.folder)/\(name)_\(index).png")
        if clip.keyBlack { keyed += clearBlack(&sheet) }
        if let alpha = clip.alphaFolder {
            let got = clearEnclosedBackground(&sheet, against: "Art/\(alpha)/\(name)_\(index).png")
            if got > 0 { pockets.append((index, got)) }
        }
        let box = drawnBox(sheet)
        loaded.append((clip, index, sheet, box, pawLine(sheet)))
    }
    if clip.keyBlack {
        print("    keyed \(keyed) background pixels off the black")
        if pockets.isEmpty {
            print("    no pockets the flood couldn't reach")
        } else {
            let where_ = pockets.map { "frame \($0.frame): \($0.pixels)px" }.joined(separator: ", ")
            print("    cleared \(pockets.reduce(0) { $0 + $1.pixels })px of enclosed background"
                + " the flood couldn't reach — \(where_)")
        }
    }
}

/// One canvas for all twenty-eight frames.
///
/// Across every clip, not per clip: the game gives Benny one size and one ground
/// line, so the gallop and the slide have to agree about where the floor is or he
/// hops as one hands over to the other.
///
/// Within a clip the frames keep the positions they were drawn in. That is the
/// animation — a paw leaving the floor during a gallop, the body dropping into a
/// crouch before a jump — and re-pinning every frame to a common paw line
/// flattens all of it. So an unpinned clip is moved as a whole: one offset for
/// all its frames, taken from its deepest paw line, which is the pose actually
/// standing on the ground.
///
/// The slide is the exception and is pinned frame by frame. Its drawn ground
/// contact climbs steadily as he goes down, which is not animation — it is Benny
/// floating upward while he ducks.
private func reference(_ frames: [(clip: Clip, index: Int, sheet: Bitmap, box: Box, paws: Int)])
    -> (dx: Int, dy: Int) {
    // Horizontally, the middle of the drawing averaged over the clip; vertically,
    // the lowest paw line it reaches.
    let centres = frames.map { ($0.box.left + $0.box.right) / 2 }
    return (centres.reduce(0, +) / centres.count, frames.map(\.paws).max()!)
}

private var placed: [(clip: Clip, index: Int, sheet: Bitmap, box: Box, dx: Int, dy: Int)] = []
for clip in clips {
    let mine = loaded.filter { $0.clip.asset == clip.asset }
    let ref = reference(mine)
    for frame in mine {
        // Pinned clips hang each frame from its own paw line; the rest move as
        // one, so whatever the drawing does between frames survives.
        let dy = clip.pinPaws ? -frame.paws : -ref.dy
        placed.append((clip, frame.index, frame.sheet, frame.box, -ref.dx, dy))
    }
}

// The canvas is the union of everything once placed, measured rather than
// assumed — the jump reaches highest and the slide widest, and neither is
// knowable before the offsets are worked out.
private let left = placed.map { $0.box.left + $0.dx }.min()!
private let right = placed.map { $0.box.right + $0.dx }.max()!
private let top = placed.map { $0.box.top + $0.dy }.min()!
private let bottom = placed.map { $0.box.bottom + $0.dy }.max()!
private let canvas = (width: right - left + 1, height: bottom - top + 1)
private let pawRow = -top
print("  canvas \(canvas.width)x\(canvas.height), the ground line on row \(pawRow)")

private var landed: [String: [Int]] = [:]

/// The part of the canvas that is Benny in *every* frame of a clip — the torso
/// and head — which is what the physics box is measured off. See
/// `DogArt.bodyWidthFraction` for why it is the intersection and not the
/// envelope: the legs sweep through a far larger area than the dog occupies at
/// any one moment, and a box drawn round the envelope ends runs on air.
private var everywhere: [String: [Bool]] = [:]

for frame in placed {
    var out = Bitmap(width: canvas.width, height: canvas.height)
    for y in frame.box.top...frame.box.bottom {
        for x in frame.box.left...frame.box.right {
            let tx = x + frame.dx - left, ty = y + frame.dy - top
            guard tx >= 0, tx < canvas.width, ty >= 0, ty < canvas.height else { continue }
            let from = frame.sheet.offset(x, y), to = out.offset(tx, ty)
            for channel in 0..<4 { out.pixels[to + channel] = frame.sheet.pixels[from + channel] }
        }
    }
    install(out, named: "\(frame.clip.asset)_\(frame.index - 1)")
    landed[frame.clip.asset, default: []].append(pawLine(out))

    var mask = everywhere[frame.clip.asset]
        ?? [Bool](repeating: true, count: canvas.width * canvas.height)
    for y in 0..<canvas.height {
        for x in 0..<canvas.width where !out.isDrawn(x, y) { mask[y * canvas.width + x] = false }
    }
    everywhere[frame.clip.asset] = mask
}

// The guard. Everything above is arithmetic that looks right whether or not it
// is, and a frame out of line is invisible until Benny is on screen hopping.
print("  paw lines after registration:")
for clip in clips {
    let rows = landed[clip.asset] ?? []
    let spread = (rows.max() ?? 0) - (rows.min() ?? 0)
    print("    \(clip.asset): \(rows.map(String.init).joined(separator: " "))  spread \(spread)px")
    if clip.pinPaws, spread > slideTolerance {
        fatalError("\(clip.asset) didn't pin — paw lines \(spread)px apart."
            + " Benny would float as he ducks.")
    }
}

// MARK: - The physics box

private func ratio(_ v: Int, of total: Int) -> String { String(format: "%.3f", Double(v) / Double(total)) }
private func ratio(_ v: Double, of total: Int) -> String { String(format: "%.3f", v / Double(total)) }

/// The three fractions that make one pose's physics box, read off the mask of
/// what is Benny in every frame of that clip.
///
/// The height is taken **from the paw line upward**, not from the drawn shape's
/// own bottom, because that is what `makeDogPhysics` does with it: the box's
/// bottom is pinned to the paw line and only its height is free. The torso does
/// not reach the floor, so some of this box is the empty air under his chest —
/// unavoidable while the bottom is pinned, and the same compromise the numbers
/// it replaces were carrying.
private func physicsBox(_ asset: String) -> (width: String, height: String, offsetX: String) {
    let mask = everywhere[asset]!
    var box = Box(left: canvas.width, right: -1, top: canvas.height, bottom: -1)
    var area = 0
    for y in 0..<canvas.height {
        for x in 0..<canvas.width where mask[y * canvas.width + x] {
            area += 1
            box.left = min(box.left, x); box.right = max(box.right, x)
            box.top = min(box.top, y); box.bottom = max(box.bottom, y)
        }
    }
    // A guard, because an intersection is the one measurement here that can come
    // back empty — one frame drawn a few pixels off its fellows and there is no
    // pixel that is dog in all of them, and the printed fractions would be
    // nonsense that still reads like numbers.
    guard area > canvas.width * canvas.height / 100 else {
        fatalError("\(asset): only \(area)px is Benny in every frame."
            + " The frames don't overlap enough to measure a body box from.")
    }
    let width = box.right - box.left + 1
    let centre = Double(box.left + box.right) / 2 - Double(canvas.width - 1) / 2
    print("    \(asset): \(width)x\(pawRow - box.top) box, \(area)px of it dog in all"
        + " \(landed[asset]!.count) poses")
    return (ratio(width, of: canvas.width),
            ratio(pawRow - box.top, of: canvas.height),
            ratio(centre, of: canvas.width))
}

print("  physics boxes:")
private let body = physicsBox("benny_run")
private let duck = physicsBox("benny_slide")
print("""

paste into DogArt:

    static let bodyWidthFraction: CGFloat = \(body.width)
    static let bodyHeightFraction: CGFloat = \(body.height)
    static let bodyOffsetXFraction: CGFloat = \(body.offsetX)

    static let groundLineFraction: CGFloat = \(ratio(canvas.height - 1 - pawRow, of: canvas.height))

    static let slideWidthFraction: CGFloat = \(duck.width)
    static let slideHeightFraction: CGFloat = \(duck.height)
    static let slideOffsetXFraction: CGFloat = \(duck.offsetX)

`aspect` is read off the texture at runtime, so it follows the canvas with
nothing to paste: \(canvas.width)/\(canvas.height) = \(String(format: "%.3f", Double(canvas.width) / Double(canvas.height))), against 1.097 before.
""")
