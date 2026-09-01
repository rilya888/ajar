import SwiftUI

enum PaywallWindow {
    static let id = "paywall"

    /// The activate() matters: an LSUIElement app opens its windows behind everything else.
    static func open(_ openWindow: OpenWindowAction) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// One window: what Pro is, what it costs, where to buy, and where to paste the key.
/// No countdown, no "offer ends", no red badge — the trial doesn't nag and neither does this.
struct PaywallView: View {
    @Environment(AppState.self) private var state

    @State private var key = ""
    @State private var error: String?

    /// ponytail: live Paddle checkout isn't set up yet (docs/TODO.md) — domain is real, path is a placeholder.
    static let purchaseURL = URL(string: "https://quietunit.com/ajar/buy")!
    static let price = "$9"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ajar Pro").font(.title2).bold()

            if let email = state.license.email {
                Label("Licensed to \(email)", systemImage: "checkmark.seal")
                Text("Thank you. The key works on every Mac you own — no activation limit, no sign-in.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    feature("Push the lid to its stop", "Turns on Do Not Disturb by default — works on Free too.")
                    feature("Swap in your own Shortcut", "Replace the stop's on/off pair with music, lights, a scene, anything.")
                }
                Text("One-time purchase, \(Self.price). Free updates, works offline.")
                    .font(.callout).foregroundStyle(.secondary)

                Link(destination: Self.purchaseURL) {
                    Text("Buy Ajar Pro — \(Self.price)")
                }
                .buttonStyle(.borderedProminent)

                Divider()

                Text("Already bought it? Paste the key from your purchase email.")
                    .font(.callout)
                HStack {
                    TextField("email@example.com|order.signature", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(activate)
                    Button("Activate", action: activate)
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                // "Restore" without a server is exactly this: the same key again, on any Mac.
                Text("Lost the key? Reply to your purchase email — there is nothing to restore online.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 420, height: 340)
    }

    private func feature(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "laptopcomputer.badge.checkmark")
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func activate() {
        do {
            try state.license.activate(key)
            error = nil
            key = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}
