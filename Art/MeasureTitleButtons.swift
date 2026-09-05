#!/usr/bin/env swift
//
//  MeasureTitleButtons.swift
//  Benny's Great Escape
//
//  Finds the painted buttons in the title illustration and prints the
//  rectangles `TitleView` lays its tap targets out from.
//
//      swift Art/MeasureTitleButtons.swift
//
//  Run from the repository root. Repainting the title screen is a rerun and a
//  paste rather than a re-measure.
//
//  The buttons live inside the artwork, so SwiftUI has to be told where they
//  are, and it is told in fractions of the painting so the targets track the
//  paint on any screen shape. Typing those fractions in by eye is what this
//  replaces, and the reason it is worth replacing is `PressTint`: a press is
//  answered by darkening the button, and the shadow is drawn to the button's
//  *outer* edge. Measure the bright fill alone and the tint stops short of the
//  outline, leaving a lit rim around a button that is supposed to be pressed —
//  which is exactly the tell that gave the first hand-measured attempt away.
//
//  So `paint` here is the fill *plus* the outline around it, found by walking
//  outward from the fill until the foliage starts.
//
//  Checked against the three buttons of the previous title screen, whose
//  constants had been measured by hand and looked right on a device: this
//  finds SETTINGS to within a pixel on all four sides, ABOUT to within seven,
//  and PLAY to within nine — that last on its right edge alone, which backs
//  onto shadowed dirt rather than foliage and so is the one edge with nothing
//  to stop at. The cross-edge median is what keeps it to nine.
//

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Tuning

private let artwork = "BennysGreatEscape/Assets.xcassets/title_art.imageset/title_art.png"

/// Buttons are in the lower part of the picture. Everything above is sky,
/// foliage, the logo and the dog — and the logo is painted on the same timber
/// as the PLAY button, so it would otherwise come back as a fifth button.
private let searchFrom = 0.60

/// A button has to be at least this wide, as a fraction of the picture, before
/// it is a button rather than a highlight on a leaf.
private let minimumWidth = 0.12

/// …and its fill has to account for this much of its own bounding box. A
/// rounded rectangle nearly fills its box even with the lettering punched out
/// of it; a diagonal branch or a spray of grass does not.
private let minimumFill = 0.62

/// How much of an edge has to be outline before that edge counts as outline
/// rather than the scenery behind it, and how far out it is worth looking, as
/// a fraction of the button's own height.
private let outlineShare = 0.55
private let outlineReach = 0.16

/// How generous the tap target is beyond the paint, as a fraction of the
/// button's own size. The painted buttons are small targets for a thumb, and
/// this is the margin the hand-measured constants already carried.
private let tapMargin = 0.10

// MARK: - Reading the picture

private struct Bitmap {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

    func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let o = offset(x, y)
        return (Int(pixels[o]), Int(pixels[o + 1]), Int(pixels[o + 2]))
    }

    func luminance(_ x: Int, _ y: Int) -> Int {
        let c = rgb(x, y)
        return (299 * c.r + 587 * c.g + 114 * c.b) / 1000
    }
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

// MARK: - What a button is made of

/// The pale stone the small buttons are cut from.
///
/// Bright, and warm without being *only* warm — the blue channel is what tells
/// stone from sunlit bark, which is every bit as bright and red but has almost
/// no blue in it.
private func isStone(_ c: (r: Int, g: Int, b: Int)) -> Bool {
    c.r >= 205 && c.g >= 178 && c.b >= 135 && c.r >= c.g && c.g >= c.b
}

/// The timber the PLAY button is cut from: strongly red over green over blue.
/// Foliage fails it on the first test — grass and leaves have more green than
/// red — and bark fails it on the second, being nowhere near this saturated.
private func isTimber(_ c: (r: Int, g: Int, b: Int)) -> Bool {
    c.r >= 110 && c.r <= 215
        && c.g * 3 < c.r * 2
        && c.b * 3 < c.g * 2
}

private func isButtonPaint(_ c: (r: Int, g: Int, b: Int)) -> Bool {
    isStone(c) || isTimber(c)
}

// MARK: - Finding them

