import SwiftUI

struct SidebarView: View {
    @Environment(UpdateCenter.self) private var center

    var body: some View {
        @Bindable var center = center

        List(selection: $center.filter) {
            Section("Library") {
                row(.updates, symbol: "arrow.down.circle.fill", tint: .accentColor)
                row(.all, symbol: "square.grid.2x2.fill", tint: .blue)
                row(.upToDate, symbol: "checkmark.seal.fill", tint: .green)
                row(.unknown, symbol: "questionmark.circle.fill", tint: .gray)
                row(.ignored, symbol: "eye.slash.fill", tint: .secondary)
            }
            Section("Sources") {
                ForEach(UpdateSource.allCases.filter { $0 != .unknown }) { source in
                    row(.source(source), symbol: source.symbol, tint: source.tint)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ filter: SidebarFilter, symbol: String, tint: Color) -> some View {
        Label {
            Text(filter.title)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: filter == .updates ? center.updates.count : 0)
        }
        .badge(center.apps(matching: filter).count)
        .tag(filter)
    }
}

extension UpdateSource {
    var tint: Color {
        switch self {
        case .appStore: .blue
        case .sparkle: .orange
        case .electron: .teal
        case .homebrew: .brown
        case .setapp: .pink
        case .unknown: .gray
        }
    }
}
