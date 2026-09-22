#!/usr/bin/env swift
//
//  CutCliffGap.swift
//  Benny's Great Escape
//
//  Cuts the chasm out of the painted source in this directory and writes it
//  straight into the asset catalogue.
//
//      swift Art/CutCliffGap.swift
//
//  Run from the repository root. Rerunning overwrites the asset in place, so a
//  repainted gap is a rerun rather than a hand edit.
//
//  ## What it is looking for
//
//  A chasm: a stretch where the turf stops, cut earth falls away on both sides,
//  and nothing but haze between them. Nothing here is typed in — the turf line,
//  the opening, the walls and the slice boundaries are all found in the
//  painting, and the numbers `Cliff` needs are printed at the end.
//
//  ## Two things this has to get right
//
//  **Follow the walls, not the turf.** The chasm is wider at the bottom than at
//  the lip — the walls lean out as they go down, which is what gives it depth.
//  Cropping to where the turf stops slices the lower walls off. So the crop is
//  taken from the widest point the void reaches at any depth.
//
//  **Go all the way down.** The ground this sits in runs dirt to the bottom of
//  the painting, so the gap does too, and the crop simply ends where the image
//  does. There is no depth to choose: the crop's bottom edge and the backdrop's
//  bottom edge are the same row of the same painting, so they land together.
//  An earlier ground had a green field under the dirt and the pit had to stop
//  at a depth someone picked, which never looked like falling away.
//
//  ## And one that bit
//
//  Take the RGB raw. Core Graphics only hands back premultiplied bytes, which
//  is the same as compositing over black: a pixel of (91,142,64) at alpha 180
//  arrives as (64,100,45). Sampling that to measure the dirt, or writing it
//  back out, bakes the background into the paint — that is what put a bright
//  seam across the dirt line the first time. So `load` divides the alpha back
//  out and `write` puts it back.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tuning

/// How far past the widest point of the walls the crop reaches, in source
/// pixels — the ledge it carries on each side, which lands on real ground.
private let lipMargin = 16

/// How wide the alpha ramp at each side is.
///
/// The crop's outer ends lie on top of the game's own turf and dirt. Same
/// painting, so the same colours, but not the same *columns* — the gap turns up
/// wherever it turns up — so a hard edge there shows as a join. Narrower than
/// `lipMargin`, so it never reaches the wall itself.
private let sideFade = 14

/// A few pixels in from the wall, so the cap that holds it at native scale
/// can't clip it.
private let capMargin = 6

/// How many rows at the top of the crop fade in rather than starting opaque,
/// so the chasm emerges from the bush line instead of beginning at a cut.
///
/// Stopped flat on the turf line, the sprite's first painted row lands against
/// whatever the backdrop happens to have directly above it — and since the gap
/// turns up wherever the spawn puts it, that is an unrelated stretch of the
/// same bush line. Two different bits of foliage meeting at a straight edge,
/// measured at 28 levels across the opening where the painting's own change
/// there is 0.6.
///
/// Fading works because of what makes the edge so visible in the first place:
/// above the turf line the two paintings *are the same picture*, so this blends
/// bush line into bush line at matching tone, differing only in shape. A dozen
/// rows is the knee — 3.4 against the painting's own 2.1, where four rows still
/// leaves 8.2 and twenty only reaches 2.5 while spreading the blend far enough
/// up that the two patterns start to ghost.
///
/// Not the crown that used to sit here. That was three times as tall, opaque,
/// and there to hide turf sprigs — which is placement's job now. This hides
/// nothing; it only keeps the sprite from having a straight edge.
private let topFade = 12


/// Mirrors `BackdropArt`: what the turf band is worth in scene units, which is
/// what sets the crop's scale. `CropBackground.swift` prints these.
private let grassLineFraction = 0.5098
private let earthLineFraction = 0.6152
private let standFraction = 0.5
private let skySplitFraction = 0.3098
private let sceneHeight = 500.0
private let groundTop = 175.0

// MARK: - Bitmap

/// 8-bit RGBA, top-down, colour kept *un*premultiplied — see the note above.
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
    for i in stride(from: 0, to: bitmap.pixels.count, by: 4) {
        let alpha = Int(bitmap.pixels[i + 3])
        guard alpha > 0, alpha < 255 else { continue }
        for channel in 0..<3 {
            bitmap.pixels[i + channel] = UInt8(min(255, Int(bitmap.pixels[i + channel]) * 255 / alpha))
        }
    }
    return bitmap
}

private func write(_ bitmap: Bitmap, to path: String) {
    var pixels = bitmap.pixels
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let alpha = Int(pixels[i + 3])
        guard alpha < 255 else { continue }
        for channel in 0..<3 { pixels[i + channel] = UInt8(Int(pixels[i + channel]) * alpha / 255) }
    }
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

private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }

// MARK: - Reading the painting

private let source = load("Art/cliff_source.png")

private func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    let o = source.offset(x, y)
    return (Int(source.pixels[o]), Int(source.pixels[o + 1]), Int(source.pixels[o + 2]))
}

