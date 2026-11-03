import SwiftUI

struct AppListView: View {
    @Environment(UpdateCenter.self) private var center

    var body: some View {
        @Bindable var center = center
        let apps = center.visibleApps

        List(selection: $center.selection) {
            ForEach(apps) { app in
                AppRow(app: app)
                    .tag(app.id)
            }
        }
        .listStyle(.inset)
        .animation(.smooth, value: apps.map(\.id))
        .overlay {
            if apps.isEmpty && !center.isBusy {
                emptyState
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HeroHeader()
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !center.searchText.isEmpty {
            ContentUnavailableView.search(text: center.searchText)
        } else if center.filter == .updates {
            ContentUnavailableView {
                Label("Everything's Fresh", systemImage: "sparkles")
                    .symbolEffect(.breathe)
            } description: {
                Text("All \(center.apps.count) apps are up to date.")
            }
        } else {
            ContentUnavailableView("Nothing Here", systemImage: "tray",
                                   description: Text("No apps match this filter."))
        }
    }
}
