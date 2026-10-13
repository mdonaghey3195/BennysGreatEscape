#!/usr/bin/env swift
//
//  CutAngry.swift
//  Benny's Great Escape
//
//  Cuts Benny's six angry frames and his serious pose out of the sheets in this
//  directory, and writes them straight into the asset catalogue.
//
//      swift Art/CutAngry.swift
//
//  Run from the repository root. Rerunning overwrites the assets in place.
//
//  Same shape as `CutRabbit`, which solved this a fortnight ago, and the same
//  one real problem: the frames have to be hung from something rigid or Benny's
//  rocket wanders about underneath him as the animation plays. Here it wanders
//  by twenty-four pixels and then snaps back eighteen on the last frame, which
//  is both a visible fault and exactly the shape a registration bug takes — so
//  it is taken out, and any recoil the shot wants is put back in code where it
//  can be shaped.
//
//  The landmark is the rocket's red nose cone, and it is found as the largest
//  red *blob* rather than simply the reddest pixels. That distinction matters
//  on precisely one frame: the sixth draws an anger burst over Benny's head in
//  the same red as the nose, and keying on colour alone drags the landmark up
//  into it. Taking the largest connected component separates them, and the
//  guard at the end is what proves it did.
//
//  The serious pose goes through the same path from the same landmark, because
//  it is the frame the anger hands over to and a jump there would be the most
//  visible of the lot.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tuning

/// How opaque a pixel has to be to count as drawn.
private let drawn: UInt8 = 40

/// How many blank columns separate one frame from the next on the sheet.
private let cellGap = 60

/// How far apart two frames' nose cones may sit after registration before this
/// refuses to install them. Nought is what it achieves; one is slack for a
/// redraw whose anti-aliasing lands differently.
private let noseTolerance = 1

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

    /// The rocket's red, straightened for alpha so a soft edge reads as the
    /// colour it was painted rather than as a darker version of it.
    func isRed(_ x: Int, _ y: Int) -> Bool {
        let o = offset(x, y)
        let a = Double(pixels[o + 3]) / 255
        guard a > 0.7 else { return false }
        let r = Double(pixels[o]) / a, g = Double(pixels[o + 1]) / a, b = Double(pixels[o + 2]) / a
        return r > 165 && g < 100 && b < 100 && r - g > 80 && r - b > 80
    }
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

private func install(_ frame: Bitmap, named name: String) {
    let directory = "BennysGreatEscape/Assets.xcassets/\(name).imageset"
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    write(frame, to: "\(directory)/\(name).png")
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

// MARK: - Finding things

private func columns(of sheet: Bitmap) -> [(left: Int, right: Int)] {
    var any = [Bool](repeating: false, count: sheet.width)
    for x in 0..<sheet.width {
        for y in stride(from: 0, to: sheet.height, by: 2) where sheet.isDrawn(x, y) {
            any[x] = true
            break
        }
    }
    var runs: [(left: Int, right: Int)] = []
    var start: Int?
    var blank = 0
    for x in 0..<sheet.width {
        if any[x] {
            if start == nil { start = x }
            blank = 0
        } else if let from = start {
            blank += 1
            if blank > cellGap { runs.append((from, x - blank)); start = nil }
        }
    }
    if let from = start { runs.append((from, sheet.width - 1)) }
    return runs
}

private struct Box {
    var left: Int, right: Int, top: Int, bottom: Int
    var centreX: Double { Double(left + right) / 2 }
    var centreY: Double { Double(top + bottom) / 2 }
}

/// The rocket's nose cone: the largest red blob in the cell.
///
/// Largest rather than reddest — see the header. The burst on the sixth frame is
/// the same red and sits higher, so colour alone picks the wrong thing, and it
/// picks it on exactly the frame whose registration matters most.
private func noseCone(in sheet: Bitmap, left: Int, right: Int) -> Box {
    var seen = [Bool](repeating: false, count: sheet.width * sheet.height)
    var best: (size: Int, box: Box)?
    for seedY in 0..<sheet.height {
        for seedX in left...right {
            let seed = seedY * sheet.width + seedX
            guard !seen[seed], sheet.isRed(seedX, seedY) else { continue }
            var stack = [seed]
            seen[seed] = true
            var box = Box(left: seedX, right: seedX, top: seedY, bottom: seedY)
            var size = 0
            while let pixel = stack.popLast() {
                let px = pixel % sheet.width, py = pixel / sheet.width
                size += 1
                box.left = min(box.left, px); box.right = max(box.right, px)
                box.top = min(box.top, py); box.bottom = max(box.bottom, py)
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = px + dx, ny = py + dy
                    guard nx >= left, nx <= right, ny >= 0, ny < sheet.height else { continue }
                    let next = ny * sheet.width + nx
                    guard !seen[next], sheet.isRed(nx, ny) else { continue }
                    seen[next] = true
                    stack.append(next)
                }
            }
            if best == nil || size > best!.size { best = (size, box) }
        }
    }
    guard let found = best else { fatalError("no red found in x \(left)-\(right) — is this the right sheet?") }
    return found.box
}

