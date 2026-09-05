#!/usr/bin/env swift
//
//  CropBackground.swift
//  Benny's Great Escape
//
//  Cuts the scrolling background out of the long painted source in this
//  directory, and writes it straight into the asset catalogue.
//
//      swift Art/CropBackground.swift
//
//  Run from the repository root. Rerunning overwrites the asset in place, so a
//  repainted background is a rerun rather than a hand edit.
//
//  The source is deliberately longer than the game needs. What it holds is a
//  little over two copies of the same stretch of countryside, and the job here
//  is to find exactly one of them: a crop that, laid end to end with itself,
//  joins with nothing to see. Get the width wrong and the world jumps every
//  time it comes round; get the width right but the *offset* wrong and it still
//  does, less obviously, which is worse.
//
//  So neither is typed in. The period is found by sliding the image over itself
//  and taking the lag that matches best, the offset by asking which join is
//  cleanest at that period, and both are printed along with the rows the scene
//  is built from — the grass Benny stands on, and the band of flat sky the two
//  scrolling layers are split at.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tuning

/// How far apart two stretches of the image have to be before one can be called
/// a repeat of the other rather than more of the same hillside.
private let shortestPeriod = 1200

/// Rows worth comparing. The flat sky above and the flat field below match
/// everywhere and would drown the signal — what carries it is the clouds, the
/// hills, the bush line, the grass and the earth.
private let interesting: [(Int, Int)] = [(200, 900), (1040, 1470)]

/// How wide a stretch either side of a join is judged on. A single column can
/// match by luck; twenty-five of them in a row cannot.
private let joinWidth = 12

/// How far a sky pixel can sit from its row's true colour and still be a
/// blemish rather than a cloud, and how far it has to sit to be cloud.
///
/// Measured off the painting, and the two are not close: 93% of sky pixels are
/// within 14 of their row, every cloud pixel is 60 or more away, and the band
/// between them holds almost nothing. A ramp across that empty gap takes the
/// blemishes out without touching a cloud or hardening its soft edge.
private let skyBlemish = 15
private let skyCloud = 55

/// How many rows either side the gradient is averaged over. The row-by-row
/// reading of it carries the painting's own faint horizontal banding, and
/// smoothing takes that out along with everything else.
private let gradientSmoothing = 8

// MARK: - Bitmap

/// 8-bit RGBA, premultiplied, top-down — the same shape `SliceIntroSheets`
/// works in, for the same reason: it is what `CGContext` hands back.
private struct Bitmap {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }
}

private func load(_ path: String) -> Bitmap {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("can't read \(path) — run this from the repository root")
    }
    var bitmap = Bitmap(width: image.width, height: image.height,
                        pixels: [UInt8](repeating: 0, count: image.width * image.height * 4))
    bitmap.pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
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
            data: buffer.baseAddress,
            width: bitmap.width,
            height: bitmap.height,
            bitsPerComponent: 8,
            bytesPerRow: bitmap.width * 4,
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

// MARK: - Finding the repeat

/// How unalike two columns are, averaged over the rows worth looking at.
private func difference(_ sheet: Bitmap, _ a: Int, _ b: Int, rows: [Int]) -> Double {
    var total = 0
    for y in rows {
        let oa = sheet.offset(a, y), ob = sheet.offset(b, y)
        for channel in 0..<3 {
            total += abs(Int(sheet.pixels[oa + channel]) - Int(sheet.pixels[ob + channel]))
        }
    }
    return Double(total) / Double(rows.count * 3)
}

/// The lag at which the image most looks like itself.
///
/// Slid over itself and scored at every offset, the artwork's own period falls
/// out as a clear minimum rather than a tie — and the curve either side of it is
/// smooth, which is what says it is one real repeat and not a coincidence.
private func period(of sheet: Bitmap, rows: [Int]) -> Int {
    var best = (cost: Double.infinity, lag: 0)
    var curve: [(Int, Double)] = []
    for lag in stride(from: shortestPeriod, through: sheet.width - shortestPeriod, by: 1) {
        var total = 0.0
        var count = 0
        for x in stride(from: 0, to: sheet.width - lag, by: 7) {
            total += difference(sheet, x, x + lag, rows: rows)
            count += 1
        }
        let cost = total / Double(count)
        curve.append((lag, cost))
        if cost < best.cost { best = (cost, lag) }
    }

    let neighbours = curve.filter { abs($0.0 - best.lag) <= 12 && $0.0 != best.lag }
    let margin = (neighbours.map(\.1).reduce(0, +) / Double(neighbours.count)) - best.cost
    print("  period \(best.lag)px  (self-difference \(fmt(best.cost)),"
        + " \(fmt(margin)) better than its neighbours)")
    return best.lag
}

