import Foundation

/// Looks up Mac App Store apps through the public iTunes lookup API, in batches.
actor AppStoreProvider {
    private struct Lookup: Decodable {
        let results: [Listing]
    }

    private struct Listing: Decodable {
        let bundleId: String
        let trackId: Int
        let version: String
        let releaseNotes: String?
        let trackViewUrl: URL?
    }

    private var listings: [String: Listing] = [:]

    func prepare(_ apps: [InstalledApp]) async {
        let ids = apps.filter(\.hasAppStoreReceipt).map(\.bundleID)
        let country = Locale.current.region?.identifier ?? "US"
        await withTaskGroup(of: [Listing].self) { group in
            for start in stride(from: 0, to: ids.count, by: 40) {
                let chunk = ids[start..<min(start + 40, ids.count)]
                group.addTask {
                    var components = URLComponents(string: "https://itunes.apple.com/lookup")!
                    components.queryItems = [
                        URLQueryItem(name: "bundleId", value: chunk.joined(separator: ",")),
                        URLQueryItem(name: "entity", value: "macSoftware"),
                        URLQueryItem(name: "country", value: country),
                    ]
                    return (try? await HTTP.json(Lookup.self, from: components.url!).results) ?? []
                }
            }
            for await batch in group {
                for listing in batch { listings[listing.bundleId] = listing }
            }
        }
    }

    func check(_ app: InstalledApp) -> UpdateResult? {
        guard app.hasAppStoreReceipt, let listing = listings[app.bundleID] else { return nil }
        let newer = VersionComparison.isNewer(latest: listing.version, latestBuild: nil,
                                              installedVersion: app.version, installedBuild: app.build)
        return UpdateResult(
            status: newer ? .updateAvailable : .upToDate,
            source: .appStore,
            latestVersion: listing.version,
            releaseNotesURL: listing.trackViewUrl,
            releaseNotes: listing.releaseNotes,
            storeURL: URL(string: "macappstore://apps.apple.com/app/id\(listing.trackId)")
        )
    }
}
