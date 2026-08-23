#!/usr/bin/env swift
//
//  SliceIntroSheets.swift
//  Benny's Great Escape
//
//  Cuts the two intro sheets in this directory into the frames the opening clip
//  plays, and writes them straight into the asset catalogue.
//
//      swift Art/SliceIntroSheets.swift
//
//  Run from the repository root. Rerunning it overwrites the frames in place,
//  so retouching a sheet is a rerun rather than a hand edit.
//
//  Both sheets arrive with the background *painted* — plain white on the walk
//  sheet, a fake transparency checkerboard on the rabbit sheet — so the
//  background has to be keyed out rather than read off an alpha channel. The
//  walk sheet does carry an alpha channel, but all it holds is a scatter of
//  holes along its right-hand edge; `load` lays both over white to be rid of it.
//
//  It also prints the handful of fractions `IntroArt` in GameScene.swift is
//  built from. They are measured off the artwork rather than typed in by hand,
//  so re-cutting a redrawn sheet reprints the numbers to paste back.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tuning

/// What counts as background, per sheet — the two arrived with different ones.
private struct Key {
    /// Light enough to be background, and dark enough to be solid drawing.
    ///
    /// Two thresholds rather than one, because a single cutoff leaves a white
    /// rim around every figure: the artwork is anti-aliased against its
    /// background, so the outermost pixel of an outline is part ink, part paper.
    /// Between the two a pixel is an edge, and gets partial alpha.
    var background: Int
    var drawing: Int

    /// How grey a light pixel has to be to count as background.
    ///
    /// Luminance alone can't do it on the walk sheet, which draws a soft contact
    /// shadow under every figure. The shadow is as pale as the paper (199–253),
    /// so no cutoff separates them — but it also rims each figure in grey, and
    /// that rim seals the paper *between* the man's legs off from the border the
    /// flood starts at. Key on luminance alone and every frame keeps a white
    /// puddle standing between its ankles.
    ///
    /// Colour separates them cleanly where brightness can't: the shadow is
    /// neutral (saturation ~11) and everything drawn is not — the shirt 74, the
    /// skin 67, the trousers 118. So a pale pixel is background only if it has
    /// no colour in it, and a pale pixel that does is kept.
    var maxSaturation: Int

    /// Plain paper, plus a shadow to see through.
    static let walk = Key(background: 195, drawing: 170, maxSaturation: 34)

    /// Paper is perfectly neutral; Benny's white chest and muzzle are a warm
    /// cream. It is a narrow distinction, and the only one there is — see
    /// `seal`, which is the one place it is needed.
    static let paperLuminance = 245
    static let paperSaturation = 3

    /// A painted "transparency" checkerboard, in two shades of near-white
    /// (249 and 255), and no shadows. Far enough above the rabbit's grey coat
    /// (~176) that his colour never needs to be consulted.
    static let rabbit = Key(background: 242, drawing: 205, maxSaturation: 255)

    /// Plain white paper, no shadows and no checkerboard. Same rabbit, so the
    /// same wide berth over his coat — and the grass he is eating is green
    /// enough that saturation never has to be brought into it either.
    static let graze = Key(background: 240, drawing: 200, maxSaturation: 255)

    /// The rabbit sheet has its frame number stamped in the corner of every
    /// cell. Painted out before keying, or each frame ships with a numeral
    /// floating beside the rabbit.
    static let labelPatch = 132

}

private enum Find {
    /// A figure counts as the man if it reaches into the top of the row and
    /// stands most of the row's height. Height is what actually does the work:
    /// the shortest man on the sheet is the one diving after Benny at the end,
    /// at 227px, and the tallest dog is the one leaping out of the leash, at
    /// 160. Nothing lands between them, so the cut has a wide berth on both
    /// sides — and it is how the row is cut into its nineteen frames.
    ///
    /// The top band is the looser of the two for the same reason: that diving
    /// man has his head down at 0.29 of the row, lower than any other pose, and
    /// the band has to reach him.
    static let manTopBand = 0.45
    static let manHeight = 0.60

