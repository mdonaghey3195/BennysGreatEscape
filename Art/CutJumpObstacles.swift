#!/usr/bin/env swift
//
//  CutJumpObstacles.swift
//  Benny's Great Escape
//
//  Turns the five painted props in this directory into the obstacles Benny
//  jumps, and prints the `ObstacleArt.Piece` each one becomes.
//
//      swift Art/CutJumpObstacles.swift
//
//  Run from the repository root. It reads the `*_source.png` files here and
//  writes the catalogue, so rerunning it is idempotent — the sources are never
//  the thing being edited.
//
//  Three jobs.
//
//  **Keying.** These arrived on the same flat cream field the bench and the
//  swingset did, so the keying below is `CutBench`'s, feather, un-compositing,
//  size filter and all. Copied rather than shared because these scripts are
//  standalone by design — the same way `CutBench` copied it from `CutSwingset`.
//
//  **Measuring.** Every piece carries a `solid`: the box or disc that actually
//  ends a run, which is deliberately not the whole drawing. Each of these props
//  has something a player would be furious to die on — a branch stub, fringe
//  leaves, the flare at a stump's foot — and the rules below are written to
//  leave those out. There is a longer note on each above the function that
//  implements it.
//
//  **Sizing.** A jump obstacle's height is solved, not chosen: it comes out of
//  `GameScene.obstacleHeight(_:at:)` so that clearing it leaves the same
//  `ObstacleArt.clearance` whatever the prop's proportions. The `heightRange` in
//  the catalogue is only a clamp around that answer, so this solves it here too
//  — against the same mirrored constants — and prints the clamp rather than
//  leaving it to be worked out by hand.
//
//  **What it does not do is decide.** Each piece also gets an overlay written to
//  `Art/preview/`, with the proposed solid drawn over the keyed art, and those
//  are meant to be looked at. The rules below agreed with the eye on four of
//  these five first time; the log stack they got wrong, and only the picture
//  said so.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tuning

/// How far a pixel may sit from the cream and still be field, when it is
/// *enclosed* by the drawing — the gap under a branch, the hole through a
/// stack. Strict, because there is nothing to stop a loose test here eating
/// into a sunlit cut face from the inside.
private let enclosedTolerance = 30.0

/// The same, for field reached from the border.
///
/// Looser, and it has to be. These paintings carry a soft drop shadow that
/// fades towards the cream without ever arriving, so at the strict tolerance a
/// pale shelf survives under every log and reads as white against turf. A
/// gradient has no natural cut-off, but the flood tells you where the drawing
/// starts by ceasing to grow: on the single log it takes 130044 pixels at 30,
/// 133371 at 50 — the shadow — and then only 663 more at 70. Fifty is that
/// plateau, not a preference.
private let borderTolerance = 50.0

/// The smallest enclosed run of cream that is really a hole in the drawing,
/// rather than a pale highlight within it.
///
/// Size is the only thing that separates them; colour cannot, which is what the
/// bench's rivets taught. But the number matters more than it looks. It was
/// 2000, inherited from the bench, and the single log has a genuine 1801-pixel
/// hole in the crook of its branch — so the field was handed back and the game
/// shipped with a cream blob wedged under the branch.
///
/// Two hundred, against real holes of 1801 and spurious patches of at most 11:
/// eighteen times clear on both sides. `verifyMargin` below refuses to install
/// anything that is not.
private let smallestField = 200

/// How comfortable that separation has to be before the cut is trusted.
///
/// The rail the crook blob went straight past. A threshold sitting in the
/// middle of a wide gap is fine; one with a reclaimed patch pressing up against
/// a kept region means the two populations have merged and the size test no
/// longer distinguishes anything. Fail rather than punch a hole and hope it
/// gets noticed on screen.
private let verifyMargin = 4.0

/// How far the feather reaches in from the keyed edge.
///
/// Deeper than the bench's two. The boundary there was a painted outline
/// against flat cream and genuinely two pixels wide; here the border tolerance
/// is cutting through the tail of a soft shadow, so the last of it wants
/// dissolving rather than a hard edge.
private let featherDepth = 4

