//
//  Leaderboard.swift
//  Benny's Great Escape
//
//  The global board, which is Game Center's rather than ours. Everything
//  GameKit lives behind this one object, so the views and the scene never
//  import it.
//
//  There is no database here and there is no server. A run is a single
//  ascending Int, which is the one shape Game Center exists to serve, and in
//  return Apple keeps the scores, owns the identities, does the ranking and
//  watches for cheating. What we keep on the device is what we always kept:
//  `bestScore`, which is nobody's business but the player's.
//

import GameKit

@MainActor
final class Leaderboard: ObservableObject {
    static let shared = Leaderboard()

    /// Matches the leaderboard created in App Store Connect. A typo here fails
    /// silently — submissions go nowhere and the board comes back empty — so
    /// it is written once, here.
    static let id = "benny.bestrun"

    /// Drives which face `LeaderboardView` shows. Published because
    /// authentication finishes long after the view has been drawn.
    @Published private(set) var isAuthenticated = false

    private var hasRequestedAuthentication = false

    private init() {}

    // MARK: - Signing in

    /// Called once at launch.
    ///
    /// GameKit calls the handler back on its own schedule and more than once —
    /// on sign-in, on sign-out, and when the player switches accounts — so this
    /// sets it up and then gets out of the way. It is deliberately not awaited
    /// anywhere: the game is fully playable signed out, and a title screen that
    /// waited on the network before it would take a tap would be a bad trade
    /// for a feature most players open once.
    func authenticate() {
        guard !hasRequestedAuthentication else { return }
        hasRequestedAuthentication = true

        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            // The sign-in sheet. Presented if GameKit asks for it, and only
            // then — never summoned, so a player who has declined is not asked
            // again every launch.
            if let viewController {
                Self.present(viewController)
                return
            }
            self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            // Off, always. It is a floating Game Center widget that parks
            // itself over a corner of the artwork and stays there during play,
            // on top of the score.
            GKAccessPoint.shared.isActive = false
        }
    }

    private static func present(_ viewController: UIViewController) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let root = scene?.keyWindow?.rootViewController else { return }
        // Anything already up — the About page, Settings — owns the screen, and
        // presenting from underneath it throws.
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(viewController, animated: true)
    }

    // MARK: - Posting a run

    /// Fire and forget, and deliberately so.
    ///
    /// This is called from the crash, with the retry prompt already on screen.
    /// A submission that failed — no signal, not signed in, Game Center having
    /// a bad day — must not put an error in front of a player who is trying to
    /// start another run, so nothing here is awaited and nothing is surfaced.
    /// The score is not lost in any way that matters: the next run posts again.
    func submit(_ score: Int) {
        guard isAuthenticated else { return }
        Task {
            try? await GKLeaderboard.submitScore(
                score,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [Self.id]
            )
        }
    }

    // MARK: - Reading the board

    /// The top hundred, all time, plus wherever the player themselves sits.
    ///
    /// The player's own standing comes back separately from the list rather
    /// than being found in it, which is the whole reason to ask GameKit rather
    /// than to keep a table of our own: somebody ranked 4,000th is not in the
    /// top hundred and can still be told they are 4,000th.
    func loadTop100() async throws -> (you: Standing?, standings: [Standing]) {
        let boards = try await GKLeaderboard.loadLeaderboards(IDs: [Self.id])
        guard let board = boards.first else { throw LeaderboardError.missingBoard }

        // The range is 1-based. A location of 0 throws rather than returning
        // the first hundred.
        let (mine, everyone, _) = try await board.loadEntries(
            for: .global,
            timeScope: .allTime,
            range: NSRange(location: 1, length: 100)
        )
        return (mine.map(Standing.init), everyone.map(Standing.init))
    }

    /// One line of the board.
    ///
    /// GameKit's own entry type is left at this boundary on purpose. It carries
    /// a live `GKPlayer` and cannot be constructed, which would make the board
    /// screen impossible to lay out without a signed-in account and a network —
    /// and the screen is the part most worth being able to look at.
    struct Standing: Identifiable, Equatable {
        let rank: Int
        let name: String
        /// Already formatted, so the suffix set in App Store Connect survives.
        let score: String
        let isYou: Bool

        var id: Int { rank }

        init(rank: Int, name: String, score: String, isYou: Bool) {
            self.rank = rank
            self.name = name
            self.score = score
            self.isYou = isYou
        }

        init(_ entry: GKLeaderboard.Entry) {
            let isYou = entry.player == GKLocalPlayer.local
            self.init(
                rank: entry.rank,
                name: isYou ? "You" : entry.player.displayName,
                score: entry.formattedScore,
                isYou: isYou
            )
        }
    }

    enum LeaderboardError: Error {
        /// The ID above doesn't match anything in App Store Connect, or the
        /// board has no localization and so isn't live yet.
        case missingBoard
    }

    /// Why a load failed, in the two flavours that call for different words.
    ///
    /// Worth telling apart because the screen used to call both of them a
    /// connection problem, and they are nothing alike: one is the player's
    /// signal and clears itself, the other is a board that was never set up and
    /// will still be missing however many times they tap Try Again.
    enum Failure: Equatable {
        /// Game Center has nothing under `Leaderboard.id`. Ours to fix, not
        /// theirs: the app has no record in App Store Connect, or the
        /// leaderboard doesn't exist there, or it exists with no localization
        /// and so was never published.
        case notConfigured

        /// Game Center couldn't be reached. Retrying is worth a try.
        case offline
    }

    /// Sorts a thrown error into one of those.
    ///
    /// Anything unrecognised is treated as `offline`, which is the safer of the
    /// two to be wrong about: it offers a retry and blames nobody, where a
    /// wrong `notConfigured` would tell a player the feature doesn't exist.
    static func failure(for error: Error) -> Failure {
        if error is LeaderboardError { return .notConfigured }

        let ns = error as NSError
        guard ns.domain == GKErrorDomain,
              let code = GKError.Code(rawValue: ns.code) else { return .offline }

        switch code {
        // The app itself isn't known to Game Center, or the ID isn't a board
        // it has. Both mean the same thing to a player and to us.
        case .gameUnrecognized, .notSupported, .invalidParameter:
            return .notConfigured
        default:
            return .offline
        }
    }
}
