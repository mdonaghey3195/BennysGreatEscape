#!/usr/bin/env swift
//
//  CutRabbit.swift
//  Benny's Great Escape
//
//  Cuts the four frames of the rabbit laughing in his UFO out of the sheet in
//  this directory, and writes them straight into the asset catalogue.
//
//      swift Art/CutRabbit.swift
//
//  Run from the repository root. Rerunning overwrites the assets in place, so a
//  redrawn sheet is a rerun rather than a hand edit.
//
//  The sheet arrived unusually clean — four saucers in a row, every drawn block
//  exactly the same size, no horizontal drift between them — so almost nothing
//  here is about cutting. Two things are.
//
//  The first is that the numbers 1 to 4 are drawn under the saucers, in the
//  picture, as labels for whoever was going to use it. They are separated from
//  the art by a wide band of nothing, which is what makes them easy: find the
//  gap, cut above it, and they never reach the game.
//
//  The second is registration, and it is the only real work. The four saucers
//  sit at four different heights on the sheet — nought, minus twelve, plus
//  nine, plus thirty-one — and a sprite swapping between them in place would
//  jump forty-three pixels up and down as it played. That is not a subtle fault
//  on a craft that is meant to hang in the air. So every frame is moved onto a
//  common canvas by its own saucer rim, and the script refuses to install if
//  they do not all land on the same row afterwards.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tuning

/// How opaque a pixel has to be to count as drawn.
///
/// The art is anti-aliased against nothing, so its edges ramp all the way down
/// to zero. Low enough to keep the soft rim of the dome, high enough that the
/// faint speckle in the empty parts of the sheet is not mistaken for art.
private let drawn: UInt8 = 40

/// How many empty columns separate one saucer from the next.
///
/// The cells are not evenly pitched — 1583, 1601 and 1630 apart — so they are
/// found by looking rather than by dividing the width into four. Any run of
/// blank columns longer than this is a gap between frames.
private let cellGap = 50

/// How many rows of nothing separate the saucers from the numbers written under
/// them. Measured at about 140; half that is a safe thing to look for.
private let labelGap = 60

/// How far apart two frames' rims may sit after registration before this
/// refuses to install them, in pixels. Nought would be ideal and is what it
/// actually achieves; one is here so a redrawn sheet with a half-pixel of
/// anti-aliasing on the rim doesn't fail for nothing.
private let rimTolerance = 1

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
    func isDrawn(_ x: Int, _ y: Int) -> Bool { pixels[offset(x, y) + 3] > drawn }
}

private func load(_ path: String) -> Bitmap {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("can't read \(path) — run this from the repository root")
    }
    var bitmap = Bitmap(width: image.width, height: image.height)
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

