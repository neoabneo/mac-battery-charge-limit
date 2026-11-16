import Foundation
import BCLShared

/// The app's only disk write: one UserDefaults key holding the whole settings blob, rewritten
/// when the user changes a setting. There is no log file, cache, statistics database or updater.
final class SettingsStore {
    // UserDefaults.standard is already the app's own domain, keyed by bundle id.
    private static let storageKey = "settings"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> BCLSettings {
        guard let text = defaults.string(forKey: Self.storageKey),
              let settings = BCLSettings.decode(fromJSON: text) else { return BCLSettings() }
        return settings
    }

    func save(_ settings: BCLSettings) {
        defaults.set(settings.encodedJSON(), forKey: Self.storageKey)
    }
}
