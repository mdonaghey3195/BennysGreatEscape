#!/usr/bin/env swift
//
//  CutBench.swift
//  Benny's Great Escape
//
//  Turns the painted bench in this directory into the obstacle the game ducks
//  under, and prints the three numbers `ObstacleArt.bench` is built from.
//
//      swift Art/CutBench.swift
//
//  Run from the repository root. It reads `bench_source.png` here and writes
//  the catalogue, so rerunning it is idempotent — the source is never the thing
//  being edited.
//
//  Two jobs.
//
//  **Keying.** Like the swingset, this one arrived on a flat cream field rather
//  than on transparency. Cut away by colour, for the same two reasons: there is
//  no cream in the drawing, and half the field is *enclosed* — the gaps between
//  the backrest slats, and the pane under the seat between the legs — none of
//  which anything working inward from the border would reach. The keying below
//  is `CutSwingset`'s, feather and all, because the problem is the same one.
//
//  **Measuring.** A duck obstacle is sized from `duckClearance`: the seat has
//  to end up 52pt above the turf whatever else is true, so where the seat sits
//  *within the drawing* is what decides how big the whole bench comes out.
//  `ObstacleArt.benchHeight` does that sum; this prints the fraction it needs.
//
//  That fraction is the whole story of this particular repaint. The old bench
//  was backless and its seat sat 70% of the way up the drawing; this one has a
//  back, so the same seat is only 41% up a much taller picture, and the bench
//  is rendered half as tall again to put the seat back where it belongs.
//
//  Which costs something, and it is worth writing down rather than discovering
//  later: the old bench could be *hurdled* instead of ducked, but only at the
//  top scroll speed, where a jump cleared its 59pt box with about 105ms to
//  spare. A back puts the box at 101pt, and 507ms of airtime above that will
//  not cover the 685ms the bench and Benny take to pass each other. So this
//  bench can only be ducked, at any speed, and the game's one either/or
//  obstacle becomes a second swingset in that respect.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tuning

/// How far a pixel may sit from the corner's cream and still be field.
private let backgroundTolerance = 30.0

/// The smallest run of cream-coloured pixels that is really field.
///
/// The background is not quite flat — it carries a vignette, varying by up to
/// 25 levels across the sheet, so the colour test has to be loose enough to
/// swallow that. Loose enough that it also swallows the specular highlight on
/// each leg rivet, which punched a hole clean through it.
///
/// Size tells them apart where colour cannot, and not by a narrow margin: the
/// four real regions here are the field and the three gaps between backrest
/// slats, at 932000, 35000, 10500 and 8400 pixels. The forty spurious ones are
/// every last highlight, and not one reaches 100.
private let smallestField = 2000

/// How far the feather reaches in from the keyed edge. Two pixels: the drawing
/// is anti-aliased over about that, and going further would start dissolving
/// the outline itself.
private let featherDepth = 2

/// How much of the drawing's width is sampled, either side of centre, when
/// looking for the underside of the seat.
///
/// The middle only. The legs splay towards the feet and the armrest-less ends
/// overhang, so the full width never reads as open air even where it is.
private let seatSearchFraction = 0.25

/// How big the bench should come out, in scene units.
///
/// Not a free choice of scale — it can't be. A duck obstacle is sized backwards
/// from `duckClearance`, so with the seat pinned 41.6pt above the turf the
/// render follows from where the seat sits *within* the drawing:
///
///     rendered width  = 40.8 x (source width  / open air under the seat)
///     rendered height = 40.8 x (source height / open air under the seat)
///
/// Which means shrinking the bench is a matter of taking material out of the
/// picture, not of drawing it smaller. As painted it came out 200x100, the same
/// footprint as the swingset — but solid where the swingset is an open frame,
/// and half again as tall as the backless bench it replaced, so it dominated
/// everything around it.
///
/// Width lands exactly. Height cannot: the backrest has a rhythm, and the only
/// heights available are the ones that keep it. See `spliceBack`.
private let targetWidth = 170.0
private let targetHeight = 80.0

