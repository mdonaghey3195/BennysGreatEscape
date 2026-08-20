//
//  SettingsView.swift
//  Benny's Great Escape
//
//  The illustration is the screen. The card, its carved heading, the sound icon
//  and the row's text are all painted, so nothing here redraws them — the only
//  live parts are the switch, which has to show a state the painting can't, an
//  invisible target over the row that takes the tap, and the way out.
//
//  Positions are fractions of the artwork, mapped through the same aspect-fill
//  transform the image itself uses, so the live switch stays on top of the
//  painted one whatever shape the screen is.
//

import SwiftUI

struct SettingsView: View {
    /// The same key the game reads, so the preference survives a relaunch and
    /// both screens agree without either owning it.
    @AppStorage("musicOn") private var musicOn = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let row = Art.soundRow.frame(in: size)
            let knob = Art.toggle.frame(in: size)
            let back = Art.back.frame(in: size)

            ZStack(alignment: .topLeading) {
                Image("settings_art")
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()

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
                // take the tap — nothing is drawn over it.
                Button { dismiss() } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: back.width, height: back.height)
                .position(x: back.midX, y: back.midY)
                .accessibilityLabel("Back")
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        // The rest of the game hides it; a clock over the illustration here
        // would be the only place it shows.
        .statusBarHidden()
        // Applying the change here rather than inside the row keeps it working
        // however the value came to change.
        .onChange(of: musicOn) { _, isOn in
            Music.shared.isEnabled = isOn
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

/// Sampled from `settings_art` so the drawn switch matches the painted one.
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

/// Where things sit in `settings_art`, as fractions of it. Measured off the
/// PNG — re-measure these if the illustration is ever redrawn.
private enum Art {
    static let size = CGSize(width: 941, height: 1672)

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
    static let toggle = Rect(x0: 0.672, y0: 0.453, x1: 0.892, y1: 0.510)

    /// The whole painted row — icon, title, detail and switch.
    static let soundRow = Rect(x0: 0.110, y0: 0.430, x1: 0.900, y1: 0.535)

    /// The painted BACK plate. Only a target; the drawing is in the artwork.
    ///
    /// The shipped PNG is not quite the supplied original — the plate sat
    /// tight under the divider with a wide empty gap beneath it, so it was
    /// lifted and moved 120px down the card, and the space it left cloned over
    /// with parchment. Re-measure this if the illustration is ever replaced.
    static let back = Rect(x0: 0.300, y0: 0.652, x1: 0.700, y1: 0.731)
}

#Preview {
    SettingsView()
}