private func isTurf(_ x: Int, _ y: Int) -> Bool {
    let c = rgb(x, y); return c.b < 70 && c.g > 150 && c.r > 95
}

private func isEarth(_ x: Int, _ y: Int) -> Bool {
    let c = rgb(x, y); return c.r > 70 && c.g < 100 && c.b < 50
}

/// Open air inside the chasm.
///
/// The one test that separates it cleanly from everything else down there: the
/// haze in the gap is blue-green, so its blue channel beats its red. Cut earth,
/// turf and the tufts growing on the walls are all the other way round, which
/// keeps a tuft near the edge from being read as part of the void.
private func isVoid(_ x: Int, _ y: Int) -> Bool {
    let c = rgb(x, y); return c.b > c.r
}

/// Where the turf and the cut earth begin — read off the installed backdrop
/// rather than re-derived here.
///
/// The gap is the backdrop's own painting with a hole cut in it, at the same
/// size and the same vertical scale, so these rows are *the same rows*. Taking
/// them from the ground the gap has to line up with makes that agreement
/// structural instead of something two measurements have to arrive at
/// separately — and two measurements is exactly what went wrong: read across
/// this painting, the median first-turf row lands 25 rows high, partly on tufts
/// clinging to the walls and partly on hill greens light enough to pass for
/// turf. Everything below depends on these two numbers.
private let ground = load("BennysGreatEscape/Assets.xcassets/bg_scroll.imageset/bg_scroll.png")

private func groundLine(_ from: Int, _ test: (Bitmap, Int, Int) -> Bool) -> Int {
    var tops: [Int] = []
    for x in stride(from: 0, to: ground.width, by: 7) {
        for y in from..<ground.height where test(ground, x, y) { tops.append(y); break }
    }
    tops.sort()
    return tops[tops.count / 2]
}

private func turfTest(_ b: Bitmap, _ x: Int, _ y: Int) -> Bool {
    let o = b.offset(x, y)
    return Int(b.pixels[o + 2]) < 70 && Int(b.pixels[o + 1]) > 150 && Int(b.pixels[o]) > 95
}

private func earthTest(_ b: Bitmap, _ x: Int, _ y: Int) -> Bool {
    let o = b.offset(x, y)
    return Int(b.pixels[o]) > 70 && Int(b.pixels[o + 1]) < 100 && Int(b.pixels[o + 2]) < 50
}

private let turfLine = groundLine(ground.height / 3, turfTest)
private let earthLine = groundLine(turfLine, earthTest)
private let turfBand = earthLine - turfLine

guard ground.height == source.height else {
    fatalError("""
        the gap painting is \(source.height) rows tall and the backdrop is \(ground.height) — \
        they have to be the same painting at the same scale for the rows to mean the same thing
        """)
}

/// Where the turf surface stops and starts again — the lip, and so the opening
/// Benny actually falls into.
private let opening: (from: Int, to: Int) = {
    let bare = (0..<source.width).map { x in
        !(turfLine..<min(turfLine + 25, source.height)).contains { isTurf(x, $0) }
    }
    var best = (from: 0, to: 0), start: Int?
    for x in 0...source.width {
        let inRun = x < source.width && bare[x]
        if inRun, start == nil { start = x }
        if !inRun, let s = start {
            if x - s > best.to - best.from { best = (s, x) }
            start = nil
        }
    }
    guard best.to > best.from else { fatalError("no chasm found in Art/cliff_source.png") }
    return (best.from, best.to - 1)
}()

/// The widest the void gets at any depth — the walls lean out as they fall, so
/// this is further apart than the lip is, and it is what the crop has to carry.
private let widest: (from: Int, to: Int) = {
    var from = source.width, to = 0
    for y in earthLine..<source.height {
        var run = (start: -1, length: 0), current = -1
        for x in 0...source.width {
            let inRun = x < source.width && isVoid(x, y)
            if inRun, current < 0 { current = x }
            if !inRun, current >= 0 {
                if x - current > run.length { run = (current, x - current) }
                current = -1
            }
        }
        guard run.length > 40 else { continue }
        from = min(from, run.start)
        to = max(to, run.start + run.length - 1)
    }
    guard to > from else { fatalError("could not follow the chasm walls down") }
    return (from, to)
}()

// MARK: - Cutting

/// Scene units per source pixel, fixed by landing the painting's turf band on
/// the game's own — the same derivation `Cliff.artScale` makes.
private let anchorFraction = grassLineFraction + standFraction * (earthLineFraction - grassLineFraction)
private let drawnHeight = max((sceneHeight - groundTop) / anchorFraction, groundTop / (1 - anchorFraction))
private let landHeight = drawnHeight * (1 - skySplitFraction)
private let gameTurfBand = landHeight * (earthLineFraction - grassLineFraction) / (1 - skySplitFraction)
private let artScale = gameTurfBand / Double(turfBand)

private let cropLeft = max(0, widest.from - lipMargin)
private let cropRight = min(source.width, widest.to + lipMargin + 1)