/// How much of the widest row a row must carry to count as part of the solid.
///
/// This is what puts the top of a box below the decoration. The single log's
/// branch stub, the wispy top of a bush — they are narrow, so the row they
/// start at carries a small fraction of the drawing's width and is excluded,
/// and the box stops at the shoulder where the mass actually is.
///
/// Six tenths, and the number is less delicate than it looks: on the single log
/// every threshold from a half to seven tenths returns the same row, because
/// there the silhouette genuinely steps. It is worth checking a new prop against
/// its own profile rather than assuming that.
private let solidCoverage = 0.6

/// How high a column's paint must reach, as a fraction of the solid's top, for
/// that column to be inside the solid.
///
/// This is the width rule, and it is deliberately not "how many rows of this
/// column are painted". Coverage across the band is the obvious test and it is
/// wrong for anything stepped: on the stacked logs it read the right-hand end as
/// mostly empty — which it is, since only the lower log is there — and returned
/// a box three quarters of the width that visibly cut the stack in half. What
/// matters is not how much of the column is filled but whether there is anything
/// there tall enough for Benny to hit, which is what this asks.
private let solidReach = 0.5

/// How much the measured width is pulled in afterwards.
///
/// The convention `Piece.solid` already describes: measure off the alpha, then
/// trim a little in Benny's favour. Brushing the last few pixels of a silhouette
/// — the outermost leaves, the lip of a cut face — should not end a run, for the
/// same reason his own trailing paws are outside his body box.
private let widthTrim = 0.95

/// How much a disc is pulled in from its best fit, for the same reason.
private let radiusTrim = 0.96

// MARK: - Mirrors of `Layout` / `ObstacleArt`

/// Everything needed to solve a height the way the game does. Mirrored rather
/// than imported because this is a standalone script; `CutBench` mirrors
/// `clearanceAboveFeet` the same way. If a number here disagrees with
/// `GameScene`, the printed clamp is wrong and the game will quietly clip it.
private let worldScale = 0.8
private let speedScale = worldScale.squareRoot()
private let openingSpeed = 280 * speedScale
private let topSpeed = 440 * speedScale
private let gravity = 9.0 * 150
private let jumpHeight = 180 * worldScale
private let launchVelocity = (2 * gravity * jumpHeight).squareRoot()
private let dogSolid = 125 * worldScale * 0.729
private let underfoot = 12 * worldScale - 7 * worldScale
private let clearance = 0.15
private let heightJitter = 0.04

