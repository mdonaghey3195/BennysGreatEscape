#!/usr/bin/env swift
//
//  CropSky.swift
//  Benny's Great Escape
//
//  Cuts the high-altitude sky the flying phase is played against, and writes it
//  straight into the asset catalogue.
//
//      swift Art/CropSky.swift
//
//  Run from the repository root. Rerunning overwrites the asset in place, so a
//  repainted sky is a rerun rather than a hand edit.
//
//  `CropBackground` can't do this one. That script's whole job is to find the
//  three rows the running game is staged against — the grass line, the lip of
//  the cut earth, and the band of flat sky the two scrolling layers are split
//  at — and this painting has no ground in it at all. What it needs instead is
//  much smaller: make it tile, and leave it alone otherwise.
//
//  Making it tile is the only real work. The source is a single stretch of sky
//  rather than a repeat, so there is no period to find — the image *is* the
//  tile, and its last column simply has to sit against its first without
//  showing a line. Measured on the painting as it arrived that join is 2.62 out
//  of 255, against 0.29 of ordinary column-to-column variation: nine times the
//  brushwork, which at this size is a seam down a flat sky every few seconds.
//
//  Two things cause it, and each has its own pass. Seven wisps run off the side
//  edges, drawn as though the picture carried on — those are rubbed out.
//  Underneath them the gradient is very slightly uneven across the width, which
//  is what is left over after the wisps go; every row is put back onto its own
//  colour, which takes it to nothing.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tuning

/// How far a pixel can sit from its row's true colour and still be sky rather
/// than cloud, and how far it has to sit to be cloud outright.
///
/// Lower than `CropBackground`'s pair, and deliberately. The clouds there are
/// solid white against solid blue and every cloud pixel is 60 or more off its
/// row; these are wisps, and a good many of them are only fifteen or twenty
/// values from the sky they sit in. Judge them by the other script's numbers and
/// half the weather in this painting reads as a blemish and gets flattened away.
private let skyBlemish = 6
private let skyCloud = 14

/// How many rows either side the gradient is averaged over, to take out the
/// painting's own faint horizontal banding before it is used as a reference.
private let gradientSmoothing = 6

/// How much worse than ordinary brushwork the finished tile's own wrap may be
/// before this refuses to install it — and how far apart the two columns have to
/// actually be before that ratio is allowed an opinion. Same reasoning, and the
/// same numbers, as `CropBackground`: a ratio alone is unfair to a smooth band,
/// where two values out of 255 reads as a catastrophe and looks like nothing.
private let wrapTolerance = 2.5
private let wrapFloor = 5.0

// MARK: - Bitmap

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

// MARK: - The gradient

/// What colour the sky is meant to be at each row, read off the painting itself
/// and then smoothed.
///
/// By median rather than mean, which is the whole trick: cloud is never most of
/// a row, so the middle value of a row is the sky behind the cloud whatever the
/// weather is doing in it.
private func gradient(of sheet: Bitmap) -> [[Int]] {
    var readings: [[Int]] = []
    for y in 0..<sheet.height {
        var channels: [[Int]] = [[], [], []]
        for x in stride(from: 0, to: sheet.width, by: 3) {
            let o = sheet.offset(x, y)
            for c in 0..<3 { channels[c].append(Int(sheet.pixels[o + c])) }
        }
        readings.append(channels.map { $0.sorted()[$0.count / 2] })
    }
    return readings.indices.map { y in
        let low = max(0, y - gradientSmoothing)
        let high = min(readings.count - 1, y + gradientSmoothing)
        return (0..<3).map { channel in
            (low...high).map { readings[$0][channel] }.reduce(0, +) / (high - low + 1)
        }
    }
}

// MARK: - Making it tile

