//
//  GameView.swift
//  Benny's Great Escape
//
//  Hosts the SpriteKit scene and the score readout, and holds the title screen
//  over the top until the player taps to begin.
//

import SpriteKit
import SwiftUI

struct GameView: View {
    @AppStorage("bestScore") private var bestScore = 0

    /// Built once and held. Creating the scene inside `body` — even indirectly,
    /// via a `GeometryReader` — hands `SpriteView` a brand new scene on every
    /// re-render, so recording a best score would restart the game that just
    /// ended.
    @State private var scene = GameScene.make()

    /// Drawn here rather than as an `SKLabelNode` so it always lands inside the
    /// safe area — the scene is scaled with `.aspectFill`, which crops whichever
    /// edges don't match the screen's aspect.
    @State private var score = 0

    /// Three states, not two: while the opening clip runs, neither the title
    /// nor the score belongs over the top of it.
    @State private var phase: Phase = .title

    private enum Phase {
        case title, intro, playing
    }

    // Each control is taught once, ever.
    @AppStorage("seenJumpHint") private var seenJumpHint = false
    @AppStorage("seenSlideHint") private var seenSlideHint = false

    /// Set on the Settings page; read here only to tell `Music` about it at
    /// launch. Deliberately separate from whether the game currently wants
    /// music — see `Music`.
    @AppStorage("musicOn") private var musicOn = true
    @State private var hint: Hint?

    /// Play was tapped before the run's art had finished loading. The run
    /// starts on its own the moment it has — see `start`.
    @State private var startWhenReady = false

    private enum Hint {
        case jump, slide
    }