/// What `targetWidth` and `targetHeight` are checked against — `ObstacleArt`
/// does the real sum, off `duckClearance`, and this only has to agree with it.
private let clearanceAboveFeet = 52.0 * 0.8 + 6.0 * 0.8 - 7.0 * 0.8

/// The narrowest a gap between backrest slats may be squeezed to, in source
/// pixels. Below this the slats read as one panel and the bench stops being a
/// slatted bench.
private let narrowestGap = 5

/// How wide a stretch either side of a horizontal splice is judged on when
/// choosing where to make it. One column can match by luck; twenty cannot.
private let spliceJudgeWidth = 20

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

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

    func colour(_ x: Int, _ y: Int) -> [Double] {
        let o = offset(x, y)
        return [Double(pixels[o]), Double(pixels[o + 1]), Double(pixels[o + 2])]
    }

    func isPainted(_ x: Int, _ y: Int) -> Bool { pixels[offset(x, y) + 3] > 8 }

    /// The rectangle of the drawing that is actually painted.
    var painted: (left: Int, right: Int, top: Int, bottom: Int) {
        var left = width, right = -1, top = height, bottom = -1
        for y in 0..<height {
            for x in 0..<width where isPainted(x, y) {
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard right >= 0 else { fatalError("nothing painted") }
        return (left, right, top, bottom)
    }

    func cropped(x: Int, y: Int, width w: Int, height h: Int) -> Bitmap {
        var out = Bitmap(width: w, height: h)
        for row in 0..<h {
            let from = offset(x, y + row)
            let to = out.offset(0, row)
            for channel in 0..<(w * 4) { out.pixels[to + channel] = pixels[from + channel] }
        }
        return out
    }
}

private func distance(_ a: [Double], _ b: [Double]) -> Double {
    let dr = a[0] - b[0], dg = a[1] - b[1], db = a[2] - b[2]
    return (dr * dr + dg * dg + db * db).squareRoot()
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

/// Replaces the cream field with transparency.

/// The colour does the deciding and the feather does the finishing. Along the
/// boundary a pixel is part cream and part drawing, and how much of each is
/// recoverable: the compositing that produced it says `seen = a * paint + (1-a)
/// * cream`, so comparing how far the pixel has travelled from cream against
/// how far the drawing beside it has travelled gives `a`, and the premultiplied
/// colour falls out of the same equation. Which is what keeps the outline from
/// coming out either jagged or ringed with cream.
private func key(_ sheet: Bitmap) -> Bitmap {
    let cream = sheet.colour(0, 0)
    let count = sheet.width * sheet.height
    func index(_ x: Int, _ y: Int) -> Int { y * sheet.width + x }

    var background = [Bool](repeating: false, count: count)
    var field = 0
    for y in 0..<sheet.height {
        for x in 0..<sheet.width {
            let c = sheet.colour(x, y)
            guard abs(c[0] - cream[0]) < backgroundTolerance,
                  abs(c[1] - cream[1]) < backgroundTolerance,
                  abs(c[2] - cream[2]) < backgroundTolerance else { continue }
            background[index(x, y)] = true
            field += 1
        }
    }

    // How deep into the drawing each pixel is, up to the feather's reach. Only
    // the first couple of pixels are ever part cream; past that the drawing is
    // itself, and is left exactly as painted.
    // Anything cream-coloured but too small to be field is a highlight inside
    // the drawing, and has to be handed back — see `smallestField`.
    var visited = [Bool](repeating: false, count: count)
    var reclaimed = 0
    var largestReclaimed = 0
    var smallestKept = Int.max
    for seed in 0..<count where background[seed] && !visited[seed] {
        var region = [seed]
        visited[seed] = true
        var head = 0
        while head < region.count {
            let pixel = region[head]; head += 1
            let x = pixel % sheet.width, y = pixel / sheet.width
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < sheet.width, ny >= 0, ny < sheet.height else { continue }
                let next = index(nx, ny)
                guard background[next], !visited[next] else { continue }
                visited[next] = true
                region.append(next)
            }
        }
        if region.count < smallestField {
            for pixel in region { background[pixel] = false }
            reclaimed += region.count
            largestReclaimed = max(largestReclaimed, region.count)
            field -= region.count
        } else {
            smallestKept = min(smallestKept, region.count)
        }
    }
    if reclaimed > 0 {
        print("  handed back \(reclaimed) pixels in patches too small to be field"
            + " — largest was \(largestReclaimed), against \(smallestKept) for the smallest kept")
    }

    var depth = [Int](repeating: featherDepth + 1, count: count)
    for pixel in 0..<count where background[pixel] { depth[pixel] = 0 }
    for _ in 0..<featherDepth {
        var next = depth
        for y in 0..<sheet.height {
            for x in 0..<sheet.width {
                let here = index(x, y)
                guard depth[here] > featherDepth else { continue }
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < sheet.width, ny >= 0, ny < sheet.height else { continue }
                    if depth[index(nx, ny)] <= featherDepth {
                        next[here] = min(next[here], depth[index(nx, ny)] + 1)
                    }
                }
            }
        }
        depth = next
    }

    var closest = Double.greatestFiniteMagnitude
    var out = Bitmap(width: sheet.width, height: sheet.height)
    for y in 0..<sheet.height {
        for x in 0..<sheet.width {
            let here = index(x, y)
            let o = sheet.offset(x, y)
            if background[here] { continue }
            if depth[here] > featherDepth {
                closest = min(closest, distance(sheet.colour(x, y), cream))
                for channel in 0..<3 { out.pixels[o + channel] = sheet.pixels[o + channel] }
                out.pixels[o + 3] = 255
                continue
            }
            // On the boundary. The drawing's own colour is taken from the
            // nearest pixel that isn't, which for an outline this thick is the
            // outline itself — so the alpha comes out of the ink, where the
            // travel from cream is longest and the estimate steadiest.
            let seen = sheet.colour(x, y)
            var travelled = 0.0
            for dy in -3...3 {
                for dx in -3...3 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < sheet.width, ny >= 0, ny < sheet.height,
                          depth[index(nx, ny)] > featherDepth else { continue }
                    travelled = max(travelled, distance(sheet.colour(nx, ny), cream))
                }
            }
            let alpha = travelled > 1 ? min(1.0, distance(seen, cream) / travelled) : 1.0
            out.pixels[o + 3] = UInt8((alpha * 255).rounded())
            for channel in 0..<3 {
                let premultiplied = seen[channel] - (1 - alpha) * cream[channel]
                out.pixels[o + channel] = UInt8(max(0, min(alpha * 255, premultiplied)).rounded())
            }
        }
    }
    print("  keyed \(field) pixels of field"
        + String(format: " — the closest the drawing itself comes to it is %.0f, against a %.0f tolerance",
                 closest, backgroundTolerance * 3.0.squareRoot()))
    return out
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

