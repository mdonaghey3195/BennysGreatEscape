//
//  Haptics.swift
//  Benny's Great Escape
//
//  What the game does in the hand. Three weights for the three things that
//  happen to Benny, and a tick for the painted buttons.
//
//  Deliberately not tied to the sound switch. Muting a game in a quiet room is
//  exactly the moment a player still wants to feel it, and iOS already has a
//  system-level control for anyone who wants none of this.
//

import UIKit

enum Haptics {
    /// Held rather than made on demand.
    ///
    /// A generator has to spin the Taptic Engine up before it can fire, and one
    /// created at the moment of impact misses that impact — which is to say the
    /// first landing of every run, which is the one that teaches the player the
    /// game does this at all.
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let selection = UISelectionFeedbackGenerator()

    /// Called at launch, and again after each use — the engine idles back down
    /// after a moment, so staying ready is a repeated request rather than a
    /// one-off.
    static func prepare() {
        light.prepare()
        medium.prepare()
        heavy.prepare()
        selection.prepare()
    }

    /// Paws down. The lightest of the three: it happens on every jump, and
    /// anything heavier turns a run into a rattle.
    static func land() {
        light.impactOccurred()
        light.prepare()
    }

    /// Going down on his side.
    static func slide() {
        medium.impactOccurred()
        medium.prepare()
    }

    /// Running into something. The only heavy one in the game, which is what
    /// makes it mean anything.
    static func crash() {
        heavy.impactOccurred()
        heavy.prepare()
    }

    /// A painted button taking a press. Fired from the button styles in
    /// `GameStyle`, so every button in the app gets it without asking.
    static func press() {
        selection.selectionChanged()
        selection.prepare()
    }
}