    var body: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: scene)
                .ignoresSafeArea()

            // Always in the tree, shown by opacity, rather than added when the
            // run begins. A view's first layout is its dear one — the rounded
            // font, the symbol, the shadow are all loaded then — and added on
            // the frame the run started it measured 60–120 ms of main thread,
            // with the hint card: a visible catch on Benny's first stride.
            // Laid out here at launch it costs the title screen instead, where
            // nothing is moving. Hit-testing is off while hidden so the clip's
            // skip-tap still reaches the scene.
            scoreboard
                .opacity(phase == .playing ? 1 : 0)
                .allowsHitTesting(phase == .playing)
                .animation(.easeOut(duration: 0.35), value: phase)

            // The same for the hint card: one of each is laid out invisibly at
            // launch, so the first one that matters is a fade and not a build.
            if hint == nil {
                HintCard(symbol: "arrow.up", title: "JUMP!", detail: "Swipe up to leap over obstacles.")
                    .opacity(0)
                    .allowsHitTesting(false)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 60)
            }

            // Sits above the scene and takes the first tap itself, so the
            // scene's own touch handling stays purely swipe-and-retry.
            if phase == .title {
                TitleView(bestScore: bestScore, onStart: start)
                    .transition(.opacity)
            }

            if let hint {
                hintCard(hint)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 60)
                    .allowsHitTesting(false)
            }

            // Only ever seen on a tap that beat the loading, which on a phone
            // means a tap within about a second of launch.
            if startWhenReady {
                Text("Loading…")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.35), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .onAppear {
            Music.shared.isEnabled = musicOn
            // The same switch. The settings row says "Turn game sounds on or
            // off", and the effects are game sounds.
            Sfx.shared.isEnabled = musicOn
            // Both loaded up front: an effect that decodes its file on the frame
            // it first plays, and a haptic generator that spins the engine up on
            // the frame it first fires, are both a miss.
            Probe.time("Sfx.prepare") { Sfx.shared.prepare() }
            Probe.time("Music.prepare") { Music.shared.prepare() }
            Probe.time("Haptics.prepare") { Haptics.prepare() }
            // Game Center is *not* signed into here. It used to be, and the
            // sign-in finishes a second or so after launch with a system
            // banner — or, signed out, a sheet — on the main thread: measured
            // at 450–600 ms of stall in the simulator, landing under the title
            // or, for a quick tap on Play, on the opening clip. It now happens
            // at the first game over, where the screen is still and the
            // player is reading "Tap to retry", or when the board is opened.
            // `Leaderboard.submit` holds that first score until it is signed in.
            scene.onScoreChange = { score = $0 }
            scene.onGameOver = {
                bestScore = max(bestScore, $0)
                // Every run, not just the ones that beat the local best. Game
                // Center keeps the higher of the two itself, and posting
                // unconditionally means a score still reaches the board on a
                // device whose `bestScore` was wiped by a restore.
                Leaderboard.shared.submit($0)
                Music.shared.duck()
            }
            scene.onRetry = { Music.shared.unduck() }
            scene.onIntroFinished = beginPlaying
            scene.onFirstLowObstacle = {
                guard !seenSlideHint else { return }
                seenSlideHint = true
                show(.slide)
            }
            Probe.mark("title up")
            #if DEBUG
            // `-AutoPlay`: taps Play two seconds in — see `GameScene.autoplayTick`.
            if GameScene.autoplays {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { start() }
            }
            #endif
        }
    }

    @ViewBuilder
    private func hintCard(_ hint: Hint) -> some View {
        switch hint {
        case .jump:
            HintCard(symbol: "arrow.up", title: "JUMP!", detail: "Swipe up to leap over obstacles.")
        case .slide:
            HintCard(symbol: "arrow.down", title: "DUCK!", detail: "Swipe down to slide under low obstacles.")
        }
    }

    private func show(_ which: Hint) {
        scene.note("hint card \(which)")
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { hint = which }
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(.easeOut(duration: 0.3)) {
                if hint == which { hint = nil }
            }
        }
    }

    /// Play, which now rolls the opening clip rather than dropping straight
    /// into a run.
    ///
    /// The card can be dropped in the same turn because the scene isn't
    /// changing under it — the clip has been standing there behind it since the
    /// world was built. See `stageIntro`.
    ///
    /// Held until the run's art is decoded and on the GPU. `ArtWarmer` starts
    /// that the moment the scene is built, and on a phone it is done well
    /// before a finger can reach the button; the hold is for the tap that
    /// isn't, so that a run never opens on a frame that is still loading.
    private func start() {
        guard GameScene.ArtWarmer.isReady(.run) else {
            guard !startWhenReady else { return }
            withAnimation(.easeOut(duration: 0.2)) { startWhenReady = true }
            GameScene.ArtWarmer.whenReady(.run) {
                startWhenReady = false
                start()
            }
            return
        }
        Probe.mark("Play tapped")
        scene.start()
        withAnimation(.easeOut(duration: 0.35)) { phase = .intro }
    }

    /// The clip is over — either it played out or it was tapped away — and this
    /// is the moment the game actually begins.
    ///
    /// The theme starts here rather than on Play, so the clip runs silent and
    /// the music lands with Benny. Likewise the jump hint, which would otherwise
    /// have come and gone before there was anything to jump.
    private func beginPlaying() {
        scene.note("run begins")
        Music.shared.play()
        withAnimation(.easeOut(duration: 0.35)) { phase = .playing }
        if !seenJumpHint {
            seenJumpHint = true
            show(.jump)
        }
    }

    /// Back out to the title. The scene is wound back to its opening state so
    /// the next Play is a fresh run rather than resuming a half-finished one.
    private func returnToTitle() {
        scene.returnToTitle()
        Music.shared.stop()
        score = 0
        withAnimation(.easeOut(duration: 0.3)) { phase = .title }
    }

    private var scoreboard: some View {
        HStack(alignment: .top) {
            // Sits above the SpriteView, so it takes the tap rather than the
            // scene turning it into a jump.
            CircleBackButton(action: returnToTitle)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(score)")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: score)

                if bestScore > 0 {
                    Text("Best \(bestScore)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        // 0.7, up from 0.55. Sampled off the sky actually
                        // behind this corner of the HUD, 0.55 gives 4.01:1 and
                        // this gives 6.30:1 — the first is under the 4.5:1
                        // readability bar and this is comfortably over it.
                        //
                        // Still clearly secondary to the score above it, which
                        // runs at full strength and measures 11.5:1 on screen.
                        .foregroundStyle(.black.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

#Preview {
    GameView()
}
