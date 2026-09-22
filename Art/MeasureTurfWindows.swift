#!/usr/bin/env swift
//
//  MeasureTurfWindows.swift
//  Benny's Great Escape
//
//  Finds where in the scrolling backdrop a cliff gap can be put without turf
//  sprigs ending up stranded over the hole, and prints the one constant
//  `GameScene.cliffSpawnX` steers by.
//
//      swift Art/MeasureTurfWindows.swift
//
//  Run from the repository root. Rerunning after a repaint, or after retuning
//  `Cliff.maxGapWidth`, reprints the constant — so neither is a re-derivation
//  by hand.
//
//  The problem it answers: the gap sprite stops at the turf line, so the real
//  `land` layer shows through the opening. That is what makes the gap look
//  like a hole rather than a patch, but it also means the turf's own sprigs —
//  the tufts drawn poking up out of the strip — show through it, standing in
//  mid-air over nothing. A cliff holds its place against the backdrop for
//  life, so where it lands in the repeat when it spawns is where it stays, and
//  picking that spot is the whole of the fix.
//
//  They are sparse: most columns carry no sprig at all and only a hundredth
//  carry a tall one. But a gap is wide, and it has to clear *every* column it
//  spans, so the windows are few and narrow — and they run out entirely not
//  far above `maxGapWidth`, which is where that number comes from.
//

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Tuning

/// The widest opening the game will ask for — `Cliff.maxGapWidth`.
///
/// Measured at the widest and used for every gap: a narrower one centred on
/// the same spot sits strictly inside the span checked here, so one constant
/// covers the whole range of widths `cliffGapWidth(at:)` produces.
private let gapWidth = 170.0

/// How tall a sprig may be and still be allowed to show over the gap.
///
/// How tall a sprig may be and still be allowed to show over the hole.
///
/// The same two and a half units the original 113-unit gap left showing, which
/// nobody ever objected to. It is what `maxGapWidth` is set against: inside one
/// ground period the longest stretch this clear runs 181 units, and that is the
/// widest gap that can be placed without something standing over it.
private let sprigTolerance = 2.5

/// Mirrors `Layout`. The two row fractions this also needs are not here —
/// they are measured off the sheet below, so this can never disagree with the
/// art it is measuring.
private let standFraction = 0.5
private let sceneHeight = 500.0
private let groundTop = 175.0

// MARK: - Bitmap

/// 8-bit RGBA, premultiplied, top-down — same shape `CropBackground` works in,
/// and for the same reason: it is what `CGContext` hands back.
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

// MARK: - Measuring

private let sheet = load("BennysGreatEscape/Assets.xcassets/bg_scroll.imageset/bg_scroll.png")

/// The same median-across-columns reading `CropBackground` takes, so the rows
/// mean here what they mean there — and measured off the installed sheet, so a
/// repaint cannot leave this script quietly measuring the wrong rows.
private func line(_ from: Int, _ test: (Int, Int) -> Bool) -> Int {
    var tops: [Int] = []
    for x in stride(from: 0, to: sheet.width, by: 7) {
        for y in from..<sheet.height where test(x, y) { tops.append(y); break }
    }
    tops.sort()
    return tops[tops.count / 2]
}

private func isEarth(_ x: Int, _ y: Int) -> Bool {
    let o = sheet.offset(x, y)
    let r = Int(sheet.pixels[o]), g = Int(sheet.pixels[o + 1]), b = Int(sheet.pixels[o + 2])
    return r > 70 && g < 100 && b < 50
}

private let grassRow = line(sheet.height / 3) { isTurf($0, $1) }
private let earthRow = line(grassRow, isEarth)
private let grassLineFraction = Double(grassRow) / Double(sheet.height)
private let earthLineFraction = Double(earthRow) / Double(sheet.height)

/// Scene units per pixel of the sheet, by the same chain `BackdropArt` uses:
/// the crop is drawn tall enough to reach the bottom of the scene from the row
/// the world stands on, and its width follows from its aspect.
private let anchorFraction = grassLineFraction + standFraction * (earthLineFraction - grassLineFraction)
private let drawnHeight = max((sceneHeight - groundTop) / anchorFraction, groundTop / (1 - anchorFraction))
private let tileWidth = drawnHeight * (Double(sheet.width) / Double(sheet.height))
private let unitsPerPixel = tileWidth / Double(sheet.width)

