//
//  TitleView.swift
//  Benny's Great Escape
//
//  The title card. Deliberately just a scrim and some type — the live scene
//  runs behind it, so Benny is already galloping across the hills while you
//  read the name.
//

import SwiftUI

struct TitleView: View {
    let bestScore: Int
    let onStart: () -> Void

    @State private var prompting = false

    var body: some View {
        ZStack {
            // Barely there. The type carries its own shadow, so the scrim only
            // has to take the edge off — any heavier and it drains the colour
            // out of the sky, which is most of the game's charm.
            LinearGradient(
                colors: [.black.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                Text("Benny's")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("GREAT ESCAPE")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .kerning(2)
                    .foregroundStyle(.white)

                if bestScore > 0 {
                    Text("Best \(bestScore)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, 6)
                }

                Text("Tap to run · tap to jump")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 22)
                    .opacity(prompting ? 1 : 0.45)
            }
            // Sits in the band of clear sky between the sun and the hills,
            // rather than at the very top where it collides with the sun.
            .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
            .offset(y: -20)
        }
        // The whole screen starts the game, not just the text.
        .contentShape(Rectangle())
        .onTapGesture(perform: onStart)
        .onAppear {
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                prompting = true
            }
        }
    }
}

#Preview {
    ZStack {
        Color(red: 0.55, green: 0.82, blue: 0.98)
        TitleView(bestScore: 17, onStart: {})
    }
    .ignoresSafeArea()
}
