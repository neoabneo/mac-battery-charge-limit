import AppKit

/// Menu bar extras are ordered by a per-app "NSStatusItem Preferred Position <item>" preference that
/// AppKit reads only when the item is created. Control Center stores the battery item's value, so
/// writing a value just above it lands this app's item immediately to the left of the system icon.
enum MenuBarPlacement {
    static let autosaveName = "BatteryChargeLimit"
    static let positionKey = "NSStatusItem Preferred Position " + autosaveName

    private static let controlCenterDomain = "com.apple.controlcenter"
    private static let batteryKey = "NSStatusItem Preferred Position Battery"
    private static let keyPrefix = "NSStatusItem Preferred Position "

    /// Returns true when a new position had to be stored, which is when the item must be rebuilt
    /// for AppKit to pick the value up.
    static func apply() -> Bool {
        guard let target = targetValue() else { return false }
        let defaults = UserDefaults.standard
        if defaults.string(forKey: positionKey) != nil && defaults.integer(forKey: positionKey) == target {
            return false
        }
        defaults.set(target, forKey: positionKey)
        defaults.synchronize()
        return true
    }

    private static func targetValue() -> Int? {
        guard let battery = controlCenterValue(forKey: batteryKey) else { return nil }
        let toTheLeft = controlCenterPreferredPositions().filter { $0 > battery }
        if let next = toTheLeft.min() { return battery + max(8, (next - battery) / 2) }
        return battery + 40
    }

    private static func controlCenterPreferredPositions() -> [Int] {
        guard let keys = CFPreferencesCopyKeyList(
            controlCenterDomain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        ) as? [String] else { return [] }
        return keys.filter { $0.hasPrefix(keyPrefix) }.compactMap(controlCenterValue(forKey:))
    }

    private static func controlCenterValue(forKey key: String) -> Int? {
        CFPreferencesCopyAppValue(key as CFString, controlCenterDomain as CFString) as? Int
    }
}
