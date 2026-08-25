//
//  GameStyle.swift
//  Benny's Great Escape
//
//  The handful of tokens the illustrated screens share, pulled from the
//  artwork itself so the SwiftUI parts sit on top of it seamlessly.
//

import SwiftUI

enum GameStyle {
    /// Sampled from the About page's parchment panel.
    static let parchment = Color(red: 245 / 255, green: 229 / 255, blue: 201 / 255)

    /// The deep navy the headings are set in.
    static let ink = Color(red: 0.10, green: 0.20, blue: 0.35)

    /// Laid over a painted button while a finger is down. The title screen's
    /// buttons live inside the illustration, so they can't light up on their
    /// own — this is the only way they can answer a press.
    ///
    /// Slightly blue rather than pure black, because a flat black wash reads as
    /// a dimmed screenshot; a cool shadow reads as a shadow.
    static let pressShadow = Color(red: 0.06, green: 0.07, blue: 0.12).opacity(0.16)

    /// The amber of the painted buttons.
    static let amber = Color(red: 0.98, green: 0.76, blue: 0.24)
    static let amberDeep = Color(red: 0.85, green: 0.58, blue: 0.10)
}

/// The round amber back button the illustrated screens use — drawn rather than
/// painted into the art, so it can sit clear of the Dynamic Island and be a
/// proper size under a thumb.
struct CircleBackButton: View {
    let action: () -> Void
    var symbol = "arrow.left"
    var label = "Back"

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [GameStyle.amber, GameStyle.amberDeep],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3))
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                }
        }
        .buttonStyle(SpringyButton())
        .accessibilityLabel(label)
    }
}

struct SpringyButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .hapticOnPress(configuration.isPressed)
    }
}

private extension View {
    /// A tick as the finger lands, not as it lifts.
    ///
    /// Fired from the button styles rather than from the buttons, so every
    /// painted button in the app gets it without being told — the title
    /// screen's three, and both ways back out. `onChange` rather than a plain
    /// call in `makeBody`, because a style's body is evaluated whenever SwiftUI
    /// feels like it and a haptic fired from one would go off at random.
    func hapticOnPress(_ isPressed: Bool) -> some View {
        onChange(of: isPressed) { _, pressed in
            if pressed { Haptics.press() }
        }
    }
}

/// Lays a button-shaped shadow over a painted button while a finger is down.
///
/// Buttons that live inside an illustration can't light up on their own, so a
/// press is answered by darkening them. Shared by the title screen and the
/// settings BACK plate so every painted button answers a press the same way.
///
/// The shadow is an *overlay* rather than the button's label, and the label
/// stays a plain `Color.clear`. That keeps the hit-testing path identical to a
/// button with no press state at all — a label held at zero opacity is the kind
/// of thing that can quietly stop taking taps.
struct PressTint: ButtonStyle {
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
            .hapticOnPress(configuration.isPressed)
    }
}

/// The About page's way out: the label on a plate you can see the artwork
/// through.
///
/// Solid, it was one more object competing with the logo for the same corner of
/// the illustration; gone entirely, the letters had nothing holding them
/// together. Half-there does both jobs — the sky and the foliage carry on
/// through it, and the letters still sit on something.
///
/// The white label keeps its shadows regardless. The plate is too faint to be
/// relied on for contrast, so what actually makes the letters legible is the
/// same thing that made them legible with no plate at all: a soft shadow to
/// lift them off the background and a hard one under it for a carved edge.
struct SignBackButton: View {
    let action: () -> Void
    var label = "BACK"

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 16, weight: .black))
                Text(label)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .kerning(0.5)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .shadow(color: Wood.outline.opacity(0.55), radius: 0, y: 1.5)
            .padding(.horizontal, 15)
            .frame(height: 38)
            .background { plate }
            // Grown to a thumb-sized target around the plate, and made solid so
            // the gaps between the letters take the tap too.
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(SpringyButton())
        .accessibilityLabel("Back")
    }

    /// Timber, most of the way there.
    ///
    /// 0.82 and not a half: brown over sky-blue turns grey long before it turns
    /// see-through, so a plate at half strength doesn't read as translucent
    /// wood, it reads as a smudge on the artwork. This is as far as it can be
    /// taken down while still being made of the same stuff as the painted
    /// signs — the tree and the foliage come through it, and it is still brown.
    ///
    /// The rim is carried at more of it than the fill: an edge that fades at the
    /// same rate as what it encloses stops reading as an edge.
    private var plate: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Wood.light, Wood.base, Wood.deep],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(0.82)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Wood.outline.opacity(0.9), lineWidth: 2.5)
            }
            .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
    }
}

/// Sampled from the signage in the game's artwork, so the plate is the same
/// timber as the painted signs even at half strength.
private enum Wood {
    static let light = Color(red: 0.66, green: 0.38, blue: 0.10)
    static let base = Color(red: 0.56, green: 0.29, blue: 0.055)
    static let deep = Color(red: 0.43, green: 0.20, blue: 0.03)
    static let outline = Color(red: 0.24, green: 0.10, blue: 0.02)
}
