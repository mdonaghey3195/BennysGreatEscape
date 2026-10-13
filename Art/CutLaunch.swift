#!/usr/bin/env swift
//
//  CutLaunch.swift
//  Benny's Great Escape
//
//  Cuts the five sheets of the launch — Benny sliding into his dog house, the
//  roof opening, and the rocket carrying him out of it — into the sprites
//  `ObstacleArt`'s neighbour `LaunchArt` hangs the clip on, and prints the
//  numbers that place them.
//
//      swift Art/CutLaunch.swift
//
//  Run from the repository root. It reads the `launch_*_source.png` sheets here
//  and writes the catalogue, so rerunning it is idempotent.
//
//  **Nothing is keyed.** All five sheets arrived on a real alpha channel, and
//  this script refuses to run on one that didn't — the reason is written out in
//  `Art/CutDogs.swift`, and it is the same reason: a white-furred beagle on a
//  pale field cannot be separated from it by colour, and the only place that
//  shows up is in the game.
//
//  **Two of the four clips are not clips.** That is the measurement the whole
//  build turns on, so it is worth stating plainly. Every frame of the climb
//  sheet separates into exactly two pieces: a house of about 1,201,400 pixels,
//  and a rocket of *exactly* 345,414 — the same number in all five. It is one
//  drawing being moved, not five drawings. And the rise sheet is those same two
//  pieces overlapping: its blob grows from 1,202,780 to 1,544,968, against
//  1,201,462 + 345,414 = 1,546,876 for the two apart.
//
//  So the rocket is cut out once and flown up *behind* the house, and the
//  house's own drawing does the occluding — which is what the rise sheet's early
//  frames are a picture of. Seventeen frames, several of them nearly four
//  thousand pixels tall, collapse to two textures and a move action. Baking them
//  instead would have cost something like a hundred megabytes of resident
//  texture to say the same thing.
//
//  The slide keeps its nine frames — Benny is occluded and deforms as he goes in
//  — and the roof keeps its eight, being hinged to the house it swings off.
//
//  **Everything is registered on the house**, which is the one thing on screen
//  through all four clips and the one thing that must not move between them. The
//  slide sheet needs it: its house is a constant 1233x1038 in every frame but
//  wanders ±30 pixels, which is the same trouble the bench's dogs gave and wants
//  the same answer. The others are consistent to the pixel and only need
//  agreeing with each other.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tuning

/// How opaque a pixel has to be before this script will measure it.
private let solidEnough = 40

/// The smallest region that is a real piece of drawing rather than a speck.
private let smallestFigure = 15_000

/// How much of the sheets' resolution to keep.
///
/// The house plays about 162 scene units wide, and the widest device this ships
/// to gives roughly 3.5 pixels to a unit — call it 570 pixels against the 1233
/// the sheets draw it at. Half throws away nothing anybody can see and takes
/// three quarters of the memory with it.
private let outputScale = 0.5

/// How far the slide's frames are allowed to have wandered, in source pixels.
/// Measured drift is ±30; this is the window the search looks in.
private let driftSearch = 70

/// How much of the house is Benny-free, measured in from its right edge.
///
/// He comes in from the left and goes in the door, which is on the left face, so
/// the right half of the drawing is his business in none of the nine frames.
/// That half is what the frames are lined up on.
private let cleanHouseFraction = 0.5

/// Room left around each part's drawing on its own canvas, in source pixels.
private let canvasPadding = 12

