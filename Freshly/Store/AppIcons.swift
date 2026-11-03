import AppKit

/// Caches Finder icons so list scrolling stays smooth.
@MainActor
enum AppIcons {
    private static var cache: [URL: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        if let cached = cache[url] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[url] = icon
        return icon
    }
}
