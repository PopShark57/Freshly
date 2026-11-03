import Foundation

/// Finds application bundles in the Applications folders and reads their metadata.
enum AppScanner {
    static func scan(includeUserApplications: Bool) async -> [InstalledApp] {
        var roots = [URL(filePath: "/Applications")]
        if includeUserApplications {
            roots.append(FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"))
        }
        let bundles = roots.flatMap(appBundles(in:))

        return await withTaskGroup(of: InstalledApp?.self) { group in
            for url in bundles {
                group.addTask { readApp(at: url) }
            }
            var apps: [InstalledApp] = []
            for await app in group {
                if let app { apps.append(app) }
            }
            // A bundle ID can appear twice (e.g. a copy in ~/Applications); keep the first by path.
            var seen = Set<String>()
            return apps
                .sorted { $0.url.path < $1.url.path }
                .filter { seen.insert($0.bundleID).inserted }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// `.app` bundles directly inside `root`, plus one level of plain subfolders (Utilities, vendor suites…).
    private static func appBundles(in root: URL) -> [URL] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: .skipsHiddenFiles) else {
            return []
        }
        var result: [URL] = []
        for entry in entries {
            if entry.pathExtension == "app" {
                result.append(entry)
            } else if (try? entry.resourceValues(forKeys: Set(keys)))?.isDirectory == true,
                      let children = try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                result.append(contentsOf: children.filter { $0.pathExtension == "app" })
            }
        }
        return result
    }

    static func readApp(at url: URL) -> InstalledApp? {
        let contents = url.appending(path: "Contents")
        guard let data = try? Data(contentsOf: contents.appending(path: "Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String
        else { return nil }

        let fm = FileManager.default
        let hasReceipt = fm.fileExists(atPath: contents.appending(path: "_MASReceipt/receipt").path)
        // Apple's bundled apps update with macOS itself; App Store-delivered Apple apps (Xcode, Pages…) still count.
        if bundleID.hasPrefix("com.apple.") && !hasReceipt { return nil }

        let short = (plist["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let build = (plist["CFBundleVersion"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let feed = (plist["SUFeedURL"] as? String).flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
        let electron = contents.appending(path: "Resources/app-update.yml")

        return InstalledApp(
            url: url,
            // The Finder name is what people recognise, so prefer it over CFBundleName.
            name: url.deletingPathExtension().lastPathComponent,
            bundleID: bundleID,
            version: short.isEmpty ? build : short,
            build: build,
            hasAppStoreReceipt: hasReceipt,
            sparkleFeedURL: feed,
            electronUpdateConfig: fm.fileExists(atPath: electron.path) ? electron : nil
        )
    }
}