/// Mirrors `ObstacleArt.sizeTiers` — the speeds a prop may be sized for. Each
/// piece gets one fixed size per tier and steps between them as the world
/// speeds up, so the clamp below has to hold all of them.
private let sizeTiers = [openingSpeed, 290.0, 335.0]

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
///
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

    func near(_ x: Int, _ y: Int, _ tolerance: Double) -> Bool {
        let c = sheet.colour(x, y)
        return abs(c[0] - cream[0]) < tolerance
            && abs(c[1] - cream[1]) < tolerance
            && abs(c[2] - cream[2]) < tolerance
    }

    var background = [Bool](repeating: false, count: count)

    // The outer field, flooded in from the border at the looser tolerance. Done
    // as a flood rather than a plain colour test so that the loosening cannot
    // reach anything enclosed: a pale cut face in the middle of a log is the
    // same colour as the shadow outside it, and only reachability tells them
    // apart.
    var queue: [Int] = []
    for x in 0..<sheet.width {
        for y in [0, sheet.height - 1] where near(x, y, borderTolerance) && !background[index(x, y)] {
            background[index(x, y)] = true
            queue.append(index(x, y))
        }
    }
    for y in 0..<sheet.height {
        for x in [0, sheet.width - 1] where near(x, y, borderTolerance) && !background[index(x, y)] {
            background[index(x, y)] = true
            queue.append(index(x, y))
        }
    }
    var head = 0
    while head < queue.count {
        let pixel = queue[head]; head += 1
        let x = pixel % sheet.width, y = pixel / sheet.width
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, nx < sheet.width, ny >= 0, ny < sheet.height else { continue }
            let next = index(nx, ny)
            guard !background[next], near(nx, ny, borderTolerance) else { continue }
            background[next] = true
            queue.append(next)
        }
    }
    var field = background.filter { $0 }.count
    print("  outer field \(field) pixels, flooded from the border")

    // Then the enclosed field, at the strict tolerance: holes right through the
    // drawing, like the gap in the crook of the single log's branch. A pale
    // highlight looks identical and must not be cut, so these go by size — see
    // `smallestField`, and `verifyMargin` for what happens when that stops
    // separating them.
    var visited = [Bool](repeating: false, count: count)
    var reclaimed = 0
    var largestReclaimed = 0
    var smallestKept = Int.max
    for seed in 0..<count where !background[seed] && !visited[seed]
        && near(seed % sheet.width, seed / sheet.width, enclosedTolerance) {
        var region = [seed]
        visited[seed] = true
        var walk = 0
        while walk < region.count {
            let pixel = region[walk]; walk += 1
            let x = pixel % sheet.width, y = pixel / sheet.width
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < sheet.width, ny >= 0, ny < sheet.height else { continue }
                let next = index(nx, ny)
                guard !background[next], !visited[next], near(nx, ny, enclosedTolerance) else { continue }
                visited[next] = true
                region.append(next)
            }
        }
        if region.count < smallestField {
            reclaimed += region.count
            largestReclaimed = max(largestReclaimed, region.count)
        } else {
            for pixel in region { background[pixel] = true }
            field += region.count
            smallestKept = min(smallestKept, region.count)
        }
    }
    if smallestKept < Int.max || reclaimed > 0 {
        print("  enclosed: kept \(smallestKept == Int.max ? 0 : smallestKept)px at the smallest, "
            + "handed back \(reclaimed)px with \(largestReclaimed) the largest patch")
    }
    // The rail. A gap this wide means the two populations are plainly separate
    // and the threshold's exact value doesn't matter; a narrow one means it
    // does, and nobody should find that out by spotting a blob on screen.
    if smallestKept < Int.max, largestReclaimed > 0,
       Double(smallestKept) < Double(largestReclaimed) * verifyMargin {
        fatalError("""
            enclosed regions are no longer clearly separated by size: the largest \
            patch handed back is \(largestReclaimed)px against \(smallestKept)px for the \
            smallest kept, inside the \(verifyMargin)x margin. One of them is being \
            treated wrongly. Look at the drawing before touching `smallestField`.
            """)
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
        + String(format: " — the closest the drawing itself comes to it is %.0f, against a %.0f reach",
                 closest, borderTolerance * 3.0.squareRoot()))
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

// MARK: - Reading the silhouette

/// How wide the painted silhouette is on each row, top to bottom.
private func rowWidths(of sheet: Bitmap) -> [Int] {
    (0..<sheet.height).map { y in
        var left = sheet.width, right = -1
        for x in 0..<sheet.width where sheet.isPainted(x, y) {
            left = min(left, x); right = max(right, x)
        }
        return right >= left ? right - left + 1 : 0
    }
}

/// How high the paint reaches in each column, measured up from the drawing's
/// foot as a fraction of its height.
private func columnReach(of sheet: Bitmap) -> [Double] {
    (0..<sheet.width).map { x in
        for y in 0..<sheet.height where sheet.isPainted(x, y) {
            return Double(sheet.height - y) / Double(sheet.height)
        }
        return 0
    }
}

/// The box: how high the solid mass reaches and how wide it is.
///
/// The top comes from `solidCoverage` and the width from `solidReach`, each for
/// the reason given where it is defined. The base is left at the drawing's foot
/// rather than measured — for a jump obstacle it makes no difference, since
/// Benny meets it standing on the ground either way, and pinning it at nought
/// is one fewer number that can be wrong.
private func boxSolid(of sheet: Bitmap) -> (top: Double, width: Double, offsetX: Double) {
    let widths = rowWidths(of: sheet)
    let widest = Double(widths.max() ?? 1)
    let topRow = widths.firstIndex { Double($0) >= solidCoverage * widest } ?? 0
    let top = Double(sheet.height - topRow) / Double(sheet.height)

    let reach = columnReach(of: sheet)
    let inside = (0..<sheet.width).filter { reach[$0] >= solidReach * top }
    guard let left = inside.first, let right = inside.last else { return (top, 1, 0) }
    let centre = (Double(left) + Double(right)) / 2
    return (
        top,
        Double(right - left + 1) / Double(sheet.width) * widthTrim,
        (centre - Double(sheet.width - 1) / 2) / Double(sheet.width)
    )
}