    /// How much of the man's crown is averaged to find where he stands
    /// horizontally. His head is the one landmark that keeps its size and shape
    /// in all nineteen poses, which is what makes it the thing to align on — the
    /// same reasoning that aligns Benny's own frames on his collar.
    static let crown = 45

    /// Smaller than this, either way, and it is a stray rather than a drawing.
    /// Worth saying out loud because the rightmost thing in the row is taken to
    /// be the dog, and one speck past his nose would elect itself.
    ///
    /// Height is what the threshold is really set by. What survives keying and
    /// isn't drawing is the dark core of a contact shadow, and those come out as
    /// slivers — 28 to 163 wide and never more than five tall. The smallest
    /// thing actually drawn is the slipped leash lying in the grass on the last
    /// frame, at 56 by 22. So anything with real height to it is a drawing, and
    /// the cutoff sits in the wide gap between five and twenty-two.
    static let speck = 12
}

// MARK: - Bitmap

/// 8-bit RGBA, premultiplied, laid out top-down — row 0 is the top of the
/// picture, which is how `CGContext` hands the buffer back.
private struct Bitmap {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

    func luminance(at offset: Int) -> Int {
        (Int(pixels[offset]) * 299 + Int(pixels[offset + 1]) * 587 + Int(pixels[offset + 2]) * 114) / 1000
    }

    /// How much colour a pixel carries, ignoring how bright it is.
    func saturation(at offset: Int) -> Int {
        let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
        return max(r, max(g, b)) - min(r, min(g, b))
    }

