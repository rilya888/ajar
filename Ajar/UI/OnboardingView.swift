import AppKit
import SwiftUI

// MARK: - Pure logic

/// First-run flag. Same `UserDefaults` load/save shape as `Calibration`/`ShortcutBindings`,
/// so it's testable with an injected suite instead of touching `.standard`.
enum OnboardingState {
    static let defaultsKey = "hasCompletedOnboarding"

    static func hasCompleted(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func markCompleted(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: defaultsKey)
    }
}

/// The one thing that decides whether the compatibility screen can advance. A pure function
/// of `currentAngle == nil` — no sensor found, no continue button, ever. `LidAngleReader`
/// documents `currentAngle == nil` as the single source of truth for "no sensor" (ARCHITECTURE.md);
/// this is that same rule, named and tested on its own.
enum CompatibilityGate {
    static func isCompatible(currentAngle: Int?) -> Bool {
        currentAngle != nil
    }
}

// MARK: - Screens

enum OnboardingStep {
    case compatibility, calibrate, gesture, login
}

struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @State private var step: OnboardingStep = .compatibility

    var body: some View {
        Group {
            switch step {
            case .compatibility:
                CompatibilityStepView(onContinue: { step = .calibrate })
            case .calibrate:
                CalibrateStepView(onContinue: { step = .gesture })
            case .gesture:
                GestureStepView(onContinue: { step = .login })
            case .login:
                LoginStepView(onFinish: { state.completeOnboarding() })
            }
        }
        .frame(width: 480, height: 440)
    }
}

/// Screen 1. Compatibility is checked before anything else, including any mention of price
/// (PRODUCT.md, ARCHITECTURE.md): a Mac with no sensor sees an honest explanation and a way to
/// remove Ajar, never a paywall. There is no Continue button on the incompatible branch — this
/// is a dead end by design.
private struct CompatibilityStepView: View {
    @Environment(AppState.self) private var state
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let angle = state.sensor.currentAngle,
               CompatibilityGate.isCompatible(currentAngle: angle) {
                Text("Ajar found your lid sensor")
                    .font(.title2.bold())
                Text("Your lid is open at \(angle)°.")
                    .font(.system(size: 32, weight: .semibold))
                    .monospacedDigit()
                Text("That's the best proof this works — Ajar is reading your lid angle right now, live.")
                    .foregroundStyle(.secondary)
                Spacer()
                HStack {
                    Spacer()
                    Button("Continue", action: onContinue)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Ajar isn't supported on this Mac")
                    .font(.title2.bold())
                Text("\(Self.modelIdentifier()) doesn't expose the lid angle sensor Ajar reads. There's nothing to fix — Ajar simply can't do anything on this machine.")
                    .foregroundStyle(.secondary)
                Link("Check the compatibility list", destination: MenuBarViewModel.compatibilityURL)
                Spacer()
                Text("Drag Ajar to the Trash — it has no use here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Reveal Ajar in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                }
            }
        }
        .padding(32)
    }

    private static func modelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "This Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}

/// Screen 2. The affirmative path is a real 3 s measurement (`CalibrationRunner`, same driver
/// Settings ▸ Zones uses). Skipping is allowed — Continue is never blocked on it — but the
/// consequence is spelled out, not hidden: no calibration, no `stop` zone.
private struct CalibrateStepView: View {
    @Environment(AppState.self) private var state
    @State private var runner = CalibrationRunner()
    @State private var importFailed = false
    let onContinue: () -> Void

