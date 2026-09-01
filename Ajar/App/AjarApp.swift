import SwiftUI

@main
struct AjarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(appDelegate.state)
        } label: {
            MenuBarIconView(model: appDelegate.state.menuBar)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appDelegate.state)
        }
        // ponytail: Stage 1 — the paywall Window scene is gone so it's unreachable.
        // PaywallView.swift stays in the tree for Block 13. See AppState.proUnlockedForFreeStage.
    }
}

/// Owns the single `AppState` and shows onboarding on first launch.
///
/// A plain `NSApplicationDelegate` hook, not a SwiftUI `.onAppear` on the menu bar label:
/// Block 07 already found that SwiftUI's own window-opening actions (`openSettings()`) go
/// quiet from inside a `MenuBarExtra` in this `LSUIElement` app. `applicationDidFinishLaunching`
/// is the one AppKit callback guaranteed to fire once, after the app has finished setting up —
/// driving the onboarding window from here sidesteps the same class of problem.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Updater.controller   // arms Sparkle's daily background check
        state.showOnboardingIfNeeded()
    }
}
