#!/usr/bin/env swift
//
//  CutDogs.swift
//  Benny's Great Escape
//
//  Cuts the two dogs who sit on the second bench of a run out of their sheet,
//  and prints the numbers `ObstacleArt.occupiedBench` hangs them by.
//
//      swift Art/CutDogs.swift
//
//  Run from the repository root. It reads `dogs_source.png` here and writes the
//  catalogue, so rerunning it is idempotent — the source is never the thing
//  being edited.
//
//  **This script replaces one that cut a whole bench**, and the reason is worth
//  keeping, because it is the difference between the two rounds of this.
//
//  The first sheet drew the dogs *already sitting on a bench*. That forced two
//  things it could not deliver. It made the bench part of the animation, so the
//  five drawings had to agree about the bench to the pixel or the prop juddered
//  — and being five independent generations, they didn't. And it made the
//  occupied bench a second, differently-proportioned bench that had to be
//  wrestled back to the length of the real one, first by splicing and then, when
//  there turned out to be no band of bench to splice that wasn't under a dog, by
//  drawing its legs 42% longer.
//
//  This sheet draws the dogs alone, so none of that arises. The bench is no
//  longer redrawn at all: `occupiedBench` uses `bench`'s own texture and hangs
//  these over it, which makes the two benches the same size because they are the
//  same bench. The only thing that can move between poses is a dog.
//
//  **It also cannot repeat the bug that sent the first one back.** That sheet
//  arrived on a flat cream field, and the black dog's white chest is painted in
//  the same cream — `(250,243,231)` of fur against `(249,244,229)` of field, a
//  distance of two. Keying the background by colour therefore keyed his chest,
//  blaze, muzzle and paws as well: ten thousand pixels a frame of dog with the
//  scrolling grass showing through them, which read in game as a green-chested
//  dog churning. No colour test separates those two creams; nothing but the
//  drawing's own alpha does. So this script does not key at all — it *requires*
//  an alpha channel and stops if one is missing, which is the only reliable way
//  to be told that a future sheet has gone back to a painted background.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tuning

/// The smallest drawn region that is a whole dog. They run about 60,000 pixels
/// each and the largest thing that isn't one is a caption glyph at 190, so this
/// only has to land somewhere in between.
private let smallestFigure = 20_000

/// How opaque a pixel has to be before this script will *measure* it.
///
/// Only the measuring — where a figure ends, how tall it is, which row the seat
/// starts at. Nothing is thrown away on the strength of it: the pixels below it
/// are the anti-aliased rim, and cutting those would trade a faint halo for a
/// hard jagged edge, which is the worse of the two by far.
///
/// Higher than the 8 the other scripts use because this sheet has a thin warm
/// matte around each figure, and a bounding box that includes it is a dog
/// measured a few pixels too big in every direction.
private let solidEnough = 40

/// How much of a dog's height its poses may differ by before something is wrong
/// with the sheet rather than with the dog. The five poses of each come in
/// within 1.4%, so this is loose; it is here to catch a sheet that isn't five
/// poses of the same animal.
private let poseTolerance = 0.06

/// Where the dogs sit and how big they are, as fractions of the bench drawing —
/// x from its centre, height of its height.
///
/// Not measured off anything, because there is nothing to measure: the dogs and
/// the bench were drawn apart and how they meet is a composition rather than a
/// fact. These are read off the version already seen and approved, and the
/// preview is what confirms them. Both heights are over 1 because a sitting dog
/// is taller than the bench it sits on.
private let blackDogX = -0.17
private let blackDogHeight = 0.91
private let goldenX = 0.14
private let goldenHeight = 1.08

/// How much of the sheet's own height each dog is allowed to keep above its
/// feet, so that both dogs' canvases crop to their drawings and nothing else.
private let canvasPadding = 8