/// How many pixels a row or a column needs before it counts as the edge of the
/// drawing.
///
/// Not one, which is what `drawn` used to accept and what cost a day. The
/// bottom row of the roof sheet's closed frame holds exactly one pixel, at
/// alpha 41 — one above the threshold — sixty-six rows below the house itself.
/// Standing the frame on its bounding box therefore stood it on that speck, and
/// since that frame is the one held through the cross-fade, the dog house
/// hopped seventeen units off the turf every launch.
///
/// Six is far below anything really drawn here — every outline in this art is
/// several pixels thick — and far above a stray.
private let solidRun = 6

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

    func draw(into canvas: inout Bitmap, x: Int, y: Int) {
        for row in 0..<height {
            let ty = y + row
            guard ty >= 0, ty < canvas.height else { continue }
            for column in 0..<width {
                let tx = x + column
                guard tx >= 0, tx < canvas.width else { continue }
                let from = offset(column, row), to = canvas.offset(tx, ty)
                let a = Double(pixels[from + 3]) / 255
                guard a > 0 else { continue }
                for channel in 0..<4 {
                    let over = Double(pixels[from + channel])
                    let under = Double(canvas.pixels[to + channel])
                    canvas.pixels[to + channel] = UInt8(min(255, (over + under * (1 - a)).rounded()))
                }
            }
        }
    }

    func scaled(by factor: Double) -> Bitmap {
        let w = max(1, Int((Double(width) * factor).rounded()))
        let h = max(1, Int((Double(height) * factor).rounded()))
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

    /// The rectangle the drawing actually occupies.
    ///
    /// A row or column only counts once it carries `solidRun` pixels. A single
    /// stray is not an edge, and treating one as an edge is what made the dog
    /// house hop — see `solidRun`.
    var drawn: (left: Int, right: Int, top: Int, bottom: Int) {
        var rows = [Int](repeating: 0, count: height)
        var columns = [Int](repeating: 0, count: width)
        for y in 0..<height {
            for x in 0..<width where isDrawn(x, y) { rows[y] += 1; columns[x] += 1 }
        }
        guard let top = rows.firstIndex(where: { $0 >= solidRun }),
              let bottom = rows.lastIndex(where: { $0 >= solidRun }),
              let left = columns.firstIndex(where: { $0 >= solidRun }),
              let right = columns.lastIndex(where: { $0 >= solidRun })
        else { fatalError("nothing drawn") }
        return (left, right, top, bottom)
    }
}

private func load(_ path: String) -> Bitmap {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("can't read \(path) — run this from the repository root")
    }
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast:
        fatalError("""
            \(path) has no alpha channel.

            This script will not key one in. Benny's white fur is painted in the
            same cream a flat background would be, so any colour key cuts him up
            along with the field — see Art/CutDogs.swift. Export on transparency.
            """)
    default: break
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
    var centreY: Int { (top + bottom) / 2 }
}

private func regions(of sheet: Bitmap,
                     x xr: ClosedRange<Int>, y yr: ClosedRange<Int>) -> [Region] {
    let w = sheet.width
    var mask = [Bool](repeating: false, count: w * sheet.height)
    for y in yr { for x in xr where sheet.isDrawn(x, y) { mask[y * w + x] = true } }
    var seen = [Bool](repeating: false, count: w * sheet.height)
    var found: [Region] = []
    for y0 in yr {
        for x0 in xr {
            let seed = y0 * w + x0
            guard mask[seed], !seen[seed] else { continue }
            var stack = [seed]
            seen[seed] = true
            var size = 0, left = w, right = -1, top = sheet.height, bottom = -1
            while let pixel = stack.popLast() {
                size += 1
                let x = pixel % w, y = pixel / w
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard xr.contains(nx), yr.contains(ny) else { continue }
                    let k = ny * w + nx
                    guard mask[k], !seen[k] else { continue }
                    seen[k] = true
                    stack.append(k)
                }
            }
            found.append(Region(size: size, left: left, right: right, top: top, bottom: bottom))
        }
    }
    return found.sorted { $0.size > $1.size }
}

/// Bands of consecutive rows or columns carrying paint, split on gaps.
private func bands(_ counts: [Int], minGap: Int) -> [(Int, Int)] {
    var out: [(Int, Int)] = []
    var start: Int? = nil
    var blank = 0
    for (i, n) in counts.enumerated() {
        if n > 0 {
            if start == nil { start = i }
            blank = 0
        } else {
            blank += 1
            if let s = start, blank >= minGap { out.append((s, i - blank)); start = nil }
        }
    }
    if let s = start { out.append((s, counts.count - 1)) }
    return out
}

private func rowBands(of sheet: Bitmap, minGap: Int) -> [(Int, Int)] {
    var counts = [Int](repeating: 0, count: sheet.height)
    for y in 0..<sheet.height {
        for x in 0..<sheet.width where sheet.isDrawn(x, y) { counts[y] += 1 }
    }
    return bands(counts, minGap: minGap)
}

private func colBands(of sheet: Bitmap, minGap: Int) -> [(Int, Int)] {
    var counts = [Int](repeating: 0, count: sheet.width)
    for y in 0..<sheet.height {
        for x in 0..<sheet.width where sheet.isDrawn(x, y) { counts[x] += 1 }
    }
    return bands(counts, minGap: minGap)
}

// MARK: - Lining the slide up on its house