private struct Box {
    var left: Int, top: Int, right: Int, bottom: Int
    var area: Int

    var width: Int { right - left + 1 }
    var height: Int { bottom - top + 1 }
    var fill: Double { Double(area) / Double(width * height) }
}

/// Every run of paint that is joined to itself.
///
/// The lettering is punched out of the stone buttons and sits *inside* them, so
/// it makes holes rather than splitting them; on PLAY the lettering is pale and
/// the button is timber, so both are paint and the whole button comes back as
/// one piece either way.
private func components(in bitmap: Bitmap) -> [Box] {
    let top = Int(Double(bitmap.height) * searchFrom)
    var seen = [Bool](repeating: false, count: bitmap.width * bitmap.height)
    var boxes: [Box] = []

    for y in top..<bitmap.height {
        for x in 0..<bitmap.width {
            let start = y * bitmap.width + x
            if seen[start] || !isButtonPaint(bitmap.rgb(x, y)) { continue }

            var box = Box(left: x, top: y, right: x, bottom: y, area: 0)
            var stack = [(x, y)]
            seen[start] = true

            while let (cx, cy) = stack.popLast() {
                box.area += 1
                box.left = min(box.left, cx)
                box.right = max(box.right, cx)
                box.top = min(box.top, cy)
                box.bottom = max(box.bottom, cy)

                for (nx, ny) in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)] {
                    guard nx >= 0, nx < bitmap.width, ny >= top, ny < bitmap.height else { continue }
                    let index = ny * bitmap.width + nx
                    guard !seen[index], isButtonPaint(bitmap.rgb(nx, ny)) else { continue }
                    seen[index] = true
                    stack.append((nx, ny))
                }
            }
            boxes.append(box)
        }
    }
    return boxes
}

/// Follows the dark outline outward from the fill on all four sides.
///
/// Two things make this harder than looking for dark pixels. The outline is
/// dark, but so is the foliage the buttons sit on — under the ABOUT button
/// there is no gap in brightness between the two at all. What separates them is
/// colour: the outline is a dark *brown* and the foliage a dark *green*, so a
/// pixel is only outline if it is dark and has at least as much red in it as
/// green.
///
/// The second is that an edge is only straight in the middle. Counting along a
/// whole side sweeps the count through the corners, where the edge has already
/// curved away and what is being counted is the scenery past it — which is what
/// makes a majority vote along the side report no outline at all. So the
/// outline is followed along a handful of individual lines across the flat
/// middle instead, and their median taken; one line that runs into the gear
/// icon or a notch in the shading cannot carry it.
///
/// The four sides are then reduced to a single stroke the same way. The artist
/// drew one outline of one width around each button, so the four should agree —
/// and where one of them runs away into shadowed dirt, as the right of PLAY
/// does, the median is the three that didn't.
private func grownThroughOutline(_ box: Box, in bitmap: Bitmap) -> (box: Box, growths: [Int]) {
    let reach = max(2, Int(Double(box.height) * outlineReach))

    /// Still on the button rather than out in the park.
    ///
    /// Not a darkness test, which was the first thing tried and does not work:
    /// the shaded rim is lit by the same sun as everything else and runs from
    /// about 100 to about 150 depending on which side of which button it is on,
    /// so any cutoff that keeps all of it also keeps half the undergrowth.
    ///
    /// What is reliable is the thing being stopped at. The buttons sit on
    /// grass and leaves, and foliage is the only thing around them with more
    /// green in it than red — the outline is dark brown, the rim is mid brown,
    /// the fill is pale or timber, and none of them are green.
    func isOutline(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, x < bitmap.width, y >= 0, y < bitmap.height else { return false }
        let c = bitmap.rgb(x, y)
        guard c.g <= c.r else { return false }
        // And stop if the gap has been walked clear across into the next
        // button along.
        return !isButtonPaint(c)
    }

    func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        return sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2] + 1) / 2
    }

    /// Where the outline stops, walked out from `edge` along one line.
    func run(_ outline: (Int) -> Bool) -> Int {
        var distance = 0
        while distance < reach, outline(distance + 1) { distance += 1 }
        return distance
    }

    /// Five lines across the middle third of a side.
    func lines(from low: Int, to high: Int) -> [Int] {
        let span = high - low
        return (1...5).map { low + span / 3 + span * $0 / 15 }
    }

    let growths = [
        median(lines(from: box.left, to: box.right).map { x in
            run { isOutline(x, box.top - $0) }
        }),
        median(lines(from: box.left, to: box.right).map { x in
            run { isOutline(x, box.bottom + $0) }
        }),
        median(lines(from: box.top, to: box.bottom).map { y in
            run { isOutline(box.left - $0, y) }
        }),
        median(lines(from: box.top, to: box.bottom).map { y in
            run { isOutline(box.right + $0, y) }
        }),
    ]
    let stroke = median(growths)

    return (Box(left: box.left - stroke, top: box.top - stroke,
                right: box.right + stroke, bottom: box.bottom + stroke,
                area: box.area), growths)
}