/// How far forward on the seat the dogs sit: 0 at its back edge, 1 at its front
/// lip.
///
/// The bench is drawn in perspective and its seat is 85 rows deep, so this is
/// the whole difference between a dog sitting on a bench and a dog standing
/// behind one. The first version of this script had no such number — it stood
/// them on "the top of the seat", which is a real edge and the wrong one: the
/// *far* one. Both dogs hovered, with the entire seat surface showing beneath
/// their paws.
///
/// Near the front, because that is where a dog sits. Far enough back that the
/// paws are on the front slat rather than over the lip, which at 1.0 looked
/// like two dogs perching on the edge about to get down.
private let seatDepth = 0.88

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

    func alpha(_ x: Int, _ y: Int) -> Int { Int(pixels[offset(x, y) + 3]) }

    func isDrawn(_ x: Int, _ y: Int) -> Bool { alpha(x, y) >= solidEnough }

    func cropped(x: Int, y: Int, width w: Int, height h: Int) -> Bitmap {
        var out = Bitmap(width: w, height: h)
        for row in 0..<h {
            let sy = y + row
            guard sy >= 0, sy < height else { continue }
            for col in 0..<w {
                let sx = x + col
                guard sx >= 0, sx < width else { continue }
                let from = offset(sx, sy), to = out.offset(col, row)
                for channel in 0..<4 { out.pixels[to + channel] = pixels[from + channel] }
            }
        }
        return out
    }

    /// Composites this over `canvas` at `x`, `y`. Both sides are premultiplied,
    /// which is what makes this the plain `over` operator.
    func draw(into canvas: inout Bitmap, x: Int, y: Int) {
        for row in 0..<height {
            let ty = y + row
            guard ty >= 0, ty < canvas.height else { continue }
            for column in 0..<width {
                let tx = x + column
                guard tx >= 0, tx < canvas.width else { continue }
                let from = offset(column, row), to = canvas.offset(tx, ty)
                let alpha = Double(pixels[from + 3]) / 255
                guard alpha > 0 else { continue }
                for channel in 0..<4 {
                    let over = Double(pixels[from + channel])
                    let under = Double(canvas.pixels[to + channel])
                    canvas.pixels[to + channel] = UInt8(min(255, (over + under * (1 - alpha)).rounded()))
                }
            }
        }
    }

    func scaled(toWidth w: Int, height h: Int) -> Bitmap {
        guard w != width || h != height else { return self }
        var out = Bitmap(width: w, height: h)
        let source = cgImage()
        out.pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return out
    }

    func cgImage() -> CGImage {
        var copy = pixels
        return copy.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!.makeImage()!
        }
    }

    /// The rectangle actually drawn on.
    var drawn: (left: Int, right: Int, top: Int, bottom: Int) {
        var left = width, right = -1, top = height, bottom = -1
        for y in 0..<height {
            for x in 0..<width where isDrawn(x, y) {
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard right >= 0 else { fatalError("nothing drawn") }
        return (left, right, top, bottom)
    }
}

private func load(_ path: String) -> (bitmap: Bitmap, hadAlpha: Bool) {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("can't read \(path) — run this from the repository root")
    }
    let hadAlpha: Bool
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast: hadAlpha = false
    default: hadAlpha = true
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
    return (bitmap, hadAlpha)
}

private func write(_ bitmap: Bitmap, to path: String) {
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, bitmap.cgImage(), nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("can't write \(path)") }
}

private func install(_ bitmap: Bitmap, named name: String) {
    let directory = "BennysGreatEscape/Assets.xcassets/\(name).imageset"
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    write(bitmap, to: "\(directory)/\(name).png")
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

// MARK: - Regions

private struct Region {
    var size: Int
    var left: Int, right: Int, top: Int, bottom: Int
    var width: Int { right - left + 1 }
    var height: Int { bottom - top + 1 }
    var centreX: Int { (left + right) / 2 }
    var centreY: Int { (top + bottom) / 2 }
}

/// Every four-connected run of drawn pixels.
private func regions(of sheet: Bitmap) -> [Region] {
    let count = sheet.width * sheet.height
    var mask = [Bool](repeating: false, count: count)
    for y in 0..<sheet.height {
        for x in 0..<sheet.width where sheet.isDrawn(x, y) { mask[y * sheet.width + x] = true }
    }
    var visited = [Bool](repeating: false, count: count)
    var found: [Region] = []
    for seed in 0..<count where mask[seed] && !visited[seed] {
        var stack = [seed]
        visited[seed] = true
        var size = 0
        var left = sheet.width, right = -1, top = sheet.height, bottom = -1
        while let pixel = stack.popLast() {
            size += 1
            let x = pixel % sheet.width, y = pixel / sheet.width
            left = min(left, x); right = max(right, x)
            top = min(top, y); bottom = max(bottom, y)
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < sheet.width, ny >= 0, ny < sheet.height else { continue }
                let next = ny * sheet.width + nx
                guard mask[next], !visited[next] else { continue }
                visited[next] = true
                stack.append(next)
            }
        }
        found.append(Region(size: size, left: left, right: right, top: top, bottom: bottom))
    }
    return found
}

