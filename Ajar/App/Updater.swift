import AppKit
import Sparkle

/// Sparkle's entire footprint in this app.
///
/// One controller, created once at launch: `startingUpdater: true` arms the background
/// check, and Sparkle's own default interval is already 86400 s, so the daily schedule
/// needs no key of its own. Feed URL and public EdDSA key live in `Info.plist`
/// (`SUFeedURL`, `SUPublicEDKey`) — changing the feed is a build setting, not code.
///
/// Kept out of `AppState` on purpose: `AppState` is built by the unit tests, and nothing
/// in a test run should start a real updater or reach the network.
enum Updater {
    static let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: reminders
    )

    private static let reminders = GentleReminders()
}

/// `LSUIElement` app: no Dock icon, so a scheduled update alert opens behind whatever the
/// user is looking at and is never seen. Sparkle warns about exactly this at launch.
/// A broken updater cannot be fixed by an update, so the alert is pulled to the front.
private final class GentleReminders: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !state.userInitiated else { return }
        NSApp.activate(ignoringOtherApps: true)
    }
}
