#!/usr/bin/env swift
//
//  RaiseHeader.swift
//  Benny's Great Escape
//
//  Gives the About and Leaderboard header more sky above the logo, so the paw
//  above BENNY'S clears the Dynamic Island.
//
//      swift Art/RaiseHeader.swift
//
//  Run from the repository root. It reads `about_header_source.png` in this
//  directory and writes the asset, so rerunning it is idempotent — the source
//  is never the thing being extended.
//
//  The header is drawn full width with nothing above it, which is the whole
//  point of it: the illustration runs to the top of the screen rather than
//  sitting in a card. That also puts its top 60 points behind the island, and
//  the paw was landing at 35 — squarely underneath.
//
//  Moving the artwork down would leave a gap above it, and scaling it up enough
//  to matter would crop the dog off the side. So the canvas grows instead: rows
//  are added at the top, and each column continues whatever it already had.
//
//  Which is easy here, and it is worth saying why, because it is the fact the
//  whole approach rests on: every column of this drawing is *sky* at its top
//  edge except the tree in the left-hand quarter. Even the dog only reaches up
//  to about a sixth of the way down, with clear sky above him. So almost all of
//  the new strip is more of a sky that was already there, and only the tree has
//  to be invented.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tuning

/// How far down the paw should end up, in points on a 393pt-wide screen.
///
/// The safe area's top inset is 59 on the phones that have an island, so this
/// is a clear nine points below the lowest thing that could cover it.
private let paw = 68.0

/// The width the header is drawn at. It is laid out full-bleed, so this is the
/// screen, and it is what turns points into pixels of artwork.
private let screenWidth = 393.0

/// What counts as sky: bright, and blue by a clear margin. Used only on the top
/// row of each column, to decide what that column should be continued with.
private func isSky(_ colour: [Int]) -> Bool {
    colour[2] > 170 && colour[2] > colour[0] + 35
}

/// How many rows the sky's gradient is measured over before it is continued
/// upward. Long enough to be a slope rather than noise, short enough that
/// plenty of columns are still sky all the way down it.
private let gradientRun = 40

// MARK: - Bitmap

private struct Bitmap {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

    func colour(_ x: Int, _ y: Int) -> [Int] {
        let o = offset(x, y)
        return [Int(pixels[o]), Int(pixels[o + 1]), Int(pixels[o + 2])]
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
            data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
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

// MARK: - Where the paw is

/// The gold paw above the logo — the thing the island was covering, and so the
/// thing the whole exercise is measured against.
private func pawRow(in sheet: Bitmap) -> Int {
    for y in 0..<(sheet.height / 2) {
        for x in stride(from: sheet.width / 6, to: sheet.width * 2 / 3, by: 2) {
            let c = sheet.colour(x, y)
            if c[0] > 215, c[1] > 150, c[1] < 220, c[2] < 90 { return y }
        }
    }
    fatalError("can't find the paw — has the header been redrawn?")
}

// MARK: - Growing it

/// Adds `rows` of new artwork above the drawing, continuing each column with
/// whatever that column already held.
///
/// Two ways of continuing, chosen per column by what is at its top edge:
///
/// **Sky** is extended by its own gradient. The sky is a smooth vertical ramp,
/// so the slope over the first `gradientRun` rows says what is above them, and
/// following it upward is both correct and invisible — it also darkens toward
/// the top, which is what a sky does.
///
/// **Anything else** — in this drawing, only the tree — is mirrored. Foliage
/// has no structure that a reflection betrays, so it reads as more canopy, and
/// the join is seamless by construction since a reflection meets itself.
private func grow(_ sheet: Bitmap, by rows: Int) -> Bitmap {
    var taller = Bitmap(width: sheet.width, height: sheet.height + rows,
                        pixels: [UInt8](repeating: 255, count: sheet.width * (sheet.height + rows) * 4))

    // The drawing itself, moved down to make room.
    for y in 0..<sheet.height {
        let from = sheet.offset(0, y)
        let to = taller.offset(0, y + rows)
        for i in 0..<(sheet.width * 4) { taller.pixels[to + i] = sheet.pixels[from + i] }
    }

    // One slope for the whole sky, not one per column.
    //
    // The sky is a single vertical ramp, so every column that is sky agrees
    // about it — and measuring per column is a trap: plenty of columns are sky
    // at the top edge and a cloud or the dog forty rows down, and a slope drawn
    // through *that* extrapolates into stripes.
    let clear = (0..<sheet.width).filter { x in
        (0...gradientRun).allSatisfy { row in isSky(sheet.colour(x, row)) }
    }
    func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

    let slope = (0..<3).map { channel in
        median(clear.map { x in
            Double(sheet.colour(x, gradientRun)[channel] - sheet.colour(x, 0)[channel])
                / Double(gradientRun)
        })
    }
    print(String(format: "  sky rises %.2f, %.2f, %.2f per row, measured over %d clear columns",
                 slope[0], slope[1], slope[2], clear.count))

    // What the sky is at the join, once, rather than column by column.
    //
    // The sky has no horizontal variation to preserve — it is a vertical ramp —
    // and some columns meet the top edge inside a wisp of cloud. Carrying each
    // column's own colour upward paints those wisps into stripes running off the
    // top of the picture, so the strip is built from one colour and each column
    // is only eased into it.
    let clean = (0..<3).map { channel in
        median(clear.map { x in Double(sheet.colour(x, 0)[channel]) })
    }

    /// Over how many rows a column lets go of its own colour. Short enough to be
    /// clean well before the top, long enough that the join can't be seen.
    let settle = 20.0

    var skyColumns = 0
    for x in 0..<sheet.width {
        let top = sheet.colour(x, 0)

        if isSky(top) {
            skyColumns += 1
            for y in 0..<rows {
                // Distance above the original top edge, in rows.
                let up = Double(rows - y)
                let blend = min(1, up / settle)
                let o = taller.offset(x, y)
                for channel in 0..<3 {
                    let anchor = Double(top[channel]) * (1 - blend) + clean[channel] * blend
                    let value = anchor - slope[channel] * up
                    taller.pixels[o + channel] = UInt8(max(0, min(255, Int(value.rounded()))))
                }
                taller.pixels[o + 3] = 255
            }
        } else {
            for y in 0..<rows {
                let mirrored = min(sheet.height - 1, rows - 1 - y)
                let from = sheet.offset(x, mirrored)
                let to = taller.offset(x, y)
                for channel in 0..<4 { taller.pixels[to + channel] = sheet.pixels[from + channel] }
            }
        }
    }
    print("  \(skyColumns) of \(sheet.width) columns continued as sky, the rest mirrored")
    return taller
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

print("about header")

private let source = load("Art/about_header_source.png")
private let scale = screenWidth / Double(source.width)
private let was = pawRow(in: source)
print("  source \(source.width)x\(source.height), paw at row \(was)"
    + String(format: " — %.1f pt down as drawn", Double(was) * scale))

/// How many rows of sky it takes to put the paw where it should be. Solved
/// rather than tried: adding rows moves the paw down *and* makes the drawing
/// taller, which scales it back up again, so the two have to be settled
/// together.
private let added = Int((paw / scale - Double(was)).rounded())
guard added > 0 else { fatalError("the paw is already at \(paw)pt — nothing to do") }

private let taller = grow(source, by: added)
install(taller, named: "about_header")

private let now = pawRow(in: taller)
private let scaleNow = screenWidth / Double(taller.width)
print("  added \(added) rows -> \(taller.width)x\(taller.height)")
print(String(format: "  paw now %.1f pt down, header %.1f pt tall",
             Double(now) * scaleNow, Double(taller.height) * scaleNow))
