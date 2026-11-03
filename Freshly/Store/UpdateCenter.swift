import AppKit
import Observation
import OSLog
import SwiftUI
import UserNotifications

enum SidebarFilter: Hashable {
    case updates, all, upToDate, unknown, ignored
    case source(UpdateSource)

    var title: String {
        switch self {
        case .updates: "Updates"
        case .all: "All Apps"
        case .upToDate: "Up to Date"
        case .unknown: "Unknown"
        case .ignored: "Ignored"
        case let .source(source): source.label
        }
    }
}

/// What the big "Update" button does for an app.
enum UpdateAction: Hashable {
    case appStore(URL), brewUpgrade(String), launch, website(URL)

    var title: String {
        switch self {
        case .appStore: "App Store"
        case .brewUpgrade: "Upgrade"
        case .launch: "Open"
        case .website: "Website"
        }
    }

    var symbol: String {
        switch self {
        case .appStore: "bag.fill"
        case .brewUpgrade: "mug.fill"
        case .launch: "arrow.up.forward.app.fill"
        case .website: "safari.fill"
        }
    }

    var help: String {
        switch self {
        case .appStore: "Open this app's page in the App Store"
        case let .brewUpgrade(token): "Run brew upgrade --cask \(token)"
        case .launch: "Open the app so its built-in updater can install the new version"
        case .website: "Open the developer's website"
        }
    }
}

enum SettingsKey {
    static let includeUserApplications = "includeUserApplications"
    static let includeBetas = "includeBetas"
    static let checkIntervalHours = "checkIntervalHours"
    static let notifyOnUpdates = "notifyOnUpdates"
}

@Observable
@MainActor
final class UpdateCenter {
    enum Phase: Equatable { case idle, scanning, checking }

    private(set) var apps: [InstalledApp] = []
    private(set) var results: [InstalledApp.ID: UpdateResult] = [:]
    private(set) var phase: Phase = .idle
    private(set) var checkedCount = 0
    private(set) var lastChecked: Date?
    private(set) var ignoredApps: Set<String> = []
    private(set) var ignoredVersions: [String: String] = [:]

    var filter: SidebarFilter? = .updates
    var searchText = ""
    var selection: InstalledApp.ID?

    let brew = BrewRunner()
    private var scheduler: NSBackgroundActivityScheduler?