private func install(_ frame: Bitmap, named name: String) {
    let directory = "BennysGreatEscape/Assets.xcassets/\(name).imageset"
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    write(frame, to: "\(directory)/\(name).png")
    // Matches every other imageset here: one universal representation and no
    // scale, so the drawing is resolution-independent and sized by the scene.
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

// MARK: - Finding the frames

/// Where the saucers are across the sheet, found by looking for runs of drawn
/// columns rather than by dividing the width — see `cellGap`.
private func columns(of sheet: Bitmap) -> [(left: Int, right: Int)] {
    var drawnColumn = [Bool](repeating: false, count: sheet.width)
    for x in 0..<sheet.width {
        for y in stride(from: 0, to: sheet.height, by: 2) where sheet.isDrawn(x, y) {
            drawnColumn[x] = true
            break
        }
    }
    var runs: [(left: Int, right: Int)] = []
    var start: Int?
    var blank = 0
    for x in 0..<sheet.width {
        if drawnColumn[x] {
            if start == nil { start = x }
            blank = 0
        } else if let from = start {
            blank += 1
            if blank > cellGap {
                runs.append((from, x - blank))
                start = nil
            }
        }
    }
    if let from = start { runs.append((from, sheet.width - 1)) }
    return runs
}

/// Where the art stops and the labels begin, in a single cell.
///
/// The numbers under the saucers are drawn in the sheet itself. Rather than
/// trusting a row typed in here, the cut is made at the wide band of nothing
/// between the two — which keeps working if the sheet is redrawn taller, or
/// with the labels moved, or with no labels at all.
private func artBottom(of sheet: Bitmap, left: Int, right: Int) -> Int {
    var lastDrawn = 0
    var blank = 0
    for y in 0..<sheet.height {
        var any = false
        for x in stride(from: left, through: right, by: 2) where sheet.isDrawn(x, y) {
            any = true
            break
        }
        if any {
            // A run of blank rows long enough to be the gap, and art below it:
            // everything from here down is a label.
            if blank > labelGap, lastDrawn > 0 { return lastDrawn }
            lastDrawn = y
            blank = 0
        } else if lastDrawn > 0 {
            blank += 1
        }
    }
    return lastDrawn
}

/// The widest drawn row of a frame — the saucer's rim, and the landmark every
/// frame is lined up on.
///
/// The rim rather than the bounding box, because a box moves when the rabbit's
/// ears do and the rim does not. On this sheet the two happen to agree exactly,
/// which is worth knowing: it says the frames are translations of one another
/// and nothing has been redrawn at a different size.
private func rimRow(of sheet: Bitmap, left: Int, right: Int, bottom: Int) -> Int {
    var best = (row: 0, width: 0)
    for y in 0...bottom {
        var count = 0
        for x in stride(from: left, through: right, by: 2) where sheet.isDrawn(x, y) { count += 1 }
        if count > best.width { best = (y, count) }
    }
    return best.row
}

private func bounds(of sheet: Bitmap, left: Int, right: Int, bottom: Int)
    -> (top: Int, bottom: Int) {
    var top = bottom
    var last = 0
    for y in 0...bottom {
        for x in stride(from: left, through: right, by: 2) where sheet.isDrawn(x, y) {
            top = min(top, y)
            last = max(last, y)
            break
        }
    }
    return (top, last)
}

// MARK: - Cutting

print("rabbit")

private let sheet = load("Art/ufo_source.png")
print("  source \(sheet.width)x\(sheet.height)")

private let cells = columns(of: sheet)
guard cells.count == 4 else {
    fatalError("expected four saucers, found \(cells.count) — \(cells)")
}

private struct Cell {
    let left: Int, right: Int, top: Int, bottom: Int, rim: Int
}

private let found: [Cell] = cells.map { cell in
    let cut = artBottom(of: sheet, left: cell.left, right: cell.right)
    let box = bounds(of: sheet, left: cell.left, right: cell.right, bottom: cut)
    return Cell(left: cell.left, right: cell.right, top: box.top, bottom: box.bottom,
                rim: rimRow(of: sheet, left: cell.left, right: cell.right, bottom: cut))
}

print("  frame   cell            drawn rows      size        rim")
for (index, cell) in found.enumerated() {
    print(String(format: "    %d   x %4d-%4d   y %4d-%4d   %4dx%4d   %5d",
                 index + 1, cell.left, cell.right, cell.top, cell.bottom,
                 cell.right - cell.left + 1, cell.bottom - cell.top + 1, cell.rim))
}

/// One canvas for all four, big enough to hold every frame once each is hung
/// from its own rim. Worked out rather than assumed: the frames are the same
/// size on this sheet, and the next one along may not be.
private let above = found.map { $0.rim - $0.top }.max()!
private let below = found.map { $0.bottom - $0.rim }.max()!
private let canvas = (width: found.map { $0.right - $0.left + 1 }.max()!,
                      height: above + below + 1)
print("  canvas \(canvas.width)x\(canvas.height), rim on row \(above)")

private var rims: [Int] = []
for (index, cell) in found.enumerated() {
    var frame = Bitmap(width: canvas.width, height: canvas.height)
    // Hung from the rim, and centred across — which on this sheet moves nothing
    // sideways, because every cell is the same width.
    let dx = (canvas.width - (cell.right - cell.left + 1)) / 2
    let dy = above - cell.rim
    for y in cell.top...cell.bottom {
        for x in cell.left...cell.right {
            let ty = y + dy, tx = x - cell.left + dx
            guard ty >= 0, ty < canvas.height, tx >= 0, tx < canvas.width else { continue }
            let from = sheet.offset(x, y), to = frame.offset(tx, ty)
            for channel in 0..<4 { frame.pixels[to + channel] = sheet.pixels[from + channel] }
        }
    }
    rims.append(rimRow(of: frame, left: 0, right: canvas.width - 1, bottom: canvas.height - 1))
    install(frame, named: "ufo_\(index)")
}

// The guard. Everything above is arithmetic that looks right whether or not it
// is, and a frame out of line here is invisible until the thing is on screen
// bobbing about — which is exactly how the dog house's hop survived three
// rounds of looking at it.
print("  rims after registration: \(rims.map(String.init).joined(separator: ", "))")
private let spread = rims.max()! - rims.min()!
guard spread <= rimTolerance else {
    fatalError("the frames don't line up — rims \(spread)px apart after registration."
        + " A sprite swapping between them would jump by that much.")
}
print("  all four rims within \(spread)px — the saucer holds still")

print("""

paste into UfoArt:

    static let aspect: CGFloat = \(String(format: "%.4f", Double(canvas.width) / Double(canvas.height)))
""")