    func isOpaque(_ x: Int, _ y: Int) -> Bool { pixels[offset(x, y) + 3] > 8 }
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
        // Laid over white first. The walk sheet carries an alpha channel with a
        // scatter of fully transparent pixels along its right-hand edge, and
        // premultiplied those read back as black — which is to say as ink, in
        // the one place the flood needs clear paper to start from.
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

// MARK: - Keying

/// Clears the background by flooding inward from the sheet's border, rather
/// than by thresholding every light pixel.
///
/// The difference matters: Benny's chest and muzzle, the man's shirt highlights
/// and the rabbit's tail are all as pale as the paper they are drawn on, and a
/// global threshold punches holes straight through them. A flood can only reach
/// what the outside can reach, and the drawings' heavy cartoon outlines close
/// every silhouette, so enclosed white stays white.
private func key(_ sheet: inout Bitmap, _ threshold: Key, from seeds: [Int]? = nil) {
    var reached = [Bool](repeating: false, count: sheet.width * sheet.height)
    var queue: [Int] = []
    queue.reserveCapacity(sheet.width * sheet.height / 2)

    if let seeds {
        queue = seeds
    } else {
        for x in 0..<sheet.width {
            queue.append(x)
            queue.append((sheet.height - 1) * sheet.width + x)
        }
        for y in 0..<sheet.height {
            queue.append(y * sheet.width)
            queue.append(y * sheet.width + sheet.width - 1)
        }
    }

    var head = 0
    while head < queue.count {
        let index = queue[head]
        head += 1
        guard !reached[index] else { continue }

        let offset = index * 4
        let luminance = sheet.luminance(at: offset)
        guard luminance > threshold.drawing else { continue }
        reached[index] = true

        guard luminance >= threshold.background, sheet.saturation(at: offset) <= threshold.maxSaturation else {
            // Either an anti-aliased edge — part ink, part paper — or something
            // pale but coloured, which is drawing however bright it is. Both
            // stop the flood; the edge additionally gets its coverage back from
            // how far it has darkened, then is unmatted from the white it was
            // blended against, which premultiplied is just subtracting the
            // paper's share out. Without that every figure keeps a pale halo
            // where the artwork faded into its background.
            let span = threshold.background - threshold.drawing
            let coverage = max(0, min(255, 255 * (threshold.background - luminance) / span))
            let paper = 255 - coverage
            for channel in 0..<3 {
                sheet.pixels[offset + channel] =
                    UInt8(max(0, min(coverage, Int(sheet.pixels[offset + channel]) - paper)))
            }
            sheet.pixels[offset + 3] = UInt8(coverage)
            continue  // The silhouette. Nothing past here is background.
        }

        sheet.pixels[offset] = 0
        sheet.pixels[offset + 1] = 0
        sheet.pixels[offset + 2] = 0
        sheet.pixels[offset + 3] = 0

        let x = index % sheet.width
        if x > 0 { queue.append(index - 1) }
        if x < sheet.width - 1 { queue.append(index + 1) }
        if index >= sheet.width { queue.append(index - sheet.width) }
        if index < sheet.width * (sheet.height - 1) { queue.append(index + sheet.width) }
    }
}

/// Clears paper the flood had no way of reaching.
///
/// On three frames of the walk the leash draws a closed loop in mid-air — the
/// man's hand, down the leash, round the collar, along the dog's back and up his
/// arm again — and the paper caught inside it is sealed off from the border the
/// flood starts at. Left alone each plays as a white sail hanging off his arm.
///
/// It can't be cleared by the test the flood uses, because Benny's own white
/// chest is every bit as bright. What separates them is colour, barely: the
/// paper is perfectly neutral and his white is a warm cream. So only enclosed
/// regions that are *pure* paper go, and only where there is enough of one to be
/// a hole rather than a fleck of anti-aliasing.
///
/// The rabbit is left out of this. Nothing on his sheet draws a closed loop, so
/// there is nothing to find — and his tail is white enough to be worth not
/// risking.
@discardableResult
private func seal(_ sheet: inout Bitmap, minimumArea: Int = 200) -> [Int] {
    func isPaper(_ index: Int) -> Bool {
        let offset = index * 4
        return sheet.pixels[offset + 3] > 8
            && sheet.luminance(at: offset) >= Key.paperLuminance
            && sheet.saturation(at: offset) <= Key.paperSaturation
    }

    var visited = [Bool](repeating: false, count: sheet.width * sheet.height)
    var region: [Int] = []
    var rim: [Int] = []

    for start in 0..<(sheet.width * sheet.height) where !visited[start] && isPaper(start) {
        region.removeAll(keepingCapacity: true)
        region.append(start)
        visited[start] = true

        var head = 0
        while head < region.count {
            let index = region[head]
            head += 1
            let x = index % sheet.width
            for neighbour in [
                x > 0 ? index - 1 : -1,
                x < sheet.width - 1 ? index + 1 : -1,
                index >= sheet.width ? index - sheet.width : -1,
                index < sheet.width * (sheet.height - 1) ? index + sheet.width : -1,
            ] where neighbour >= 0 && !visited[neighbour] && isPaper(neighbour) {
                visited[neighbour] = true
                region.append(neighbour)
            }
        }

        guard region.count >= minimumArea else { continue }
        for index in region {
            let x = index % sheet.width
            for neighbour in [
                x > 0 ? index - 1 : -1,
                x < sheet.width - 1 ? index + 1 : -1,
                index >= sheet.width ? index - sheet.width : -1,
                index < sheet.width * (sheet.height - 1) ? index + sheet.width : -1,
            ] where neighbour >= 0 && !isPaper(neighbour) {
                rim.append(neighbour)
            }
            let offset = index * 4
            sheet.pixels[offset] = 0; sheet.pixels[offset + 1] = 0
            sheet.pixels[offset + 2] = 0; sheet.pixels[offset + 3] = 0
        }
    }
    return rim
}

/// Paints a corner of each cell back to paper white, before keying, so the
/// rabbit sheet's frame numbers key out with everything else.
private func erase(_ sheet: inout Bitmap, cornersOfCells columns: Int, _ rows: Int, size: Int) {
    for row in 0..<rows {
        for column in 0..<columns {
            let left = (column * sheet.width) / columns
            let top = (row * sheet.height) / rows
            for y in top..<min(top + size, sheet.height) {
                for x in left..<min(left + size, sheet.width) {
                    let o = sheet.offset(x, y)
                    sheet.pixels[o] = 255; sheet.pixels[o + 1] = 255
                    sheet.pixels[o + 2] = 255; sheet.pixels[o + 3] = 255
                }
            }
        }
    }
}

// MARK: - Finding the figures

private struct Box {
    var left: Int, top: Int, right: Int, bottom: Int  // right/bottom exclusive
    var width: Int { right - left }
    var height: Int { bottom - top }
    var centreX: Int { (left + right) / 2 }

