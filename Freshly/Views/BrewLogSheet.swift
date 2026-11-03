import SwiftUI

struct BrewLogSheet: View {
    @Environment(UpdateCenter.self) private var center
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let brew = center.brew

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "mug.fill")
                    .font(.title)
                    .foregroundStyle(.brown.gradient)
                    .symbolEffect(.wiggle, options: .repeat(.continuous), isActive: brew.isRunning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Homebrew Upgrade").font(.title3.bold())
                    Text(brew.tokens.joined(separator: ", "))
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                statusIcon(brew)
            }

            ScrollView {
                Text(brew.log)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .defaultScrollAnchor(.bottom)
            .background(.background.secondary, in: .rect(cornerRadius: 12))

            GlassEffectContainer(spacing: 8) {
                HStack {
                    if let code = brew.exitCode, code != 0 {
                        Button {
                            brew.openInTerminal()
                        } label: {
                            Label("Open in Terminal", systemImage: "terminal")
                        }
                        .buttonStyle(.glass)
                    }
                    Spacer()
                    Button(brew.isRunning ? "Running…" : "Done") { dismiss() }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(brew.isRunning)
                }
                .controlSize(.large)
            }
        }
        .padding(20)
        .frame(width: 640, height: 440)
    }

    @ViewBuilder
    private func statusIcon(_ brew: BrewRunner) -> some View {
        if brew.isRunning {
            ProgressView().controlSize(.small)
        } else if brew.skipped {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
        } else if brew.exitCode == 0 {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: brew.exitCode)
        } else if brew.exitCode != nil {
            Image(systemName: "xmark.octagon.fill")
                .font(.title2)
                .foregroundStyle(.red)
        }
    }
}
