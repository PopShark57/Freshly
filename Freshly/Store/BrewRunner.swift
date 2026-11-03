import AppKit
import Observation

/// Runs `brew upgrade --cask` and streams its output for the log sheet.
@Observable
@MainActor
final class BrewRunner {
    private(set) var log = ""
    private(set) var tokens: [String] = []
    private(set) var isRunning = false
    private(set) var exitCode: Int32?
    /// brew finished but declined to upgrade something.
    private(set) var skipped = false
    var isPresented = false

    /// Called with the upgraded tokens once brew exits successfully.
    @ObservationIgnored var onFinish: ((Set<String>) -> Void)?

    func upgrade(_ tokens: [String]) {
        guard !isRunning else { isPresented = true; return }
        self.tokens = tokens
        exitCode = nil
        skipped = false
        isPresented = true
        Task { await run(tokens) }
    }

    private func run(_ tokens: [String]) async {
        guard let brew = HomebrewProvider.brewPath else {
            log = "Homebrew isn't installed. Get it from https://brew.sh"
            exitCode = 127
            return
        }
        isRunning = true
        log = "$ brew upgrade --cask \(tokens.joined(separator: " "))\n\n"

        let process = Process()
        process.executableURL = URL(filePath: brew)
        process.arguments = ["upgrade", "--cask"] + tokens
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_COLOR"] = "1"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let output = AsyncStream<String> { continuation in
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(String(decoding: data, as: UTF8.self))
                }
            }
        }

        do {
            try process.run()
        } catch {
            log += "Couldn't start brew: \(error.localizedDescription)\n"
            isRunning = false
            exitCode = -1
            return
        }

        for await chunk in output { log += chunk.replacing(#/\u{1B}\[[0-9;]*m/#, with: "") }
        let status = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            }
        }

        exitCode = status
        isRunning = false
        // brew exits 0 even when it refuses a cask (disabled, pinned…), so look for its warning too.
        skipped = status == 0 && log.contains("Not upgrading")
        if skipped {
            log += "\n⚠︎ Homebrew skipped the upgrade. See the warning above."
        } else {
            log += status == 0 ? "\n✓ Done." : "\n✗ brew exited with status \(status). Some casks need your password — try “Open in Terminal”."
        }
        if status == 0 { onFinish?(Set(tokens)) }
    }

    /// Runs the same command in Terminal, for casks whose installers need sudo.
    func openInTerminal() {
        let script = FileManager.default.temporaryDirectory.appending(path: "freshly-brew-upgrade.command")
        let body = "#!/bin/zsh\nbrew upgrade --cask \(tokens.joined(separator: " "))\n"
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch {
            log += "\nCouldn't open Terminal: \(error.localizedDescription)"
        }
    }
}