// MARK: - Reading the drawing

/// The underside of the seat, as a fraction of the drawing's height measured up
/// from its feet — `ObstacleArt.benchUnderseat`.
///
/// Found as the open air between the legs: scanning up the middle of the
/// drawing from the bottom, the first row carrying paint is the seat's
/// underside. The middle only, for the reason `seatSearchFraction` gives.
private func underseatFraction(of sheet: Bitmap) -> (fraction: Double, row: Int) {
    let inset = Int(Double(sheet.width) * seatSearchFraction)
    let from = inset, to = sheet.width - 1 - inset
    var y = sheet.height - 1
    while y > 0 {
        var painted = false
        for x in from...to where sheet.isPainted(x, y) { painted = true; break }
        if painted { break }
        y -= 1
    }
    let openAir = sheet.height - 1 - y
    return (Double(openAir) / Double(sheet.height), y)
}

/// How much of the drawing's width the bench actually occupies at the seat —
/// the widest part, and what the physics box is measured against.
private func seatWidthFraction(of sheet: Bitmap, seatRow: Int) -> Double {
    let row = max(0, seatRow - 4)
    var left = sheet.width, right = -1
    for x in 0..<sheet.width where sheet.isPainted(x, row) {
        left = min(left, x); right = max(right, x)
    }
    guard right >= left else { return 1 }
    return Double(right - left + 1) / Double(sheet.width)
}