/// How far each slide frame has to move to put its house where the last frame's
/// is.
///
/// One-dimensional, and twice: the columns of the drawing carry the horizontal
/// offset and the rows the vertical, because what is being corrected is a
/// translation and a translation separates. Cheap enough to search the whole
/// drift window exhaustively, where matching the full picture two-dimensionally
/// would be billions of comparisons for the same answer.
///
/// Read off the right-hand `cleanHouseFraction` of the house only. Benny is
/// somewhere in the left of every frame — running at it, halfway through the
/// door, or a tail — and including him would line the frames up on *him*, which
/// is the one thing in the clip that is supposed to move.
/// Positive means the reference sits that far to the right of, or below, this
/// frame — so a frame is lined up by drawing it *at* what comes back, not at
/// the negative of it. Getting that backwards looks exactly like getting it
/// right: the frames move, the offsets print, and the only place it shows is in
/// the finished clip.
private func drift(of frame: Bitmap, against reference: Bitmap,
                   clean: ClosedRange<Int>) -> (dx: Int, dy: Int) {
    // Columns over the whole width, rows over the clean columns only. The row
    // profile has to be narrowed or Benny's own height dominates it; the column
    // profile doesn't, because the comparison below only ever reads the clean
    // part of it.
    func profiles(_ b: Bitmap) -> (cols: [Double], rows: [Double]) {
        var cols = [Double](repeating: 0, count: b.width)
        var rows = [Double](repeating: 0, count: b.height)
        for y in 0..<b.height {
            for x in 0..<b.width where b.alpha(x, y) > 0 {
                let a = Double(b.alpha(x, y))
                cols[x] += a
                if clean.contains(x) { rows[y] += a }
            }
        }
        return (cols, rows)
    }
    let (rc, rr) = profiles(reference)
    let (fc, fr) = profiles(frame)

    /// The shift that best lays `f` over `r`, judged only where the drawing
    /// actually is. Averaging over the whole array instead would divide every
    /// candidate by the same few thousand empty columns, which flattens the
    /// difference between them to nothing and hands back nought every time.
    func best(_ f: [Double], _ r: [Double], over range: ClosedRange<Int>) -> Int {
        var bestShift = 0, bestCost = Double.greatestFiniteMagnitude
        for shift in -driftSearch...driftSearch {
            var cost = 0.0, n = 0
            for i in range {
                let j = i + shift
                guard i >= 0, i < f.count, j >= 0, j < r.count else { continue }
                cost += abs(f[i] - r[j]); n += 1
            }
            guard n > 0 else { continue }
            let mean = cost / Double(n)
            if mean < bestCost { bestCost = mean; bestShift = shift }
        }
        return bestShift
    }

    // Rows are judged over the drawing's own height, columns over the clean half
    // of the house — the two stretches that hold something to line up on.
    let painted = rr.indices.filter { rr[$0] > 0 }
    let rows = (painted.first ?? 0)...(painted.last ?? (rr.count - 1))
    return (best(fc, rc, over: clean), best(fr, rr, over: rows))
}

// MARK: - The check

private func preview(_ parts: [(name: String, frames: [Bitmap])], to path: String) {
    var strips: [Bitmap] = []
    for part in parts {
        let cell = part.frames[0]
        let gap = 24
        var strip = Bitmap(width: (cell.width + gap) * (part.frames.count + 1) + gap,
                           height: cell.height + gap * 2)
        for pixel in 0..<(strip.width * strip.height) {
            strip.pixels[pixel * 4] = 120; strip.pixels[pixel * 4 + 1] = 170
            strip.pixels[pixel * 4 + 2] = 210; strip.pixels[pixel * 4 + 3] = 255
        }
        for (index, frame) in part.frames.enumerated() {
            frame.draw(into: &strip, x: gap + index * (cell.width + gap),
                       y: gap + cell.height - frame.height)
        }
        // All the poses averaged. The house is the same drawing in every one of
        // them, so it has to come out of this sharp; anything soft about it is a
        // frame that never got lined up.
        var average = Bitmap(width: cell.width, height: cell.height)
        for pixel in 0..<(cell.width * cell.height * 4) {
            average.pixels[pixel] = UInt8((part.frames.reduce(0.0) {
                $0 + Double($1.pixels[pixel])
            } / Double(part.frames.count)).rounded())
        }
        average.draw(into: &strip, x: gap + part.frames.count * (cell.width + gap), y: gap)
        strips.append(strip)
    }

    let width = strips.map(\.width).max()!
    let height = strips.reduce(0) { $0 + $1.height }
    var sheet = Bitmap(width: width, height: height)
    var y = 0
    for strip in strips { strip.draw(into: &sheet, x: 0, y: y); y += strip.height }

    try? FileManager.default.createDirectory(
        atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true
    )
    write(sheet, to: path)
}

private func round3(_ v: Double) -> String { String(format: "%.3f", v) }

// MARK: - The slide

print("launch")
private let slideSheet = load("Art/launch_slide_source.png")
print("  slide sheet \(slideSheet.width)x\(slideSheet.height)")

