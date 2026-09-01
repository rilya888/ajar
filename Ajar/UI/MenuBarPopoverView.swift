import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(AppState.self) private var state

    @State private var loginEnabled = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var suppressor = state.suppressor
        let model = state.menuBar

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.angleText)
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()
                    Text(model.zoneText).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let message = model.sensorMessage {
                Text(message).font(.callout)
                Link("Check compatibility", destination: MenuBarViewModel.compatibilityURL)
                    .font(.callout)
            } else {
                Divider()
                ForEach(model.zoneLines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(line.title)
                            .fontWeight(line.isCurrent ? .semibold : .regular)
                        Spacer(minLength: 8)
                        Text(line.isLocked ? "Pro" : line.effect)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                    .opacity(line.isLocked ? 0.6 : 1)
                }
            }

            if let status = model.statusLine {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
            if let shortcutError = model.shortcutErrorLine {
                Text(shortcutError).font(.footnote).foregroundStyle(.red)
            }

            Divider()
            Toggle("Pause Ajar", isOn: $suppressor.isPaused)
            Toggle("Launch at login", isOn: $loginEnabled)
                .onChange(of: loginEnabled) { _, enabled in
                    do {
                        try LaunchAtLogin.setEnabled(enabled)
                        loginError = nil
                    } catch {
                        loginEnabled = !enabled
                        loginError = "Couldn't change login item: \(error.localizedDescription)"
                    }
                }
            if let loginError {
                Text(loginError).font(.footnote).foregroundStyle(.red)
            }
            HStack {
                // SettingsLink, not a Button calling openSettings(): from a MenuBarExtra in an
                // LSUIElement app the environment action silently does nothing. The activate()
                // is still needed — an accessory app opens the window behind everything else.
                SettingsLink {
                    Text("Settings…")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    NSApp.activate(ignoringOtherApps: true)
                })
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
