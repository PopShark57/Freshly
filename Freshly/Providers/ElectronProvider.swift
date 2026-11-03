import Foundation

/// Just enough YAML for electron-updater's flat config and `latest-mac.yml` files.
struct ElectronYAML: Sendable {
    var values: [String: String] = [:]
    var fileURLs: [String] = []

    init(_ text: String) {
        for line in text.split(whereSeparator: \.isNewline) {
            let isTopLevel = !(line.first?.isWhitespace ?? true) && !line.hasPrefix("-")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let entry = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed
            guard let colon = entry.firstIndex(of: ":") else { continue }
            let key = entry[..<colon].trimmingCharacters(in: .whitespaces)
            let value = entry[entry.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            if isTopLevel, !value.isEmpty, value != "null" {
                values[key] = value
            } else if key == "url", !value.isEmpty {
                fileURLs.append(value)
            }
        }
    }

    subscript(key: String) -> String? { values[key] }
}

struct ElectronProvider: Sendable {
    func check(_ app: InstalledApp) async throws -> UpdateResult? {
        guard let configURL = app.electronUpdateConfig,
              let text = try? String(contentsOf: configURL, encoding: .utf8)
        else { return nil }
        let config = ElectronYAML(text)
        let channelFile = "\(config["channel"] ?? "latest")-mac.yml"

        switch config["provider"] {
        case "github":
            guard let owner = config["owner"], let repo = config["repo"] else { return nil }
            return try await GitHubReleases.latest(owner: owner, repo: repo, installed: app)
        case "generic":
            guard let base = config["url"].flatMap(URL.init(string:)) else { return nil }
            return try await checkFeed(base: base, file: channelFile, app: app)
        case "s3":
            guard let bucket = config["bucket"] else { return nil }
            let path = config["path"].map { "/" + $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) } ?? ""
            let base = config["endpoint"].map { "\($0)/\(bucket)\(path)" } ?? "https://\(bucket).s3.amazonaws.com\(path)"
            guard let url = URL(string: base) else { return nil }
            return try await checkFeed(base: url, file: channelFile, app: app)
        default:
            // "custom" providers and private shares can't be checked from outside the app.
            return nil
        }
    }

    private func checkFeed(base: URL, file: String, app: InstalledApp) async throws -> UpdateResult {
        let feedURL = base.appending(path: file)
        let feed = ElectronYAML(String(decoding: try await HTTP.data(from: feedURL), as: UTF8.self))
        guard let latest = feed["version"] else { throw ProviderError.unreadable("\(file) has no version") }

        // Prefer the build for this Mac's architecture, then any zip/dmg.
        let preferred = feed.fileURLs.first { $0.contains("arm64") } ?? feed.fileURLs.first ?? feed["path"]
        let directory = URL(string: base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/")
        let download = preferred.flatMap { URL(string: $0, relativeTo: directory) }?.absoluteURL

        let newer = VersionComparison.isNewer(latest: latest, latestBuild: nil, installedVersion: app.version, installedBuild: app.build)
        return UpdateResult(status: newer ? .updateAvailable : .upToDate, source: .electron,
                            latestVersion: latest, downloadURL: download)
    }
}

enum GitHubReleases {
    private struct Release: Decodable {
        let tag_name: String
        let name: String?
        let html_url: URL
        let body: String?
        let assets: [Asset]
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
    }

    static func latest(owner: String, repo: String, installed app: InstalledApp) async throws -> UpdateResult {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        let release = try await HTTP.json(Release.self, from: url, headers: ["Accept": "application/vnd.github+json"])
        let version = release.tag_name.drop { !$0.isNumber }
        let macAsset = release.assets.first { $0.name.hasSuffix(".dmg") && $0.name.contains("arm64") }
            ?? release.assets.first { $0.name.hasSuffix(".dmg") }
            ?? release.assets.first { $0.name.contains("mac") && $0.name.hasSuffix(".zip") }
        let newer = VersionComparison.isNewer(latest: String(version), latestBuild: nil,
                                              installedVersion: app.version, installedBuild: app.build)
        return UpdateResult(status: newer ? .updateAvailable : .upToDate, source: .electron,
                            latestVersion: String(version), releaseNotesURL: release.html_url,
                            releaseNotes: release.body, downloadURL: macAsset?.browser_download_url)
    }
}