private let slideRows = rowBands(of: slideSheet, minGap: 60)
guard slideRows.count == 9 else { fatalError("expected nine slide frames, found \(slideRows.count)") }

private let slideRaw = slideRows.map { band in
    slideSheet.cropped(x: 0, y: band.0, width: slideSheet.width, height: band.1 - band.0 + 1)
}

// The last frame is the house on its own — Benny is inside by then — so it is
// what the other eight are lined up against.
private let slideHouse = slideRaw[8].drawn
private let cleanFrom = slideHouse.left + Int(Double(slideHouse.right - slideHouse.left) * cleanHouseFraction)
print("  house alone in frame 8: x \(slideHouse.left)-\(slideHouse.right) (w \(slideHouse.right - slideHouse.left + 1))"
    + ", lined up on columns \(cleanFrom)-\(slideHouse.right)")

private var slideShifted: [Bitmap] = []
for (index, frame) in slideRaw.enumerated() {
    let d = index == 8 ? (dx: 0, dy: 0)
                       : drift(of: frame, against: slideRaw[8], clean: cleanFrom...slideHouse.right)
    var moved = Bitmap(width: frame.width, height: frame.height)
    // Drawn at `+d`, not `-d`. `drift` reports where the reference is relative
    // to this frame, so moving the frame *by* that lands it on the reference;
    // negating it pushes the frame the same distance the wrong way and leaves
    // it twice as far out as it started. It did, for a while, and the house
    // skated sideways through the whole slide — see `drift`.
    frame.draw(into: &moved, x: d.dx, y: d.dy)
    slideShifted.append(moved)
    print("    frame \(index): moved \(d.dx), \(d.dy)")
}

// Did it work? Registration applied backwards looks exactly like registration
// that works — the frames move, the offsets print, and the only place it shows
// is as the house skating about in the finished clip. So the result is measured
// rather than trusted: the house's right-hand edge, which is the one landmark
// Benny never reaches, has to land on the same column in all nine.
private let registeredRights = slideShifted.map { frame -> Int in
    var right = -1
    for x in stride(from: frame.width - 1, through: 0, by: -1) {
        var run = 0
        for y in 0..<frame.height where frame.isDrawn(x, y) { run += 1 }
        if run >= solidRun { right = x; break }
    }
    return right
}
private let rightSpread = (registeredRights.max() ?? 0) - (registeredRights.min() ?? 0)
print("  registered: the house's right edge lands within \(rightSpread)px across the nine")
guard rightSpread <= 8 else {
    fatalError("the slide's frames are \(rightSpread)px apart after registering — they are"
        + " not lined up, and the dog house will slide about as they play."
        + " Check the sign on the drift: it is drawn at +d, not -d.")
}

// One canvas for all nine, big enough for the widest of them once lined up.
private let slideBoxes = slideShifted.map(\.drawn)
private let slideLeft = slideBoxes.map(\.left).min()! - canvasPadding
private let slideRight = slideBoxes.map(\.right).max()! + canvasPadding
private let slideTop = slideBoxes.map(\.top).min()! - canvasPadding
private let slideBottom = slideBoxes.map(\.bottom).max()!
private let slideFrames = slideShifted.map {
    $0.cropped(x: slideLeft, y: slideTop,
               width: slideRight - slideLeft + 1, height: slideBottom - slideTop + 1)
        .scaled(by: outputScale)
}
for (index, frame) in slideFrames.enumerated() { install(frame, named: "launch_slide_\(index)") }
print("  launch_slide_* \(slideFrames[0].width)x\(slideFrames[0].height)")

// Where the house stands on that canvas, as fractions of it — what the game
// pins every part of the clip to.
private let slideHouseLeftFraction = Double(slideHouse.left - slideLeft) / Double(slideRight - slideLeft + 1)
private let slideHouseWidthFraction = Double(slideHouse.right - slideHouse.left + 1) / Double(slideRight - slideLeft + 1)
// And where the drawn Benny stands in the first frame, so the real one can be
// swapped for him without either of them moving.
private let bennyBox = regions(of: slideShifted[0], x: 0...(slideShifted[0].width - 1),
                               y: 0...(slideShifted[0].height - 1))
    .filter { $0.size >= smallestFigure }
    .sorted { $0.left < $1.left }.first!
private let bennyCentreFraction = Double((bennyBox.left + bennyBox.right) / 2 - slideLeft)
    / Double(slideRight - slideLeft + 1)
print("  drawn Benny in frame 0: x \(bennyBox.left)-\(bennyBox.right), centre at "
    + round3(bennyCentreFraction) + " across the canvas")