    private let log = Logger(subsystem: "com.freshly.Freshly", category: "UpdateCenter")
    private var instance: String { String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16) }

    init() {
        defer { log.notice("UpdateCenter created (\(self.instance)), lastChecked: \(String(describing: self.lastChecked))") }
        UserDefaults.standard.register(defaults: [
            SettingsKey.includeUserApplications: true,
            SettingsKey.includeBetas: false,
            SettingsKey.checkIntervalHours: 24,
            SettingsKey.notifyOnUpdates: true,
        ])
        loadSnapshot()
        brew.onFinish = { [weak self] tokens in
            guard let self else { return }
            let affected = apps.filter { tokens.contains(results[$0.id]?.brewToken ?? "") }
            Task { await self.recheck(affected) }
        }
    }

    // MARK: - Derived state

    var isBusy: Bool { phase != .idle }

    var progress: Double {
        switch phase {
        case .idle: 1
        case .scanning: 0
        case .checking: apps.isEmpty ? 0 : Double(checkedCount) / Double(apps.count)
        }
    }

    func result(for app: InstalledApp) -> UpdateResult? { results[app.id] }

    func isIgnored(_ app: InstalledApp) -> Bool {
        ignoredApps.contains(app.bundleID)
            || (ignoredVersions[app.bundleID] != nil && ignoredVersions[app.bundleID] == results[app.id]?.latestVersion)
    }

    func hasUpdate(_ app: InstalledApp) -> Bool {
        results[app.id]?.status == .updateAvailable && !isIgnored(app)
    }

    var updates: [InstalledApp] { apps.filter(hasUpdate) }

    var brewUpgradeable: [InstalledApp] {
        updates.filter { results[$0.id].map { $0.brewManaged && $0.brewHasUpdate } ?? false }
    }

    var selectedApp: InstalledApp? { apps.first { $0.id == selection } }

    func apps(matching filter: SidebarFilter) -> [InstalledApp] {
        apps.filter { app in
            let result = results[app.id]
            switch filter {
            case .updates: return hasUpdate(app)
            case .all: return true
            case .upToDate: return result?.status == .upToDate
            case .unknown: return result?.status == .unknown || result?.status == .failed
            case .ignored: return isIgnored(app)
            case let .source(source): return result?.source == source && result?.status != .unknown
            }
        }
    }

    var visibleApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return apps(matching: filter ?? .all)
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.bundleID.localizedStandardContains(query) }
            .sorted { lhs, rhs in
                let l = hasUpdate(lhs), r = hasUpdate(rhs)
                return l != r ? l : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    // MARK: - Checking

    func bootstrap() async {
        // Unit tests use the app as their host; don't hit the network or the scheduler there.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        log.notice("Bootstrap (\(self.instance))")
        scheduleBackgroundChecks()
        let stale = lastChecked.map { $0.timeIntervalSinceNow < -3600 } ?? true
        if stale || apps.isEmpty { await refresh() }
    }

    func refresh(forceCatalogue: Bool = false) async {
        guard !isBusy else { return }
        log.notice("Refresh started (\(self.instance))")
        defer { log.notice("Refresh finished (\(self.instance)), lastChecked: \(String(describing: self.lastChecked))") }
        let previousUpdates = Set(updates.map { "\($0.bundleID)@\(results[$0.id]?.latestVersion ?? "")" })

        withAnimation(.smooth) { phase = .scanning }
        let defaults = UserDefaults.standard
        let scanned = await AppScanner.scan(includeUserApplications: defaults.bool(forKey: SettingsKey.includeUserApplications))
        withAnimation(.smooth) {
            apps = scanned
            results = results.filter { id, _ in scanned.contains { $0.id == id } }
        }
        await check(scanned, forceCatalogue: forceCatalogue, markingChecked: true)
        saveSnapshot()

        let fresh = updates.filter { !previousUpdates.contains("\($0.bundleID)@\(results[$0.id]?.latestVersion ?? "")") }
        if !fresh.isEmpty { notify(about: fresh) }
    }

    /// Re-reads the given apps from disk (e.g. after an upgrade) and checks them again.
    func recheck(_ targets: [InstalledApp]) async {
        guard !isBusy, !targets.isEmpty else { return }
        let reread = targets.compactMap { AppScanner.readApp(at: $0.url) }
        for app in reread {
            if let index = apps.firstIndex(where: { $0.id == app.id }) { apps[index] = app }
        }
        await check(reread, forceCatalogue: true)
        saveSnapshot()
    }

    private func check(_ targets: [InstalledApp], forceCatalogue: Bool, markingChecked: Bool = false) async {
        withAnimation(.smooth) {
            phase = .checking
            checkedCount = apps.count - targets.count
            for app in targets where results[app.id] == nil { results[app.id] = .checking }
        }
        let checker = UpdateChecker(includeBetas: UserDefaults.standard.bool(forKey: SettingsKey.includeBetas))
        await checker.prepare(targets, forceRefresh: forceCatalogue)

        await withTaskGroup(of: (InstalledApp.ID, UpdateResult).self) { group in
            var pending = targets.makeIterator()
            func enqueue() {
                guard let app = pending.next() else { return }
                group.addTask { (app.id, await checker.check(app)) }
            }
            for _ in 0..<10 { enqueue() }
            while let (id, result) = await group.next() {
                withAnimation(.snappy) {
                    results[id] = result
                    checkedCount += 1
                }
                enqueue()
            }
        }
        // Finish in one transaction: views re-render as soon as the phase flips, so a later
        // lastChecked change on its own could leave the header showing its "never checked" state.
        withAnimation(.bouncy) {
            if markingChecked { lastChecked = .now }
            phase = .idle
        }
        updateDockBadge()
    }

    // MARK: - Actions

    func primaryAction(for app: InstalledApp) -> UpdateAction? {
        guard let result = results[app.id], result.status == .updateAvailable else { return nil }
        if let store = result.storeURL { return .appStore(store) }
        if result.brewManaged, result.brewHasUpdate, let token = result.brewToken { return .brewUpgrade(token) }
        if result.source == .sparkle || result.source == .electron { return .launch }
        if let homepage = result.homepageURL { return .website(homepage) }
        return .launch
    }

    func perform(_ action: UpdateAction, for app: InstalledApp) {
        switch action {
        case let .appStore(url), let .website(url): NSWorkspace.shared.open(url)
        case let .brewUpgrade(token): brew.upgrade([token])
        case .launch: NSWorkspace.shared.openApplication(at: app.url, configuration: .init())
        }
    }

    func upgradeAllWithHomebrew() {
        let tokens = brewUpgradeable.compactMap { results[$0.id]?.brewToken }
        if !tokens.isEmpty { brew.upgrade(tokens) }
    }

    func reveal(_ app: InstalledApp) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    func ignoreApp(_ app: InstalledApp) {
        withAnimation { _ = ignoredApps.insert(app.bundleID) }
        saveSnapshot()
    }

    func ignoreVersion(_ app: InstalledApp) {
        guard let latest = results[app.id]?.latestVersion else { return }
        withAnimation { ignoredVersions[app.bundleID] = latest }
        saveSnapshot()
    }

    func unignore(bundleID: String) {
        withAnimation {
            ignoredApps.remove(bundleID)
            ignoredVersions[bundleID] = nil
        }
        saveSnapshot()
    }

    func name(forBundleID bundleID: String) -> String {
        apps.first { $0.bundleID == bundleID }?.name ?? bundleID
    }

    // MARK: - Background checks & notifications

    func scheduleBackgroundChecks() {
        scheduler?.invalidate()
        scheduler = nil
        let hours = UserDefaults.standard.integer(forKey: SettingsKey.checkIntervalHours)
        guard hours > 0 else { return }

        let scheduler = NSBackgroundActivityScheduler(identifier: "com.freshly.Freshly.check")
        scheduler.repeats = true
        scheduler.interval = TimeInterval(hours) * 3600
        scheduler.tolerance = scheduler.interval / 10
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.refresh()
                completion(.finished)
            }
        }
        self.scheduler = scheduler
    }

    private func notify(about fresh: [InstalledApp]) {
        guard UserDefaults.standard.bool(forKey: SettingsKey.notifyOnUpdates), !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = fresh.count == 1 ? "\(fresh[0].name) has an update" : "\(fresh.count) app updates available"
        content.body = fresh.prefix(5).map { "\($0.name) → \(results[$0.id]?.latestVersion ?? "new")" }.joined(separator: "\n")
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    private func updateDockBadge() {
        let count = updates.count
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var apps: [InstalledApp]
        var results: [String: UpdateResult]
        var lastChecked: Date?
        var ignoredApps: Set<String>
        var ignoredVersions: [String: String]
    }

    private static let snapshotURL = URL.applicationSupportDirectory.appending(path: "Freshly/state.json")

    private func saveSnapshot() {
        let snapshot = Snapshot(apps: apps, results: results.filter { $0.value.status != .checking },
                                lastChecked: lastChecked, ignoredApps: ignoredApps, ignoredVersions: ignoredVersions)
        do {
            try FileManager.default.createDirectory(at: Self.snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: Self.snapshotURL, options: .atomic)
        } catch {
            print("Freshly: couldn't save state: \(error)")
        }
    }

    private func loadSnapshot() {
        guard let data = try? Data(contentsOf: Self.snapshotURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        apps = snapshot.apps
        results = snapshot.results
        lastChecked = snapshot.lastChecked
        ignoredApps = snapshot.ignoredApps
        ignoredVersions = snapshot.ignoredVersions
    }
}
