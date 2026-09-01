import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TabView {
            ZonesSettingsTab(state: state)
                .tabItem { Label("Zones", systemImage: "angle") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
    }
}

private struct ZonesSettingsTab: View {
    let state: AppState

    @State private var draft: Calibration
    @State private var invalidField: Field?
    @State private var smoother: AngleDisplaySmoother
    @State private var displayedAngle: Int?
    @State private var runner = CalibrationRunner()

    private enum Field { case lowThreshold, hysteresis, dwell }

    init(state: AppState) {
        self.state = state
        _draft = State(initialValue: state.calibration)
        _smoother = State(initialValue: AngleDisplaySmoother(displayed: state.sensor.currentAngle))
        _displayedAngle = State(initialValue: state.sensor.currentAngle)
    }

    var body: some View {
        Form {
            ZoneScaleView(calibration: draft, angle: displayedAngle)
                .frame(height: 28)
                .padding(.vertical, 4)

            slider(
                "Half-closed at", field: .lowThreshold,
                value: Double(draft.lowThreshold),
                range: Double(draft.closedBelow + 1)...Double((draft.maxAngle ?? 180) - draft.stopMargin - 1),
                unit: "°"
            ) { $0.lowThreshold = Int($1) }

            slider(
                "Hysteresis", field: .hysteresis,
                value: Double(draft.hysteresis),
                range: 0...20,
                unit: "°"
            ) { $0.hysteresis = Int($1) }

            slider(
                "Hold time", field: .dwell,
                value: draft.dwell,
                range: 0.2...3.0,
                unit: " s", decimals: 1
            ) { $0.dwell = $1 }

            VStack(alignment: .leading, spacing: 4) {
                Button(runner.isRunning ? "Measuring…" : "Calibrate maximum") {
                    runner.start(reading: { state.sensor.currentAngle })
                }
                .disabled(runner.isRunning)

                switch runner.outcome {
                case .measuring:
                    Text("Now push the lid until it stops, and hold it there for 3 seconds.")
                        .font(.footnote).foregroundStyle(.secondary)
                case .succeeded(let maxAngle):
                    Text("Calibrated: \(maxAngle)°.")
                        .font(.footnote).foregroundStyle(.secondary)
                case .failed(let observedMax):
                    Text("Only reached \(observedMax)°. Start from your normal position, then push the lid to the stop while this runs.")
                        .font(.footnote).foregroundStyle(.red)
                case nil:
                    if let maxAngle = draft.maxAngle {
                        Text("Currently calibrated to \(maxAngle)°.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Not calibrated yet — the stop zone doesn't exist until you do this.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Shortcuts") {
                StopShortcutBindingRow(state: state)
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: runner.outcome) { _, outcome in
            guard case .succeeded(let maxAngle) = outcome else { return }
            var candidate = draft
            candidate.maxAngle = maxAngle
            draft = candidate
            state.calibration = candidate
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            displayedAngle = smoother.update(angle: state.sensor.currentAngle, now: Date())
        }
        .onAppear { state.shortcuts.refreshAvailable() }
    }

    /// Applies one field of a slider edit. Rejected by `Calibration.isValid` → the field is
    /// flagged and `draft` stays put, so the slider's binding snaps back to the old value.
    private func apply(_ field: Field, _ mutate: (inout Calibration) -> Void) {
        var candidate = draft
        mutate(&candidate)
        guard candidate.isValid else {
            invalidField = field
            return
        }
        invalidField = nil
        draft = candidate
        state.calibration = candidate
    }

    @ViewBuilder
    private func slider(
        _ title: String, field: Field, value: Double, range: ClosedRange<Double>,
        unit: String, decimals: Int = 0,
        set: @escaping (inout Calibration, Double) -> Void
    ) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(
                    value: Binding(get: { value }, set: { newValue in apply(field) { set(&$0, newValue) } }),
                    in: range
                )
                Text(String(format: "%.\(decimals)f%@", value, unit))
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
        }
        if invalidField == field {
            Text("That would overlap another zone — value not changed.")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

private struct ZoneScaleView: View {
    let calibration: Calibration
    let angle: Int?

    private var scaleMax: Double {
        Double(calibration.maxAngle ?? max(calibration.lowThreshold + 40, 140))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    segment(0, calibration.closedBelow, width: width, color: .secondary.opacity(0.35))
                    segment(calibration.closedBelow, calibration.lowThreshold, width: width, color: .blue)
                    if let maxAngle = calibration.maxAngle {
                        segment(calibration.lowThreshold, maxAngle - calibration.stopMargin, width: width, color: .secondary.opacity(0.15))
                        segment(maxAngle - calibration.stopMargin, maxAngle, width: width, color: .purple)
                    } else {
                        segment(calibration.lowThreshold, Int(scaleMax), width: width, color: .secondary.opacity(0.15))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))

                if let angle {
                    let fraction = min(max(Double(angle) / scaleMax, 0), 1)
                    Rectangle()
                        .fill(.primary)
                        .frame(width: 2)
                        .offset(x: width * fraction - 1)
                }
            }
        }
    }

    private func segment(_ from: Int, _ to: Int, width: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: width * CGFloat(max(0, to - from)) / CGFloat(scaleMax))
    }
}

/// The `stop` zone's pair of pickers: what runs on enter, what runs on exit. `low` has no row
/// here at all — it's hardcoded to the built-in mic mute, in every tier (ShortcutAction.swift).
/// `stop` always shows an effective shortcut, `DefaultShortcuts` until swapped, and the pickers
/// let anyone choose whatever `shortcuts list` returns.
///
/// ponytail: Stage 1 (free-first) — no Pro gate here. `tier` is pinned to `.pro`
/// (AppState.proUnlockedForFreeStage); Block 13 restores the disabled-with-"Pro"-badge state.
private struct StopShortcutBindingRow: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("On pushed to the stop", picker(edge: .enter, label: "On enter"))
            row("On leaving the stop", picker(edge: .exit, label: "On exit"))
        }
    }

    private func row(_ title: String, _ control: some View) -> some View {
        HStack {
            Text(title).frame(width: 160, alignment: .leading)
            control
        }
    }

    private func picker(edge: ZoneEdge, label: String) -> some View {
        let binding = Binding<String>(
            get: { state.shortcutBindings.shortcut(for: .stop, edge: edge) ?? DefaultShortcuts.name(for: edge) },
            set: { name in
                var bindings = state.shortcutBindings
                // Picking the default stores nothing. Storing it would freeze a copy of the name,
                // and a frozen copy outlives the shortcut it points at: renaming the shipped
                // default once left every stop push calling a shortcut that no longer existed.
                bindings.set(name == DefaultShortcuts.name(for: edge) ? nil : name, for: .stop, edge: edge)
                state.shortcutBindings = bindings
            }
        )
        var options = [DefaultShortcuts.name(for: edge)]
        for name in state.shortcuts.available where !options.contains(name) {
            options.append(name)
        }
        return Picker(label, selection: binding) {
            ForEach(options, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        .labelsHidden()
    }
}

private struct AboutSettingsTab: View {
    @Environment(AppState.self) private var state

    private static let siteURL = URL(string: "https://quietunit.com/ajar")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Form {
            LabeledContent("Version", value: version)
            Link("quietunit.com/ajar", destination: Self.siteURL)
            Button("Show intro again") { state.showOnboarding() }

            // ponytail: Stage 1 (free-first) — no license/trial status shown, no paywall entry.
            // Block 13 restores this Section. Licensing code stays in Ajar/Licensing/.

            Section {
                Button("Check for Updates…") { Updater.controller.checkForUpdates(nil) }
                Text("Ajar checks for updates once a day on its own.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
