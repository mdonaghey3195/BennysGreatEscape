//
//  AboutView.swift
//  Benny's Great Escape
//
//  A popup card, not a screen — presented by `TitleView` the same way
//  `SettingsView` is: an overlay above a dimmed title screen rather than a
//  full-screen cover. The whole card — heading, Benny, the copy, BACK — is
//  one painted illustration; only the two ways out are live.
//
//  Positions are fractions of `about_card`, mapped through the same
//  aspect-fill transform the image itself uses, so the live targets stay put
//  whatever size the card is drawn at.
//

import SwiftUI

struct AboutView: View {
    /// Closed by `TitleView`, which owns whether the popup is showing at all —
    /// same shape as `SettingsView.onDismiss`.
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let top = Art.topBack.tap.frame(in: size)
            let topPaint = Art.topBack.paint.frame(in: size)
            let bottom = Art.bottomBack.tap.frame(in: size)
            let bottomPaint = Art.bottomBack.paint.frame(in: size)

            ZStack(alignment: .topLeading) {
                // A true cutout, same as `settings_card` — real alpha around
                // the rounded corners, nothing to clip.
                Image("about_card")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)

                // Two ways out, because the artwork paints two: the small
                // disc in the heading and the full BACK plate underneath.
                // Both just dismiss — there's nothing else live on this card.
                Button(action: onDismiss) {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(PressTint(shadow: topPaint.size,
                                       cornerRadius: topPaint.height * Art.topBack.cornerRadius))
                .frame(width: top.width, height: top.height)
                .position(x: top.midX, y: top.midY)
                .accessibilityLabel("Back")

                Button(action: onDismiss) {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(PressTint(shadow: bottomPaint.size,
                                       cornerRadius: bottomPaint.height * Art.bottomBack.cornerRadius))
                .frame(width: bottom.width, height: bottom.height)
                .position(x: bottom.midX, y: bottom.midY)
                .accessibilityLabel("Back")
            }
            .frame(width: size.width, height: size.height)
        }
        // A floating card needs to lift off whatever is behind it — the
        // backdrop used to do this job by simply being the whole screen.
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
    }
}

/// Where things sit in `about_card`, as fractions of it. Measured off the
/// PNG — re-measure these if the illustration is ever redrawn.
private enum Art {
    static let size = CGSize(width: 1024, height: 1536)

    struct Rect {
        let x0, y0, x1, y1: CGFloat

        /// Maps into view space through the same aspect-fill transform the
        /// image itself uses, so the live targets track the painted ones.
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
    /// round its corners are as a fraction of its height. `paint` is the
    /// plate's *outer* edge — the dark outline included — so the press tint
    /// covers it rather than leaving a bright ring around a held button.
    struct Button {
        let tap: Rect
        let paint: Rect
        let cornerRadius: CGFloat
    }

    /// The whole heading pill — the small circular arrow at its left is the
    /// drawn affordance, but the pill reads as one button and answers a tap
    /// anywhere on it.
    static let topBack = Button(
        tap: Rect(x0: 0.070, y0: 0.050, x1: 0.925, y1: 0.187),
        paint: Rect(x0: 0.084, y0: 0.061, x1: 0.915, y1: 0.176),
        cornerRadius: 0.30
    )

    /// The BACK plate under the copy.
    static let bottomBack = Button(
        tap: Rect(x0: 0.250, y0: 0.815, x1: 0.750, y1: 0.933),
        paint: Rect(x0: 0.260, y0: 0.824, x1: 0.739, y1: 0.924),
        cornerRadius: 0.30
    )
}

#Preview {
    AboutView(onDismiss: {})
}
