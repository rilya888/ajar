import Foundation
import Observation
import os

/// Which names are currently in flight. Pure and Process-free on purpose: this is the piece
/// the block's unit tests cover, per CLAUDE.md — the Shortcuts call itself is not mocked.
struct ShortcutRunGate: Equatable {
    private var inFlight: Set<String> = []

    /// True if `name` may run now; marks it in flight until `finished(_:)`. A second call for
    /// the same name while the first hasn't finished is refused — a stuck Shortcut must never
    /// pile up behind the next lid gesture.
    mutating func start(_ name: String) -> Bool {
        guard !inFlight.contains(name) else { return false }
        inFlight.insert(name)
        return true
    }

    mutating func finished(_ name: String) {
        inFlight.remove(name)
    }
}

/// The only layer that touches `/usr/bin/shortcuts`. Runs by name, asynchronously, and never
/// lets one hung run block the next.
///
/// Path chosen: `Process` on `/usr/bin/shortcuts run <name>`, not `NSUserAppleScriptTask`.
/// This is a reasoned default, not a measured one — see docs/STATUS.md: no test Shortcut and no
/// GUI access were available to this agent, so the launch-latency comparison the block asks for
/// was not run. `shortcuts` is also already the binary `refreshAvailable()` needs for `list`,
/// so one binary covers both instead of mixing in AppleScript. Owner still needs to measure and
/// confirm before the ~700 ms risk line in PRODUCT.md can be signed off.
@Observable
final class ShortcutRunner {
    private static let binary = "/usr/bin/shortcuts"

    private let log = Logger(subsystem: "com.quietunit.ajar", category: "shortcuts")
    @ObservationIgnored private let queue = DispatchQueue(label: "com.quietunit.ajar.shortcuts")
    @ObservationIgnored private var gate = ShortcutRunGate()

    /// `shortcuts list`, cached here so Settings only pays for it once per window open —
    /// call `refreshAvailable()` when the Zones tab appears, not on every picker render.
    private(set) var available: [String] = []

    /// Shown as a line in the popover. Not queued or timestamped: the newest failure replaces
    /// the last, and a later successful run clears it.
    private(set) var lastError: String?

    func refreshAvailable() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: Self.binary)
        task.arguments = ["list"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            available = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        } catch {
            log.error("shortcuts list failed: \(error.localizedDescription, privacy: .public)")
            available = []
        }
    }

    /// Fire-and-forget. Dropped, not queued, if `name` is already running.
    func run(_ name: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.gate.start(name) else {
                self.log.notice("skipped \(name, privacy: .public): already running")
                return
            }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: Self.binary)
            task.arguments = ["run", name]
            task.terminationHandler = { [weak self] process in
                self?.queue.async { self?.gate.finished(name) }
                let status = process.terminationStatus
                DispatchQueue.main.async {
                    if status == 0 {
                        self?.lastError = nil
                    } else {
                        let message = "Shortcut \"\(name)\" failed (exit \(status))."
                        self?.log.error("\(message, privacy: .public)")
                        self?.lastError = message
                    }
                }
            }
            do {
                try task.run()
            } catch {
                self.gate.finished(name)
                let message = "Shortcut \"\(name)\" couldn't start: \(error.localizedDescription)"
                self.log.error("\(message, privacy: .public)")
                DispatchQueue.main.async { self.lastError = message }
            }
        }
    }
}