// The house on its own, to scroll in on before any of this starts.
//
// Taken from frame 0 and not from frame 8, which is the obvious candidate and
// the wrong one: by frame 8 Benny is inside but his tail and a back paw are
// still in the doorway, and a dog house arriving with a tail hanging out of it
// gives the whole thing away a second early. In frame 0 he is clear of it, so
// the two are separate pieces of drawing and the house is simply the other one.
//
// Emitted on the slide's own canvas, so the swap from this to frame 0 is a
// change of texture on a sprite that doesn't move.
// From the *registered* frame 0, not the raw one. Cutting it from the raw frame
// leaves it 47 pixels out — frame 0's own drift correction — so the house jumps
// the instant the clip takes over from it, which is the one seam in the whole
// sequence that has to be invisible. It also makes Benny unmeasurable: see
// `track`, which finds him by cancelling this against each frame.
private let houseOnly = regions(of: slideShifted[0], x: 0...(slideShifted[0].width - 1),
                                y: 0...(slideShifted[0].height - 1))
    .filter { $0.size >= smallestFigure }
    .sorted { $0.left < $1.left }.last!
private var shutCanvas = Bitmap(width: slideShifted[0].width, height: slideShifted[0].height)
slideShifted[0]
    .cropped(x: houseOnly.left, y: houseOnly.top,
             width: houseOnly.width, height: houseOnly.height)
    .draw(into: &shutCanvas, x: houseOnly.left, y: houseOnly.top)
install(shutCanvas.cropped(x: slideLeft, y: slideTop,
                           width: slideRight - slideLeft + 1,
                           height: slideBottom - slideTop + 1).scaled(by: outputScale),
        named: "launch_house_shut")
print("  launch_house_shut: the house alone, \(houseOnly.width)x\(houseOnly.height),"
    + " on the slide's canvas")

/// How far the drawn Benny travels across the clip, as a fraction of the canvas.
///
/// Measured off his *trailing* edge — his tail — and not his centre, for a
/// reason the first attempt at this found the hard way. He overlaps the house
/// from the third frame on, so he can only be separated from it by cancelling
/// the house out; and the nine houses on this sheet are nine independently drawn
/// houses, so registering them still leaves a rim of disagreement everywhere the
/// roof and the name plate differ. That rim wrecks any measurement of his right
/// edge or his centre. His left edge is clean, because the leftmost thing in the
/// picture is always him and never the house.
///
/// It measures the right thing too: while he is going through the door his tail
/// keeps advancing at the pace the rest of him did, and it stops when the last of
/// him is inside — which is exactly where the clip should stop being paced.
///
/// What it is for: the clip has to play at whatever speed the world is doing, so
/// he slides in at the pace he was running rather than after the game has
/// stopped to let him. `Launch` divides this by `gameSpeed`.
private func bennySteps() -> [Double] {
    let full = shutCanvas.cropped(x: slideLeft, y: slideTop,
                                  width: slideRight - slideLeft + 1,
                                  height: slideBottom - slideTop + 1)
    var edges: [Int] = []
    for (index, shifted) in slideShifted.enumerated() {
        let frame = shifted.cropped(x: slideLeft, y: slideTop,
                                    width: slideRight - slideLeft + 1,
                                    height: slideBottom - slideTop + 1)
        var left = -1
        scan: for x in 0..<frame.width {
            var run = 0
            for y in 0..<frame.height
            where frame.alpha(x, y) >= solidEnough && frame.alpha(x, y) - full.alpha(x, y) > 60 {
                run += 1
                // A column of him, not a pixel of anti-aliasing along a roof.
                if run > 12 { left = x; break scan }
            }
        }
        guard left >= 0 else { continue }
        edges.append(left)
        print(String(format: "    frame %d: his tail at %d, %.4f across", index, left,
                     Double(left) / Double(frame.width)))
    }
    // Each frame's own advance, not just the total. What the clip is timed off:
    // evenly-timed frames that are unevenly drawn are what made the slide lurch.
    let width = Double(slideRight - slideLeft + 1)
    return edges.dropFirst().enumerated().map { Double($1 - edges[$0]) / width }
}
print("  the drawn Benny, frame by frame:")
private let slideSteps = bennySteps()
private let slideSpan = slideSteps.reduce(0, +)
print("  his step each frame: " + slideSteps.map { String(format: "%.4f", $0) }.joined(separator: ", "))
print(String(format: "  %.4f of the canvas in all, getting into the house", slideSpan))

// MARK: - The roof

private let roofSheet = load("Art/launch_roof_source.png")
print("  roof sheet \(roofSheet.width)x\(roofSheet.height)")
private let roofRows = rowBands(of: roofSheet, minGap: 60)
private let roofCols = colBands(of: roofSheet, minGap: 60)
print("  \(roofRows.count) rows x \(roofCols.count) columns")

