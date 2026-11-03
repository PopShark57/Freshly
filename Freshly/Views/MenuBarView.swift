import SwiftUI

struct MenuBarView: View {
    @Environment(UpdateCenter.self) private var center
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let updates = center.updates

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Freshly").font(.headline)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                if center.isBusy {
                    ProgressView(value: center.progress)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }
            }

            if updates.isEmpty {
                Label("Everything's fresh", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(updates) { app in
                            row(app)
                        }
                    }
                }
                .frame(maxHeight: 280)
                .scrollBounceBehavior(.basedOnSize)
            }

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        Task { await center.refresh(forceCatalogue: true) }
                    } label: {
                        Label("Check Now", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                    .disabled(center.isBusy)

                    Spacer()

                    Button {
                        openWindow(id: "main")
                        NSApp.activate()
                    } label: {
                        Text("Open Freshly")
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                    }
                    .buttonStyle(.glass)
                    .help("Quit Freshly")
                }
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var status: String {
        if center.isBusy { return "Checking \(center.checkedCount) of \(center.apps.count)…" }
        let count = center.updates.count
        return count == 0 ? "\(center.apps.count) apps up to date" : "\(count) update\(count == 1 ? "" : "s") available"
    }

    private func row(_ app: InstalledApp) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIcons.icon(for: app.url))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.name).lineLimit(1)
                Text("\(app.version) → \(center.result(for: app)?.latestVersion ?? "?")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let action = center.primaryAction(for: app) {
                Button {
                    center.perform(action, for: app)
                } label: {
                    Image(systemName: action.symbol)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help(action.help)
            }
        }
        .padding(.horizontal, 6)
    }
}