/// Rubs out any cloud that sits across the painting's side edge.
///
/// The wisps that run off an edge were drawn as though the picture carried on
/// past it. It doesn't — the last column sits against the first — so laid end to
/// end they put half of one wisp against half of another, twice a lap.
///
/// Flood rather than a column walk, because a cloud is a blob: walking in row by
/// row would clear the rows that reach the edge and leave crescents of the ones
/// that don't.
///
/// What goes is reported by row, for the same reason `CropBackground` reports
/// it: this is the one step that takes painted work out of the picture, and a
/// repainted sky is mostly clouds being moved around. Without the rows printed
/// there is nothing to connect a wisp that vanished to the edge it was drawn
/// against — and the fix for that is always to move it in the source, never
/// anything in here.
private func clearEdgeClouds(_ sheet: inout Bitmap, sky: [[Int]])
    -> (clouds: [(rows: ClosedRange<Int>, side: String, pixels: Int)], pixels: Int) {

    // Judged at `skyCloud`, not at `skyBlemish`, and the difference is large.
    // The flood takes the whole blob it lands on, so the test decides how far a
    // wisp is chased inland — and on a painting this soft, "anything at all off
    // the row" runs the two together and swallows most of the weather near the
    // edge. Dropped to `skyBlemish` this cleared 99,071 pixels against 45,662,
    // more than twice the painted work destroyed, and left no more cloud
    // standing. Only something that is unambiguously cloud is worth chasing.
    func isCloud(_ x: Int, _ y: Int) -> Bool {
        let o = sheet.offset(x, y)
        var worst = 0
        for c in 0..<3 { worst = max(worst, abs(Int(sheet.pixels[o + c]) - sky[y][c])) }
        return worst > skyCloud
    }

    var seen = [Bool](repeating: false, count: sheet.width * sheet.height)
    var blobs: [(rows: ClosedRange<Int>, side: String, pixels: Int)] = []
    var cleared = 0

    for y in 0..<sheet.height {
        for x in [0, sheet.width - 1] {
            let seed = y * sheet.width + x
            guard !seen[seed], isCloud(x, y) else { continue }
            var top = y, bottom = y, size = 0
            var touchesLeft = false, touchesRight = false
            var stack = [seed]
            seen[seed] = true
            while let pixel = stack.popLast() {
                let px = pixel % sheet.width, py = pixel / sheet.width
                let o = sheet.offset(px, py)
                for c in 0..<3 { sheet.pixels[o + c] = UInt8(sky[py][c]) }
                cleared += 1
                size += 1
                top = min(top, py)
                bottom = max(bottom, py)
                if px == 0 { touchesLeft = true }
                if px == sheet.width - 1 { touchesRight = true }
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = px + dx, ny = py + dy
                    guard nx >= 0, nx < sheet.width, ny >= 0, ny < sheet.height else { continue }
                    let next = ny * sheet.width + nx
                    guard !seen[next], isCloud(nx, ny) else { continue }
                    seen[next] = true
                    stack.append(next)
                }
            }
            let side = touchesLeft && touchesRight ? "both edges"
                     : touchesLeft ? "left edge" : "right edge"
            blobs.append((top...bottom, side, size))
        }
    }
    return (blobs, cleared)
}

/// Puts every row back onto its own colour, except where there is cloud.
///
/// What this is for is the half of the seam the wisps don't explain. With them
/// gone the join still scored 1.75 out of 255, because the gradient is very
/// slightly uneven across the width — a vignette, or the light the sky was lit
/// by — and a column at one edge is simply not the same blue as a column at the
/// other. Flatten each row and that difference is gone by construction.
///
/// The ramp is what keeps the clouds: nothing within `skyBlemish` of the row
/// survives, everything past `skyCloud` is untouched, and the smoothstep across
/// the gap means a wisp's soft edge is let down gently instead of being cut off
/// at a contour line.
private func flatten(_ sheet: inout Bitmap, sky: [[Int]]) -> (moved: Int, worst: Int) {
    var moved = 0, worst = 0
    for y in 0..<sheet.height {
        for x in 0..<sheet.width {
            let o = sheet.offset(x, y)
            let distance = (0..<3).map { abs(Int(sheet.pixels[o + $0]) - sky[y][$0]) }.max()!
            let keep = ramp(distance, from: skyBlemish, to: skyCloud)
            guard keep < 1 else { continue }
            var shifted = 0
            for c in 0..<3 {
                let was = Int(sheet.pixels[o + c])
                let now = Int((Double(was) * keep + Double(sky[y][c]) * (1 - keep)).rounded())
                sheet.pixels[o + c] = UInt8(max(0, min(255, now)))
                shifted = max(shifted, abs(now - was))
            }
            if shifted > 0 { moved += 1; worst = max(worst, shifted) }
        }
    }
    return (moved, worst)
}