    private var isCalibrated: Bool { state.calibration.maxAngle != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calibrate the stop")
                .font(.title2.bold())
            Text("Push the lid until it stops, and hold it there for 3 seconds. Ajar remembers that angle as the top of the range.")
                .foregroundStyle(.secondary)

            Button(runner.isRunning ? "Measuring…" : "Push the lid until it stops") {
                runner.start(reading: { state.sensor.currentAngle })
            }
            .disabled(runner.isRunning)

            outcomeText

            if !isCalibrated {
                Text("Skip this and the stop zone stays off until you calibrate later, in Settings ▸ Zones.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button("Add the default stop shortcuts") { addDefaultShortcuts() }
                if importFailed {
                    Text("Couldn't download the shortcuts — check your connection and try again.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Text("Pushing the lid to the stop turns on Do Not Disturb, and back off when you pull away — free, always on. Trial and Pro can swap either for a different Shortcut later, in Settings ▸ Zones.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            HStack {
                Spacer()
                Button("Continue", action: onContinue)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .onChange(of: runner.outcome) { _, outcome in
            guard case .succeeded(let maxAngle) = outcome else { return }
            var candidate = state.calibration
            candidate.maxAngle = maxAngle
            state.calibration = candidate
        }
    }

    @ViewBuilder
    private var outcomeText: some View {
        switch runner.outcome {
        case .measuring:
            Text("Hold the lid at the stop…")
                .font(.footnote).foregroundStyle(.secondary)
        case .succeeded(let maxAngle):
            Text("Calibrated: \(maxAngle)°. The stop zone is ready.")
                .font(.footnote).foregroundStyle(.secondary)
        case .failed(let observedMax):
            Text("Only reached \(observedMax)°. Start from your normal position, then push the lid to the stop while this runs.")
                .font(.footnote).foregroundStyle(.red)
        case nil:
            if isCalibrated, let maxAngle = state.calibration.maxAngle {
                Text("Already calibrated to \(maxAngle)°.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// Each import pops Shortcuts.app's own "Add Shortcut" confirmation — no Accessibility, no
    /// silent install. Safe to tap more than once: Shortcuts overwrites the same-named shortcut
    /// rather than duplicating it. Needs the network (the two files are hosted), so it can fail.
    @MainActor
    private func addDefaultShortcuts() {
        importFailed = false
        Task {
            for name in [DefaultShortcuts.stopEnter, DefaultShortcuts.stopExit] {
                do {
                    NSWorkspace.shared.open(try await DefaultShortcuts.download(name))
                } catch {
                    importFailed = true
                }
            }
        }
    }
}

/// Screen 3. The honesty PRODUCT.md insists on: the Zoom/Meet caveat, word for word what the
/// landing page says (docs/release/site.md), shown as body text, not a disclaimer nobody reads.
/// The Continuity-microphone gap (found on hardware in Block 04/09, STATUS.md) rides along here
/// because it's the same kind of "the mute didn't do what you expected" surprise.
private struct GestureStepView: View {
    let onContinue: () -> Void

    /// Verbatim match required with docs/release/site.md.
    static let zoomWarning = "macOS will mute your input device. Zoom and Meet will still show you as unmuted in their own UI."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The gesture")
                .font(.title2.bold())
            Text("Close the lid halfway and Ajar mutes your microphone. Open it back up and it unmutes — but only if Ajar was the one that muted it in the first place.")
                .foregroundStyle(.secondary)

            Text(Self.zoomWarning)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Text("If your default microphone is an iPhone connected over Continuity, Ajar can't mute it at all — Continuity doesn't expose a mute or volume control to any app.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
            HStack {
                Spacer()
                Button("Continue", action: onContinue)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
    }
}

/// Screen 4. One toggle, on by default — Ajar only reacts to the lid while it's running.
private struct LoginStepView: View {
    @State private var loginEnabled = true
    @State private var error: String?
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Launch at login")
                .font(.title2.bold())
            Text("Ajar only reacts to the lid while it's running. Keep it launching automatically and the gesture is always live.")
                .foregroundStyle(.secondary)
            Toggle("Launch Ajar at login", isOn: $loginEnabled)
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            Spacer()
            HStack {
                Spacer()
                Button("Get started") {
                    do {
                        try LaunchAtLogin.setEnabled(loginEnabled)
                    } catch {
                        self.error = "Couldn't change login item: \(error.localizedDescription)"
                    }
                    onFinish()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
    }
}

// MARK: - Window + AppState wiring

/// Hosts `OnboardingView` in its own titled window — the app is `LSUIElement`, so there is no
/// window otherwise. Built with plain AppKit rather than a SwiftUI `Window` scene: `AppDelegate`
/// already opens this from `applicationDidFinishLaunching`, and keeping the same AppKit path
/// end to end avoids relying on SwiftUI's own window-opening machinery inside a `MenuBarExtra`
/// app, which Block 07 found unreliable for `openSettings()`.
final class OnboardingWindowController: NSWindowController {
    convenience init(state: AppState) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Ajar"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView().environment(state))
        self.init(window: window)
    }
}

extension AppState {
    var hasCompletedOnboarding: Bool {
        get { OnboardingState.hasCompleted() }
        set { if newValue { OnboardingState.markCompleted() } }
    }

    /// Called once from `AppDelegate.applicationDidFinishLaunching`.
    func showOnboardingIfNeeded() {
        guard !hasCompletedOnboarding else { return }
        showOnboarding()
    }

    /// Also the target of Settings ▸ About ▸ "Show intro again".
    func showOnboarding() {
        let controller = OnboardingWindowController(state: self)
        onboardingWindow = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        (onboardingWindow as? NSWindowController)?.close()
        onboardingWindow = nil
    }
}
