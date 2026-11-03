import SwiftUI

struct AppRow: View {
    @Environment(UpdateCenter.self) private var center
    let app: InstalledApp

    var body: some View {
        let result = center.result(for: app)

        HStack(spacing: 12) {
            Image(nsImage: AppIcons.icon(for: app.url))
                .resizable()
                .interpolation(.high)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let result, result.status != .checking {
                        SourceBadge(source: result.source)
                    }
                    if result?.brewManaged == true {
                        Image(systemName: "mug.fill")
                            .font(.caption2)
                            .foregroundStyle(.brown)
                            .help("Installed with Homebrew")
                    }
                    Text(app.folderDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VersionPill(app: app, result: result, ignored: center.isIgnored(app))

            if center.hasUpdate(app), let action = center.primaryAction(for: app) {
                Button {
                    center.perform(action, for: app)
                } label: {
                    Label(action.title, systemImage: action.symbol)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
                .help(action.help)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 5)
        .animation(.bouncy, value: result?.status)
        .contextMenu { AppActionsMenu(app: app) }
    }
}

struct SourceBadge: View {
    let source: UpdateSource

    var body: some View {
        Label(source.label, systemImage: source.symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(source.tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(source.tint.opacity(0.12), in: .capsule)
    }
}

/// "installed → latest", with a tinted glass capsule when there's something new.
struct VersionPill: View {
    let app: InstalledApp
    let result: UpdateResult?
    let ignored: Bool

    var body: some View {
        Group {
            switch result?.status {
            case .checking, nil:
                HStack(spacing: 6) {
                    Text(app.version).foregroundStyle(.secondary)
                    ProgressView().controlSize(.mini)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)

            case .updateAvailable where !ignored:
                HStack(spacing: 5) {
                    Text(app.version).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                    Text(result?.latestVersion ?? "?")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .glassEffect(.regular.tint(.green.opacity(0.25)), in: .capsule)

            case .upToDate:
                Label(app.version, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
                    .padding(.horizontal, 10).padding(.vertical, 4)

            case .managed:
                Label(app.version, systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .help(result?.message ?? "")

            case .failed:
                Label(app.version, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .help(result?.message ?? "Couldn't check")

            default:
                Label(app.version, systemImage: ignored ? "eye.slash" : "questionmark.circle")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .help(result?.message ?? "")
            }
        }
        .font(.callout.monospacedDigit())
        .lineLimit(1)
        .fixedSize()
        .contentTransition(.numericText())
    }
}

/// Shared between the row context menu and the inspector's "More" menu.
struct AppActionsMenu: View {
    @Environment(UpdateCenter.self) private var center
    let app: InstalledApp

    var body: some View {
        let result = center.result(for: app)

        if let action = center.primaryAction(for: app) {
            Button(action.title, systemImage: action.symbol) { center.perform(action, for: app) }
        }
        if let token = result?.brewToken, result?.brewManaged == true, result?.brewHasUpdate == true {
            Button("Upgrade with Homebrew", systemImage: "mug") { center.brew.upgrade([token]) }
        }
        if let download = result?.downloadURL {
            Button("Download Latest", systemImage: "arrow.down.circle") { NSWorkspace.shared.open(download) }
        }
        if let notes = result?.releaseNotesURL {
            Button("Release Notes", systemImage: "doc.text") { NSWorkspace.shared.open(notes) }
        }
        if let homepage = result?.homepageURL {
            Button("Website", systemImage: "safari") { NSWorkspace.shared.open(homepage) }
        }
        Divider()
        Button("Open App", systemImage: "arrow.up.forward.app") { center.perform(.launch, for: app) }
        Button("Show in Finder", systemImage: "folder") { center.reveal(app) }
        Button("Check Again", systemImage: "arrow.clockwise") { Task { await center.recheck([app]) } }
        Divider()
        if center.isIgnored(app) {
            Button("Stop Ignoring", systemImage: "eye") { center.unignore(bundleID: app.bundleID) }
        } else {
            if result?.status == .updateAvailable, let latest = result?.latestVersion {
                Button("Skip Version \(latest)", systemImage: "forward") { center.ignoreVersion(app) }
            }
            Button("Ignore \(app.name)", systemImage: "eye.slash") { center.ignoreApp(app) }
        }
    }
}
