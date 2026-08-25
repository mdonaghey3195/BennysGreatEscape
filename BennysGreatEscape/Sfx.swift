//
//  Sfx.swift
//  Benny's Great Escape
//
//  The game's sound effects, and the small amount of state it takes to keep
//  them polite: they share the session `Music` set up, obey the same switch the
//  player threw for the music, and go quiet rather than missing when a file
//  isn't there.
//
//  The sounds themselves live in `Sounds/` at the repo root, along with the
//  script that renders them.
//

import AVFoundation

/// One instance, holding every player the game will ever need, all loaded
/// before the first one is asked for.
///
/// Loading on first use would be simpler and wrong: an `AVAudioPlayer` reads and
/// decodes its file the first time it plays, and the frame that happens on is
/// the frame Benny first jumps.
final class Sfx {
    static let shared = Sfx()

    enum Sound: String, CaseIterable {
        case jump = "sfx_jump"
        case land = "sfx_land"
        case slide = "sfx_slide"
        case crash = "sfx_crash"
    }

    /// Balance, in one table rather than spread across the call sites.
    ///
    /// The files are all mastered to the same -3 dBFS, deliberately — a render
    /// is a shape, not a level, and how loud a shape should be is a decision
    /// about the game rather than about the sound. `Music` plays at 0.55, and
    /// these sit around and under it: the crash is the only one allowed to be
    /// louder than the tune, because it is the only one that ends a run.
    private static let trim: [Sound: Float] = [
        .jump: 0.42,
        .land: 0.52,
        .slide: 0.38,
        .crash: 0.95,
    ]

    private static let barkTrim: Float = 0.85

    /// How many players each sound gets.
    ///
    /// An `AVAudioPlayer` retriggered while it is still sounding cuts itself
    /// off, and landing while the last landing is still ringing is normal play
    /// rather than an edge case. Two is enough for anything the game can
    /// actually produce: nothing here repeats faster than a jump.
    private static func voices(for sound: Sound) -> Int {
        switch sound {
        case .jump, .land: return 2
        case .slide, .crash: return 1
        }
    }

    /// Mirrors the player's saved preference, the same one `Music` reads. The
    /// settings row says "Turn game sounds on or off", so it means all of them.
    var isEnabled = true

    private var voices: [Sound: [AVAudioPlayer]] = [:]
    private var nextVoice: [Sound: Int] = [:]
    private var barks: [AVAudioPlayer] = []
    private var isLoaded = false

    private init() {}

    // MARK: - Loading

    /// Called once at launch. Safe to call again; it only does anything the
    /// first time.
    func prepare() {
        guard !isLoaded else { return }
        isLoaded = true

        // `Music` sets this too, and whichever gets there first wins — but
        // neither can assume the other loaded at all. `.ambient` is the polite
        // category: it honours the ring/silent switch and mixes rather than
        // interrupting.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        for sound in Sound.allCases {
            let level = Self.trim[sound] ?? 1
            voices[sound] = (0..<Self.voices(for: sound)).compactMap { _ in
                load(sound.rawValue, volume: level)
            }
            nextVoice[sound] = 0
        }

        // Numbered, and probed until one is missing, so the dog can be given
        // more barks by dropping the files in — the same stance `IntroArt`
        // takes with its frames.
        var index = 0
        while let bark = load("sfx_bark_\(index)", volume: Self.barkTrim) {
            barks.append(bark)
            index += 1
        }
    }

    private func load(_ name: String, volume: Float) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url)
        else {
            // A game with one sound missing is still a game — and this is how
            // the effects stay a pure asset drop.
            return nil
        }
        player.volume = volume
        player.prepareToPlay()
        return player
    }

    // MARK: - Playing

    func play(_ sound: Sound) {
        guard isEnabled, let players = voices[sound], !players.isEmpty else { return }

        // Round-robin rather than "the first one not playing": with two voices
        // they come to the same thing, and this can't be fooled by a player
        // that has finished but not yet reported it.
        let index = (nextVoice[sound] ?? 0) % players.count
        nextVoice[sound] = index + 1

        let player = players[index]
        player.currentTime = 0
        player.play()
    }

    /// The real dog, off a phone recording. More than one take of him, picked
    /// between at random: a bark is the most recognisable sound in the game and
    /// the same waveform twice is what gives a sample away.
    func bark() {
        guard isEnabled, let player = barks.randomElement() else { return }
        player.currentTime = 0
        player.play()
    }
}
