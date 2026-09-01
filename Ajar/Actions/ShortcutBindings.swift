import Foundation

/// Which side of a zone transition a Shortcut is bound to.
enum ZoneEdge: String, Codable {
    case enter
    case exit
}

/// `zone.edge → Shortcut name`. Flat dictionary, not a nested model: the only operations
/// anyone needs are "what's bound here" and "bind this here".
struct ShortcutBindings: Codable, Equatable {
    private var values: [String: String] = [:]

    private static func key(_ zone: Zone, _ edge: ZoneEdge) -> String {
        "\(zone.rawValue).\(edge.rawValue)"
    }

    func shortcut(for zone: Zone, edge: ZoneEdge) -> String? {
        values[Self.key(zone, edge)]
    }

    /// `nil` or empty clears the binding.
    mutating func set(_ name: String?, for zone: Zone, edge: ZoneEdge) {
        let key = Self.key(zone, edge)
        if let name, !name.isEmpty {
            values[key] = name
        } else {
            values.removeValue(forKey: key)
        }
    }
}

extension ShortcutBindings {
    static let defaultsKey = "shortcutBindings"

    static func load(from defaults: UserDefaults = .standard) -> ShortcutBindings {
        guard let data = defaults.data(forKey: defaultsKey),
              let bindings = try? JSONDecoder().decode(ShortcutBindings.self, from: data) else {
            return ShortcutBindings()
        }
        return bindings
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// The `stop` zone's out-of-the-box action, shipped so the zone never does nothing: turn Do Not
/// Disturb on at the stop, off on the way out. Free tier always runs these two, unchanged, forever
/// — the same "always works" guarantee `MicMuter` gives `low`. Trial/Pro can swap either edge for
/// a different Shortcut in Settings ▸ Zones; losing Pro access reverts to these, it never deletes
/// the custom pick (buying back in restores it).
enum DefaultShortcuts {
    /// No colon in either name: the imported shortcut is named after the file it was opened from,
    /// so these strings double as filenames, and `:` is the legacy path separator on macOS.
    static let stopEnter = "Ajar Do Not Disturb"
    static let stopExit = "Ajar Resume Focus"

    static func name(for edge: ZoneEdge) -> String {
        switch edge {
        case .enter: return stopEnter
        case .exit: return stopExit
        }
    }

    private static let hostedFile: [String: String] = [
        stopEnter: "https://quietunit.com/ajar/shortcuts/do-not-disturb-on.shortcut",
        stopExit: "https://quietunit.com/ajar/shortcuts/do-not-disturb-off.shortcut"
    ]

    /// Downloads the hosted, signed `.shortcut` to a temp file for the caller to `open`.
    ///
    /// Not `shortcuts://import-shortcut?url=…`: Shortcuts.app rejects that outright on macOS 26
    /// ("The shortcut URL provided was invalid", logged 7 ms in, before it ever fetches the file),
    /// whatever the encoding. Opening the downloaded file is the ordinary double-click path —
    /// Shortcuts validates the signature and shows its own "Add Shortcut" confirmation, still the
    /// only install route that needs no Accessibility.
    ///
    /// Saved as `<name>.shortcut`, not under the hosted filename: Shortcuts names the imported
    /// shortcut after the file, and that name is what `shortcuts run` later looks up.
    static func download(_ name: String) async throws -> URL {
        guard let file = hostedFile[name], let remote = URL(string: file) else {
            throw URLError(.badURL)
        }
        // Cache-busting is not paranoia: nginx sends no Cache-Control, so URLSession heuristically
        // caches off Last-Modified and happily reinstalls a stale shortcut after the hosted file
        // is fixed — which is exactly what happened here.
        let request = URLRequest(url: remote, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let local = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension("shortcut")
        try data.write(to: local)
        return local
    }
}

/// What to run for one committed transition. Pure — no Process, no Shortcuts, testable without
/// touching either. Only the `stop` zone ever runs a Shortcut: `low` is hardcoded to the built-in
/// mic mute (Actions/MicMuter.swift) and never gets a custom binding, in any tier.
enum ShortcutAction {
    /// Leaving `stop` always fires its exit shortcut, suppressed or not — the same reasoning as
    /// `MicMuter`'s restore: suppression must never strand whatever the enter shortcut turned on.
    /// Entering is gated, matching `ZoneAction.decide` for the built-in mute. Free tier — or any
    /// tier with the edge unbound — falls back to `DefaultShortcuts`, so `stop` always does
    /// something.
    static func decide(_ transition: ZoneTransition, bindings: ShortcutBindings, tier: Tier, suppressed: Bool) -> [String] {
        var names: [String] = []
        if transition.from == .stop {
            names.append(shortcut(edge: .exit, bindings: bindings, tier: tier))
        }
        if !suppressed, transition.to == .stop {
            names.append(shortcut(edge: .enter, bindings: bindings, tier: tier))
        }
        return names
    }

    private static func shortcut(edge: ZoneEdge, bindings: ShortcutBindings, tier: Tier) -> String {
        guard tier.unlocksPro, let custom = bindings.shortcut(for: .stop, edge: edge) else {
            return DefaultShortcuts.name(for: edge)
        }
        return custom
    }
}
