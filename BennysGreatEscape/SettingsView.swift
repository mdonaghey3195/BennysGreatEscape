//
//  SettingsView.swift
//  Benny's Great Escape
//
//  A popup card, not a screen — presented by `TitleView` as an overlay above
//  a dimmed title screen rather than a full-screen cover, so Benny, the logo
//  and the lake stay put behind it instead of being redrawn a second time.
//
//  The card, its carved heading, the sound icon and the row's text are all
//  painted, so nothing here redraws them — the only live parts are the
//  switch, which has to show a state the painting can't, an invisible target
//  over the row that takes the tap, and the way out.
//
//  Positions are fractions of `settings_card`, mapped through the same
//  aspect-fill transform the image itself uses, so the live switch stays on
//  top of the painted one whatever size the card is drawn at.
//

import SwiftUI

struct SettingsView: View {
    /// The same key the game reads, so the preference survives a relaunch and
    /// both screens agree without either owning it.
    @AppStorage("musicOn") private var musicOn = true

    /// Closed by `TitleView`, which owns whether the popup is showing at all —
    /// this view doesn't know if it's a sheet, a cover or an overlay, only how
    /// to ask to go away.
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let row = Art.soundRow.frame(in: size)
            let knob = Art.toggle.frame(in: size)
            let back = Art.back.tap.frame(in: size)
            let backPaint = Art.back.paint.frame(in: size)

            ZStack(alignment: .topLeading) {
                // A true cutout — real alpha around the rounded corners, not a
                // rectangular crop — so nothing needs clipping to hide a
                // background that was never baked in behind it.
                Image("settings_card")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)

                // The whole painted row is the target, not just the switch —
                // the switch is the smallest thing on the screen and a settings
                // row that only answers a direct hit on it is needlessly fussy.
                Button { musicOn.toggle() } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: row.width, height: row.height)
                .position(x: row.midX, y: row.midY)
                .accessibilityLabel("Sound")
                .accessibilityValue(musicOn ? "On" : "Off")
                .accessibilityHint("Double tap to turn game sounds \(musicOn ? "off" : "on")")

                // Sits exactly over the painted switch and covers it, because
                // the painting can only ever say ON. Hit testing is off so the
                // row underneath keeps the tap.
                StoneSwitch(isOn: musicOn)
                    .frame(width: knob.width, height: knob.height)
                    .position(x: knob.midX, y: knob.midY)
                    .allowsHitTesting(false)

                // BACK is painted into the illustration, so this only has to
                // take the tap and darken the plate while a finger is down —
                // the same answer the title screen's painted buttons give.
                Button(action: onDismiss) {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(PressTint(shadow: backPaint.size,
                                       cornerRadius: backPaint.height * Art.back.cornerRadius))
                .frame(width: back.width, height: back.height)
                .position(x: back.midX, y: back.midY)
                .accessibilityLabel("Back")
            }
            .frame(width: size.width, height: size.height)
        }
        // A floating card needs to lift off whatever is behind it — the
        // backdrop used to do this job by simply being the whole screen.
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
        .onChange(of: musicOn) { _, isOn in
            Music.shared.isEnabled = isOn
            Sfx.shared.isEnabled = isOn
        }
    }
}

/// The switch, drawn to sit on top of the painted one: a dark outline, an
/// olive-grey stone ring, a deep green track that greys out when off, and a
/// carved bone knob. Colours are sampled from the artwork so the live switch
/// and the painting agree.
private struct StoneSwitch: View {
    let isOn: Bool

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let ring = max(3, h * 0.15)

