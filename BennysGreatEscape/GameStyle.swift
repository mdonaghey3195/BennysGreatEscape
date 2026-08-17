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
        .accessibilityLabel("Back")
    }
}

struct SpringyButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
