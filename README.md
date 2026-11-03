# Freshly

A macOS 27 app that scans `/Applications` (and `~/Applications`) and finds updates for everything it can.

## Where updates come from

Each app is checked against the first source that applies:

1. **App Store**: apps with an App Store receipt are looked up in batches through the iTunes lookup API.
2. **Sparkle**: the app's `SUFeedURL` appcast. Beta channels are optional, and releases that need a newer macOS are skipped.
3. **Electron**: `app-update.yml` (electron-updater) with the `generic`, `github` or `s3` providers.
4. **Homebrew**: the public cask catalogue (`formulae.brew.sh`), matched by app bundle name. Apps installed with brew can be upgraded in the app.

Setapp builds (`*-setapp` bundle IDs) are marked as managed by Setapp. Apple's built-in apps are skipped because they update with macOS.

Freshly compares against the version actually installed on disk, not Homebrew's Caskroom record. That makes it more accurate than `brew outdated --greedy` for apps that update themselves.

## Build

Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
xcodebuild -project Freshly.xcodeproj -scheme Freshly -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Debug/Freshly.app
```

Run the tests with the same command, using `test` in place of `build`. To regenerate the icon, run `swift Tools/make-icon.swift Freshly/Assets.xcassets/AppIcon.appiconset`.

## Layout

- `Freshly/Scanning`: finds app bundles and reads their `Info.plist`
- `Freshly/Versioning`: forgiving version comparison
- `Freshly/Providers`: the App Store, Sparkle, Electron and Homebrew checkers, plus `UpdateChecker`, which runs them in order
- `Freshly/Store`: `UpdateCenter`, the observable app state with saving and background checks, and `BrewRunner`
- `Freshly/Views`: SwiftUI views with Liquid Glass styling, the menu bar extra and Settings

The app is not sandboxed, because it has to read other apps' bundles and run `brew`.