            // Layered outward-in the way the painting is: outline, stone ring,
            // then the track sunk inside it.
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(Palette.outline)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Palette.stoneLight, Palette.stone],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(max(1.5, h * 0.05))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [isOn ? Palette.trackLight : Palette.trackOffLight,
                                     isOn ? Palette.track : Palette.trackOff],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(Capsule().strokeBorder(Palette.outline.opacity(0.45), lineWidth: 1))
                    .padding(ring)

                Text(isOn ? "ON" : "OFF")
                    .font(.system(size: h * 0.32, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.label)
                    .shadow(color: .black.opacity(0.35), radius: 0, y: 1)
                    // Sits on the opposite side to the knob.
                    .padding(isOn ? .leading : .trailing, h * 0.26)
                    .frame(maxWidth: .infinity, alignment: isOn ? .leading : .trailing)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Palette.knobLight, Palette.knob],
                            center: .init(x: 0.38, y: 0.32),
                            startRadius: 0,
                            endRadius: h * 0.5
                        )
                    )
                    .overlay(Circle().strokeBorder(Palette.outline.opacity(0.75), lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 2, x: isOn ? -1 : 1, y: 1)
                    .padding(ring * 0.9)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isOn)
        }
    }
}

/// Sampled from `settings_card` so the drawn switch matches the painted one.
private enum Palette {
    static let outline = Color(red: 0.263, green: 0.192, blue: 0.161)
    static let stone = Color(red: 0.561, green: 0.525, blue: 0.427)
    static let stoneLight = Color(red: 0.690, green: 0.663, blue: 0.541)
    static let track = Color(red: 0.267, green: 0.424, blue: 0.031)
    static let trackLight = Color(red: 0.345, green: 0.510, blue: 0.071)
    static let trackOff = Color(red: 0.380, green: 0.360, blue: 0.310)
    static let trackOffLight = Color(red: 0.470, green: 0.450, blue: 0.395)
    static let knob = Color(red: 0.976, green: 0.886, blue: 0.737)
    static let knobLight = Color(red: 0.996, green: 0.961, blue: 0.886)
    static let label = Color(red: 0.922, green: 0.929, blue: 0.886)
}

/// Where things sit in `settings_card`, as fractions of it. Measured off the
/// PNG — re-measure these if the illustration is ever redrawn.
private enum Art {
    static let size = CGSize(width: 1364, height: 1153)

    struct Rect {
        let x0, y0, x1, y1: CGFloat

        /// Maps into view space through the same aspect-fill transform the
        /// image itself uses, so the live parts track the painted ones.
        func frame(in view: CGSize) -> CGRect {
            let scale = max(view.width / Art.size.width, view.height / Art.size.height)
            let drawn = CGSize(width: Art.size.width * scale, height: Art.size.height * scale)
            let ox = (view.width - drawn.width) / 2
            let oy = (view.height - drawn.height) / 2
            return CGRect(
                x: ox + x0 * drawn.width,
                y: oy + y0 * drawn.height,
                width: (x1 - x0) * drawn.width,
                height: (y1 - y0) * drawn.height
            )
        }
    }

    /// The painted switch. The live one is drawn a touch larger so no painted
    /// edge shows around it.
    static let toggle = Rect(x0: 0.718, y0: 0.385, x1: 0.939, y1: 0.519)

    /// The whole painted row — icon, title, detail and switch.
    static let soundRow = Rect(x0: 0.068, y0: 0.357, x1: 0.939, y1: 0.542)

    /// A painted button: where it can be tapped, where it actually is, and how
    /// round its corners are as a fraction of its height. `paint` is the
    /// plate's *outer* edge — the dark outline included — so the press tint
    /// covers it rather than leaving a bright ring around a held button.
    struct Button {
        let tap: Rect
        let paint: Rect
        let cornerRadius: CGFloat
    }

    /// The painted BACK plate. The drawing is in the artwork; only the tap and
    /// the press tint are live.
    static let back = Button(
        tap: Rect(x0: 0.241, y0: 0.680, x1: 0.754, y1: 0.863),
        paint: Rect(x0: 0.265, y0: 0.689, x1: 0.731, y1: 0.854),
        cornerRadius: 0.31
    )
}

#Preview {
    SettingsView(onDismiss: {})
}
