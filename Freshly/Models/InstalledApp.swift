import Foundation

/// An application bundle found on disk.
struct InstalledApp: Identifiable, Hashable, Sendable, Codable {
    var id: String { url.path }

    let url: URL
    let name: String
    let bundleID: String
    /// `CFBundleShortVersionString`, falling back to `CFBundleVersion`.
    let version: String
    /// `CFBundleVersion`.
    let build: String
    let hasAppStoreReceipt: Bool
    let sparkleFeedURL: URL?
    let electronUpdateConfig: URL?

    var displayVersion: String {
        build.isEmpty || build == version ? version : "\(version) (\(build))"
    }

    /// Setapp builds carry a `-setapp` bundle ID suffix and are updated by Setapp, not their own feeds.
    var isSetapp: Bool {
        bundleID.hasSuffix("-setapp") || url.path.contains("/Applications/Setapp/")
    }

    var folderDescription: String {
        url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

/// Where Freshly learned about an app's latest version.
enum UpdateSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case appStore, sparkle, electron, homebrew, setapp, unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appStore: "App Store"
        case .sparkle: "Sparkle"
        case .electron: "Electron"
        case .homebrew: "Homebrew"
        case .setapp: "Setapp"
        case .unknown: "Unknown"
        }
    }

    var symbol: String {
        switch self {
        case .appStore: "app.badge.fill"
        case .sparkle: "sparkles"
        case .electron: "atom"
        case .homebrew: "mug.fill"
        case .setapp: "square.grid.3x3.square"
        case .unknown: "questionmark.app.dashed"
        }
    }
}

enum UpdateStatus: String, Codable, Sendable {
    /// `managed`: another updater (Setapp) owns this app, so Freshly only reports it.
    case checking, upToDate, updateAvailable, managed, unknown, failed
}

/// The outcome of checking one app.
struct UpdateResult: Codable, Sendable, Hashable {
    var status: UpdateStatus
    var source: UpdateSource
    var latestVersion: String?
    var releaseNotesURL: URL?
    /// HTML (Sparkle descriptions) or plain text (App Store, GitHub) notes.
    var releaseNotes: String?
    var releaseNotesAreHTML = false
    var downloadURL: URL?
    var storeURL: URL?
    var homepageURL: URL?
    /// Homebrew cask token, set whenever a cask matches this app.
    var brewToken: String?
    /// True when the app was installed through Homebrew, so `brew upgrade` can update it.
    var brewManaged = false
    /// True when the Homebrew cask is newer than the installed copy.
    var brewHasUpdate = false
    var message: String?
    var checkedAt = Date.now

    static let checking = UpdateResult(status: .checking, source: .unknown)

    static func unknown(_ message: String? = nil) -> UpdateResult {
        UpdateResult(status: .unknown, source: .unknown, message: message)
    }
}
