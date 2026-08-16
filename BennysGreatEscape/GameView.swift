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

    var body: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: scene)
                .ignoresSafeArea()

            if hasStarted {
                scoreboard
                    .transition(.opacity)
            } else {
                // Sits above the scene and takes the first tap itself, so the
                // scene's own touch handling stays purely jump-and-retry.
                TitleView(bestScore: bestScore, onStart: start)
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .onAppear {
            scene.onScoreChange = { score = $0 }
            scene.onGameOver = { bestScore = max(bestScore, $0) }
        }
    }

    private func start() {
        scene.start()
        withAnimation(.easeOut(duration: 0.35)) { hasStarted = true }
    }

    private var scoreboard: some View {
        HStack(alignment: .top) {
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
