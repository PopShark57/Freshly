import Foundation

/// Matches apps against the public Homebrew cask catalogue and the local Caskroom.
actor HomebrewProvider {
    struct Cask: Sendable {
        let token: String
        let version: String
        let homepage: URL?
        let autoUpdates: Bool
        /// Set when Homebrew has disabled the cask (e.g. "fails_gatekeeper_check"); `brew upgrade` refuses it.
        var disabledReason: String? = nil
    }

    struct Match: Sendable {
        let cask: Cask
        let installedViaBrew: Bool
        let result: UpdateResult?
    }

    private static let catalogueURL = URL(string: "https://formulae.brew.sh/api/cask.json")!
    private static let cacheURL = URL.cachesDirectory.appending(path: "com.freshly.Freshly/cask.json")

    private var casksByAppName: [String: [Cask]] = [:]
    /// Caskroom contents: token → versions brew has installed.
    private var installedVersions: [String: Set<String>] = [:]
    private var loaded = false

    /// The brew executable, if Homebrew is installed.
    nonisolated static var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func prepare(forceRefresh: Bool) async {
        installedVersions = Self.readCaskroom()
        guard forceRefresh || !loaded, let data = await loadCatalogue(forceRefresh: forceRefresh) else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        var index: [String: [Cask]] = [:]
        for entry in json {
            guard let token = entry["token"] as? String, let version = entry["version"] as? String else { continue }
            let cask = Cask(token: token, version: version,
                            homepage: (entry["homepage"] as? String).flatMap(URL.init(string:)),
                            autoUpdates: entry["auto_updates"] as? Bool ?? false,
                            disabledReason: entry["disabled"] as? Bool == true
                                ? (entry["disable_reason"] as? String ?? "disabled").replacingOccurrences(of: "_", with: " ")
                                : nil)
            for name in Self.appNames(in: entry["artifacts"] as? [Any] ?? []) {
                index[name.lowercased(), default: []].append(cask)
            }
        }
        casksByAppName = index
        loaded = true
    }

    func match(_ app: InstalledApp) -> Match? {
        guard let candidates = casksByAppName[app.url.lastPathComponent.lowercased()], !candidates.isEmpty else { return nil }
        // Prefer whatever brew actually installed, then the stable (non-@variant) cask, then the shortest token.
        let installed = candidates.first { installedVersions[$0.token] != nil }
        let stable = candidates.filter { !$0.token.contains("@") }.min { $0.token.count < $1.token.count }
        let cask = installed ?? stable ?? candidates[0]

        var result = Self.compare(cask, with: app)
        // Brew already installed this exact release; the app just labels itself differently
        // (Deluge's "1.3.15.1" cask ships an app that says "1.3.15").
        if result?.status == .updateAvailable, installedVersions[cask.token]?.contains(cask.version) == true {
            result?.status = .upToDate
        }
        return Match(cask: cask, installedViaBrew: installedVersions[cask.token] != nil, result: result)
    }

    /// nil when the cask's version can't be meaningfully compared with the app's (e.g. "latest", or a bare build number).
    static func compare(_ cask: Cask, with app: InstalledApp) -> UpdateResult? {
        guard cask.version != "latest" else { return nil }
        let parts = cask.version.split(separator: ",", maxSplits: 1).map(String.init)
        let latest = Version(parts[0]), installed = Version(app.version)
        guard latest.isValid, installed.isValid else { return nil }

        let newer: Bool
        if latest.components.count == 1, installed.components.count > 1 {
            // The cask tracks build numbers (e.g. MailMate's "5673"); compare against CFBundleVersion instead.
            let build = Version(app.build)
            guard build.isValid, build.components.count == 1 else { return nil }
            newer = latest > build
        } else {
            newer = VersionComparison.isNewer(latest: parts[0], latestBuild: parts.count > 1 ? parts[1] : nil,
                                              installedVersion: app.version, installedBuild: app.build)
        }
        return UpdateResult(status: newer ? .updateAvailable : .upToDate, source: .homebrew,
                            latestVersion: parts[0],
                            releaseNotesURL: URL(string: "https://formulae.brew.sh/cask/\(cask.token)"),
                            homepageURL: cask.homepage)
    }

    private func loadCatalogue(forceRefresh: Bool) async -> Data? {
        let fm = FileManager.default
        if !forceRefresh,
           let modified = try? fm.attributesOfItem(atPath: Self.cacheURL.path)[.modificationDate] as? Date,
           modified.timeIntervalSinceNow > -3600,
           let cached = try? Data(contentsOf: Self.cacheURL) {
            return cached
        }
        do {
            let data = try await HTTP.data(from: Self.catalogueURL)
            try? fm.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: Self.cacheURL, options: .atomic)
            return data
        } catch {
            // Offline: a stale catalogue beats none.
            return try? Data(contentsOf: Self.cacheURL)
        }
    }

    /// App bundle names from a cask's `artifacts`, e.g. `[{"app": ["Foo.app", {"target": "Bar.app"}]}]`.
    private static func appNames(in artifacts: [Any]) -> [String] {
        var names: [String] = []
        for case let artifact as [String: Any] in artifacts {
            guard let apps = artifact["app"] as? [Any] else { continue }
            for item in apps {
                if let name = item as? String {
                    names.append((name as NSString).lastPathComponent)
                } else if let options = item as? [String: Any], let target = options["target"] as? String {
                    names.append((target as NSString).lastPathComponent)
                }
            }
        }
        return names
    }

    private static func readCaskroom() -> [String: Set<String>] {
        let fm = FileManager.default
        for root in ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"] {
            guard let tokens = try? fm.contentsOfDirectory(atPath: root) else { continue }
            var result: [String: Set<String>] = [:]
            for token in tokens where !token.hasPrefix(".") {
                let versions = (try? fm.contentsOfDirectory(atPath: "\(root)/\(token)")) ?? []
                result[token] = Set(versions.filter { !$0.hasPrefix(".") })
            }
            return result
        }
        return [:]
    }
}
