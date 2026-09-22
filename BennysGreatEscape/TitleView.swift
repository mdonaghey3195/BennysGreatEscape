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
                // Everything the title screen actually is, grouped so a single
                // modifier can disable all of it at once while a popup is up
                // — a popup over this card is pointless if PLAY is still
                // reachable behind the dimming.
                Group {
                    // Painted landscape, 1844x853 — close enough to the widest
                    // supported phone's own aspect (2.174) that `.scaledToFill`
                    // crops only a sliver off the sides on anything narrower, the
                    // same way the gameplay scene's own background does. Replaces
                    // the portrait painting the landscape spike used to letterbox;
                    // `Art.Rect.frame(in:)` matches with `max` again now that
                    // there's a real landscape painting to fill with.
                    Image("title_art")
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()

                    target(Art.play, in: size, action: onStart)
                        .accessibilityLabel("Play")

                    target(Art.leaderboard, in: size) { openLeaderboard() }
                        .accessibilityLabel("Leaderboard")

                    target(Art.settings, in: size) { openSettings() }
                        .accessibilityLabel("Settings")

                    target(Art.about, in: size) { openAbout() }
                        .accessibilityLabel("About")
                }
                .allowsHitTesting(!showingSettings && !showingLeaderboard && !showingAbout)
                .accessibilityHidden(showingSettings || showingLeaderboard || showingAbout)

                // Popups, not screens: Benny and the logo stay put and dim
                // behind them rather than being redrawn a second time — see
                // `SettingsView`. Tapping the scrim is the same way out as
                // each card's own close control.
                if showingSettings {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { closeSettings() }

                    SettingsView(onDismiss: closeSettings)
                        .aspectRatio(1364.0 / 1153.0, contentMode: .fit)
                        .frame(width: size.width * 0.34)
                        .position(x: size.width / 2, y: size.height / 2)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }

                if showingLeaderboard {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { closeLeaderboard() }

                    LeaderboardView(bestScore: bestScore, onDismiss: closeLeaderboard)
                        .frame(width: size.width * 0.42, height: size.height * 0.86)
                        .position(x: size.width / 2, y: size.height / 2)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }

                if showingAbout {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { closeAbout() }

                    AboutView(onDismiss: closeAbout)
                        .aspectRatio(1024.0 / 1536.0, contentMode: .fit)
                        .frame(height: size.height * 0.86)
                        .position(x: size.width / 2, y: size.height / 2)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
    }

    private func openSettings() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showingSettings = true
        }
    }

    private func closeSettings() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showingSettings = false
        }
    }

    private func openLeaderboard() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showingLeaderboard = true
        }
    }

    private func closeLeaderboard() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showingLeaderboard = false
        }
    }

    private func openAbout() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showingAbout = true
        }
    }

    private func closeAbout() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showingAbout = false
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
    static let size = CGSize(width: 1844, height: 853)

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

    // PLAY's paint rect is measured by hand rather than by
    // `MeasureTitleButtons.swift` — this new painting's wood grain and
    // lighting fall outside the script's `isTimber` colour test across most of
    // the button, so the automated pass only ever caught a thin band through
    // the lettering (406x29 instead of the true ~440x143). LEADERBOARD,
    // SETTINGS and ABOUT are pale stone rather than timber, matched the
    // script's `isStone` test fine, and are pasted straight from its output.
    static let play = Button(
        tap: Rect(x0: 0.551, y0: 0.464, x1: 0.814, y1: 0.648),
        paint: Rect(x0: 0.564, y0: 0.472, x1: 0.802, y1: 0.640),
        cornerRadius: 0.31
    )

    // `tap.x1` here and `tap.x0` on SETTINGS are trimmed to meet at the middle
    // of the gap between them rather than the script's plain 10% margin —
    // these two sit close enough side by side that the usual margin has them
    // overlap, and whichever target the ZStack adds second (SETTINGS) would
    // quietly win the shared strip.
    static let leaderboard = Button(
        tap: Rect(x0: 0.521, y0: 0.658, x1: 0.685, y1: 0.775),
        paint: Rect(x0: 0.528, y0: 0.662, x1: 0.680, y1: 0.770),
        cornerRadius: 0.22
    )

    static let settings = Button(
        tap: Rect(x0: 0.685, y0: 0.655, x1: 0.849, y1: 0.777),
        paint: Rect(x0: 0.689, y0: 0.660, x1: 0.841, y1: 0.773),
        cornerRadius: 0.20
    )

    static let about = Button(
        tap: Rect(x0: 0.591, y0: 0.784, x1: 0.776, y1: 0.898),
        paint: Rect(x0: 0.599, y0: 0.789, x1: 0.768, y1: 0.893),
        cornerRadius: 0.20
    )
}

#Preview {
    TitleView(bestScore: 17, onStart: {})
}
