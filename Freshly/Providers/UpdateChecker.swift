import Foundation

/// Runs the providers for one app in priority order: App Store → Sparkle → Electron → Homebrew.
struct UpdateChecker: Sendable {
    let appStore = AppStoreProvider()
    let homebrew = HomebrewProvider()
    let electron = ElectronProvider()
    let sparkle: SparkleProvider

    init(includeBetas: Bool) {
        sparkle = SparkleProvider(includeBetas: includeBetas)
    }

    func prepare(_ apps: [InstalledApp], forceRefresh: Bool) async {
        async let store: Void = appStore.prepare(apps)
        async let brew: Void = homebrew.prepare(forceRefresh: forceRefresh)
        _ = await (store, brew)
    }

    func check(_ app: InstalledApp) async -> UpdateResult {
        if app.isSetapp {
            return UpdateResult(status: .managed, source: .setapp,
                                message: "Setapp installs updates for this app. Its version can lag the developer's own release.")
        }
        let brew = await homebrew.match(app)
        var errors: [String] = []
        var result = await appStore.check(app)

        if result == nil, app.sparkleFeedURL != nil {
            do { result = try await sparkle.check(app) } catch { errors.append("Sparkle feed: \(error.localizedDescription)") }
        }
        if result == nil, app.electronUpdateConfig != nil {
            do { result = try await electron.check(app) } catch { errors.append("Electron feed: \(error.localizedDescription)") }
        }
        if result == nil {
            result = brew?.result
        }

        guard var final = result else {
            if errors.isEmpty {
                return .unknown(app.hasAppStoreReceipt ? "Not found on the App Store in your region" : "No update feed found for this app")
            }
            return UpdateResult(status: .failed, source: .unknown, message: errors.joined(separator: "\n"))
        }
        if let brew {
            final.brewToken = brew.cask.token
            final.brewManaged = brew.installedViaBrew
            final.brewHasUpdate = brew.result?.status == .updateAvailable && brew.cask.disabledReason == nil
            if final.homepageURL == nil { final.homepageURL = brew.cask.homepage }
            if let reason = brew.cask.disabledReason {
                errors.append("Homebrew has disabled the \(brew.cask.token) cask (\(reason)), so brew can't update it.")
            }
        }
        if !errors.isEmpty { final.message = errors.joined(separator: "\n") }
        final.checkedAt = .now
        return final
    }
}
