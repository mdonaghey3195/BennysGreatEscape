//
//  AboutView.swift
//  Benny's Great Escape
//

import SwiftUI

struct AboutView: View {
    let bestScore: Int

    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let bundle = Bundle.main
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image("benny_jump_1")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 130)
                        .padding(.top, 12)

                    VStack(spacing: 8) {
                        Text("Benny's Great Escape")
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .multilineTextAlignment(.center)

                        Text("Tap to jump. That's the whole game.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if bestScore > 0 {
                        VStack(spacing: 2) {
                            Text("\(bestScore)")
                                .font(.system(size: 44, weight: .heavy, design: .rounded))
                            Text("obstacles cleared, best run")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                    }

                    Text("Benny is a real dog. He started out hidden inside a pet-tracking app, behind a triple-tap, and escaped.")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text(version)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .padding(24)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    AboutView(bestScore: 17)
}