/// The disc: a least-squares circle through the upper silhouette.
///
/// Kasa's fit, which is linear and so has no starting guess to get wrong. The
/// outer twelfth of the columns is dropped either side — that is where a bush's
/// loose leaves and a log's end cap sit, and they drag a circle off its centre.
///
/// It also reports whether a disc is the right shape at all, which is not a
/// matter of how well the arc fits. A circle can sit beautifully on the top of
/// something that is nothing like round: the squared hedge fits one to an
/// average error of two hundredths, but at radius 0.88 against a drawing only
/// 1.29 wide the disc would be wider than the picture it is meant to be inside.
/// So `fits` asks whether it would, and the catalogue takes a box when it
/// wouldn't.
private func discSolid(of sheet: Bitmap) -> (radius: Double, centre: Double, rms: Double, fits: Bool) {
    var points: [(Double, Double)] = []
    let margin = sheet.width / 12
    for x in margin..<(sheet.width - margin) {
        for y in 0..<sheet.height where sheet.isPainted(x, y) {
            points.append((Double(x), Double(y)))
            break
        }
    }
    guard points.count > 8 else { return (0, 0, .greatestFiniteMagnitude, false) }

    // Solving the 3x3 normal equations of `2x·cx + 2y·cy + c = x² + y²`.
    var m = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 3)
    for (x, y) in points {
        let row = [2 * x, 2 * y, 1.0]
        let rhs = x * x + y * y
        for i in 0..<3 {
            for j in 0..<3 { m[i][j] += row[i] * row[j] }
            m[i][3] += row[i] * rhs
        }
    }
    for i in 0..<3 {
        var pivot = i
        for r in (i + 1)..<3 where abs(m[r][i]) > abs(m[pivot][i]) { pivot = r }
        m.swapAt(i, pivot)
        guard abs(m[i][i]) > 1e-9 else { return (0, 0, .greatestFiniteMagnitude, false) }
        let d = m[i][i]
        for j in i..<4 { m[i][j] /= d }
        for r in 0..<3 where r != i {
            let f = m[r][i]
            for j in i..<4 { m[r][j] -= f * m[i][j] }
        }
    }
    let cx = m[0][3], cy = m[1][3], c = m[2][3]
    let radius = (c + cx * cx + cy * cy).squareRoot()

    var error = 0.0
    for (x, y) in points {
        error += abs(((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot() - radius)
    }
    let height = Double(sheet.height)
    let aspect = Double(sheet.width) / height
    return (
        radius / height * radiusTrim,
        (height - 1 - cy) / height,
        error / Double(points.count) / height,
        2 * (radius / height * radiusTrim) <= aspect
    )
}

// MARK: - Sizing

/// The shape of a solid, as the jump meets it — the mirror of
/// `ObstacleArt.Solid`.
private enum Shape {
    case box(top: Double, width: Double)
    case disc(radius: Double, centre: Double)

    /// How high Benny's feet must be when the solid's centre is `gap` away, or
    /// nil where it can't reach him. See `ObstacleArt.Solid.clearance` — the
    /// rounding on the disc case is the point of the whole function.
    /// Defined over `-reach ... +reach` and clamped inside it rather than
    /// refusing at the edge — see `ObstacleArt.Solid.clearance` for why that
    /// distinction is worth 14ms.
    func clearance(at gap: Double, height: Double, aspect: Double) -> Double {
        let reach = max(0, abs(gap) - dogSolid / 2)
        switch self {
        case let .box(top, _):
            return height * top
        case let .disc(radius, centre):
            let r = height * radius
            return height * centre + max(0, r * r - reach * reach).squareRoot()
        }
    }

    /// How far either side of centre this can touch Benny, his box included.
    /// Exact, so the end samples land on a box's edge — see the note on
    /// `ObstacleArt.Solid.reach`.
    func reach(height: Double, aspect: Double) -> Double {
        switch self {
        case let .box(_, width): height * aspect * width / 2 + dogSolid / 2
        case let .disc(radius, _): height * radius + dogSolid / 2
        }
    }
}

/// The window the game will give this prop, found exactly as
/// `GameScene.obstacleHeight(_:at:)` finds it: each point of the outline admits
/// an interval of launch times, and the window is their overlap.
private func slack(_ shape: Shape, height: Double, aspect: Double, speed: Double) -> Double {
    let span = shape.reach(height: height, aspect: aspect)
    var earliest = -Double.greatestFiniteMagnitude
    var latest = Double.greatestFiniteMagnitude
    var touches = false
    for step in 0...96 {
        let gap = -span + 2 * span * Double(step) / 96
        let need = shape.clearance(at: gap, height: height, aspect: aspect) - underfoot
        guard need > 0 else { continue }
        touches = true
        let remaining = launchVelocity * launchVelocity - 2 * gravity * need
        guard remaining > 0 else { return -1 }
        let rising = (launchVelocity - remaining.squareRoot()) / gravity
        let falling = (launchVelocity + remaining.squareRoot()) / gravity
        let arrives = -gap / speed
        latest = min(latest, arrives - rising)
        earliest = max(earliest, arrives - falling)
    }
    return touches ? latest - earliest : .greatestFiniteMagnitude
}

/// The height the game will settle on — see the note at the top of the file for
/// why this is worked out here rather than left to be guessed.
private func solvedHeight(_ shape: Shape, aspect: Double, speed: Double) -> Double {
    var low = 10.0, high = 400.0
    guard slack(shape, height: low, aspect: aspect, speed: speed) > clearance else { return low }
    guard slack(shape, height: high, aspect: aspect, speed: speed) < clearance else { return high }
    for _ in 0..<50 {
        let middle = (low + high) / 2
        if slack(shape, height: middle, aspect: aspect, speed: speed) > clearance {
            low = middle
        } else {
            high = middle
        }
    }
    return low
}

// MARK: - The overlay

/// Draws the proposed solid over the keyed art, so it can be looked at.
///
/// The whole reason this script prints a proposal rather than an answer. The
/// rules agreed with the eye on four of these five; on the fifth the picture was
/// the only thing that said otherwise.
private func preview(_ sheet: Bitmap, box: (top: Double, width: Double, offsetX: Double)?,
                     disc: (radius: Double, centre: Double)?, named name: String) {
    var out = sheet
    let w = Double(sheet.width), h = Double(sheet.height)

    // Over cream, so the shape reads against the transparent background too.
    for y in 0..<sheet.height {
        for x in 0..<sheet.width where out.pixels[out.offset(x, y) + 3] < 8 {
            let o = out.offset(x, y)
            out.pixels[o] = 250; out.pixels[o + 1] = 243; out.pixels[o + 2] = 228
            out.pixels[o + 3] = 255
        }
    }
    func stroke(_ x: Int, _ y: Int) {
        guard x >= 0, x < sheet.width, y >= 0, y < sheet.height else { return }
        let o = out.offset(x, y)
        out.pixels[o] = 255; out.pixels[o + 1] = 0; out.pixels[o + 2] = 255; out.pixels[o + 3] = 255
    }
    let pen = max(2, sheet.height / 120)

    if let box {
        let centre = w / 2 + box.offsetX * w
        let left = Int(centre - box.width * w / 2), right = Int(centre + box.width * w / 2)
        let top = Int(h - box.top * h)
        for x in left...max(left, right) {
            for t in 0..<pen { stroke(x, top + t); stroke(x, sheet.height - 1 - t) }
        }
        for y in top...(sheet.height - 1) {
            for t in 0..<pen { stroke(left + t, y); stroke(right - t, y) }
        }
    }
    if let disc {
        let r = disc.radius * h, cy = h - 1 - disc.centre * h, cx = w / 2
        var angle = 0.0
        while angle < 2 * Double.pi {
            for t in 0..<pen {
                stroke(Int(cx + (r - Double(t)) * cos(angle)), Int(cy + (r - Double(t)) * sin(angle)))
            }
            angle += 0.0009
        }
    }
    try? FileManager.default.createDirectory(atPath: "Art/preview", withIntermediateDirectories: true)
    write(out, to: "Art/preview/\(name).png")
}

// MARK: - Doing it

private struct Prop {
    let source: String
    let asset: String
    /// What the piece is called in `ObstacleArt`.
    let name: String
    /// Forced to a box even where a disc would fit — nothing needs it today,
    /// but the disc test is a geometric one and a prop could pass it while
    /// still reading wrong.
    var forceBox = false
}

private let props = [
    Prop(source: "bush", asset: "obstacle_bush", name: "bush"),
    Prop(source: "hedge", asset: "obstacle_hedge", name: "hedge"),
    Prop(source: "log", asset: "obstacle_log", name: "log"),
    Prop(source: "log_stack", asset: "obstacle_log_stack", name: "logStack"),
    Prop(source: "stump", asset: "obstacle_stump", name: "stump"),
]

private func round3(_ v: Double) -> String { String(format: "%.3f", v) }

private var catalogue: [String] = []

for prop in props {
    print(prop.asset)
    let sheet = load("Art/\(prop.source)_source.png")
    print("  source \(sheet.width)x\(sheet.height)")

    let keyed = key(sheet)
    let art = keyed.painted
    let cut = keyed.cropped(
        x: art.left, y: art.top,
        width: art.right - art.left + 1, height: art.bottom - art.top + 1
    )
    install(cut, named: prop.asset)

    let aspect = Double(cut.width) / Double(cut.height)
    let box = boxSolid(of: cut)
    let disc = discSolid(of: cut)
    let useDisc = disc.fits && !prop.forceBox && disc.rms < 0.030

    print("  \(prop.asset) \(cut.width)x\(cut.height), aspect \(round3(aspect))")
    print(String(format: "  box: top %.3f width %.3f offsetX %+.3f", box.top, box.width, box.offsetX))
    print(String(format: "  disc: radius %.3f centre %.3f, average error %.4f of its height — %@",
                 disc.radius, disc.centre, disc.rms,
                 disc.fits ? "fits inside the drawing" : "WIDER than the drawing, so not a disc"))
    print("  -> \(useDisc ? "disc" : "box")")

    preview(cut, box: useDisc ? nil : box,
            disc: useDisc ? (disc.radius, disc.centre) : nil, named: prop.asset)

    let shape: Shape = useDisc
        ? .disc(radius: disc.radius, centre: disc.centre)
        : .box(top: box.top, width: box.width)
    let topPerHeight = useDisc ? disc.centre + disc.radius : box.top
    let heights = sizeTiers.map { solvedHeight(shape, aspect: aspect, speed: $0) }

    // The clamp has to hold every tier plus its jitter without touching it — a
    // bound that binds would quietly flatten a whole tier back onto the clamp.
    let low = (heights[0] * (1 - heightJitter) / worldScale).rounded(.down)
    let high = (heights[heights.count - 1] * (1 + heightJitter) / worldScale).rounded(.up)

    for (tier, height) in zip(sizeTiers, heights) {
        let inside = height * (1 - heightJitter) >= low * worldScale
            && height * (1 + heightJitter) <= high * worldScale
        print(String(format: "  tier %4.0f u/s: %5.1f x %5.1f, solid top %5.1f — window %.0fms there, %.0fms at top speed%@",
                     tier, height, height * aspect, height * topPerHeight - underfoot,
                     slack(shape, height: height, aspect: aspect, speed: tier) * 1000,
                     slack(shape, height: height, aspect: aspect, speed: topSpeed) * 1000,
                     inside ? "" : "   ** OUTSIDE THE CLAMP **"))
    }
    print("")

    let solid = useDisc
        ? "        solid: .disc(radius: \(round3(disc.radius)), centre: \(round3(disc.centre))),"
        : "        solid: .box(width: \(round3(box.width)), height: \(round3(box.top)), base: 0),"
    catalogue.append("""
        static let \(prop.name) = Piece(
            texture: load("\(prop.asset)"),
            heightRange: (\(Int(low)) * Layout.worldScale)...(\(Int(high)) * Layout.worldScale),
    \(solid)
            offsetXFraction: \(round3(useDisc ? 0 : box.offsetX))
        )
    """)
}

print("""
previews written to Art/preview/ — look at them before pasting

paste into ObstacleArt:

\(catalogue.joined(separator: "\n"))
""")