/// How round the corners are, as a fraction of the button's height.
///
/// A rounded rectangle's top row spans from `left + radius` to `right - radius`,
/// and that inset shrinks to nothing by the time the corner has finished
/// curving. So the radius is simply how far down the side has to be followed
/// before it reaches the button's full width.
private func cornerRadius(_ box: Box, in bitmap: Bitmap) -> Double {
    for dy in 0..<box.height {
        let y = box.top + dy
        guard let first = (box.left...box.right).first(where: { isButtonPaint(bitmap.rgb($0, y)) })
        else { continue }
        if first - box.left <= 1 { return Double(dy) / Double(box.height) }
    }
    return 0.5
}

// MARK: - Measuring

private let art = load(artwork)

private let buttons = components(in: art)
    .filter {
        Double($0.width) / Double(art.width) >= minimumWidth
            && $0.height >= art.height / 80
            && $0.fill >= minimumFill
    }
    .sorted { $0.area > $1.area }

guard !buttons.isEmpty else { fatalError("found no buttons in \(artwork)") }

/// Reading order: down the picture, and left to right across a shared row.
/// Two buttons are on the same row when they overlap vertically at all, which
/// on a title screen laid out in rows they either do completely or not at all.
private let ordered = buttons.sorted { a, b in
    let sameRow = a.top <= b.bottom && b.top <= a.bottom
    return sameRow ? a.left < b.left : a.top < b.top
}

private func ratio(_ value: Int, of total: Int) -> String {
    String(format: "%.3f", Double(value) / Double(total))
}

print("\(artwork) — \(art.width)x\(art.height)")
print("found \(ordered.count) painted buttons\n")

/// Whatever the layout turns out to be, the buttons are named in reading order.
/// Four is the current title screen: PLAY, then LEADERBOARD and SETTINGS side
/// by side, then ABOUT.
private let names = ordered.count == 4
    ? ["play", "leaderboard", "settings", "about"]
    : (0..<ordered.count).map { "button\($0)" }

private var block = ""
for (name, fill) in zip(names, ordered) {
    let (paint, growths) = grownThroughOutline(fill, in: art)
    let radius = cornerRadius(fill, in: art)

    let marginX = Int(Double(paint.width) * tapMargin / 2)
    let marginY = Int(Double(paint.height) * tapMargin / 2)

    print("  \(name): \(paint.width)x\(paint.height) at (\(paint.left), \(paint.top))"
        + " — outline \(growths.map(String.init).joined(separator: "/"))px"
        + " taken as \(fill.left - paint.left), corner \(Int(radius * Double(paint.height)))px")

    block += """

        static let \(name) = Button(
            tap: Rect(x0: \(ratio(paint.left - marginX, of: art.width)), y0: \(ratio(paint.top - marginY, of: art.height)), x1: \(ratio(paint.right + marginX, of: art.width)), y1: \(ratio(paint.bottom + marginY, of: art.height))),
            paint: Rect(x0: \(ratio(paint.left, of: art.width)), y0: \(ratio(paint.top, of: art.height)), x1: \(ratio(paint.right, of: art.width)), y1: \(ratio(paint.bottom, of: art.height))),
            cornerRadius: \(String(format: "%.2f", radius))
        )

    """
}

print("""

paste into TitleView's `Art`:
\(block)
""")
