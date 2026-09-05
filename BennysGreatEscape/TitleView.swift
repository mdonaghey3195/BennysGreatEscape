//
//  TitleView.swift
//  Benny's Great Escape
//
//  The title card is a single painted illustration, buttons and all. Rather
//  than redrawing those buttons in SwiftUI on top of themselves, invisible tap
//  targets are laid over the painted ones, positioned as fractions of the
//  artwork so they stay put whatever the screen's aspect.
//
//  A painted button can't light up on its own, so a press is answered by
//  darkening it: the target's own label is a shadow shaped like the button,
//  invisible until a finger is down.
//

import SwiftUI

struct TitleView: View {
    let bestScore: Int
    let onStart: () -> Void

    @State private var showingAbout = false
    @State private var showingSettings = false
    @State private var showingLeaderboard = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .topLeading) {
                Image("title_art")
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()

                target(Art.play, in: size, action: onStart)
                    .accessibilityLabel("Play")

                target(Art.leaderboard, in: size) { showingLeaderboard = true }
                    .accessibilityLabel("Leaderboard")

                target(Art.settings, in: size) { showingSettings = true }
                    .accessibilityLabel("Settings")

                target(Art.about, in: size) { showingAbout = true }
                    .accessibilityLabel("About")
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        // Full screen rather than a sheet: a card inset from the top with the
        // title screen peeking round it is exactly the stock-iOS look this
        // page is meant to avoid.
        .fullScreenCover(isPresented: $showingAbout) {
            AboutView(bestScore: bestScore)
        }
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showingLeaderboard) {
            LeaderboardView(bestScore: bestScore)
        }
    }

    /// The painted button does the work visually; this makes it tappable and
    /// darkens it while a finger is down.
    ///
    /// Two rectangles, deliberately: the tap area is the generous one, so the
    /// button stays easy to hit, while the shadow is drawn to the painted
    /// button's measured edge so it can't spill onto the foliage around it.
    private func target(_ rect: Art.Button, in size: CGSize, action: @escaping () -> Void) -> some View {
        let tap = rect.tap.frame(in: size)
        let paint = rect.paint.frame(in: size)
        return Button(action: action) {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(PressTint(shadow: paint.size, cornerRadius: paint.height * rect.cornerRadius))
        .frame(width: tap.width, height: tap.height)
        .position(x: tap.midX, y: tap.midY)
    }
}

/// Where the painted buttons sit in the artwork, as fractions of it.
///
/// Not measured by eye. `swift Art/MeasureTitleButtons.swift` finds them in the
/// PNG and prints this block, so a repainted title screen is a rerun and a
/// paste — which matters most for `paint`, the edge `PressTint` darkens to.
private enum Art {
    static let size = CGSize(width: 940, height: 1672)

    struct Rect {
        let x0, y0, x1, y1: CGFloat

        /// Maps into view space through the same aspect-fill transform the
        /// image itself uses, so the targets track the painted buttons on any
        /// screen shape.
        func frame(in view: CGSize) -> CGRect {
            let scale = max(view.width / Art.size.width, view.height / Art.size.height)
            let drawn = CGSize(width: Art.size.width * scale, height: Art.size.height * scale)
            let ox = (view.width - drawn.width) / 2
            let oy = (view.height - drawn.height) / 2
            return CGRect(
                x: ox + x0 * drawn.width,
                y: oy + y0 * drawn.height,
                width: (x1 - x0) * drawn.width,
                height: (y1 - y0) * drawn.height
            )
        }
    }

    /// A painted button: where it can be tapped, where it actually is, and how
    /// round its corners are as a fraction of its height.
    ///
    /// `paint` is the button's *outer* edge — the dark outline and the shaded
    /// rim inside it, not just the bright fill. Measuring the fill alone leaves
    /// the tint short of the edge and the button keeps a bright ring while it's
    /// held down, which is the tell that gave the first attempt away.
    /// `tap` is looser than either, on purpose.
    struct Button {
        let tap: Rect
        let paint: Rect
        let cornerRadius: CGFloat
    }

    static let play = Button(
        tap: Rect(x0: 0.206, y0: 0.685, x1: 0.787, y1: 0.790),
        paint: Rect(x0: 0.232, y0: 0.690, x1: 0.762, y1: 0.785),
        cornerRadius: 0.16
    )

    // `tap.x1` here and `tap.x0` on SETTINGS are the one pair of numbers not
    // taken straight from the script. These two buttons sit side by side with
    // only a thin gap between them, and a tap target grown by the usual tenth
    // runs into its neighbour: whichever is added to the ZStack later would
    // quietly win the strip they share. Trimmed to meet at the middle of the
    // gap, so the split between them is even and neither shadows the other.
    static let leaderboard = Button(
        tap: Rect(x0: 0.141, y0: 0.797, x1: 0.499, y1: 0.867),
        paint: Rect(x0: 0.157, y0: 0.800, x1: 0.488, y1: 0.864),
        cornerRadius: 0.28
    )

    static let settings = Button(
        tap: Rect(x0: 0.499, y0: 0.796, x1: 0.862, y1: 0.868),
        paint: Rect(x0: 0.510, y0: 0.799, x1: 0.846, y1: 0.865),
        cornerRadius: 0.28
    )

    static let about = Button(
        tap: Rect(x0: 0.295, y0: 0.871, x1: 0.703, y1: 0.937),
        paint: Rect(x0: 0.313, y0: 0.874, x1: 0.685, y1: 0.934),
        cornerRadius: 0.33
    )
}

#Preview {
    TitleView(bestScore: 17, onStart: {})
}
