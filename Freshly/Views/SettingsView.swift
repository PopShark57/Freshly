import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
            }
            Tab("Ignored", systemImage: "eye.slash") {
                IgnoredSettings()
            }
        }
        .frame(width: 500, height: 380)
    }
}

private struct GeneralSettings: View {
    @Environment(UpdateCenter.self) private var center
    @AppStorage(SettingsKey.includeUserApplications) private var includeUserApplications = true
    @AppStorage(SettingsKey.includeBetas) private var includeBetas = false
    @AppStorage(SettingsKey.checkIntervalHours) private var checkIntervalHours = 24
    @AppStorage(SettingsKey.notifyOnUpdates) private var notifyOnUpdates = true

    var body: some View {
        Form {
            Section("Scanning") {
                Toggle("Include ~/Applications", isOn: $includeUserApplications)
                Toggle("Include beta releases from Sparkle feeds", isOn: $includeBetas)
            }
            Section("Background Checks") {
                Picker("Check automatically", selection: $checkIntervalHours) {
                    Text("Never").tag(0)
                    Text("Every hour").tag(1)
                    Text("Every 6 hours").tag(6)
                    Text("Daily").tag(24)
                    Text("Weekly").tag(168)
                }
                Toggle("Notify me about new updates", isOn: $notifyOnUpdates)
            }
        }
        .formStyle(.grouped)
        .onChange(of: checkIntervalHours) { center.scheduleBackgroundChecks() }
        .onChange(of: includeUserApplications) { Task { await center.refresh() } }
        .onChange(of: includeBetas) { Task { await center.refresh() } }
        .task(id: notifyOnUpdates) {
            if notifyOnUpdates { await UpdateCenter.requestNotificationPermission() }
        }
    }
}

private struct IgnoredSettings: View {
    @Environment(UpdateCenter.self) private var center

    var body: some View {
        let ignored = center.ignoredApps.union(center.ignoredVersions.keys).sorted {
            center.name(forBundleID: $0).localizedStandardCompare(center.name(forBundleID: $1)) == .orderedAscending
        }

        Form {
            if ignored.isEmpty {
                ContentUnavailableView("Nothing Ignored", systemImage: "eye",
                                       description: Text("Right-click an app to ignore it or skip a version."))
            } else {
                ForEach(ignored, id: \.self) { bundleID in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(center.name(forBundleID: bundleID))
                            Text(center.ignoredApps.contains(bundleID)
                                 ? "All versions"
                                 : "Skipping \(center.ignoredVersions[bundleID] ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Stop Ignoring") { center.unignore(bundleID: bundleID) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
