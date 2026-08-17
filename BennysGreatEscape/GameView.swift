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

    @State private var hasStarted = false

    // Each control is taught once, ever.
    @AppStorage("seenJumpHint") private var seenJumpHint = false
    @AppStorage("seenSlideHint") private var seenSlideHint = false
    @State private var hint: Hint?

    private enum Hint {
        case jump, slide
    }

    var body: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: scene)
                .ignoresSafeArea()

            if hasStarted {
                scoreboard
                    .transition(.opacity)
            } else {
                // Sits above the scene and takes the first tap itself, so the
                // scene's own touch handling stays purely swipe-and-retry.
                TitleView(bestScore: bestScore, onStart: start)
                    .transition(.opacity)
            }

            if let hint {
                hintCard(hint)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 60)
                    .allowsHitTesting(false)
            }
        }
        .statusBarHidden()
        .onAppear {
            scene.onScoreChange = { score = $0 }
            scene.onGameOver = { bestScore = max(bestScore, $0) }
            scene.onFirstRail = {
                guard !seenSlideHint else { return }
                seenSlideHint = true
                show(.slide)
            }
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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { hint = which }
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(.easeOut(duration: 0.3)) {
                if hint == which { hint = nil }
            }
        }
    }

    private func start() {
        scene.start()
        withAnimation(.easeOut(duration: 0.35)) { hasStarted = true }
        if !seenJumpHint {
            seenJumpHint = true
            show(.jump)
        }
    }

    /// Back out to the title. The scene is wound back to its opening state so
    /// the next Play is a fresh run rather than resuming a half-finished one.
    private func returnToTitle() {
        scene.returnToTitle()
        score = 0
        withAnimation(.easeOut(duration: 0.3)) { hasStarted = false }
    }

    private var scoreboard: some View {
        HStack(alignment: .top) {
            // Sits above the SpriteView, so it takes the tap rather than the
            // scene turning it into a jump.
            CircleBackButton(action: returnToTitle, symbol: "chevron.left")

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
                        .foregroundStyle(.black.opacity(0.55))
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