private var roofRaw: [Bitmap] = []
for row in roofRows {
    for col in roofCols {
        let cell = roofSheet.cropped(x: col.0, y: row.0,
                                     width: col.1 - col.0 + 1, height: row.1 - row.0 + 1)
        var any = false
        outer: for y in 0..<cell.height {
            for x in 0..<cell.width where cell.isDrawn(x, y) { any = true; break outer }
        }
        if any { roofRaw.append(cell) }
    }
}
guard roofRaw.count == 8 else { fatalError("expected eight roof frames, found \(roofRaw.count)") }

// The roof swings up and to the right, so the house's left edge and its ground
// line are the two things it can't move — which makes them what to line up on.
private let roofBoxes = roofRaw.map(\.drawn)
private let roofWidth = roofBoxes.map { $0.right - $0.left }.max()! + 1 + canvasPadding * 2
private let roofHeight = roofBoxes.map { $0.bottom - $0.top }.max()! + 1 + canvasPadding
// Each frame stood on its own bounding box: left edge in by `canvasPadding`,
// lowest row on the canvas floor.
//
// Which is only sound because that box is now speck-proof. It was not: the
// bottom row of the closed frame holds a single pixel at alpha 41, sixty-six
// rows below the house, and standing the frame on *that* left the dog house
// hanging seventeen units above the turf for the length of the cross-fade —
// which is exactly when that frame is on screen. See `solidRun`.
private let roofFrames = zip(roofRaw, roofBoxes).map { frame, box -> Bitmap in
    var canvas = Bitmap(width: roofWidth, height: roofHeight)
    frame.draw(into: &canvas, x: canvasPadding - box.left, y: roofHeight - 1 - box.bottom)
    return canvas.scaled(by: outputScale)
}

// And a guard, because the only place the last version of this showed up was as
// a hop in the game. Every frame's house has to stand on the canvas's floor.
for (index, frame) in roofFrames.enumerated() {
    var foot = -1
    for y in stride(from: frame.height - 1, through: 0, by: -1) {
        var run = 0
        for x in 0..<frame.width where frame.isDrawn(x, y) { run += 1 }
        if run >= solidRun { foot = frame.height - 1 - y; break }
    }
    guard foot >= 0, foot <= 3 else {
        fatalError("roof frame \(index) stands \(foot) rows off the floor — it is not"
            + " level with the others, and the dog house will hop when it plays")
    }
}

for (index, frame) in roofFrames.enumerated() { install(frame, named: "launch_roof_\(index)") }
print("  launch_roof_* \(roofFrames[0].width)x\(roofFrames[0].height)"
    + "  (house left edge \(canvasPadding)px in, ground on the bottom row)")
print("  roof frame widths: \(roofBoxes.map { $0.right - $0.left + 1 }) — the first is the"
    + " house with its roof shut, which is the body every other measurement is stated against")

/// The house's body, roof closed. Every house-relative fraction below divides by
/// this rather than by whatever the drawing happens to span with the roof up,
/// so the numbers all mean the same thing and the game needs one size constant.
private let bodyWidth = Double(roofBoxes[0].right - roofBoxes[0].left + 1)
private let slideBodyWidth = Double(slideHouse.right - slideHouse.left + 1)
guard abs(bodyWidth - slideBodyWidth) <= 4 else {
    fatalError("the slide draws the house \(Int(slideBodyWidth))px wide and the roof sheet"
        + " \(Int(bodyWidth))px — they have to be the same house at the same scale")
}

// The widths agree. The *shapes* do not, and this says so rather than leaving it
// to be rediscovered: the two sheets draw different dog houses. Same width,
// 12.5% apart in aspect, and the doorway, the roof overhang and the name plate
// are all drawn differently. Nothing here can turn one into the other, so the
// clip cross-fades between them and the game carries a comment saying why.
//
// The fix is a redraw, not a tuning constant. If the slide sheet is ever redone
// against the same house as the other three, this falls silent and the
// cross-fade can go.
private let slideBodyHeight = Double(slideHouse.bottom - slideHouse.top + 1)
private let roofBodyHeight = Double(roofBoxes[0].bottom - roofBoxes[0].top + 1)
private let aspectGap = (slideBodyWidth / slideBodyHeight) / (bodyWidth / roofBodyHeight) - 1
if abs(aspectGap) > 0.02 {
    print(String(format: "  ⚠︎ the slide draws the house %.0fx%.0f and the roof sheet %.0fx%.0f"
                 + " — %.1f%% apart in aspect, so they are not the same drawing."
                 + " The clip cross-fades between them; a redraw would remove that.",
                 slideBodyWidth, slideBodyHeight, bodyWidth, roofBodyHeight, aspectGap * 100))
}