private func ramp(_ value: Int, from low: Int, to high: Int) -> Double {
    if value <= low { return 0 }
    if value >= high { return 1 }
    let t = Double(value - low) / Double(high - low)
    return t * t * (3 - 2 * t)
}

/// The last word: does what is about to be installed actually tile?
///
/// Judged per band rather than overall, because a seam that only shows in one
/// stripe of the picture averages away to nothing across the whole height — and
/// a seam in one stripe is still a line down the screen.
private func verifyWrap(_ crop: Bitmap) {
    let bands = 8
    var failed: [String] = []
    for band in 0..<bands {
        let top = band * crop.height / bands
        let bottom = (band + 1) * crop.height / bands
        var seam = 0.0, inner = 0.0
        for y in top..<bottom {
            let first = crop.offset(0, y), last = crop.offset(crop.width - 1, y)
            for channel in 0..<3 {
                seam += abs(Double(crop.pixels[last + channel]) - Double(crop.pixels[first + channel]))
            }
            for x in stride(from: 0, to: crop.width - 1, by: 29) {
                let a = crop.offset(x, y), b = crop.offset(x + 1, y)
                for channel in 0..<3 {
                    inner += abs(Double(crop.pixels[b + channel]) - Double(crop.pixels[a + channel]))
                }
            }
        }
        let rows = Double(bottom - top)
        let samples = Double((crop.width - 1 + 28) / 29)
        let seamPer = seam / (rows * 3)
        let innerPer = inner / (rows * samples * 3)
        let ratio = innerPer > 0.001 ? seamPer / innerPer : 0
        print("    rows \(top)-\(bottom - 1): wrap \(fmt(seamPer)) against \(fmt(innerPer))"
            + " of ordinary variation — \(fmt(ratio))x")
        if seamPer > wrapFloor, ratio > wrapTolerance { failed.append("\(top)-\(bottom - 1)") }
    }
    guard failed.isEmpty else {
        fatalError("this doesn't tile — bands \(failed.joined(separator: ", "))."
            + " Move whatever crosses the side edges away from them in the source.")
    }
}

// MARK: - Cutting it

print("high sky")

private var sky = load("Art/bg_sky_source.png")
print("  source \(sky.width)x\(sky.height)")

private let reference = gradient(of: sky)

private let swept = clearEdgeClouds(&sky, sky: reference)
print("  edge clouds: \(swept.clouds.count) rubbed out,"
    + " \(swept.pixels) pixels put back to sky")
for cloud in swept.clouds.sorted(by: { $0.pixels > $1.pixels }) {
    print("    rows \(cloud.rows.lowerBound)-\(cloud.rows.upperBound)"
        + " on the \(cloud.side), \(cloud.pixels) pixels"
        + " — move it clear of the edge in the source to keep it")
}

private let mended = flatten(&sky, sky: reference)
print("  flattened: \(mended.moved) pixels moved, none by more than \(mended.worst)/255")

print("  wrap:")
verifyWrap(sky)

install(sky, named: "bg_sky")
print("  bg_sky \(sky.width)x\(sky.height)")

print("""

paste into SkyArt:

    static let aspect: CGFloat = \(String(format: "%.4f", Double(sky.width) / Double(sky.height)))
""")