/// The crop starts on the turf line exactly, and carries nothing above it.
///
/// An earlier version reached higher — a "crown" of the gap painting's own haze,
/// there to cover the ground's own sprigs where they overhang the hole. It did
/// cover them, and it looked wrong doing it: a band of flat haze laid over a
/// live bush line, most obvious of all mid-jump with Benny up beside it.
///
/// So the sprigs are handled where they should be, by putting the gap
/// somewhere they aren't. That costs width — the longest sprig-free stretch in
/// the backdrop's repeat is what `Cliff.maxGapWidth` can be — and buying the
/// width back with a patch over the scenery was the wrong trade.
///
/// It does reach a little above the line, but only far enough to fade in —
/// see `topFade`.
private let cropTop = turfLine - topFade

private var crop = Bitmap(
    width: cropRight - cropLeft,
    height: source.height - cropTop,
    pixels: [UInt8](repeating: 0, count: (cropRight - cropLeft) * (source.height - cropTop) * 4)
)

for y in 0..<crop.height {
    for x in 0..<crop.width {
        let from = source.offset(cropLeft + x, cropTop + y)
        let to = crop.offset(x, y)
        for channel in 0..<4 { crop.pixels[to + channel] = source.pixels[from + channel] }
    }
}

/// How far the painting's dirt sits from the game's own.
///
/// Reported rather than corrected. It used to be corrected, because the chasm
/// came from a different painting than the ground it sat in; this one is the
/// ground's own painting with a hole cut in it, so the two match by
/// construction and there is nothing to fix. If this ever prints a real
/// difference, that assumption has broken and the crop needs looking at.
private let dirtRows = (topFade + turfBand)..<crop.height
private var dirtMean = (r: 0.0, g: 0.0, b: 0.0)
private var dirtCount = 0.0
for y in dirtRows {
    for x in 0..<crop.width where !isVoid(cropLeft + x, cropTop + y) {
        let o = crop.offset(x, y)
        dirtMean.r += Double(crop.pixels[o])
        dirtMean.g += Double(crop.pixels[o + 1])
        dirtMean.b += Double(crop.pixels[o + 2])
        dirtCount += 1
    }
}
dirtMean = (dirtMean.r / dirtCount, dirtMean.g / dirtCount, dirtMean.b / dirtCount)

/// The top edge fades in, so the chasm emerges from the bush line rather than
/// starting at a straight cut across it — see `topFade`. Before the side ramps,
/// so the two corners get both.
for y in 0..<topFade {
    let u = Double(y + 1) / Double(topFade)
    let keep = u * u * (3 - 2 * u)
    for x in 0..<crop.width {
        let o = crop.offset(x, y) + 3
        crop.pixels[o] = UInt8((Double(crop.pixels[o]) * keep).rounded())
    }
}

/// The ends of the crop lie on top of the game's own ground. Ramping the alpha
/// there blends the overlap instead of cutting a line across it — and stops
/// short of the walls, which have to stay crisp.
for i in 0..<sideFade {
    let keep = UInt8((255 * pow(Double(i) / Double(sideFade), 0.9)).rounded())
    for y in 0..<crop.height {
        let left = crop.offset(i, y) + 3
        let right = crop.offset(crop.width - 1 - i, y) + 3
        crop.pixels[left] = min(crop.pixels[left], keep)
        crop.pixels[right] = min(crop.pixels[right], keep)
    }
}

// MARK: - Installing

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

install(crop, named: "cliff_gap")

/// How much of each end is wall, and so has to be drawn at native scale
/// however wide the opening is made — see `makeCliffPit`, which cuts the sprite
/// into these two caps and a middle that takes up the slack.
///
/// It has to reach past the lip, because that is the edge the visible opening
/// is measured from: with the lip inside the cap and the cap unscaled, the hole
/// you can see stays exactly as wide as the hole you can fall into, whatever
/// the middle is doing.
private let capPx = max(opening.from - cropLeft, cropRight - 1 - opening.to) + capMargin

print("""
  source \(source.width)x\(source.height)
  turf line row \(turfLine), earth line row \(earthLine) — \(turfBand) rows of turf band
  lip opens x \(opening.from)..\(opening.to) (\(opening.to - opening.from + 1)px); \
walls reach out to \(widest.from)..\(widest.to) (\(widest.to - widest.from + 1)px)
  crop x \(cropLeft)..\(cropRight), y \(cropTop)..\(source.height) — down to the bottom of the painting
  dirt reads (\(Int(dirtMean.r)),\(Int(dirtMean.g)),\(Int(dirtMean.b))), uncorrected
  cliff_gap \(crop.width)x\(crop.height), \(fmt(artScale)) scene units per pixel
  the opening is \(fmt(Double(opening.to - opening.from + 1) * artScale)) scene units wide as painted

paste into Cliff:

    static let spritePx: CGFloat = \(crop.width)
    static let gapPx: CGFloat = \(opening.to - opening.from + 1)
    static let turfBandPx: CGFloat = \(turfBand)
    static let cropHeightPx: CGFloat = \(crop.height)
    static let capPx: CGFloat = \(capPx)
    static let fadePx: CGFloat = \(topFade)
""")
