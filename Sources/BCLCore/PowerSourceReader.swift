import Foundation
import IOKit

public struct BatteryReading {
    public var socPercent: Int?
    public var acPresent: Bool?
}

/// Reads the AppleSmartBattery registry entry, which is the same source the
/// system battery indicator uses for state-of-charge.
public final class PowerSourceReader {
    private var cachedService: io_service_t = 0

    public init() {
        cachedService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    }

    deinit {
        if cachedService != 0 { IOObjectRelease(cachedService) }
    }

    private func properties() -> [String: Any]? {
        if cachedService == 0 {
            cachedService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        }
        guard cachedService != 0 else { return nil }
        var dictionary: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(cachedService, &dictionary, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let created = dictionary?.takeRetainedValue() else { return nil }
        return created as NSDictionary as? [String: Any]
    }

    public func read() -> BatteryReading {
        var reading = BatteryReading()
        guard let properties = properties() else { return reading }

        reading.socPercent = properties["CurrentCapacity"] as? Int
        reading.acPresent = properties["ExternalConnected"] as? Bool

        return reading
    }
}