    mutating func expand(toInclude x: Int, _ y: Int) {
        left = min(left, x); right = max(right, x + 1)
        top = min(top, y); bottom = max(bottom, y + 1)
    }

    static let empty = Box(left: .max, top: .max, right: .min, bottom: .min)
    var isEmpty: Bool { left >= right }

    func union(_ other: Box) -> Box {
        Box(left: min(left, other.left), top: min(top, other.top),
            right: max(right, other.right), bottom: max(bottom, other.bottom))
    }
}

/// One drawn shape — a man, a dog, or a slipped leash lying on its own.
private struct Figure {
    var label: Int
    var box: Box
}

/// Labels every connected run of opaque pixels in the sheet.
///
/// The sheet is one long row and it is not a grid: the pairs are drawn at their
/// own spacing, and through most of the walk each dog's nose reaches past where
/// the next man's trailing heel starts — frames one and two share seventeen
/// columns, and so do two, three, four, five and six. There is no vertical cut
/// that separates all nineteen frames. What does separate them is that the
/// drawings never *touch* — so the frames are found by what is joined to what,
/// and a grid is never used at all.
///
/// Which also means a frame is not always more than one figure. For as long as
/// the leash is in the man's hand it joins him to the dog, and the pair come
/// back as a single blob; only from the frame it slips do the two separate, and
/// only then is there a dog to be told apart from him.
private func figures(in sheet: Bitmap) -> (labels: [Int], figures: [Figure]) {
    var labels = [Int](repeating: -1, count: sheet.width * sheet.height)
    var found: [Figure] = []
    var queue: [Int] = []

    for start in 0..<(sheet.width * sheet.height) {
        guard labels[start] == -1, sheet.pixels[start * 4 + 3] > 8 else { continue }

        let label = found.count
        var box = Box.empty
        queue.removeAll(keepingCapacity: true)
        queue.append(start)
        labels[start] = label

        var head = 0
        while head < queue.count {
            let index = queue[head]
            head += 1
            let x = index % sheet.width
            let y = index / sheet.width
            box.expand(toInclude: x, y)

            for neighbour in [
                x > 0 ? index - 1 : -1,
                x < sheet.width - 1 ? index + 1 : -1,
                index >= sheet.width ? index - sheet.width : -1,
                index < sheet.width * (sheet.height - 1) ? index + sheet.width : -1,
            ] where neighbour >= 0 && labels[neighbour] == -1 && sheet.pixels[neighbour * 4 + 3] > 8 {
                labels[neighbour] = label
                queue.append(neighbour)
            }
        }

        found.append(Figure(label: label, box: box))
    }
    return (labels, found)
}

/// Groups a sheet's figures into poses by the blank columns between them.
///
/// Only usable on a sheet whose gutters are clean — the walk's are not, which is
/// why it is cut by which man each drawing belongs to instead. The graze sheet's
/// six poses are drawn well clear of each other, so there the gaps are the cuts.
///
/// A pose is a group and not a single figure because the grass is drawn
/// unattached to the rabbit in the poses where his nose has not reached it yet.
private func clusters(of all: [Figure]) -> [[Figure]] {
    let drawn = all
        .filter { $0.box.width >= Find.speck && $0.box.height >= Find.speck }
        .sorted { $0.box.left < $1.box.left }

    var found: [[Figure]] = []
    for figure in drawn {
        if let last = found.last, figure.box.left < last.map(\.box.right).max()! {
            found[found.count - 1].append(figure)
        } else {
            found.append([figure])
        }
    }
    return found
}

/// The rows the sheet's drawing occupies, found from the blank gutters around
/// it. The walk sheet is a single row and so gives back a single band; the
/// gutters are clean either way, which the columns are not.
private func bands(of sheet: Bitmap) -> [Box] {
    var rows: [Bool] = []
    for y in 0..<sheet.height {
        var ink = false
        for x in 0..<sheet.width where sheet.isOpaque(x, y) { ink = true; break }
        rows.append(ink)
    }
    var found: [Box] = []
    var top: Int?
    for y in 0..<sheet.height {
        if rows[y], top == nil { top = y }
        if !rows[y], let began = top {
            found.append(Box(left: 0, top: began, right: sheet.width, bottom: y))
            top = nil
        }
    }
    if let began = top { found.append(Box(left: 0, top: began, right: sheet.width, bottom: sheet.height)) }
    return found.filter { $0.height > sheet.height / 12 }
}

// MARK: - Composing frames

/// A frame is a man, plus everything drawn between him and the next man — his
/// dog, and the leash whether it is still in his hand or sailing through the
/// air on its own.
private struct Scene {
    var man: Figure
    var dog: Figure?
    var rest: [Figure]