// MARK: - Lining the poses up

/// Crops one dog's five poses onto a shared canvas, each scaled to the first
/// one's height and standing on the same spot.
///
/// Two landmarks, and they are the two a breath can't move: how tall the dog is
/// and where his feet are. Height rather than width because width is what
/// changes when he leans; feet because they are what he is standing on, and a
/// dog whose feet wander is a dog sliding about on the seat.
///
/// Each dog is lined up against himself alone. That is the whole gain from art
/// drawn as separate figures: nothing either of them does can disturb the other,
/// and neither of them can disturb the bench, because the bench isn't here.
private func register(_ poses: [Bitmap], named name: String) -> [Bitmap] {
    let boxes = poses.map(\.drawn)
    let reference = boxes[0]
    let referenceHeight = reference.bottom - reference.top + 1

    var scaled: [Bitmap] = []
    for (index, pose) in poses.enumerated() {
        let box = boxes[index]
        let height = box.bottom - box.top + 1
        let ratio = Double(referenceHeight) / Double(height)
        if abs(ratio - 1) > poseTolerance {
            fatalError("\(name) pose \(index) is \(Int((1 / ratio - 1) * 100))% off the first one's"
                + " height — that isn't a breath, check the sheet")
        }
        let cut = pose.cropped(x: box.left, y: box.top, width: box.right - box.left + 1, height: height)
        scaled.append(cut.scaled(toWidth: Int((Double(cut.width) * ratio).rounded()),
                                 height: referenceHeight))
        print(String(format: "    %@ pose %d: %dx%d drawn, scaled x%.3f", name, index,
                     cut.width, cut.height, ratio))
    }

    // One canvas for all five: wide enough for the widest, tall enough for the
    // common height, with every dog centred on it and standing on the floor.
    let width = scaled.map(\.width).max()! + canvasPadding * 2
    let height = referenceHeight + canvasPadding
    return scaled.map { pose in
        var canvas = Bitmap(width: width, height: height)
        pose.draw(into: &canvas, x: (width - pose.width) / 2, y: height - pose.height)
        return canvas
    }
}

// MARK: - Reading the bench

/// The line on the bench the dogs stand on, and the two edges it sits between.
///
/// The seat is not a line, which is the thing that had to be learned here. It is
/// drawn as a stack of planks seen slightly from above, so on the page it is a
/// band about a sixth of the drawing deep, receding away from the viewer. Both
/// of its edges are real and they are 85 rows apart:
///
/// * the **back** is the top of the solid band, found by walking up from the
///   seat's underside for as long as the middle of the drawing stays covered —
///   the first uncovered row is the gap under the backrest;
/// * the **front** is the widest row in that band. The seat overhangs
///   everything else on the bench, so its lip is the widest part of the whole
///   drawing, which makes it a landmark rather than a guess. Measured here it
///   runs 1086 pixels across at the back and 1267 at the front.
///
/// `seatDepth` chooses between them, and that is the only free number in it —
/// where a dog's paws rest on a bench drawn in perspective is a composition,
/// not a measurement. Both edges come off the art, so a re-cut bench still
/// carries its passengers.
private func seatLine(of bench: Bitmap) -> (fraction: Double, row: Int, back: Int, front: Int) {
    let inset = Int(Double(bench.width) * 0.25)
    let from = inset, to = bench.width - 1 - inset

    var back = bench.height - 1
    while back > 0 {
        var painted = false
        for x in from...to where bench.isDrawn(x, back) { painted = true; break }
        if painted { break }
        back -= 1
    }
    let underside = back
    while back > 0 {
        var covered = 0
        for x in from...to where bench.isDrawn(x, back - 1) { covered += 1 }
        if Double(covered) / Double(to - from + 1) < 0.9 { break }
        back -= 1
    }

    var front = back, widest = -1
    for row in back...underside {
        var left = bench.width, right = -1
        for x in 0..<bench.width where bench.isDrawn(x, row) {
            left = min(left, x); right = max(right, x)
        }
        guard right >= left, right - left > widest else { continue }
        widest = right - left
        front = row
    }

    let row = back + Int((Double(front - back) * seatDepth).rounded())
    return (Double(bench.height - row) / Double(bench.height), row, back, front)
}