/// The same colour test `CropBackground.grassLine` uses, so "turf" means here
/// exactly what it means there.
private func isTurf(_ x: Int, _ y: Int) -> Bool {
    let o = sheet.offset(x, y)
    let r = Int(sheet.pixels[o]), g = Int(sheet.pixels[o + 1]), b = Int(sheet.pixels[o + 2])
    return b < 70 && g > 150 && r > 95
}

/// How far turf reaches above the turf line in each column — the height of
/// that column's sprig, in pixels, and nought where there isn't one.
private let turfRow = grassRow
private let rise: [Int] = (0..<sheet.width).map { x in
    var y = turfRow
    while y > turfRow - 120, isTurf(x, y - 1) { y -= 1 }
    return turfRow - y
}

private let gapPixels = Int((gapWidth / unitsPerPixel).rounded())
private let tolerancePixels = Int((sprigTolerance / unitsPerPixel).rounded())

/// Every left-edge position a gap of that width fits at, taken round the
/// repeat — the backdrop wraps, so a window is allowed to straddle the join.
private let fits: [Bool] = (0..<sheet.width).map { start in
    (0..<gapPixels).allSatisfy { rise[(start + $0) % sheet.width] <= tolerancePixels }
}

/// Those runs, as (first column, length), with one straddling the join joined
/// back up rather than reported as two.
private func windows() -> [(start: Int, length: Int)] {
    var found: [(start: Int, length: Int)] = []
    var start: Int?
    for x in 0..<sheet.width {
        if fits[x] {
            if start == nil { start = x }
        } else if let s = start {
            found.append((s, x - s)); start = nil
        }
    }
    if let s = start { found.append((s, sheet.width - s)) }
    if found.count > 1, found[0].start == 0,
       found[found.count - 1].start + found[found.count - 1].length == sheet.width {
        let last = found.removeLast()
        found[0] = (last.start, last.length + found[0].length)
    }
    return found
}

// MARK: - Report

private let found = windows()
private func round4(_ v: Double) -> String { String(format: "%.4f", v) }

print("""
  sheet \(sheet.width)x\(sheet.height), one repeat \(Int(tileWidth.rounded())) scene units
  turf line row \(turfRow); sprigs reach \(rise.max() ?? 0)px \
(\(round4(Double(rise.max() ?? 0) * unitsPerPixel)) units) at the worst column
  gap \(gapWidth) units = \(gapPixels)px, tolerance \(sprigTolerance) units = \(tolerancePixels)px
""")

guard !found.isEmpty else {
    print("""

  NO WINDOW. A gap this wide cannot be placed clear anywhere in the repeat.
  Either lower `Cliff.maxGapWidth` or raise `sprigTolerance` and look at what
  that actually costs on screen.
""")
    exit(1)
}

/// The phase of the gap's *centre*, which is what the cliff node is positioned
/// by — `cliffSpawnX` nudges the spawn until the centre lands on one of these.
///
/// However many there are. An earlier version printed a single number taken mod
/// half a repeat, because the painting it was written against happened to have
/// exactly two windows exactly half a repeat apart. That was a property of that
/// painting and not of anything else, and a repaint is free to have one window,
/// or three at no particular spacing.
private let centres = found
    .map { (Double($0.start) + Double($0.length) / 2 + Double(gapPixels) / 2) / Double(sheet.width) }
    .map { $0.truncatingRemainder(dividingBy: 1) }
    .sorted()

for (window, centre) in zip(found, centres) {
    print("  window \(window.length)px wide (\(round4(Double(window.length) * unitsPerPixel)) units), "
        + "gap centre at phase \(round4(centre))")
}

/// The worst case for `cliffSpawnX`: the widest a spawn might have to be nudged
/// to reach the next window, which is the largest step between them round the
/// repeat.
private let gaps = zip(centres, centres.dropFirst() + [centres[0] + 1]).map { $1 - $0 }
print("""
  \(centres.count) window(s); worst-case nudge \(Int(((gaps.max() ?? 1) * tileWidth).rounded())) units \
(a cliff arrives that much later than it was decided)
""")

print("""

paste into cliffSpawnX:

        let clearCentres: [CGFloat] = [\(centres.map(round4).joined(separator: ", "))]
""")
