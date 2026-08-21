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

                target(Art.settings, in: size) { showingSettings = true }
                    .accessibilityLabel("Settings")

                target(Art.about, in: size) { showingAbout = true }
                    .accessibilityLabel("About")

                /*if bestScore > 0 {
                    bestLabel(in: size)
                }*/
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

    /// Tucked into the clear sky to the left of Benny's head — directly under
    /// the sign is where his ears are.
    private func bestLabel(in size: CGSize) -> some View {
        let frame = Art.best.frame(in: size)
        return Text("Best \(bestScore)")
            .font(.system(size: max(15, frame.height * 0.66), weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 5, y: 2)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
    }
}

/// Where things sit in the artwork, as fractions of it. Measured off the PNG —
/// re-measure these if the illustration is ever redrawn.
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
        tap: Rect(x0: 0.222, y0: 0.681, x1: 0.774, y1: 0.792),
        paint: Rect(x0: 0.232, y0: 0.687, x1: 0.764, y1: 0.786),
        cornerRadius: 0.22
    )

    static let settings = Button(
        tap: Rect(x0: 0.301, y0: 0.793, x1: 0.697, y1: 0.867),
        paint: Rect(x0: 0.311, y0: 0.798, x1: 0.687, y1: 0.861),
        cornerRadius: 0.48
    )

    static let about = Button(
        tap: Rect(x0: 0.299, y0: 0.872, x1: 0.698, y1: 0.936),
        paint: Rect(x0: 0.309, y0: 0.877, x1: 0.688, y1: 0.930),
        cornerRadius: 0.48
    )

    static let best = Rect(x0: 0.075, y0: 0.300, x1: 0.470, y1: 0.345)
}

/// Lays a button-shaped shadow over the painted button while a finger is down.
///
/// The shadow is an *overlay* rather than the button's label, and the label
/// stays a plain `Color.clear`. That keeps the hit-testing path identical to a
/// button with no press state at all — a label held at zero opacity is the kind
/// of thing that can quietly stop taking taps.
private struct PressTint: ButtonStyle {
    let shadow: CGSize
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(GameStyle.pressShadow)
                    .frame(width: shadow.width, height: shadow.height)
                    .opacity(configuration.isPressed ? 1 : 0)
                    .allowsHitTesting(false)
            }
            // Instant down, gentle up. A press has to register the moment the
            // finger lands; fading *in* would make the button feel slow, while
            // snapping back out looks like a glitch rather than a release.
            .animation(configuration.isPressed ? nil : .easeOut(duration: 0.22),
                       value: configuration.isPressed)
    }
}

#Preview {
    TitleView(bestScore: 17, onStart: {})
}