// MARK: - The check

/// The bench with both dogs on it, one cell per pose, and all the poses
/// averaged into a last one.
///
/// The average is the point of it, and it asks a sharper question than it used
/// to. The bench is the *same pixels* in every cell — it is not being animated
/// any more — so it has to come out of the average perfectly sharp. Any softness
/// in it at all is this script compositing wrongly, not the art disagreeing with
/// itself. Only the dogs may blur.
private func preview(bench: Bitmap, black: [Bitmap], golden: [Bitmap],
                     footRow: Int, to path: String) {
    func cell(_ pose: Int) -> Bitmap {
        let blackHeight = Int(Double(bench.height) * blackDogHeight)
        let goldenHeight = Int(Double(bench.height) * goldenHeight)
        let b = black[pose].scaled(
            toWidth: Int((Double(black[pose].width) * Double(blackHeight) / Double(black[pose].height)).rounded()),
            height: blackHeight)
        let g = golden[pose].scaled(
            toWidth: Int((Double(golden[pose].width) * Double(goldenHeight) / Double(golden[pose].height)).rounded()),
            height: goldenHeight)

        // The canvas reaches as far above the bench as the taller dog does.
        // `footRow` is a row from the top of the bench drawing, so it is also
        // how much headroom the drawing already has over the dogs' feet.
        let lift = max(b.height, g.height) - footRow
        var canvas = Bitmap(width: bench.width, height: bench.height + max(0, lift))
        bench.draw(into: &canvas, x: 0, y: canvas.height - bench.height)
        let floor = canvas.height - bench.height + footRow
        b.draw(into: &canvas, x: bench.width / 2 + Int(Double(bench.width) * blackDogX) - b.width / 2,
               y: floor - b.height)
        g.draw(into: &canvas, x: bench.width / 2 + Int(Double(bench.width) * goldenX) - g.width / 2,
               y: floor - g.height)
        return canvas
    }

    let cells = (0..<black.count).map(cell)
    let one = cells[0]
    let gap = 30
    var strip = Bitmap(width: (one.width + gap) * (cells.count + 1) + gap,
                       height: one.height + gap * 2)
    for pixel in 0..<(strip.width * strip.height) {
        strip.pixels[pixel * 4] = 248
        strip.pixels[pixel * 4 + 1] = 244
        strip.pixels[pixel * 4 + 2] = 226
        strip.pixels[pixel * 4 + 3] = 255
    }
    for (index, c) in cells.enumerated() { c.draw(into: &strip, x: gap + index * (one.width + gap), y: gap) }

    var average = Bitmap(width: one.width, height: one.height)
    for pixel in 0..<(one.width * one.height * 4) {
        average.pixels[pixel] = UInt8((cells.reduce(0.0) { $0 + Double($1.pixels[pixel]) }
                                       / Double(cells.count)).rounded())
    }
    average.draw(into: &strip, x: gap + cells.count * (one.width + gap), y: gap)

    try? FileManager.default.createDirectory(
        atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true
    )
    write(strip, to: path)
}

// MARK: - Doing it

print("dogs")
private let (sheet, hadAlpha) = load("Art/dogs_source.png")
print("  source \(sheet.width)x\(sheet.height)")