/// Which offset joins most cleanly at that period — and what the worst one
/// would have cost, because the gap between them is the whole reason this is
/// measured rather than picked.
private func offset(in sheet: Bitmap, period: Int, rows: [Int]) -> Int {
    var scores: [(x: Int, cost: Double)] = []
    for x in stride(from: joinWidth, to: sheet.width - period - joinWidth, by: 1) {
        var total = 0.0
        for k in -joinWidth...joinWidth {
            total += difference(sheet, x + k, x + period + k, rows: rows)
        }
        scores.append((x, total / Double(joinWidth * 2 + 1)))
    }
    let best = scores.min { $0.cost < $1.cost }!
    let worst = scores.max { $0.cost < $1.cost }!
    print("  offset \(best.x)px  (join \(fmt(best.cost)); the worst offset,"
        + " \(worst.x), would have cost \(fmt(worst.cost)))")
    return best.x
}

// MARK: - Repairing the sky

/// Eases between two thresholds, flat at both ends.
private func ramp(_ value: Int, from low: Int, to high: Int) -> Double {
    if value <= low { return 0 }
    if value >= high { return 1 }
    let t = Double(value - low) / Double(high - low)
    return t * t * (3 - 2 * t)
}

/// Puts the sky back to the gradient it is supposed to be.
///
/// The painting arrived with ghosts in it — cloud-shaped patches of very
/// slightly wrong blue where shapes were painted and then covered over, a few
/// warmer blotches, and faint horizontal banding. None of it is more than about
/// six values out of 255, which is invisible in a thumbnail and perfectly
/// visible in the game: the sky is an enormous flat area, a soft edge across
/// one reads instantly, and here it also drifts slowly past.
///
/// What makes them removable is that the real sky has no horizontal variation
/// at all. It is a vertical gradient and nothing else, so every row has exactly
/// one correct colour and anything that isn't it is either a cloud or a
/// mistake. Those two are far apart — see `skyBlemish` and `skyCloud` — so the
/// blemishes go back to the gradient while the clouds, including the soft edges
/// that would show any heavy-handedness immediately, are left alone.
///
/// It only ever looks *up*: each column is repaired above its own horizon, so
/// nothing here can reach the hills.
private func flattenSky(_ crop: inout Bitmap) -> (repaired: Int, worst: Int) {
    // Where the sky stops, column by column. Cloud is still sky for this
    // purpose — what ends it is the blue going out of the picture.
    var horizon = [Int](repeating: 0, count: crop.width)
    for x in 0..<crop.width {
        var y = 0
        while y < crop.height, crop.pixels[crop.offset(x, y) + 2] >= 200 { y += 1 }
        horizon[x] = y
    }
    let deepest = horizon.max() ?? 0

    // The gradient, read off the painting one row at a time and then smoothed.
    var readings: [[Int]] = []
    for y in 0..<deepest {
        var samples: [[Int]] = []
        for x in stride(from: 0, to: crop.width, by: 3) where y < horizon[x] {
            let o = crop.offset(x, y)
            let colour = [Int(crop.pixels[o]), Int(crop.pixels[o + 1]), Int(crop.pixels[o + 2])]
            if colour[2] > 230, colour[0] < 190 { samples.append(colour) }
        }
        guard samples.count >= 20 else {
            readings.append(readings.last ?? [101, 187, 251])
            continue
        }
        readings.append((0..<3).map { channel in
            samples.map { $0[channel] }.sorted()[samples.count / 2]
        })
    }

    let gradient = readings.indices.map { y -> [Int] in
        let low = max(0, y - gradientSmoothing)
        let high = min(readings.count - 1, y + gradientSmoothing)
        return (0..<3).map { channel in
            (low...high).map { readings[$0][channel] }.reduce(0, +) / (high - low + 1)
        }
    }

    var repaired = 0
    var worst = 0
    for x in 0..<crop.width {
        for y in 0..<min(horizon[x], gradient.count) {
            let o = crop.offset(x, y)
            let sky = gradient[y]
            let distance = (0..<3).map { abs(Int(crop.pixels[o + $0]) - sky[$0]) }.max()!
            let keep = ramp(distance, from: skyBlemish, to: skyCloud)
            guard keep < 1 else { continue }
            // Counted by how far each pixel actually moved, not by how far it
            // started out: a cloud's outermost pixel is a long way from the sky
            // and is deliberately barely touched, and counting those would make
            // the repair look enormous when it is a few values on a blemish.
            var moved = 0
            for channel in 0..<3 {
                let was = Double(crop.pixels[o + channel])
                let to = Double(sky[channel])
                let now = max(0, min(255, Int((to + (was - to) * keep).rounded())))
                moved = max(moved, abs(now - Int(crop.pixels[o + channel])))
                crop.pixels[o + channel] = UInt8(now)
            }
            if moved > 0 { repaired += 1; worst = max(worst, moved) }
        }
    }
    return (repaired, worst)
}

// MARK: - Finding the rows

/// The top of the bright grass, which is the ground Benny runs on.
///
/// Taken as the median across the crop rather than the highest or the lowest:
/// the strip is drawn with tufts poking out of it, and the line the scene wants
/// is the one the turf actually sits at, not the tip of the tallest blade.
private func grassLine(in crop: Bitmap) -> Int {
    var tops: [Int] = []
    for x in stride(from: 0, to: crop.width, by: 7) {
        for y in (crop.height / 3)..<crop.height {
            let o = crop.offset(x, y)
            let r = Int(crop.pixels[o]), g = Int(crop.pixels[o + 1]), b = Int(crop.pixels[o + 2])
            if b < 70 && g > 150 && r > 95 { tops.append(y); break }
        }
    }
    tops.sort()
    return tops[tops.count / 2]
}