// MARK: - Taking material out

/// The solid bands across the middle of the drawing, top to bottom — the
/// backrest slats and then the seat.
///
/// Read across the middle only, for the same reason `underseatFraction` is: the
/// legs and the overhanging ends never read as open air even where they are.
private func bands(of sheet: Bitmap) -> [(top: Int, bottom: Int)] {
    let inset = Int(Double(sheet.width) * seatSearchFraction)
    var found: [(Int, Int)] = []
    var start: Int?
    for y in 0..<sheet.height {
        var covered = 0
        for x in inset...(sheet.width - 1 - inset) where sheet.isPainted(x, y) { covered += 1 }
        let solid = Double(covered) / Double(sheet.width - 2 * inset) > 0.5
        if solid, start == nil { start = y }
        if !solid, let s = start { found.append((s, y - 1)); start = nil }
    }
    if let s = start { found.append((s, sheet.height - 1)) }
    return found
}

/// Takes rows out of the backrest until the bench is as near `targetHeight` as
/// its own rhythm allows.
///
/// The back repeats — slat, gap, slat, gap, slat — so whole repeats come out
/// invisibly: what is left rejoins with the spacing it always had. That
/// quantises the height. Between repeats the only give is in the gaps, which
/// can be narrowed but not closed: shut them completely and the slatted back
/// becomes a solid panel, which is a different piece of furniture and not the
/// one that was drawn.
///
/// So this takes whole repeats while they fit, then narrows what is left over,
/// and reports where it actually landed rather than where it was aimed.
private func spliceBack(_ sheet: Bitmap, air: Int) -> Bitmap {
    let solid = bands(of: sheet)
    guard solid.count >= 3 else {
        print("  no backrest rhythm found — leaving the height alone")
        return sheet
    }
    // Everything above the seat is back; the seat is the last band.
    let slats = Array(solid.dropLast())
    let repeatHeight = slats[1].top - slats[0].top
    let wanted = Int((targetHeight * Double(air) / clearanceAboveFeet).rounded())
    var removals: [(from: Int, count: Int)] = []
    var height = sheet.height

    // Whole repeats first, keeping at least two slats so it still reads slatted.
    var slatsOut = 0
    while height - repeatHeight >= wanted, slats.count - slatsOut > 2 {
        removals.append((from: slats[slatsOut].top, count: repeatHeight))
        height -= repeatHeight
        slatsOut += 1
    }

    // Then the gaps, in order, each down to `narrowestGap`.
    var gaps: [(top: Int, height: Int)] = []
    for i in slatsOut..<(solid.count - 1) {
        gaps.append((top: solid[i].bottom + 1, height: solid[i + 1].top - solid[i].bottom - 1))
    }
    for gap in gaps where height > wanted {
        let take = min(gap.height - narrowestGap, height - wanted)
        guard take > 0 else { continue }
        removals.append((from: gap.top, count: take))
        height -= take
    }

    print("  back: \(slatsOut) slat repeat(s) of \(repeatHeight)px out, "
        + "plus \(removals.dropFirst(slatsOut).reduce(0) { $0 + $1.count })px of gap "
        + "— \(sheet.height)px to \(height)px")

    // Rebuild, skipping every removed row.
    var skip = [Bool](repeating: false, count: sheet.height)
    for r in removals {
        for y in r.from..<min(r.from + r.count, sheet.height) { skip[y] = true }
    }
    var out = Bitmap(width: sheet.width, height: height)
    var row = 0
    for y in 0..<sheet.height where !skip[y] {
        guard row < height else { break }
        let from = sheet.offset(0, y), to = out.offset(0, row)
        for channel in 0..<(sheet.width * 4) { out.pixels[to + channel] = sheet.pixels[from + channel] }
        row += 1
    }
    return out
}

