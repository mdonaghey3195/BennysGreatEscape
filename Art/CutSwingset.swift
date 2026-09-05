#!/usr/bin/env swift
//
//  CutSwingset.swift
//  Benny's Great Escape
//
//  Turns the painted swingset in this directory into the two assets the game
//  hangs together: the A-frame, and one swing to hang off it twice.
//
//      swift Art/CutSwingset.swift
//
//  Run from the repository root. It reads `swingset_source.png` here and writes
//  the catalogue, so rerunning it is idempotent — the source is never the thing
//  being edited.
//
//  Three jobs, and the middle one is the reason this exists at all.
//
//  **Keying.** Alone among the obstacle drawings this one arrived on a flat
//  cream field rather than on transparency, so the background has to be cut
//  away. By colour, which is safe here and wouldn't be everywhere: there is no
//  cream *in* the drawing, the nearest it comes being the pale highlight along
//  the top of the crossbar, and the margin between the two is printed so that a
//  repaint that closed it would say so rather than dissolve. It also has to be
//  by colour — half the background here is enclosed, the pane between each
//  swing's chains and the hole through every chain link, none of which anything
//  working inward from the border would ever reach.
//
//  **Shortening the chains.** A duck obstacle is sized from `duckClearance`:
//  whatever else is true, the seat has to end up 52pt above the turf. So where
//  the seat sits *within the drawing* decides how big the whole swingset comes
//  out, and it sits low — 25.7% up, which would render the frame at 446x198pt
//  on a 400pt-wide scene. Wider than the screen, and close enough to the next
//  obstacle at the spawn floor that the two would visibly touch.
//
//  Nothing about the drawing is wrong; there is just more chain in it than the
//  game has room for. So a band is spliced out of the free-hanging run and the
//  seats come up to meet the bar, until the frame lands at `targetHeight`. The
//  join is invisible because a chain is the same all the way down — which is
//  also why the band is taken from between the bracket and the seat hook, the
//  one stretch where that is true.
//
//  **Cutting the swings off the frame.** They are drawn as part of the picture
//  and have to become their own sprite, so that in game they can rock on the
//  bar while the frame stands still. One cut serves both: the two swings are
//  the same drawing, and `ObstacleArt` hangs the one texture at both hangers.
//
//  Everything the game needs to place any of this — the pivot, the hangers, the
//  fraction of the drawing that is open air under the seat — is measured here
//  and printed at the end, in the fractions `ObstacleArt` states them in.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tuning

/// The three numbers `Layout` uses to size a duck obstacle, restated because a
/// standalone script can't see them: how much room a sliding dog needs, how far
/// this drawing sinks into the turf, and how deep Benny himself is planted.
///
/// They are here only to say how tall the finished swingset will be, which is
/// what `targetHeight` is checked against — `ObstacleArt` does the real sum, off
/// `Layout`, so these being stale can mis-size the *art* but can never put the
/// seat at the wrong height in the game.
private let duckClearance = 52.0
private let obstacleSink = 6.0
private let dogPlantDepth = 7.0

/// How tall the swingset should stand, in scene points, and so how much chain
/// gets spliced out to get there.
///
/// Chosen against the two obstacles either side of it. The bench is 73pt tall
/// and 217 wide, and its solid box plus Benny comes to about 330 — which is the
/// number `Layout.slideDistance` is tuned against. At 110 the swingset reads as
/// clearly the bigger of the two things you duck, still fits a 400pt scene with
/// room either side, and its box plus Benny comes to about 250: the bench stays
/// the widest thing Benny slides under, so the slide's tuning is untouched.
private let targetHeight = 110.0

/// How far a colour can drift from the corner of the source and still be called
/// background. Tight, because the drawing has no cream in it — the closest it
/// comes is the pale highlight along the top of the crossbar, and that is a
/// long way off.
private let backgroundTolerance = 30.0

/// How far the feather reaches in from the keyed edge. Two pixels: the drawing
/// is anti-aliased over about that, and going further would start dissolving
/// the outline itself.
private let featherDepth = 2

/// A column still carrying paint this close to the feet belongs to a leg. It is
/// how the legs are told from the swings without either being typed in: the
/// swings hang free and stop at the seat, the legs run to the ground.
private let legFoothold = 70

/// The widest a chain is allowed to be. Above it the run has stopped being
/// chain and become the seat's hook, which is where the splice has to stop.
private let widestChain = 40

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

// MARK: - Cutting the background away

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

// MARK: - Reading the drawing

/// The underside of the crossbar, and so the line the swings pivot on.
///
/// Found as the first row that stops being solid bar — having first found where
/// the bar starts being solid, because its own top row is a soft edge and would
/// otherwise be mistaken for its bottom one.
///
/// Measured across the middle of the drawing only: the legs splay out past the
/// bar's ends further down, so the full width would never read as covered.
private func barUnderside(of sheet: Bitmap, _ art: (left: Int, right: Int, top: Int, bottom: Int)) -> Int {
    let from = art.left + (art.right - art.left) / 4
    let to = art.right - (art.right - art.left) / 4
    var solid = false
    for y in art.top...art.bottom {
        var painted = 0
        for x in from...to where sheet.isPainted(x, y) { painted += 1 }
        let covered = painted * 10 >= (to - from) * 9
        if covered { solid = true } else if solid { return y }
    }
    fatalError("can't find the bottom of the crossbar")
}

