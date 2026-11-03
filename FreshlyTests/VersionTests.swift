import Testing
@testable import Freshly

struct VersionTests {
    @Test(arguments: [
        ("1.2.3", "1.2.4"),
        ("1.2", "1.10"),
        ("v2.0", "2.0.1"),
        ("2.0-beta.3", "2.0"),
        ("2.0-beta.3", "2.0-beta.10"),
        ("1.2b4", "1.2"),
        ("5.2.1 (54014)", "5.2.2"),
    ])
    func ordering(older: String, newer: String) {
        #expect(Version(older) < Version(newer))
        #expect(!(Version(newer) < Version(older)))
    }

    @Test func equalityIgnoresPaddingAndBuildSuffixes() {
        #expect(Version("1.2") == Version("1.2.0"))
        #expect(Version("v3.1.0") == Version("3.1"))
        #expect(Version("0.0.421,abc123") == Version("0.0.421"))
        #expect(Version("1.0+20240101") == Version("1.0"))
    }

    @Test func unrecognisedSuffixesAreNotPrereleases() {
        #expect(Version("0.40.0-UNKNOWN") == Version("0.40.0"))
        #expect(Version("26.1020.0-a424ad4b") == Version("26.1020.0"))
        #expect(Version("1.0-rc1") < Version("1.0"))
        #expect(Version("1.145.0-insider") < Version("1.145.0"))
    }

    @Test func garbageIsInvalid() {
        #expect(!Version("latest").isValid)
        #expect(!Version("").isValid)
    }

    @Test func buildNumbersBreakTies() {
        #expect(VersionComparison.isNewer(latest: "5.2.1", latestBuild: "54020", installedVersion: "5.2.1", installedBuild: "54014"))
        #expect(!VersionComparison.isNewer(latest: "5.2.1", latestBuild: "54014", installedVersion: "5.2.1", installedBuild: "54014"))
        #expect(!VersionComparison.isNewer(latest: "5.2.0", latestBuild: "60000", installedVersion: "5.2.1", installedBuild: "54014"))
    }

    @Test func fullVersionsHiddenInTheBuildNumberCount() {
        #expect(!VersionComparison.isNewer(latest: "138.0.6044.65", latestBuild: nil, installedVersion: "138.0", installedBuild: "138.0.6044.65"))
        #expect(!VersionComparison.isNewer(latest: "1.43.5.11079", latestBuild: nil, installedVersion: "1.43.5", installedBuild: "1.43.5.11079"))
        #expect(VersionComparison.isNewer(latest: "138.0.6100.1", latestBuild: nil, installedVersion: "138.0", installedBuild: "138.0.6044.65"))
    }

    @Test func mismatchedBuildShapesDontCount() {
        // LM Studio: Homebrew "0.4.28,2" vs installed "0.4.28+2"
        #expect(!VersionComparison.isNewer(latest: "0.4.28", latestBuild: "2", installedVersion: "0.4.28+2", installedBuild: "0.4.28+2"))
    }

    @Test func nonNumericBuildsAreIgnored() {
        #expect(!VersionComparison.isNewer(latest: "1.0", latestBuild: "deadbeef", installedVersion: "1.0", installedBuild: "12"))
    }
}
