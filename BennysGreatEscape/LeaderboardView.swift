//
//  LeaderboardView.swift
//  Benny's Great Escape
//
//  The global top hundred, drawn the same way the About page is: the artwork
//  as a header, a parchment panel under it, and the way back out laid over the
//  corner of the illustration.
//
//  Game Center will happily present this screen itself, and it is not used.
//  `GKGameCenterViewController` is a stock iOS sheet — grouped table, system
//  font, the lot — and it would be the one surface in the game that looks like
//  a settings page rather than a painted one. The standings are fetched instead
//  and laid out here.
//
//  Nothing in this file is GameKit. It draws `Leaderboard.Standing`, which is
//  ordinary data, so the board can be laid out and looked at without a
//  signed-in account or a network — see the previews at the bottom.
//

import OSLog
import SwiftUI

struct LeaderboardView: View {
    /// The player's own best, from the device. Shown while the board is still
    /// loading and if it never arrives, so the screen always has a number on it
    /// even with no signal.
    let bestScore: Int

    @Environment(\.dismiss) private var dismiss
    @StateObject private var leaderboard = Leaderboard.shared

    @State private var phase: Phase

    /// Every way this screen can look, including signed out.
    ///
    /// One state and not a state plus a flag: signed-out is not a variation on
    /// loading or on failing, it is a fourth thing the screen can be, and
    /// keeping it in here is what stops the panel having to ask two questions
    /// to work out what to draw.
    fileprivate enum Phase: Equatable {
        case signedOut
        case loading
        case loaded(you: Leaderboard.Standing?, standings: [Leaderboard.Standing])
        case failed(Leaderboard.Failure)
    }

    init(bestScore: Int) {
        self.bestScore = bestScore
        _phase = State(initialValue: .loading)
    }