// MARK: - The house and the rocket

private let riseSheet = load("Art/launch_rise_source.png")
private let riseRows = rowBands(of: riseSheet, minGap: 80)
private let riseCols = colBands(of: riseSheet, minGap: 80)
print("  rise sheet \(riseSheet.width)x\(riseSheet.height) — \(riseRows.count) rows x \(riseCols.count) columns")

// The last frame is the only one where the two are apart.
private let lastRow = riseRows[riseRows.count - 1]
private let lastCol = riseCols[riseCols.count - 1]
private let riseLast = regions(of: riseSheet, x: lastCol.0...lastCol.1, y: lastRow.0...lastRow.1)
    .filter { $0.size >= smallestFigure }
guard riseLast.count == 2 else {
    fatalError("expected the house and the rocket apart in the last rise frame, found \(riseLast.count)")
}
private let houseRegion = riseLast[0]
private let rocketRegion = riseLast[1]
print("  house \(houseRegion.size)px \(houseRegion.width)x\(houseRegion.height)"
    + ", rocket \(rocketRegion.size)px \(rocketRegion.width)x\(rocketRegion.height)")

// Only the rocket is cut out. The house it climbs from is the roof run's last
// frame, which is the same drawing already on the same canvas — taking a second
// copy of it from this sheet would be a second thing to keep in agreement, and
// the swap from the last roof frame to it would be where they disagreed.
private let rocketArt = riseSheet.cropped(x: rocketRegion.left, y: rocketRegion.top,
                                          width: rocketRegion.width, height: rocketRegion.height)
install(rocketArt.scaled(by: outputScale), named: "launch_rocket")

// MARK: - The climb, measured

private let climbSheet = load("Art/launch_climb_source.png")
private let climbCols = colBands(of: climbSheet, minGap: 80)
print("  climb sheet \(climbSheet.width)x\(climbSheet.height) — \(climbCols.count) frames")

print("  the rocket against the house, frame by frame (its own drawing, moved):")
private var climbTrack: [(dx: Double, dy: Double)] = []
for (index, col) in climbCols.enumerated() {
    let pieces = regions(of: climbSheet, x: col.0...col.1, y: 0...(climbSheet.height - 1))
        .filter { $0.size >= smallestFigure }
    guard pieces.count == 2 else {
        print("    frame \(index): \(pieces.count) piece(s) — not separable, skipped")
        continue
    }
    let house = pieces[0], rocket = pieces[1]
    // Both measured from the house's ground-left corner, in house widths, so the
    // path survives the art being re-cut at another size.
    let dx = Double(rocket.left - house.left) / bodyWidth
    let dy = Double(house.bottom - rocket.bottom) / bodyWidth
    climbTrack.append((dx, dy))
    print(String(format: "    frame %d: rocket %dpx, %.3f across and %.3f up from the house's foot",
                 index, rocket.size, dx, dy))
}

// Where it starts: on the floor of the house, which is the one place "inside"
// can mean without guessing. The rise sheet's own last frame is no use for this
// — it is where that clip *ends*, with the rocket already well clear of the
// roof — and taking it for a start is what had the rocket popping into view
// above the house instead of climbing out of it.
//
// Sideways it is measured, and steady: 0.18 to 0.23 across the climb sheet's
// five frames, so the ascent is vertical and the wobble is just drawing.
private let startDx = Double(rocketRegion.left - houseRegion.left) / bodyWidth
private let startDy = 0.0
print(String(format: "  it leaves the rise sheet at %.3f up; it starts on the floor at 0",
             Double(houseRegion.bottom - rocketRegion.bottom) / bodyWidth))

// MARK: - Flying

private let flightSheet = load("Art/launch_flight_source.png")
private let flightPieces = regions(of: flightSheet, x: 0...(flightSheet.width - 1),
                                   y: 0...(flightSheet.height - 1))
    .filter { $0.size >= smallestFigure }
print("  flight sheet \(flightSheet.width)x\(flightSheet.height) — \(flightPieces.count) poses")

private let flightSplit = flightSheet.height / 2
private let climbing = flightPieces.filter { $0.centreY < flightSplit }.sorted { $0.left < $1.left }
private let diving = flightPieces.filter { $0.centreY >= flightSplit }.sorted { $0.left < $1.left }
print("  \(climbing.count) climbing, \(diving.count) diving")

