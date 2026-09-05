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

    /// A shade of the parchment rather than a colour of its own, for rimming
    /// something cut out of it.
    static let parchmentRim = Color(red: 0.969, green: 0.941, blue: 0.886)

    /// The brown the back arrow is cut in. Darker than the paw prints the About
    /// page's headings carry, because it has to hold at 18pt on a light disc.
    static let bark = Color(red: 0.47, green: 0.27, blue: 0.10)
}

/// The way out of every illustrated screen: a disc of the same parchment the
/// About page is written on, with a brown arrow cut into it.
///
/// Drawn rather than painted into the artwork, so it sits clear of the Dynamic
/// Island and is a proper size under a thumb wherever it is used.
///
/// It reads as part of the page rather than a control dropped on top of one
/// because it is made of the page: `GameStyle.parchment` is the panel's own
/// paper, and the rim is a shade of it rather than a white outline. The amber
/// gradient this used to wear was the loudest thing on either screen and
/// belonged to the buttons you press to go *in*, not the one you leave by.
struct CircleBackButton: View {
    let action: () -> Void
    var symbol = "arrow.left"
    var label = "Back"

    /// The drawn disc. The tap target around it is larger — 44, the smallest
    /// thing a thumb should be asked to find.
    private let diameter: CGFloat = 40

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(GameStyle.bark)
                .frame(width: diameter, height: diameter)
                .background {
                    Circle()
                        .fill(GameStyle.parchment)
                        // A rim a shade lighter than the paper, not a white
                        // ring: enough to lift the disc off dark foliage,
                        // invisible against sky.
                        .overlay(Circle().strokeBorder(GameStyle.parchmentRim, lineWidth: 2))
                        .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
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

