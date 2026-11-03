import Foundation

struct AppcastItem: Sendable, Equatable {
    var title: String?
    var shortVersion: String?
    var build: String?
    var releaseNotesLink: URL?
    var descriptionHTML: String?
    var enclosureURL: URL?
    var channel: String?
    var minimumSystemVersion: String?

    var displayVersion: String? { shortVersion ?? build ?? title }
}

/// Parses Sparkle appcast RSS feeds.
final class AppcastParser: NSObject, XMLParserDelegate {
    private var items: [AppcastItem] = []
    private var current: AppcastItem?
    private var text = ""

    static func parse(_ data: Data) -> [AppcastItem] {
        let delegate = AppcastParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch element {
        case "item":
            current = AppcastItem()
        case "enclosure":
            if let url = attributes["url"] { current?.enclosureURL = URL(string: url) }
            if let v = attributes["sparkle:version"], current?.build == nil { current?.build = v }
            if let v = attributes["sparkle:shortVersionString"], current?.shortVersion == nil { current?.shortVersion = v }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { text = "" }
        guard current != nil else { return }
        switch element {
        case "item":
            if let current { items.append(current) }
            current = nil
        case "title": current?.title = value
        case "sparkle:version": current?.build = value
        case "sparkle:shortVersionString": current?.shortVersion = value
        case "sparkle:releaseNotesLink": current?.releaseNotesLink = URL(string: value)
        case "sparkle:channel": current?.channel = value
        case "sparkle:minimumSystemVersion": current?.minimumSystemVersion = value
        case "description": if !value.isEmpty { current?.descriptionHTML = value }
        default: break
        }
    }
}

struct SparkleProvider: Sendable {
    var includeBetas: Bool

    func check(_ app: InstalledApp) async throws -> UpdateResult? {
        guard let feed = app.sparkleFeedURL else { return nil }
        let items = AppcastParser.parse(try await HTTP.data(from: feed))
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = Version("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")

        let eligible = items.filter { item in
            (includeBetas || item.channel == nil)
                && (item.minimumSystemVersion.map { Version($0) <= osVersion } ?? true)
                && item.displayVersion != nil
        }
        guard let best = eligible.max(by: { Self.isNewer($1, than: $0) }) else {
            throw ProviderError.unreadable("The appcast has no usable releases")
        }

        let newer = Self.isNewer(best, than: app)
        var latest = best.displayVersion
        // A build-only bump ("27.2.0 → 27.2.0") needs the build number to make sense.
        if newer, let short = best.shortVersion, let build = best.build, Version(short) == Version(app.version) {
            latest = "\(short) (\(build))"
        }
        return UpdateResult(
            status: newer ? .updateAvailable : .upToDate,
            source: .sparkle,
            latestVersion: latest,
            releaseNotesURL: best.releaseNotesLink,
            releaseNotes: best.descriptionHTML,
            releaseNotesAreHTML: true,
            downloadURL: best.enclosureURL
        )
    }

    static func isNewer(_ item: AppcastItem, than other: AppcastItem) -> Bool {
        VersionComparison.isNewer(latest: item.shortVersion ?? item.build, latestBuild: item.build,
                                  installedVersion: other.shortVersion ?? other.build ?? "", installedBuild: other.build ?? "")
    }

    static func isNewer(_ item: AppcastItem, than app: InstalledApp) -> Bool {
        if let short = item.shortVersion {
            return VersionComparison.isNewer(latest: short, latestBuild: item.build,
                                             installedVersion: app.version, installedBuild: app.build)
        }
        guard let build = item.build else { return false }
        // Older feeds put only one number in sparkle:version — sometimes the build, sometimes the marketing version.
        let v = Version(build)
        if v == Version(app.version) || v == Version(app.build) { return false }
        return v > Version(build.contains(".") ? app.version : app.build)
    }
}
