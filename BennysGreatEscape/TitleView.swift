//
//  TitleView.swift
//  Benny's Great Escape
//
//  The title card is a single painted illustration, buttons and all. Rather
//  than redrawing those buttons in SwiftUI on top of themselves, invisible tap
//  targets are laid over the painted ones, positioned as fractions of the
//  artwork so they stay put whatever the screen's aspect.
//

import SwiftUI

struct TitleView: View {
    let bestScore: Int
    let onStart: () -> Void

    @State private var showingAbout = false

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
    }

    /// The painted button does the work visually; this just makes it tappable,
    /// with a press state so it doesn't feel dead under the thumb.
    private func target(_ rect: Art.Rect, in size: CGSize, action: @escaping () -> Void) -> some View {
        let frame = rect.frame(in: size)
        return Button(action: action) {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(PressableTarget())
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
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

    static let play  = Rect(x0: 0.207, y0: 0.678, x1: 0.771, y1: 0.772)
    static let about = Rect(x0: 0.314, y0: 0.874, x1: 0.691, y1: 0.930)
    static let best  = Rect(x0: 0.075, y0: 0.300, x1: 0.470, y1: 0.345)
}

/// Painted buttons can't highlight themselves, so the target dips them slightly.
private struct PressableTarget: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    TitleView(bestScore: 17, onStart: {})
}
