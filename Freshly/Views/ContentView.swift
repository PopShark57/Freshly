import SwiftUI

struct ContentView: View {
    @Environment(UpdateCenter.self) private var center
    @State private var showInspector = false

    var body: some View {
        @Bindable var center = center
        @Bindable var brew = center.brew

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            AppListView()
        }
        .inspector(isPresented: $showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 320, ideal: 380, max: 560)
        }
        .searchable(text: $center.searchText, placement: .toolbar, prompt: "Search apps")
        .navigationTitle(center.filter?.title ?? "Freshly")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await center.refresh(forceCatalogue: true) }
                } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                        .symbolEffect(.rotate, options: .repeat(.continuous), isActive: center.isBusy)
                }
                .disabled(center.isBusy)
                .help("Check every app for updates (⌘R)")
            }
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Show app details")
            }
        }
        .onChange(of: center.selection) { _, selection in
            if selection != nil { withAnimation { showInspector = true } }
        }
        .sheet(isPresented: $brew.isPresented) {
            BrewLogSheet()
        }
    }

    private var subtitle: String {
        if center.phase == .scanning { return "Scanning Applications…" }
        let count = center.updates.count
        return "\(count) update\(count == 1 ? "" : "s") · \(center.apps.count) apps"
    }
}