/// The lip of the cut earth, which is the far edge of the grass.
///
/// With the grass line it brackets the strip the game is played on, and what
/// the scene wants is a row *between* them — standing on the near edge puts the
/// bush line at Benny's heels and the whole field in front of him, untouched.
private func earthLine(in crop: Bitmap, below grass: Int) -> Int {
    var tops: [Int] = []
    for x in stride(from: 0, to: crop.width, by: 7) {
        for y in grass..<crop.height {
            let o = crop.offset(x, y)
            let r = Int(crop.pixels[o]), g = Int(crop.pixels[o + 1]), b = Int(crop.pixels[o + 2])
            if r > 70 && g < 100 && b < 50 { tops.append(y); break }
        }
    }
    tops.sort()
    return tops[tops.count / 2]
}

/// The lowest flat row of sky, and so the one the two scrolling layers are
/// split at.
///
/// They travel at different speeds, so whatever row they are cut at has to look
/// the same at every horizontal position — otherwise the join slides against
/// itself and draws a line across the sky. Flat is the requirement, and the sky
/// is the only part of the picture that offers it.
///
/// The *lowest* flat row and not the flattest, which is a different row and the
/// wrong one. Everything above the split drifts slowly and everything below it
/// travels at the speed of the ground, so the split wants to be as low as it
/// can be: taken higher, it hands clouds to the fast layer and they tear past
/// at the speed of the grass. There are flat rows in the gaps *between* clouds
/// and they are a trap — this searches upward from the hills and stops at the
/// first row flat enough to cut, which is the one just above the highest hill.
private func skyLine(in crop: Bitmap, above grass: Int) -> (row: Int, deviation: Int) {
    /// Out of 255. Below this a join cannot be seen; the sky is a gradient, so
    /// insisting on nothing at all would walk the split up into the clouds.
    let flatEnough = 4

    var best = (row: 0, deviation: Int.max)
    for y in stride(from: grass - 150, through: grass / 4, by: -2) {
        var lowest = [255, 255, 255], highest = [0, 0, 0]
        for x in stride(from: 0, to: crop.width, by: 5) {
            let o = crop.offset(x, y)
            for channel in 0..<3 {
                let v = Int(crop.pixels[o + channel])
                lowest[channel] = min(lowest[channel], v)
                highest[channel] = max(highest[channel], v)
            }
        }
        let deviation = (0..<3).map { highest[$0] - lowest[$0] }.max()!
        if deviation <= flatEnough { return (y, deviation) }
        if deviation < best.deviation { best = (y, deviation) }
    }
    return best  // nowhere flat enough; the closest thing to it, and a look at the join
}

// MARK: - The asset catalogue

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

private func fmt(_ value: Double) -> String { String(format: "%.2f", value) }
private func ratio(_ value: Int, of total: Int) -> String {
    String(format: "%.4f", Double(value) / Double(total))
}

// MARK: - Cutting it

print("background")

private let source = load("Art/background_source.png")
print("  source \(source.width)x\(source.height)")

private let rows = interesting
    .flatMap { stride(from: $0.0, through: min($0.1, source.height - 1), by: 6) }
    .map { $0 }

private let tile = period(of: source, rows: rows)
private let left = offset(in: source, period: tile, rows: rows)

private var crop = Bitmap(width: tile, height: source.height,
                          pixels: [UInt8](repeating: 0, count: tile * source.height * 4))
for y in 0..<source.height {
    for x in 0..<tile {
        let from = source.offset(left + x, y)
        let to = crop.offset(x, y)
        for channel in 0..<4 { crop.pixels[to + channel] = source.pixels[from + channel] }
    }
}
private let grass = grassLine(in: crop)
private let earth = earthLine(in: crop, below: grass)
private let sky = skyLine(in: crop, above: grass)

// Measured first, off the untouched painting, and only then repaired — so what
// the scene is staged by never depends on the repair having run.
private let mended = flattenSky(&crop)
print("  sky flattened: \(mended.repaired) pixels moved, none by more than \(mended.worst)/255")

install(crop, named: "bg_scroll")
print("  bg_scroll \(crop.width)x\(crop.height)")
print("  grass line row \(grass), earth line row \(earth) — \(earth - grass) rows of field to stand in")
print("  sky split row \(sky.row) (varies by \(sky.deviation)/255 across it)")

print("""

paste into BackdropArt:

    static let grassLineFraction: CGFloat = \(ratio(grass, of: crop.height))
    static let earthLineFraction: CGFloat = \(ratio(earth, of: crop.height))
    static let skySplitFraction: CGFloat = \(ratio(sky.row, of: crop.height))
    static let aspect: CGFloat = \(ratio(crop.width, of: crop.height))
""")
