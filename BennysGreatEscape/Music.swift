//
//  Music.swift
//  Benny's Great Escape
//
//  The looping theme, and the small amount of state it takes to keep it
//  polite: it mixes with whatever the player already had going, obeys the
//  ring/silent switch, and ducks rather than stops when a run ends.
//
//  The tune itself lives in `Music/` at the repo root — score, MIDI and the
//  script that renders both.
//

import AVFoundation

/// One instance, because two would fight over the audio session and drift out
/// of phase with each other within a few bars.
final class Music {
    static let shared = Music()

    /// Loud enough to notice, quiet enough to sit under the game. This is
    /// background music; the player is listening for their own rhythm.
    private static let full: Float = 0.55

    /// Where a game over drops to, so "Good boy! Tap to retry" lands in
    /// relative quiet without the tune stopping dead every time Benny trips.
    private static let ducked: Float = 0.18

    /// Long enough that a change reads as a fade rather than a jump, short
    /// enough to have finished before the player taps to retry.
    private static let fade: TimeInterval = 0.4

    private var player: AVAudioPlayer?

    /// What the game has asked for. Whether it is actually audible also
    /// depends on `isEnabled`, which is the player's business rather than the
    /// game's — keeping the two apart is what lets the mute button survive a
    /// game over, a retry and a trip back to the title screen.
    private var wanted = false
    private var isDucked = false

    /// Mirrors the player's saved preference. Set it once at launch and then
    /// whenever they hit the button.
    var isEnabled = true {
        didSet { if isEnabled != oldValue { sync() } }
    }

    private init() {}

    // MARK: - What the game asks for

    /// Loads the player before it is wanted. Called once at launch, next to
    /// `Sfx.prepare`, for the same reason: left to `play`, the file was opened,
    /// the session activated and the first buffers decoded on the main thread
    /// on the exact frame the run began — a stall at the start of every first
    /// run of a session.
    ///
    /// Built off the main thread — opening the file and activating the session
    /// measured 200 ms, all of it before the title could draw — and handed over
    /// on it. If a run has started before the hand-over, `sync` has already
    /// loaded its own and this one is dropped.
    func prepare() {
        guard player == nil else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let built = Self.build()
            DispatchQueue.main.async {
                guard self.player == nil, let built else { return }
                self.player = built
                self.sync()
            }
        }
    }

    /// Starts a run's music, from the top if it had been stopped.
    func play() {
        wanted = true
        isDucked = false
        sync()
    }

    /// A run ended. Drops to `ducked` rather than stopping, so retrying feels
    /// continuous rather than like starting the app again.
    func duck() {
        isDucked = true
        sync()
    }

    /// Back to full for a fresh run.
    func unduck() {
        isDucked = false
        sync()
    }

    /// Leaves the game entirely. Rewinds, so the next run opens on the first
    /// bar instead of halfway through a phrase.
    func stop() {
        wanted = false
        isDucked = false
        sync()
        player?.currentTime = 0
    }

    // MARK: - Making it so

    private func sync() {
        guard wanted, isEnabled else {
            // Paused rather than stopped: muting mid-run and unmuting should
            // pick the tune up where it was, not restart it.
            player?.setVolume(0, fadeDuration: Self.fade)
            player?.pause()
            return
        }
        guard let player = player ?? load() else { return }
        player.setVolume(isDucked ? Self.ducked : Self.full, fadeDuration: Self.fade)
        if !player.isPlaying { Probe.time("Music.play") { player.play() } }
    }

    private func load() -> AVAudioPlayer? {
        let built = Self.build()
        player = built
        return built
    }

    /// The player, ready to go, or nil if the device's audio won't have it.
    private static func build() -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: "benny_theme", withExtension: "m4a") else {
            return nil
        }
        do {
            // `.ambient` is the polite category: it honours the ring/silent
            // switch, and it mixes rather than interrupting — nobody's podcast
            // should stop because Benny started running.
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            // The render is loop-clean by construction, so this needs no
            // crossfade — see `Music/README.md`.
            player.numberOfLoops = -1
            // Silent to begin with; `sync` fades it up. Otherwise the first
            // bar arrives at full volume before the fade can take hold.
            player.volume = 0
            player.prepareToPlay()
            return player
        } catch {
            // A game with no music is still a game. Anything thrown here is
            // about the device's audio, not something the player can act on.
            return nil
        }
    }
}