private func drawnBox(in sheet: Bitmap, left: Int, right: Int) -> Box {
    var box = Box(left: right, right: left, top: sheet.height, bottom: 0)
    for y in 0..<sheet.height {
        for x in left...right where sheet.isDrawn(x, y) {
            box.left = min(box.left, x); box.right = max(box.right, x)
            box.top = min(box.top, y); box.bottom = max(box.bottom, y)
        }
    }
    return box
}

// MARK: - Cutting

print("angry Benny")

private struct Pose {
    let sheet: Bitmap
    let name: String
    let box: Box     // everything drawn
    let nose: Box    // the landmark
}

private var poses: [Pose] = []

private let angry = load("Art/benny_angry_source.png")
print("  angry sheet \(angry.width)x\(angry.height)")
private let cells = columns(of: angry)
guard cells.count == 6 else { fatalError("expected six frames, found \(cells.count)") }
for (index, cell) in cells.enumerated() {
    poses.append(Pose(sheet: angry, name: "benny_angry_\(index)",
                      box: drawnBox(in: angry, left: cell.left, right: cell.right),
                      nose: noseCone(in: angry, left: cell.left, right: cell.right)))
}

private let serious = load("Art/benny_serious_source.png")
print("  serious sheet \(serious.width)x\(serious.height)")
poses.append(Pose(sheet: serious, name: "benny_serious",
                  box: drawnBox(in: serious, left: 0, right: serious.width - 1),
                  nose: noseCone(in: serious, left: 0, right: serious.width - 1)))

print("  pose              drawn size    nose cone   nose centre")
for pose in poses {
    print(String(format: "    %-16@ %4dx%-4d   %3dx%-3d    %7.1f,%7.1f",
                 pose.name,
                 pose.box.right - pose.box.left + 1, pose.box.bottom - pose.box.top + 1,
                 pose.nose.right - pose.nose.left + 1, pose.nose.bottom - pose.nose.top + 1,
                 pose.nose.centreX - Double(pose.box.left), pose.nose.centreY - Double(pose.box.top)))
}

/// One canvas for all of them, measured rather than assumed — the sixth frame
/// carries a burst above Benny's head that none of the others do, so the room
/// needed above the nose is not the room the first five want.
private let left = poses.map { Int($0.nose.centreX.rounded()) - $0.box.left }.max()!
private let right = poses.map { $0.box.right - Int($0.nose.centreX.rounded()) }.max()!
private let above = poses.map { Int($0.nose.centreY.rounded()) - $0.box.top }.max()!
private let below = poses.map { $0.box.bottom - Int($0.nose.centreY.rounded()) }.max()!
private let canvas = (width: left + right + 1, height: above + below + 1)
print("  canvas \(canvas.width)x\(canvas.height), nose centre at (\(left), \(above))")

private var landed: [(name: String, x: Int, y: Int)] = []
for pose in poses {
    var frame = Bitmap(width: canvas.width, height: canvas.height)
    let dx = left - Int(pose.nose.centreX.rounded())
    let dy = above - Int(pose.nose.centreY.rounded())
    for y in pose.box.top...pose.box.bottom {
        for x in pose.box.left...pose.box.right {
            let tx = x + dx, ty = y + dy
            guard tx >= 0, tx < canvas.width, ty >= 0, ty < canvas.height else { continue }
            let from = pose.sheet.offset(x, y), to = frame.offset(tx, ty)
            for channel in 0..<4 { frame.pixels[to + channel] = pose.sheet.pixels[from + channel] }
        }
    }
    let check = noseCone(in: frame, left: 0, right: canvas.width - 1)
    landed.append((pose.name, Int(check.centreX.rounded()), Int(check.centreY.rounded())))
    install(frame, named: pose.name)
}

// The guard. Everything above is arithmetic that looks right whether or not it
// is, and a frame out of line is invisible until the thing is on screen.
print("  noses after registration:")
for l in landed { print("    \(l.name): (\(l.x), \(l.y))") }
private let spreadX = landed.map(\.x).max()! - landed.map(\.x).min()!
private let spreadY = landed.map(\.y).max()! - landed.map(\.y).min()!
guard spreadX <= noseTolerance, spreadY <= noseTolerance else {
    fatalError("the poses don't line up — noses \(spreadX)px across and \(spreadY)px down."
        + " Benny's rocket would wander as the animation plays.")
}
print("  all \(landed.count) noses within (\(spreadX), \(spreadY))px — the rocket holds still")

print("""

paste into AngerArt:

    static let aspect: CGFloat = \(String(format: "%.4f", Double(canvas.width) / Double(canvas.height)))
""")
