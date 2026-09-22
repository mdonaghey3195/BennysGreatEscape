#!/usr/bin/env swift
//
//  MakeTileable.swift
//  Benny's Great Escape
//
//  Turns the painted countryside in this directory into a strip that repeats,
//  and writes it out as the source `CropBackground.swift` then cuts.
//
//      swift Art/MakeTileable.swift
//      swift Art/CropBackground.swift
//
//  Run from the repository root, in that order. Only needed for a painting that
//  does not already wrap — if a future one does, `CropBackground` will find its
//  period on its own and this script has nothing to do.
//
//  ## Why this exists
//
//  The world scrolls by laying copies of one repeat end to end, so the backdrop
//  has to wrap into itself. The painting this was written for does not: its last
//  column sits 8.8x further from its first than neighbouring columns normally
//  are, and 40x in the sky, which tiled would draw a vertical line down the
//  screen every few seconds.
//
//  But it does not fail evenly, and that is the whole of the trick here. The
//  *ground* in it already repeats — measured at lag 882, the turf and dirt score
//  2.3x and 2.9x against their own variation, and every row from about four
//  fifths of the way down the turf band is periodic. It is only the sky and the
//  hills, painted as one continuous scene, that do not come round again.
//
//  So the two are treated as what they are — a foreground that repeats and a
//  background that doesn't — and given different periods:
//
//  * **Foreground**, the turf and the dirt: one ground period, repeated. It
//    wraps because the painting already wraps there.
//  * **Background**, the sky, hills and bush line: the same window followed by
//    its own mirror, which wraps exactly because a palindrome always does.
//
//  The mirror is confined to the band that needs it, and the foreground running
//  on half the background's period is what keeps the result from reading as
//  symmetrical — there is no global axis for the eye to catch.
//
//  ## What was tried first
//
//  Cross-fading the seam closes it arithmetically but ghosts: blending a pale
//  hill against sky leaves the hill's edge translucent, a diagonal smudge you
//  cannot unsee. Sliding the hills vertically to meet barely helps — the shapes
//  genuinely differ, it is not an offset. And no choice of seam position gets
//  the hills nearer than 9.4x, with 67 of 168 rows still visibly disagreeing.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tuning

/// The shortest repeat worth believing in the ground, in source pixels. Short
/// enough to find a real one, long enough that a patch of similar dirt can't
/// masquerade as one.
private let shortestGroundPeriod = 400

/// How far a sky pixel has to sit from its row's own colour to be cloud rather
/// than gradient.
///
/// The sky is a pure vertical gradient — measured across this painting, the
/// median departure from a row's median colour is exactly nought — so this only
/// has to clear the dithering. Clouds are 50 to 135 levels out; nothing lives in
/// between.
private let cloudThreshold = 50.0

// MARK: - Bitmap

/// 8-bit RGBA, premultiplied, top-down — the same shape `CropBackground` works
/// in, for the same reason: it is what `CGContext` hands back.
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

private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

// MARK: - Reading the painting

private let source = load("Art/scroll_source.png")
print("tileable background")
print("  source \(source.width)x\(source.height)")

private func rgb(_ b: Bitmap, _ x: Int, _ y: Int) -> (Double, Double, Double) {
    let o = b.offset(x, y)
    return (Double(b.pixels[o]), Double(b.pixels[o + 1]), Double(b.pixels[o + 2]))
}

private func apart(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
    (abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2)) / 3
}

/// The same colour test `CropBackground.grassLine` uses, so "turf" means here
/// exactly what it means there.
private func isTurf(_ x: Int, _ y: Int) -> Bool {
    let (r, g, b) = rgb(source, x, y)
    return b < 70 && g > 150 && r > 95
}

/// The top of the bright turf.
///
/// The same median-across-columns reading `CropBackground.grassLine` takes, so
/// the two scripts agree about where the turf starts.
private let turfLine: Int = {
    var tops: [Int] = []
    for x in stride(from: 0, to: source.width, by: 7) {
        for y in (source.height / 3)..<source.height where isTurf(x, y) { tops.append(y); break }
    }
    tops.sort()
    return tops[tops.count / 2]
}()

/// How unalike two columns are over a range of rows.
private func columnDifference(_ a: Int, _ b: Int, rows: Range<Int>) -> Double {
    var total = 0.0
    for y in rows { total += apart(rgb(source, a, y), rgb(source, b, y)) }
    return total / Double(rows.count)
}

