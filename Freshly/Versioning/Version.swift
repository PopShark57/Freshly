import Foundation

/// A forgiving version number: understands `1.2.3`, `v1.2`, `1.2.3 (456)`, `2.0-beta.3`, `1.2b4` and `1.2.3,456`.
struct Version: Comparable, Sendable, CustomStringConvertible {
    let components: [Int]
    let prerelease: String?
    let raw: String

    init(_ raw: String) {
        self.raw = raw
        var s = Substring(raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        if s.first == "v" { s = s.dropFirst() }
        // Drop build suffixes such as " (456)", ",456" (Homebrew) and "+meta" (semver).
        if let cut = s.firstIndex(where: { $0 == " " || $0 == "(" || $0 == "," || $0 == "+" }) {
            s = s[..<cut]
        }
        var pre: String?
        if let dash = s.firstIndex(of: "-") {
            pre = String(s[s.index(after: dash)...])
            s = s[..<dash]
        }
        var numbers: [Int] = []
        for piece in s.split(whereSeparator: { $0 == "." || $0 == "_" }) {
            let digits = piece.prefix(while: \.isNumber)
            guard let n = Int(digits) else { break }
            numbers.append(n)
            let rest = piece.dropFirst(digits.count)
            if !rest.isEmpty {
                // "1.2b4" → prerelease "b4"
                if pre == nil { pre = String(rest) }
                break
            }
        }
        components = numbers
        // Only real pre-release tags count; suffixes like "-UNKNOWN" or a commit hash are ignored.
        prerelease = pre.flatMap { Self.isPrereleaseTag($0) ? $0 : nil }
    }

    private static let prereleaseWords = ["alpha", "beta", "rc", "pre", "preview", "dev", "nightly", "canary", "insider", "snapshot", "test"]

    private static func isPrereleaseTag(_ tag: String) -> Bool {
        if prereleaseWords.contains(where: tag.contains) { return true }
        // Short forms: "a2", "b4", "b"
        guard let first = tag.first, first == "a" || first == "b" else { return false }
        return tag.dropFirst().allSatisfy(\.isNumber)
    }

    var isValid: Bool { !components.isEmpty }

    var description: String { raw }

    static func < (lhs: Version, rhs: Version) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil), (nil, _?): return false
        case (_?, nil): return true
        case let (l?, r?): return l.compare(r, options: .numeric) == .orderedAscending
        }
    }

    static func == (lhs: Version, rhs: Version) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

enum VersionComparison {
    /// Decides whether a published release is newer than what's installed.
    ///
    /// Marketing versions are compared first; when they tie (or one side only publishes a build number)
    /// the build numbers break the tie.
    static func isNewer(latest: String?, latestBuild: String?, installedVersion: String, installedBuild: String) -> Bool {
        if let latest, Version(latest).isValid, Version(installedVersion).isValid {
            let l = Version(latest), i = Version(installedVersion)
            // Some apps keep the full version in CFBundleVersion ("138.0" / "138.0.6044.65").
            let fullBuild = Version(installedBuild)
            if installedBuild.contains("."), fullBuild.components.count > i.components.count,
               fullBuild.components.starts(with: i.components), l <= fullBuild {
                return false
            }
            if l != i { return l > i }
            // Only break ties with builds of the same shape ("54020" vs "54014", not "2" vs "0.4.28+2").
            let lb = Version(latestBuild ?? ""), ib = Version(installedBuild)
            guard lb.isValid, ib.isValid, lb.components.count == ib.components.count else { return false }
            return lb > ib
        }
        if let latestBuild, Version(latestBuild).isValid, Version(installedBuild).isValid {
            return Version(latestBuild) > Version(installedBuild)
        }
        return false
    }
}