/// Takes a band out of the bench's length to hit `targetWidth`.
///
/// Where matters. The slats run uniformly along the bench, so a band out of the
/// middle rejoins invisibly in principle — but the wood is grained, and the
/// legs and their rivets must not be clipped. So rather than picking a column,
/// every candidate is scored on how well the two edges it would leave behind
/// match, and the best is used. One dimension of the same idea the backdrop's
/// layer boundary uses.
private func spliceLength(_ sheet: Bitmap, air: Int) -> Bitmap {
    let wanted = Int((targetWidth * Double(air) / clearanceAboveFeet).rounded())
    let take = sheet.width - wanted
    guard take > 0 else { return sheet }

    // Kept well inside the legs, which are the one thing along here that isn't
    // uniform and mustn't be cut through.
    let from = sheet.width / 4
    let to = sheet.width - sheet.width / 4 - take
    guard to > from else {
        print("  length: no room to splice \(take)px — leaving it alone")
        return sheet
    }

    func mismatch(at cut: Int) -> Double {
        var total = 0.0
        for k in 0..<spliceJudgeWidth {
            let left = cut - spliceJudgeWidth + k
            let right = cut + take + k
            guard left >= 0, right < sheet.width else { return .greatestFiniteMagnitude }
            for y in 0..<sheet.height {
                let a = sheet.offset(left, y), b = sheet.offset(right, y)
                for channel in 0..<4 {
                    total += abs(Double(sheet.pixels[a + channel]) - Double(sheet.pixels[b + channel]))
                }
            }
        }
        return total / Double(spliceJudgeWidth * sheet.height * 4)
    }

    var best = (cost: Double.greatestFiniteMagnitude, cut: from)
    for cut in from...to {
        let cost = mismatch(at: cut)
        if cost < best.cost { best = (cost, cut) }
    }
    print("  length: \(take)px out at x \(best.cut) "
        + String(format: "(the join there costs %.2f, against %.2f at the worst column)",
                 best.cost, (from...to).map(mismatch).max() ?? 0)
        + " — \(sheet.width)px to \(wanted)px")

    var out = Bitmap(width: wanted, height: sheet.height)
    for y in 0..<sheet.height {
        var column = 0
        for x in 0..<sheet.width where x < best.cut || x >= best.cut + take {
            guard column < wanted else { break }
            let f = sheet.offset(x, y), t = out.offset(column, y)
            for channel in 0..<4 { out.pixels[t + channel] = sheet.pixels[f + channel] }
            column += 1
        }
    }
    return out
}

// MARK: - Doing it

print("bench")
private let sheet = load("Art/bench_source.png")
print("  source \(sheet.width)x\(sheet.height)")

private let keyed = key(sheet)
private let art = keyed.painted
private let bench = keyed.cropped(
    x: art.left, y: art.top,
    width: art.right - art.left + 1, height: art.bottom - art.top + 1
)

// The splices are measured against the open air under the seat, which is what
// sets the scale — and neither of them touches it, so it is read once here and
// holds for both.
private let air = bench.height - 1 - underseatFraction(of: bench).row

private let shortened = spliceBack(bench, air: air)
private let trimmed = spliceLength(shortened, air: air)

install(trimmed, named: "obstacle_bench")

private let seat = underseatFraction(of: trimmed)
private let width = seatWidthFraction(of: trimmed, seatRow: seat.row)
private func round3(_ v: Double) -> String { String(format: "%.3f", v) }

private let renderedHeight = clearanceAboveFeet / seat.fraction
private let renderedWidth = renderedHeight * Double(trimmed.width) / Double(trimmed.height)

print("  obstacle_bench \(trimmed.width)x\(trimmed.height)")
print("  seat underside at row \(seat.row); open air below it is "
    + "\(trimmed.height - 1 - seat.row) of \(trimmed.height) rows")
print(String(format: "  renders at %.0f x %.0f scene units (aimed at %.0f x %.0f)",
             renderedWidth, renderedHeight, targetWidth, targetHeight))

print("""

paste into ObstacleArt:

    private static let benchUnderseat: CGFloat = \(round3(seat.fraction))

    solid: .box(width: \(round3(width)), height: 1 - benchUnderseat, base: benchUnderseat),
""")