/// The ordinary column-to-column variation over a range of rows — what any
/// seam has to be judged against, since a hard join in flat sky shows at a
/// fraction of what the same figure means in busy dirt.
private func ordinaryVariation(rows: Range<Int>) -> Double {
    var total = 0.0
    for x in 1..<source.width { total += columnDifference(x - 1, x, rows: rows) }
    return total / Double(source.width - 1)
}

// MARK: - Where the foreground starts

/// How far the highest blade of turf in a column reaches above the turf line.
///
/// Per column, and contiguously from the line upward — the colour test alone
/// would answer with hill greens light enough to pass for turf, half the
/// painting away from any grass.
private func sprigTop(_ column: Int) -> Int {
    var y = turfLine
    while y > turfLine - 120, isTurf(column, y - 1) { y -= 1 }
    return y
}

/// The highest any blade of turf reaches anywhere.
private let highestSprig: Int = (0..<source.width).map(sprigTop).min() ?? turfLine

private let groundRows = highestSprig..<source.height

/// The lag at which the ground repeats.
///
/// Scored over the turf and the dirt only. The sky and hills are a one-off
/// scene and would drown the signal — which is the entire reason this script
/// exists.
private let groundPeriod: Int = {
    var best = (cost: Double.infinity, lag: 0)
    for lag in stride(from: shortestGroundPeriod, through: source.width - shortestGroundPeriod, by: 1) {
        var total = 0.0
        var count = 0
        for x in stride(from: 0, to: source.width - lag, by: 9) {
            total += columnDifference(x, x + lag, rows: groundRows)
            count += 1
        }
        let cost = total / Double(count)
        if cost < best.cost { best = (cost, lag) }
    }
    return best.lag
}()

private let groundNormal = ordinaryVariation(rows: groundRows)
print("  turf line row \(turfLine); the tallest sprig reaches row \(highestSprig)")
print("  ground repeats every \(groundPeriod)px "
    + "(\(fmt(columnDifference(0, groundPeriod, rows: groundRows) / groundNormal))x its own variation)")

// MARK: - Where to cut

/// Which columns carry cloud, so the cut can be put between them.
///
/// The sky is a flat vertical gradient, so a column's own departure from its
/// row's median is cloud and nothing else. Cutting in clear sky is what lets the
/// clouds be left alone entirely rather than faded or dropped.
private let skyRows = 0..<(turfLine / 2)
private let cloudColumn: [Bool] = {
    var medians: [(Double, Double, Double)] = []
    for y in skyRows {
        var reds: [Double] = [], greens: [Double] = [], blues: [Double] = []
        for x in stride(from: 0, to: source.width, by: 5) {
            let c = rgb(source, x, y); reds.append(c.0); greens.append(c.1); blues.append(c.2)
        }
        reds.sort(); greens.sort(); blues.sort()
        medians.append((reds[reds.count / 2], greens[greens.count / 2], blues[blues.count / 2]))
    }
    return (0..<source.width).map { x in
        skyRows.contains { y in
            let c = rgb(source, x, y), m = medians[y - skyRows.lowerBound]
            return max(abs(c.0 - m.0), abs(c.1 - m.1), abs(c.2 - m.2)) > cloudThreshold
        }
    }
}()

/// Where to take the one ground period from: a window whose two ends both land
/// in clear sky, and whose ground joins most cleanly.
private let start: Int = {
    var best = (cost: Double.infinity, start: -1)
    for s in 0...(source.width - groundPeriod) {
        let e = s + groundPeriod - 1
        guard !cloudColumn[s], !cloudColumn[e] else { continue }
        let cost = columnDifference(e, s, rows: groundRows)
        if cost < best.cost { best = (cost, s) }
    }
    guard best.start >= 0 else {
        fatalError("no window of \(groundPeriod)px has clear sky at both ends")
    }
    return best.start
}()

print("  cutting at x \(start), both ends in clear sky; "
    + "ground joins at \(fmt(columnDifference(start + groundPeriod - 1, start, rows: groundRows) / groundNormal))x")

// MARK: - Where the two layers meet