// The one thing this script refuses to do without. See the header: a sheet with
// a painted background is a sheet whose white fur will be cut away as
// background, and the only place that shows up is in the game.
guard hadAlpha else {
    fatalError("""
        Art/dogs_source.png has no alpha channel.

        This script will not key one in. The black dog's white fur is painted in
        the same cream a flat background would be — (250,243,231) against
        (249,244,229) — so any colour key cuts his chest, blaze, muzzle and paws
        out along with the field, and the game draws scrolling grass through the
        holes. Export the dogs on transparency.
        """)
}
print("  alpha channel present — nothing is keyed")

// The halo, reported rather than removed. Everything faint around a figure is
// counted, and then the part of it that is *warm* — which is the matte, not the
// drawing, since neither dog is outlined in orange. The anti-aliasing has to be
// kept, so the only question is whether the coloured part of this has grown
// enough to show; at a few hundred pixels it has not.
private var faint = 0, warm = 0
for y in 0..<sheet.height {
    for x in 0..<sheet.width {
        let a = sheet.alpha(x, y)
        guard a > 0, a < solidEnough else { continue }
        faint += 1
        let o = sheet.offset(x, y)
        let scale = 255.0 / Double(a)
        let r = Double(sheet.pixels[o]) * scale
        let g = Double(sheet.pixels[o + 1]) * scale
        let b = Double(sheet.pixels[o + 2]) * scale
        if r > 120, r - g > 60, r - b > 60 { warm += 1 }
    }
}
print("  \(faint) faint edge pixels, \(warm) of them warm enough to be matte rather than"
    + " anti-aliasing — kept either way, see `solidEnough`")

private let figures = regions(of: sheet).filter { $0.size >= smallestFigure }
guard figures.count == 10 else {
    fatalError("expected ten dogs, found \(figures.count) regions over \(smallestFigure) pixels")
}

// Two rows of five: the black dog above, the golden below. Reading order within
// a row is the order the poses run in.
private let rows = Dictionary(grouping: figures) { $0.centreY < sheet.height / 2 }
private let topRow = rows[true]!.sorted { $0.left < $1.left }
private let bottomRow = rows[false]!.sorted { $0.left < $1.left }
guard topRow.count == 5, bottomRow.count == 5 else {
    fatalError("expected five poses a row, found \(topRow.count) and \(bottomRow.count)")
}

private func poses(_ row: [Region]) -> [Bitmap] {
    row.map { sheet.cropped(x: $0.left, y: $0.top, width: $0.width, height: $0.height) }
}

print("  lining each dog up against his own first pose:")
private let black = register(poses(topRow), named: "black ")
private let golden = register(poses(bottomRow), named: "golden")

for (index, pose) in black.enumerated() { install(pose, named: "dog_black_\(index)") }
for (index, pose) in golden.enumerated() { install(pose, named: "dog_golden_\(index)") }
print("  dog_black_*  \(black[0].width)x\(black[0].height)")
print("  dog_golden_* \(golden[0].width)x\(golden[0].height)")

private let (bench, _) = load("BennysGreatEscape/Assets.xcassets/obstacle_bench.imageset/obstacle_bench.png")
private let seat = seatLine(of: bench)
print("  obstacle_bench \(bench.width)x\(bench.height); seat runs from its back edge at row"
    + " \(seat.back) to its front lip at row \(seat.front)")
print(String(format: "  dogs stand on row %d, %.0f%% forward — %.3f of the drawing up from its feet",
             seat.row, seatDepth * 100, seat.fraction))

preview(bench: bench, black: black, golden: golden, footRow: seat.row,
        to: "Art/preview/bench_dogs.png")

private func round3(_ v: Double) -> String { String(format: "%.3f", v) }

print("""

paste into ObstacleArt:

    private static let dogSeat: CGFloat = \(round3(seat.fraction))

    private static let blackDog = Overlay(
        frames: numberedTextures("dog_black"),
        xFraction: \(round3(blackDogX)), yFraction: dogSeat,
        heightFraction: \(round3(blackDogHeight)), phase: 0
    )

    private static let goldenDog = Overlay(
        frames: numberedTextures("dog_golden"),
        xFraction: \(round3(goldenX)), yFraction: dogSeat,
        heightFraction: \(round3(goldenHeight)), phase: 2
    )
""")
