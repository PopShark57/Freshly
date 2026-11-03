import Foundation
import Testing
@testable import Freshly

struct AppcastParserTests {
    static let appcast = """
    <?xml version="1.0" standalone="yes"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item>
          <title>5.3.0 beta</title>
          <sparkle:channel>beta</sparkle:channel>
          <sparkle:version>55000</sparkle:version>
          <sparkle:shortVersionString>5.3.0</sparkle:shortVersionString>
          <enclosure url="https://example.com/beta.zip" length="1" type="application/octet-stream"/>
        </item>
        <item>
          <title>5.2.1</title>
          <description><![CDATA[<h2>Fixes</h2><ul><li>Faster</li></ul>]]></description>
          <sparkle:releaseNotesLink>https://example.com/notes/5.2.1</sparkle:releaseNotesLink>
          <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
          <enclosure url="https://example.com/5.2.1.zip" sparkle:version="54014" sparkle:shortVersionString="5.2.1" length="1" type="application/octet-stream"/>
        </item>
        <item>
          <title>5.2.0</title>
          <sparkle:version>53900</sparkle:version>
          <sparkle:shortVersionString>5.2.0</sparkle:shortVersionString>
        </item>
      </channel>
    </rss>
    """

    @Test func parsesElementsAndEnclosureAttributes() throws {
        let items = AppcastParser.parse(Data(Self.appcast.utf8))
        #expect(items.count == 3)
        #expect(items[0].channel == "beta")
        let stable = items[1]
        #expect(stable.shortVersion == "5.2.1")
        #expect(stable.build == "54014")
        #expect(stable.enclosureURL?.absoluteString == "https://example.com/5.2.1.zip")
        #expect(stable.releaseNotesLink?.absoluteString == "https://example.com/notes/5.2.1")
        #expect(stable.descriptionHTML?.contains("<li>Faster</li>") == true)
        #expect(stable.minimumSystemVersion == "14.0")
    }

    @Test func comparesAgainstInstalledApp() {
        let item = AppcastItem(shortVersion: "5.2.1", build: "54014")
        #expect(SparkleProvider.isNewer(item, than: app(version: "5.2.0", build: "53900")))
        #expect(!SparkleProvider.isNewer(item, than: app(version: "5.2.1", build: "54014")))
    }

    @Test func handlesFeedsWithOnlyOneVersionNumber() {
        // Marketing version in sparkle:version
        #expect(SparkleProvider.isNewer(AppcastItem(build: "2.4.1"), than: app(version: "2.4.0", build: "240")))
        #expect(!SparkleProvider.isNewer(AppcastItem(build: "2.4.0"), than: app(version: "2.4.0", build: "240")))
        // Build number in sparkle:version
        #expect(SparkleProvider.isNewer(AppcastItem(build: "250"), than: app(version: "2.4.0", build: "240")))
        #expect(!SparkleProvider.isNewer(AppcastItem(build: "240"), than: app(version: "2.4.0", build: "240")))
    }
}

struct ElectronYAMLTests {
    @Test func parsesUpdaterConfig() {
        let config = ElectronYAML("""
        owner: ipfs
        repo: ipfs-desktop
        provider: github
        acl: null
        updaterCacheDirName: ipfs-desktop-updater
        """)
        #expect(config["provider"] == "github")
        #expect(config["owner"] == "ipfs")
        #expect(config["repo"] == "ipfs-desktop")
        #expect(config["acl"] == nil)
    }

    @Test func parsesLatestMacFeed() {
        let feed = ElectronYAML("""
        version: 8.33.0
        files:
          - url: signal-desktop-mac-x64-8.33.0.zip
            sha512: abc==
            size: 160585650
          - url: signal-desktop-mac-arm64-8.33.0.zip
            sha512: def==
        path: signal-desktop-mac-x64-8.33.0.zip
        releaseDate: '2026-10-29T17:00:00.000Z'
        """)
        #expect(feed["version"] == "8.33.0")
        #expect(feed["path"] == "signal-desktop-mac-x64-8.33.0.zip")
        #expect(feed["releaseDate"] == "2026-10-29T17:00:00.000Z")
        #expect(feed.fileURLs == ["signal-desktop-mac-x64-8.33.0.zip", "signal-desktop-mac-arm64-8.33.0.zip"])
    }
}

struct HomebrewComparisonTests {
    private func cask(_ version: String) -> HomebrewProvider.Cask {
        HomebrewProvider.Cask(token: "example", version: version, homepage: nil, autoUpdates: false)
    }

    @Test func buildNumberCasksCompareAgainstBuilds() {
        #expect(HomebrewProvider.compare(cask("5673"), with: app(version: "1.13.2", build: "5673"))?.status == .upToDate)
        #expect(HomebrewProvider.compare(cask("5680"), with: app(version: "1.13.2", build: "5673"))?.status == .updateAvailable)
        // No usable build to compare with → no verdict rather than a false "update".
        #expect(HomebrewProvider.compare(cask("5071136"), with: app(version: "1.0.12", build: "1.0.12")) == nil)
    }

    @Test func commaVersionsUseTheBuildPart() {
        #expect(HomebrewProvider.compare(cask("5.2.1,54020"), with: app(version: "5.2.1", build: "54014"))?.status == .updateAvailable)
        #expect(HomebrewProvider.compare(cask("latest"), with: app(version: "1.0", build: "1")) == nil)
    }
}

private func app(version: String, build: String) -> InstalledApp {
    InstalledApp(url: URL(filePath: "/Applications/Test.app"), name: "Test", bundleID: "com.example.test",
                 version: version, build: build, hasAppStoreReceipt: false, sparkleFeedURL: nil, electronUpdateConfig: nil)
}