/// The row the tile switches from mirrored background to repeated foreground,
/// column by column.
///
/// A straight row will not do, and that is worth stating plainly because it
/// looks like it should. In the tile's second half everything above the join
/// comes from mirrored columns and everything below from repeated ones, so at
/// the join the bush line jumps from one part of the painting to another. Drawn
/// straight it slices the tops off the bushes in one flat line — measured at
/// seven times the change the painting makes between any other pair of rows,
/// and every candidate row from 400 down to 455 is between six and twenty-three
/// times. There is nowhere flat enough to hide a straight cut: the only rows in
/// this painting uniform enough are up in the sky.
///
/// So the join is allowed to bend. For each column it costs what the mirrored
/// row above disagrees with the repeated row below, and the cheapest path
/// across is the one that threads between the bushes rather than through them —
/// the usual answer to this in texture work, and a good fit for foliage, which
/// is blobby enough to hide a join that follows it.
///
/// It may never sit below a blade of turf in *either* mapping: below the join
/// is foreground, so a sprig below it keeps its own turf, while one above it
/// would be mirrored away from the turf it grows out of and left in mid-air.
private let boundary: [Int] = {
    let ceiling = (0..<groundPeriod).map { x in
        min(sprigTop(start + x), sprigTop(start + groundPeriod - 1 - x))
    }
    let lowest = ceiling.min() ?? turfLine
    let top = max(1, lowest - 30)
    let rows = Array(top...turfLine)

    /// What a viewer sees at the join: the mirrored row above, sitting directly
    /// on the repeated row below.
    func cost(_ x: Int, _ y: Int) -> Double {
        guard y <= ceiling[x] else { return .infinity }
        return apart(rgb(source, start + groundPeriod - 1 - x, y - 1), rgb(source, start + x, y))
    }

    var best = rows.map { cost(0, $0) }
    var cameFrom = [[Int]](repeating: [Int](repeating: 0, count: rows.count), count: groundPeriod)
    for x in 1..<groundPeriod {
        var next = [Double](repeating: .infinity, count: rows.count)
        for i in 0..<rows.count {
            var from = i
            var cheapest = best[i]
            if i + 1 < rows.count, best[i + 1] < cheapest { cheapest = best[i + 1]; from = i + 1 }
            if i > 0, best[i - 1] < cheapest { cheapest = best[i - 1]; from = i - 1 }
            cameFrom[x][i] = from
            next[i] = cheapest + cost(x, rows[i])
        }
        best = next
    }

    var i = best.enumerated().min { $0.element < $1.element }?.offset ?? 0
    var path = [Int](repeating: 0, count: groundPeriod)
    for x in stride(from: groundPeriod - 1, through: 0, by: -1) {
        path[x] = rows[i]
        if x > 0 { i = cameFrom[x][i] }
    }
    return path
}()

private let joinCost = (0..<groundPeriod)
    .map { apart(rgb(source, start + groundPeriod - 1 - $0, boundary[$0] - 1), rgb(source, start + $0, boundary[$0])) }
    .reduce(0, +) / Double(groundPeriod)
private let joinNormal = (max(1, (boundary.min() ?? turfLine) - 4)...turfLine)
    .map { y in (0..<source.width).map { apart(rgb(source, $0, y), rgb(source, $0, y - 1)) }.reduce(0, +) / Double(source.width) }
    .reduce(0, +) / Double(turfLine - max(1, (boundary.min() ?? turfLine) - 4) + 1)

print("  layers meet between rows \(boundary.min() ?? 0) and \(boundary.max() ?? 0), "
    + "joining at \(fmt(joinCost / joinNormal))x the painting's own row-to-row change")

// MARK: - Building it

private let tileWidth = groundPeriod * 2
private var tile = Bitmap(width: tileWidth, height: source.height,
                          pixels: [UInt8](repeating: 0, count: tileWidth * source.height * 4))

for y in 0..<source.height {
    for x in 0..<tileWidth {
        let half = x / groundPeriod
        let within = x % groundPeriod
        // Above the join the painting never comes round, so the second half is
        // the first one mirrored — a palindrome wraps whatever it contains.
        // Below, the painting already repeats, so the period is laid down
        // twice. The join bends to follow the foliage; see `boundary`.
        let mirrored = y < boundary[within]
        let read = (mirrored && half == 1) ? (groundPeriod - 1 - within) : within
        let from = source.offset(start + read, y)
        let to = tile.offset(x, y)
        for channel in 0..<4 { tile.pixels[to + channel] = source.pixels[from + channel] }
    }
}

write(tile, to: "Art/background_source.png")
print("  background_source \(tile.width)x\(tile.height) — mirrored above the join, repeated below")
print("  now run: swift Art/CropBackground.swift")