/// The stretch of the drawing the swings hang in, which is everything between
/// the legs.
///
/// The legs are the columns still painted near the feet — the swings stop at
/// the seat, a long way up — so the innermost of those on each side is the
/// edge of the strip, and everything in between belongs to the swings.
private func swingStrip(of sheet: Bitmap, _ art: (left: Int, right: Int, top: Int, bottom: Int)) -> ClosedRange<Int> {
    let middle = (art.left + art.right) / 2
    var left = art.left, right = art.right
    for x in art.left...art.right {
        var footed = false
        for y in (art.bottom - legFoothold)...art.bottom where sheet.isPainted(x, y) { footed = true }
        guard footed else { continue }
        if x < middle { left = max(left, x) } else { right = min(right, x) }
    }
    guard left + 2 < right else { fatalError("the legs meet — can't find the swings between them") }
    return (left + 1)...(right - 1)
}

/// The columns each swing occupies. Two groups, split at the gap between them.
private func swingGroups(of sheet: Bitmap, strip: ClosedRange<Int>, from top: Int, to bottom: Int) -> [ClosedRange<Int>] {
    var groups: [ClosedRange<Int>] = []
    var start: Int?
    var last = strip.lowerBound
    for x in strip {
        var painted = false
        for y in top...bottom where sheet.isPainted(x, y) { painted = true }
        if painted {
            if start == nil { start = x }
            last = x
        } else if let began = start, x - last > 100 {
            // A chain and the seat below it are one swing with clear air
            // between their columns at some rows; only the gap between the two
            // swings is wide enough to mean anything.
            groups.append(began...last)
            start = nil
        }
    }
    if let began = start { groups.append(began...last) }
    return groups
}

/// The lowest painted row in a range of columns — the underside of the seat,
/// which is the whole point: it is what has to land on the clearance line.
private func lowestPainted(in sheet: Bitmap, columns: ClosedRange<Int>, from top: Int, to bottom: Int) -> Int {
    for y in stride(from: bottom, through: top, by: -1) {
        for x in columns where sheet.isPainted(x, y) { return y }
    }
    fatalError("nothing painted in \(columns)")
}

/// Where the free-hanging chain begins and ends: below the bracket at the bar,
/// above the hook at the seat. The band spliced out has to come from inside it,
/// because it is the only stretch that is the same all the way down.
private func chainRun(of sheet: Bitmap, columns: ClosedRange<Int>, from top: Int, to bottom: Int) -> ClosedRange<Int> {
    func widestRun(_ y: Int) -> Int {
        var widest = 0, run = 0
        for x in columns {
            if sheet.isPainted(x, y) { run += 1; widest = max(widest, run) } else { run = 0 }
        }
        return widest
    }
    var began: Int?
    for y in top...bottom {
        let widest = widestRun(y)
        if began == nil, widest <= widestChain { began = y }
        if let start = began, widest > widestChain { return start...(y - 1) }
    }
    fatalError("can't find the free-hanging chain")
}

// MARK: - Shortening the chains

/// Lifts everything below `row` up by `rows`, within the strip the swings hang
/// in. The chain above the join and the chain below it are the same chain, so
/// what is lost is length and nothing else.
private func splice(_ sheet: Bitmap, strip: ClosedRange<Int>, at row: Int, rows: Int, to bottom: Int) -> Bitmap {
    var out = sheet
    for y in row...bottom {
        for x in strip {
            let to = out.offset(x, y)
            if y + rows <= bottom {
                let from = sheet.offset(x, y + rows)
                for channel in 0..<4 { out.pixels[to + channel] = sheet.pixels[from + channel] }
            } else {
                for channel in 0..<4 { out.pixels[to + channel] = 0 }
            }
        }
    }
    return out
}