private func installPoses(_ list: [Region], prefix: String) -> [Bitmap] {
    // One canvas for the run, every pose centred on it, so swapping between them
    // doesn't shift the rocket.
    let width = list.map(\.width).max()! + canvasPadding * 2
    let height = list.map(\.height).max()! + canvasPadding * 2
    var out: [Bitmap] = []
    for (index, r) in list.enumerated() {
        let piece = flightSheet.cropped(x: r.left, y: r.top, width: r.width, height: r.height)
        var canvas = Bitmap(width: width, height: height)
        piece.draw(into: &canvas, x: (width - r.width) / 2, y: (height - r.height) / 2)
        let scaled = canvas.scaled(by: outputScale)
        install(scaled, named: "\(prefix)_\(index)")
        out.append(scaled)
    }
    print("  \(prefix)_* \(out[0].width)x\(out[0].height)")
    return out
}
private let flyFrames = installPoses(climbing, prefix: "launch_fly")
private let diveFrames = installPoses(diving, prefix: "launch_dive")

// MARK: - The check and the numbers

preview([("slide", slideFrames), ("roof", roofFrames),
         ("fly", flyFrames), ("dive", diveFrames)],
        to: "Art/preview/launch.png")

// How big everything is against everything else. Stated as ratios rather than
// sizes so that the clip follows Benny: he is the one thing in it whose size the
// game already decides, and the house, the rocket and the flight poses are all
// hung off him.
private let houseInDogWidths = bodyWidth / Double(bennyBox.right - bennyBox.left + 1)
private let rocketInHouseWidths = Double(rocketRegion.width) / bodyWidth

// The flight sheet is drawn at its own scale, so the first pose — the same
// upright rocket the climb ends on — is measured against `launch_rocket` and the
// whole run sized to agree with it. Swapping between them then doesn't resize
// the rocket in the middle of the shot.
private let flyCanvasWidth = Double(flyFrames[0].width) / outputScale
private let flyPoseHeight = Double(climbing[0].height)
private let flyWidthInHouseWidths =
    Double(rocketRegion.height) / bodyWidth                  // the rocket's height, in house widths
    * flyCanvasWidth / flyPoseHeight                         // the canvas that gives the pose that height
print(String(format: "  the house is %.3f Benny-lengths; the rocket %.3f house-widths;"
             + " the flight canvas %.3f", houseInDogWidths, rocketInHouseWidths, flyWidthInHouseWidths))

print("""

paste into LaunchArt:

    /// The slide's canvas, in fractions of itself: where the house stands on it,
    /// how wide the house is across it, and where the drawn Benny starts —
    /// which is the mark the real one is swapped at. Its ground line is the
    /// canvas's own bottom row, so an anchor of 0 puts it on the turf.
    static let slideHouseLeft: CGFloat = \(round3(slideHouseLeftFraction))
    static let slideHouseWidth: CGFloat = \(round3(slideHouseWidthFraction))
    static let slideBennyCentre: CGFloat = \(round3(bennyCentreFraction))

    /// How far each frame of the slide moves him, across the canvas, and the sum
    /// of them. The clip is timed off the steps rather than played at a flat
    /// rate — the art spaces him almost twice as far apart between the first two
    /// frames as between the middle two, and a flat frame time turns that into a
    /// lurch. See `Launch.slideBeats(at:)`.
    static let slideSteps: [CGFloat] = [\(slideSteps.map { round3($0) }.joined(separator: ", "))]
    static let slideSpan: CGFloat = \(round3(slideSpan))

    /// The roof's canvas: the house's left edge is \(canvasPadding) source pixels in and its
    /// foot is the bottom row, so both are stated against the canvas.
    static let roofHouseLeft: CGFloat = \(round3(Double(canvasPadding) / Double(roofWidth)))
    static let roofHouseWidth: CGFloat = \(round3(Double(roofBoxes[0].right - roofBoxes[0].left + 1) / Double(roofWidth)))

    /// The climb, in house widths from the house's ground-left corner.
    static let rocketFrom = CGPoint(x: \(round3(startDx)), y: \(round3(startDy)))
    static let rocketTo = CGPoint(x: \(round3(climbTrack.last?.dx ?? 0)), y: \(round3(climbTrack.last?.dy ?? 0)))

    /// Sizes, each against the thing it hangs off, so the whole clip follows
    /// Benny — the one thing in it the game already decides the size of.
    static let houseInDogs: CGFloat = \(round3(houseInDogWidths))
    static let rocketInHouses: CGFloat = \(round3(rocketInHouseWidths))
    static let flyInHouses: CGFloat = \(round3(flyWidthInHouseWidths))
""")
_ = diveFrames
