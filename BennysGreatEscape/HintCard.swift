//
//  HintCard.swift
//  Benny's Great Escape
//
//  Both verbs are swipes and a tap does nothing, so a player who taps gets no
//  feedback at all. These aren't a nicety — without them the game is opaque on
//  first launch.
//

import SwiftUI

struct HintCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 28)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

#Preview {
    ZStack {
        Color(red: 0.44, green: 0.80, blue: 0.36)
        VStack {
            HintCard(symbol: "arrow.up", title: "JUMP!", detail: "Swipe up to leap over obstacles.")
            HintCard(symbol: "arrow.down", title: "DUCK!", detail: "Swipe down to slide under low obstacles.")
        }
    }
    .ignoresSafeArea()
}