/// Wipes the swings off the drawing, leaving the frame they hung on.
private func erase(_ sheet: Bitmap, strip: ClosedRange<Int>, from top: Int, to bottom: Int) -> Bitmap {
    var out = sheet
    for y in top...bottom {
        for x in strip {
            let o = out.offset(x, y)
            for channel in 0..<4 { out.pixels[o + channel] = 0 }
        }
    }
    return out
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

// MARK: - Doing it

print("swingset")

private let source = load("Art/swingset_source.png")
print("  source \(source.width)x\(source.height)")

private let keyed = key(source)
private let art = keyed.painted
private let artWidth = art.right - art.left + 1
private let artHeight = art.bottom - art.top + 1
print("  drawing \(artWidth)x\(artHeight) at \(art.left),\(art.top)"
    + String(format: " — aspect %.3f", Double(artWidth) / Double(artHeight)))

private let bar = barUnderside(of: keyed, art)
private let strip = swingStrip(of: keyed, art)
private let groups = swingGroups(of: keyed, strip: strip, from: bar, to: art.bottom)
guard groups.count == 2 else {
    fatalError("expected two swings between the legs, found \(groups.count): \(groups)")
}
private let seatWas = lowestPainted(in: keyed, columns: strip, from: bar, to: art.bottom)
print("  crossbar underside at row \(bar), swings hang in columns \(strip.lowerBound)…\(strip.upperBound)")
print("  swings at \(groups.map { "\($0.lowerBound)…\($0.upperBound)" }.joined(separator: " and "))"
    + ", seats bottom out at row \(seatWas)")
print(String(format: "  as drawn the seat is %.3f up the drawing — a %.0f x %.0f pt swingset",
             Double(art.bottom - seatWas) / Double(artHeight),
             (duckClearance + obstacleSink - dogPlantDepth) * Double(artHeight) / Double(art.bottom - seatWas)
                * Double(artWidth) / Double(artHeight),
             (duckClearance + obstacleSink - dogPlantDepth) * Double(artHeight) / Double(art.bottom - seatWas)))

/// How much chain has to go. Solved rather than tried: the seat's height within
/// the drawing *is* the drawing's scale, so asking for a `targetHeight` frame is
/// asking for the seat to sit a particular fraction up it, and the difference
/// between that and where it sits now is the band to remove.
private let wantedUnderbar = (duckClearance + obstacleSink - dogPlantDepth) / targetHeight
private let trim = Int((wantedUnderbar * Double(artHeight) - Double(art.bottom - seatWas)).rounded())
guard trim > 0 else { fatalError("the seat is already high enough — nothing to splice") }

private let chain = chainRun(of: keyed, columns: groups[0], from: bar, to: seatWas)
guard chain.count > trim + 20 else {
    fatalError("only \(chain.count) rows of free chain, and \(trim) have to come out")
}
/// Centred in the free chain, so there is as much of it either side of the join
/// as there can be.
private let spliceRow = chain.lowerBound + (chain.count - trim) / 2
print("  free chain runs rows \(chain.lowerBound)…\(chain.upperBound)"
    + " — taking \(trim) rows out from \(spliceRow)")

private let spliced = splice(keyed, strip: strip, at: spliceRow, rows: trim, to: art.bottom)
private let seat = lowestPainted(in: spliced, columns: strip, from: bar, to: art.bottom)

// The frame keeps the drawing as painted: the splice only ever moved things
// hanging inside the strip, and the legs and bar that bound the drawing are
// outside it.
private let frame = erase(keyed, strip: strip, from: bar, to: art.bottom)
    .cropped(x: art.left, y: art.top, width: artWidth, height: artHeight)
install(frame, named: "obstacle_swingset_frame")

// One swing, cut with its top edge on the pivot rather than on its own paint,
// so that hanging it at the bar is a matter of putting its top edge there.
private let cut = groups[0]
private let swing = spliced
    .cropped(x: cut.lowerBound, y: bar, width: cut.count, height: seat - bar + 1)
install(swing, named: "obstacle_swingset_swing")

// MARK: - What ObstacleArt needs

private let underbar = Double(art.bottom - seat) / Double(artHeight)
private let height = (duckClearance + obstacleSink - dogPlantDepth) / underbar
private let width = height * Double(artWidth) / Double(artHeight)

/// The solid mass, measured where Benny actually meets it. He is 41pt tall
/// ducked and the box starts at 52, so the only part of this drawing his box
/// can ever touch is the seats themselves — not the chains above them.
private let seatRows = (seat - swing.height / 4)...seat
private var seatLeft = art.right, seatRight = art.left
for y in seatRows {
    for x in strip where spliced.isPainted(x, y) {
        seatLeft = min(seatLeft, x); seatRight = max(seatRight, x)
    }
}

print("")
print("  frame  \(frame.width)x\(frame.height)"
    + String(format: "  aspect %.3f", Double(frame.width) / Double(frame.height)))
print("  swing  \(swing.width)x\(swing.height)"
    + String(format: "  widthFraction %.3f", Double(swing.width) / Double(artWidth)))
print(String(format: "  renders %.0f x %.0f pt", width, height))
print("")
print(String(format: "  swingsetUnderbar   %.3f", underbar))
print(String(format: "  pivotYFraction     %.3f", Double(bar - art.top) / Double(artHeight)))
for (index, group) in groups.enumerated() {
    let centre = Double(group.lowerBound + group.upperBound) / 2
    print(String(format: "  pivotXFraction %d   %+.3f", index + 1,
                 (centre - Double(art.left + art.right) / 2) / Double(artWidth)))
}
print(String(format: "  solid box width    %.3f  (seats span %d…%d)",
             Double(seatRight - seatLeft + 1) / Double(artWidth), seatLeft, seatRight))
print(String(format: "  offsetXFraction    %+.3f",
             (Double(seatLeft + seatRight) / 2 - Double(art.left + art.right) / 2) / Double(artWidth)))
print(String(format: "  box plus Benny     %.0f pt against a %.0f pt slide",
             Double(seatRight - seatLeft + 1) / Double(artWidth) * width + 125, 400.0))
