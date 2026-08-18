//
//  AboutView.swift
//  Benny's Great Escape
//
//  Deliberately not a stock iOS sheet — an illustrated header over a parchment
//  panel, matching the rest of the game. The header is the artwork; everything
//  below it is drawn so the copy stays editable.
//

import SwiftUI

struct AboutView: View {
    let bestScore: Int

    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(short)"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            GameStyle.parchment.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Image("about_header")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)

                    panel
                }
            }
            .ignoresSafeArea(edges: .top)

            CircleBackButton { dismiss() }
                .padding(.leading, 16)
                .padding(.top, 8)
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            heading

            Text("Benny's Great Escape is a paws-itively fun endless runner where you help Benny the beagle jump and dash his way past logs, bushes, tree stumps and whatever else the countryside throws at him.")
                .aboutBody()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)

            if bestScore > 0 {
                bestRun
            }

            section(
                icon: "pawprint.fill",
                tint: GameStyle.amber,
                title: "OUR MISSION",
                body: "We created Benny's Great Escape to bring joy, challenge, and tail-wagging fun to players of all ages. Our mission is to make wholesome, engaging games that spark imagination and keep you coming back for more adventures."
            )

            section(
                icon: "heart.fill",
                tint: Color(red: 0.93, green: 0.36, blue: 0.36),
                title: "MADE WITH LOVE",
                body: "Inspired by a real dog, Benny's Great Escape was built by a developer who set out to bring his dog, Benny, to life in game form."
            )

            section(
                icon: "trophy.fill",
                tint: GameStyle.amber,
                title: "THANK YOU!",
                body: "Thank you for playing and supporting independent games. We hope you and Benny have a great adventure together! 🐾",
                showsDivider: false
            )

            Text(version)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(GameStyle.ink.opacity(0.4))
                .padding(.top, 28)
                .padding(.bottom, 44)
        }
        .background(GameStyle.parchment)
    }

    private var heading: some View {
        HStack(spacing: 12) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color(red: 0.55, green: 0.36, blue: 0.20))
            Text("ABOUT")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .kerning(1.5)
                .foregroundStyle(GameStyle.ink)
            Image(systemName: "pawprint.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color(red: 0.55, green: 0.36, blue: 0.20))
        }
        .padding(.top, 26)
        .padding(.bottom, 16)
    }

    private var bestRun: some View {
        VStack(spacing: 2) {
            Text("\(bestScore)")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(GameStyle.ink)
            Text("obstacles cleared, best run")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(GameStyle.ink.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func section(
        icon: String,
        tint: Color,
        title: String,
        body: String,
        showsDivider: Bool = true
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(tint.opacity(0.95))
                    .frame(width: 54, height: 54)
                    .background {
                        Circle()
                            .fill(tint.opacity(0.22))
                            .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 3))
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(GameStyle.ink)
                    Text(body)
                        .aboutBody()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)

            if showsDivider {
                Rectangle()
                    .fill(GameStyle.ink.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, 24)
            }
        }
    }
}

private extension Text {
    func aboutBody() -> some View {
        self
            .font(.system(size: 15.5, weight: .medium, design: .rounded))
            .foregroundStyle(GameStyle.ink.opacity(0.78))
            .lineSpacing(3)
    }
}

#Preview {
    AboutView(bestScore: 17)
}
