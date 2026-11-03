import SwiftUI
import WebKit

struct InspectorView: View {
    @Environment(UpdateCenter.self) private var center

    var body: some View {
        if let app = center.selectedApp {
            AppDetail(app: app, result: center.result(for: app))
                .id(app.id)
        } else {
            ContentUnavailableView("No App Selected", systemImage: "app.dashed",
                                   description: Text("Pick an app to see its versions and release notes."))
        }
    }
}

private struct AppDetail: View {
    @Environment(UpdateCenter.self) private var center
    let app: InstalledApp
    let result: UpdateResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            facts
            actions
            if let message = result?.message {
                Label(message, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(result?.status == .failed ? .orange : .secondary)
            }
            ReleaseNotes(result: result)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: AppIcons.icon(for: app.url))
                .resizable()
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.title2.bold())
                Text(app.bundleID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Text("Installed").foregroundStyle(.secondary)
                Text(app.displayVersion).monospacedDigit()
            }
            GridRow {
                Text("Latest").foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(result?.latestVersion ?? "—").monospacedDigit().fontWeight(.semibold)
                    if result?.status == .updateAvailable {
                        Image(systemName: "sparkles").foregroundStyle(.green)
                            .symbolEffect(.wiggle, options: .repeat(2))
                    }
                }
            }
            GridRow {
                Text("Source").foregroundStyle(.secondary)
                SourceBadge(source: result?.source ?? .unknown)
            }
            if let token = result?.brewToken {
                GridRow {
                    Text("Homebrew").foregroundStyle(.secondary)
                    Text("\(token)\(result?.brewManaged == true ? " · installed with brew" : "")")
                        .font(.callout.monospaced())
                }
            }
            if let checked = result?.checkedAt, result?.status != .checking {
                GridRow {
                    Text("Checked").foregroundStyle(.secondary)
                    Text(checked, format: .relative(presentation: .named))
                }
            }
            GridRow {
                Text("Location").foregroundStyle(.secondary)
                Text(app.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .font(.callout)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if let action = center.primaryAction(for: app) {
                    Button {
                        center.perform(action, for: app)
                    } label: {
                        Label(action.title, systemImage: action.symbol)
                    }
                    .buttonStyle(.glassProminent)
                    .help(action.help)
                }
                Button {
                    center.reveal(app)
                } label: {
                    Label("Finder", systemImage: "folder")
                }
                .buttonStyle(.glass)
                Menu {
                    AppActionsMenu(app: app)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .fixedSize()
            }
            .controlSize(.large)
        }
    }
}

private struct ReleaseNotes: View {
    let result: UpdateResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Release Notes")
                .font(.headline)

            Group {
                if let notes = result?.releaseNotes, !notes.isEmpty {
                    ScrollView {
                        Text(result?.releaseNotesAreHTML == true ? Self.attributed(notes) : AttributedString(notes))
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                } else if let url = result?.releaseNotesURL, result?.source != .homebrew {
                    WebView(url: url)
                } else {
                    ContentUnavailableView("No Release Notes", systemImage: "doc.text",
                                           description: Text("This update feed doesn't publish any."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background.secondary, in: .rect(cornerRadius: 14))
            .clipShape(.rect(cornerRadius: 14))
        }
        .frame(maxHeight: .infinity)
    }

    /// Turns appcast HTML snippets into native text that follows the system font and light/dark mode.
    private static var cache: [String: AttributedString] = [:]

    static func attributed(_ html: String) -> AttributedString {
        if let cached = cache[html] { return cached }
        let result = parse(html)
        cache[html] = result
        return result
    }

    private static func parse(_ html: String) -> AttributedString {
        let document = """
        <!doctype html><html><head><meta charset="utf-8">
        <style>body { font-family: -apple-system; font-size: 13px; } h1, h2, h3 { font-size: 14px; } img { display: none; }</style>
        </head><body>\(html)</body></html>
        """
        guard let parsed = try? NSMutableAttributedString(
            data: Data(document.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil)
        else { return AttributedString(html) }

        // Drop the HTML's hard-coded black so SwiftUI's primary color applies, and trim trailing blank lines.
        parsed.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: parsed.length))
        while parsed.string.last?.isNewline == true {
            parsed.deleteCharacters(in: NSRange(location: parsed.length - 1, length: 1))
        }
        return (try? AttributedString(parsed, including: \.appKit)) ?? AttributedString(parsed.string)
    }
}
