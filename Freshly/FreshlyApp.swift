import SwiftUI

@main
struct FreshlyApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var center = UpdateCenter()

    var body: some Scene {
        Window("Freshly", id: "main") {
            ContentView()
                .environment(center)
                .task { await center.bootstrap() }
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandMenu("Updates") {
                Button("Check for Updates") { Task { await center.refresh(forceCatalogue: true) } }
                    .keyboardShortcut("r")
                    .disabled(center.isBusy)
                Button("Upgrade All via Homebrew") { center.upgradeAllWithHomebrew() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                    .disabled(center.brewUpgradeable.isEmpty)
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(center)
        } label: {
            let count = center.updates.count
            Image(systemName: count > 0 ? "arrow.trianglehead.2.clockwise.rotate.90.circle.fill" : "checkmark.seal")
            if count > 0 { Text("\(count)") }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(center)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Keep running in the menu bar after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