    /// Stands the screen up in a given state. For the previews, which is the
    /// only way to look at a full board without a signed-in account.
    fileprivate init(bestScore: Int, phase: Phase) {
        self.bestScore = bestScore
        _phase = State(initialValue: phase)
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

            // The same corner, the same disc, the same insets as the About
            // page — the two screens share a header illustration, so anything
            // else would read as two different ways out of one place.
            GeometryReader { _ in
                CircleBackButton { dismiss() }
                    .padding(.leading, 32)
                    .padding(.top, 26)
            }
            .ignoresSafeArea(edges: .top)
        }
        .statusBarHidden()
        .task { await load() }
    }

    private static let log = Logger(subsystem: "donaghey.BennysGreatEscape", category: "leaderboard")

    private func load() async {
        guard leaderboard.isAuthenticated else {
            phase = .signedOut
            return
        }
        phase = .loading
        do {
            let result = try await leaderboard.loadTop100()
            phase = .loaded(you: result.you, standings: result.standings)
        } catch {
            // The raw error only ever reaches a developer, and it is the one
            // thing that says which of the two failures this actually is —
            // most usefully, whether Game Center returned no board for our ID
            // or refused to recognise the app at all.
            //
            // Through `Logger` rather than `print`, because this is a fault
            // that only shows up on a signed-in device: `print` goes to stdout
            // and needs Xcode attached to be seen, where this lands in the
            // unified log and can be read off a phone that is merely plugged
            // in — `log stream --predicate 'subsystem == "donaghey.BennysGreatEscape"'`.
            let ns = error as NSError
            Self.log.error(
                "leaderboard '\(Leaderboard.id, privacy: .public)' failed to load: \(ns.domain, privacy: .public) \(ns.code) — \(ns.localizedDescription, privacy: .public)"
            )
            phase = .failed(Leaderboard.failure(for: error))
        }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(spacing: 0) {
            heading
            yourBest
            board
        }
        .padding(.bottom, 44)
        .background(GameStyle.parchment)
    }

    private var heading: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 20))
                .foregroundStyle(GameStyle.amberDeep)
            Text("LEADERBOARD")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .kerning(1.5)
                .foregroundStyle(GameStyle.ink)
            Image(systemName: "trophy.fill")
                .font(.system(size: 20))
                .foregroundStyle(GameStyle.amberDeep)
        }
        .padding(.top, 26)
        .padding(.bottom, 16)
    }

    /// Lifted from `AboutView.bestRun` — the same card, so the two pages agree
    /// about what a best run looks like.
    private var yourBest: some View {
        VStack(spacing: 2) {
            Text("\(bestScore)")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(GameStyle.ink)
            Text(bestScore > 0 ? "obstacles cleared, your best run" : "no runs yet — go and get one")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(GameStyle.ink.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var board: some View {
        switch phase {
        case .signedOut:
            note("Sign in to Game Center to see how your runs stack up against everyone else's.\n\nYour best run is still saved on this device either way.")

        case .loading:
            ProgressView()
                .controlSize(.large)
                .tint(GameStyle.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)

        case .loaded(_, let standings) where standings.isEmpty:
            note("Nobody has posted a run yet.\nBe the first.")

        case let .loaded(you, standings):
            VStack(spacing: 8) {
                ForEach(standings) { row($0) }
            }
            .padding(.horizontal, 24)

            // Only when they aren't already up there in the hundred. This is
            // the part a table of our own couldn't do: a rank of 4,000 still
            // means something to the player holding it.
            if let you, !standings.contains(where: \.isYou) {
                VStack(spacing: 8) {
                    Text("YOUR RANK")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .kerning(1.2)
                        .foregroundStyle(GameStyle.ink.opacity(0.5))
                    row(you)
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
            }

        // Nothing to retry: the board isn't there to be fetched. Said the way
        // a player can act on — which is to say, not asking them to do
        // anything — while being unmistakable to us that `Leaderboard.id` has
        // no published board behind it.
        case .failed(.notConfigured):
            note("The leaderboard isn't open yet.\nCheck back soon.")

        case .failed(.offline):
            VStack(spacing: 16) {
                note("Couldn't reach the leaderboard.\nCheck your connection.")
                Button {
                    Task { await load() }
                } label: {
                    Text("TRY AGAIN")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .kerning(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .frame(height: 44)
                        .background {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [GameStyle.amber, GameStyle.amberDeep],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 3))
                        }
                }
                .buttonStyle(SpringyButton())
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15.5, weight: .medium, design: .rounded))
            .foregroundStyle(GameStyle.ink.opacity(0.78))
            .lineSpacing(3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
    }

    // MARK: - A row

    private func row(_ standing: Leaderboard.Standing) -> some View {
        let isYou = standing.isYou
        return HStack(spacing: 14) {
            // Wide enough for a four-figure rank, and allowed to shrink past
            // that rather than wrap. The player's own rank is the one number
            // here that isn't in the top hundred — it is routinely four or five
            // figures, and at 34 points "4,213" broke across two lines.
            Text("\(standing.rank)")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(rankTint(standing.rank))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 54, alignment: .center)

            Text(standing.name)
                .font(.system(size: 15.5, weight: isYou ? .black : .semibold, design: .rounded))
                .foregroundStyle(GameStyle.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(standing.score)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(GameStyle.ink)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isYou ? GameStyle.amber.opacity(0.38) : .white.opacity(0.45))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(GameStyle.amberDeep.opacity(isYou ? 0.85 : 0), lineWidth: 2.5)
                }
        }
    }

    /// Gold, silver and bronze, and then the ink everything else is set in.
    private func rankTint(_ rank: Int) -> Color {
        switch rank {
        case 1: Color(red: 0.80, green: 0.60, blue: 0.09)
        case 2: Color(red: 0.55, green: 0.57, blue: 0.60)
        case 3: Color(red: 0.66, green: 0.42, blue: 0.22)
        default: GameStyle.ink.opacity(0.55)
        }
    }
}

#Preview("Top 100") {
    LeaderboardView(bestScore: 17, phase: .loaded(you: nil, standings: [
        .init(rank: 1, name: "RabbitChaser", score: "412", isYou: false),
        .init(rank: 2, name: "Milo", score: "388", isYou: false),
        .init(rank: 3, name: "a-very-long-game-center-nickname", score: "377", isYou: false),
        .init(rank: 4, name: "You", score: "351", isYou: true),
        .init(rank: 5, name: "Poppy", score: "244", isYou: false),
    ]))
}

#Preview("Ranked below the hundred") {
    LeaderboardView(bestScore: 17, phase: .loaded(
        you: .init(rank: 4213, name: "You", score: "17", isYou: true),
        standings: [
            .init(rank: 1, name: "RabbitChaser", score: "412", isYou: false),
            .init(rank: 2, name: "Milo", score: "388", isYou: false),
        ]
    ))
}

#Preview("Signed out") {
    LeaderboardView(bestScore: 17, phase: .signedOut)
}

#Preview("Offline") {
    LeaderboardView(bestScore: 0, phase: .failed(.offline))
}