    var all: [Figure] { [man] + rest + (dog.map { [$0] } ?? []) }
}

private func scenes(in band: Box, all: [Figure], sheet: Bitmap) -> [Scene] {
    let inBand = all.filter {
        $0.box.top >= band.top && $0.box.bottom <= band.bottom
            && $0.box.width >= Find.speck && $0.box.height >= Find.speck
    }
    let men = inBand
        .filter {
            Double($0.box.top - band.top) < Double(band.height) * Find.manTopBand
                && Double($0.box.height) > Double(band.height) * Find.manHeight
        }
        .sorted { $0.box.left < $1.box.left }

    return men.enumerated().map { index, man in
        let nextMan = index + 1 < men.count ? men[index + 1].box.left : sheet.width
        // Everything standing between this man and the next belongs to him.
        // Ordered left to right, so his dog — always out in front, with the
        // slipped leash trailing behind it — is last. On the frames where the
        // leash is still in his hand there is nothing here at all: the dog is
        // joined to him and came back as part of him.
        let company = inBand
            .filter { $0.label != man.label && $0.box.centreX > man.box.left && $0.box.centreX < nextMan }
            .sorted { $0.box.centreX < $1.box.centreX }
        return Scene(man: man, dog: company.last, rest: company.dropLast())
    }
}

/// Where a frame is pinned: the man's crown horizontally, his feet vertically.
///
/// Pinning him rather than the cell is what makes the nineteen poses play as one
/// shot. The sheet's pairs are each framed on their own, so cell-relative
/// positions would have the man skating about the screen between frames; pinned,
/// he holds his ground and walks because the node walks.
///
/// The feet are read off the bottom of his whole figure, which for most of the
/// clip is the bottom of the blob he and the dog make together. That is his own
/// foot and not a paw: the dog is drawn beside and then ahead of him but never
/// below him, so on all nineteen frames the lowest thing in the drawing is a
/// shoe. Worth checking again if the sheet is ever redrawn with him lifted off
/// the ground, because then it wouldn't be.
private func anchor(of scene: Scene, in sheet: Bitmap, labels: [Int]) -> (x: Int, y: Int) {
    var sum = 0, count = 0
    for y in scene.man.box.top..<min(scene.man.box.top + Find.crown, scene.man.box.bottom) {
        for x in scene.man.box.left..<scene.man.box.right where labels[y * sheet.width + x] == scene.man.label {
            sum += x
            count += 1
        }
    }
    return (count > 0 ? sum / count : scene.man.box.centreX, scene.man.box.bottom)
}

/// Copies a frame's figures onto the shared canvas, aligned on its anchor.
///
/// Only the labelled pixels are copied, never a rectangle, so a neighbouring
/// pair overlapping this frame's bounding box can't come with it.
private func compose(
    _ figures: [Figure], anchor: (x: Int, y: Int),
    canvas: Box, sheet: Bitmap, labels: [Int]
) -> Bitmap {
    var frame = Bitmap(width: canvas.width, height: canvas.height)
    let wanted = Set(figures.map(\.label))
    for figure in figures {
        for y in figure.box.top..<figure.box.bottom {
            for x in figure.box.left..<figure.box.right {
                let index = y * sheet.width + x
                guard labels[index] == figure.label, wanted.contains(figure.label) else { continue }
                let tx = x - anchor.x - canvas.left
                let ty = y - anchor.y - canvas.top
                guard tx >= 0, ty >= 0, tx < frame.width, ty < frame.height else { continue }
                let from = index * 4
                let to = frame.offset(tx, ty)
                frame.pixels[to] = sheet.pixels[from]
                frame.pixels[to + 1] = sheet.pixels[from + 1]
                frame.pixels[to + 2] = sheet.pixels[from + 2]
                frame.pixels[to + 3] = sheet.pixels[from + 3]
            }
        }
    }
    return frame
}

// MARK: - The asset catalogue

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

private func ratio(_ value: Int, of total: Int) -> String {
    String(format: "%.3f", Double(value) / Double(total))
}

// MARK: - The walk sheet

/// The last frame that still draws the dog. After it Benny's own gallop stands
/// in and runs off, so the game never cuts between two different drawings of him
/// mid-stride — and the man is left alone on screen, which is the whole point of
/// the shot.
///
/// Sixteen and not the frame the leash actually comes free on, which is fifteen.
/// The swap wants a drawn gallop to land on, because a gallop is what Benny is
/// doing when he fades in: this frame is where his size is measured as well as
/// where he is put, and fifteen draws him gathered up in mid-leap — a foot
/// narrower than the same dog running, which would size the whole clip up by as
/// much. Sixteen is the first clean gallop, so it is the one to cut on.
private let handoff = 16

/// The rabbit pose the clip holds through the whole approach: the one with all
/// four feet under him, and so the only one that can be stood still on.
/// `IntroArt.rabbitStill` picks the same frame, and the fraction printed for it
/// below is what sizes him — the canvas is stretched by the gallop and this
/// pose doesn't fill it.
private let still = 2

print("walk sheet")

private var walkSheet = load("Art/intro_walk_sheet.png")
key(&walkSheet, .walk)
// Opening a pocket leaves its edge raw, so the same keying is run again from
// what the pocket now borders on — the inside of the loop comes out matted the
// way the outside of the figure does, rather than ringed in dots of white.
key(&walkSheet, .walk, from: seal(&walkSheet))
private let (walkLabels, walkFigures) = figures(in: walkSheet)

private var walkScenes: [Scene] = []
for band in bands(of: walkSheet) {
    walkScenes += scenes(in: band, all: walkFigures, sheet: walkSheet)
}
print("  \(walkScenes.count) frames from \(bands(of: walkSheet).count) rows")
guard walkScenes.count == 19 else { fatalError("expected 19 frames, found \(walkScenes.count)") }

// From the handoff on, the drawn dog is dropped: the game's Benny is standing in
// for him by then, and two dogs on screen would give the trick away.
private let kept: [[Figure]] = walkScenes.enumerated().map { index, scene in
    index > handoff ? [scene.man] + scene.rest : scene.all
}

private let walkAnchors = walkScenes.map { anchor(of: $0, in: walkSheet, labels: walkLabels) }

// One canvas for all nineteen, sized around the anchor rather than around the
// sheet, so every frame can be drawn at one position and one size.
private var walkCanvas = Box.empty
for (index, figures) in kept.enumerated() {
    let box = figures.dropFirst().reduce(figures[0].box) { $0.union($1.box) }
    let anchor = walkAnchors[index]
    walkCanvas = walkCanvas.union(Box(
        left: box.left - anchor.x, top: box.top - anchor.y,
        right: box.right - anchor.x, bottom: box.bottom - anchor.y
    ))
}
print("  canvas \(walkCanvas.width)x\(walkCanvas.height)")

// How far left the drawing reaches while the man is still on his mark — his
// trailing foot at full stride, canvas-relative. `Intro.manX` is placed by it.
// The frames after the handoff reach further, the dive furthest of all, but the
// turf is carrying him out of shot by then and the crop is welcome to them.
private let walkLeft = kept[0...handoff].enumerated().map { index, figures in
    figures.dropFirst().reduce(figures[0].box) { $0.union($1.box) }.left - walkAnchors[index].x
}.min()! - walkCanvas.left

private var walkFrames: [Bitmap] = []
for (index, scene) in walkScenes.enumerated() {
    let frame = compose(
        kept[index], anchor: walkAnchors[index],
        canvas: walkCanvas, sheet: walkSheet, labels: walkLabels
    )
    install(frame, named: "intro_walk_\(index)")
    walkFrames.append(frame)
    print("  frame \(index): man + \(scene.rest.count) between + \(scene.dog == nil ? "no dog" : "dog")"
        + (index > handoff ? "  (dog dropped)" : ""))
}

// Benny's last drawn position — where the gallop sprite is placed so the swap
// lands on top of the dog it replaces instead of beside him.
private let dogBox = walkScenes[handoff].dog!.box
private let handoffAnchor = walkAnchors[handoff]

// MARK: - The rabbit sheet

print("\nrabbit sheet")

private var rabbitSheet = load("Art/intro_rabbit_sheet.png")
erase(&rabbitSheet, cornersOfCells: 3, 2, size: Key.labelPatch)
key(&rabbitSheet, .rabbit)
private let (rabbitLabels, rabbitFigures) = figures(in: rabbitSheet)

// The rabbit sheet *is* an even grid, and the hop's own rise and fall is drawn
// into where he sits in his cell — so here the cell is exactly the right frame
// of reference, and the frames are simply cut and cropped together.
private let rabbitCells: [Box] = (0..<2).flatMap { row in
    (0..<3).map { column in
        Box(left: column * rabbitSheet.width / 3, top: row * rabbitSheet.height / 2,
            right: (column + 1) * rabbitSheet.width / 3, bottom: (row + 1) * rabbitSheet.height / 2)
    }
}

private var rabbitBoxes: [Box] = []
for cell in rabbitCells {
    let inside = rabbitFigures.filter {
        !$0.box.isEmpty && $0.box.centreX >= cell.left && $0.box.centreX < cell.right
            && $0.box.top >= cell.top && $0.box.top < cell.bottom && $0.box.width > 40
    }
    rabbitBoxes.append(inside.dropFirst().reduce(inside[0].box) { $0.union($1.box) })
}

// Cell-relative, so the canvas is the union of where the rabbit sits *within*
// his cell — which keeps the bounce.
private var rabbitCanvas = Box.empty
for (index, box) in rabbitBoxes.enumerated() {
    let cell = rabbitCells[index]
    rabbitCanvas = rabbitCanvas.union(Box(
        left: box.left - cell.left, top: box.top - cell.top,
        right: box.right - cell.left, bottom: box.bottom - cell.top
    ))
}
print("  canvas \(rabbitCanvas.width)x\(rabbitCanvas.height)")

for (index, cell) in rabbitCells.enumerated() {
    var frame = Bitmap(width: rabbitCanvas.width, height: rabbitCanvas.height)
    for y in 0..<rabbitCanvas.height {
        for x in 0..<rabbitCanvas.width {
            let sx = cell.left + rabbitCanvas.left + x
            let sy = cell.top + rabbitCanvas.top + y
            guard sx >= 0, sy >= 0, sx < rabbitSheet.width, sy < rabbitSheet.height else { continue }
            guard rabbitLabels[sy * rabbitSheet.width + sx] >= 0 else { continue }
            let from = rabbitSheet.offset(sx, sy)
            let to = frame.offset(x, y)
            frame.pixels[to] = rabbitSheet.pixels[from]
            frame.pixels[to + 1] = rabbitSheet.pixels[from + 1]
            frame.pixels[to + 2] = rabbitSheet.pixels[from + 2]
            frame.pixels[to + 3] = rabbitSheet.pixels[from + 3]
        }
    }
    install(frame, named: "intro_rabbit_\(index)")
}

// MARK: - The graze sheet

/// The pose the clip opens on and comes back to: sitting up with his head clear
/// of the grass. `IntroArt.grazeStill` picks the same frame, and the fractions
/// printed for it are what size him against the running rabbit.
private let sittingUp = 0

print("\ngraze sheet")

private var grazeSheet = load("Art/intro_graze_sheet.png")
key(&grazeSheet, .graze)
private let (grazeLabels, grazeFigures) = figures(in: grazeSheet)
private let grazePoses = clusters(of: grazeFigures)
print("  \(grazePoses.count) poses")
guard grazePoses.count == 6 else { fatalError("expected 6 poses, found \(grazePoses.count)") }

private let grazeBoxes = grazePoses.map { pose in
    pose.dropFirst().reduce(pose[0].box) { $0.union($1.box) }
}

/// Pinned by his rump on the ground: the left of the drawing, and the bottom of
/// it. He is eating, not travelling — the head goes down and forward while the
/// back end stays put — so the back end is what has to hold still between
/// frames. Pinned anywhere else and the whole rabbit slides about under a head
/// that is trying to reach the same tuft of grass twice.
private let grazeAnchors = grazeBoxes.map { (x: $0.left, y: $0.bottom) }

private var grazeCanvas = Box.empty
for (index, box) in grazeBoxes.enumerated() {
    let anchor = grazeAnchors[index]
    grazeCanvas = grazeCanvas.union(Box(
        left: box.left - anchor.x, top: box.top - anchor.y,
        right: box.right - anchor.x, bottom: box.bottom - anchor.y
    ))
}
print("  canvas \(grazeCanvas.width)x\(grazeCanvas.height)")

for (index, pose) in grazePoses.enumerated() {
    let frame = compose(
        pose, anchor: grazeAnchors[index],
        canvas: grazeCanvas, sheet: grazeSheet, labels: grazeLabels
    )
    install(frame, named: "intro_graze_\(index)")
    print("  pose \(index): \(pose.count) figure(s), \(grazeBoxes[index].width)x\(grazeBoxes[index].height)")
}

// MARK: - The numbers GameScene needs

// Everything below is measured off the artwork rather than guessed, and printed
// to be pasted into `IntroArt`. Re-cut a redrawn sheet and the numbers follow.
private let last = walkScenes.count - 1
private let manBottom = walkScenes[last].man.box.bottom - walkAnchors[last].y - walkCanvas.top
private let dogLeft = dogBox.left - handoffAnchor.x - walkCanvas.left
private let dogBottom = dogBox.bottom - handoffAnchor.y - walkCanvas.top
private let plantedRabbit = rabbitBoxes.enumerated()
    .map { $0.element.bottom - rabbitCells[$0.offset].top - rabbitCanvas.top }.max()!

print("""

paste into IntroArt:

    static let walkAspect: CGFloat = \(ratio(walkCanvas.width, of: walkCanvas.height))
    static let manCentreXFraction: CGFloat = \(ratio(-walkCanvas.left, of: walkCanvas.width))
    static let groundLineFraction: CGFloat = \(ratio(walkCanvas.height - manBottom, of: walkCanvas.height))
    static let dogWidthFraction: CGFloat = \(ratio(dogBox.width, of: walkCanvas.width))
    static let dogCentreXFraction: CGFloat = \(ratio(dogLeft + dogBox.width / 2, of: walkCanvas.width))
    static let walkLeftFraction: CGFloat = \(ratio(walkLeft, of: walkCanvas.width))
    static let dogGroundLineFraction: CGFloat = \(ratio(walkCanvas.height - dogBottom, of: walkCanvas.height))
    static let rabbitAspect: CGFloat = \(ratio(rabbitCanvas.width, of: rabbitCanvas.height))
    static let rabbitStillWidthFraction: CGFloat = \(ratio(rabbitBoxes[still].width, of: rabbitCanvas.width))
    static let rabbitGroundLineFraction: CGFloat = \(ratio(rabbitCanvas.height - plantedRabbit, of: rabbitCanvas.height))
    static let rabbitStillHeightFraction: CGFloat = \(ratio(rabbitBoxes[still].height, of: rabbitCanvas.height))
    static let grazeAspect: CGFloat = \(ratio(grazeCanvas.width, of: grazeCanvas.height))
    static let grazeSitHeightFraction: CGFloat = \(ratio(grazeBoxes[sittingUp].height, of: grazeCanvas.height))
    static let grazeSitCentreXFraction: CGFloat = \(ratio(grazeBoxes[sittingUp].centreX - grazeAnchors[sittingUp].x - grazeCanvas.left, of: grazeCanvas.width))
""")
