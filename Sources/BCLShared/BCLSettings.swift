import Foundation

public struct BCLSettings: Codable, Equatable {
    public static let limitRange: ClosedRange<Int> = 50...80

    /// Charging stays inhibited until state of charge falls this far below the limit, so the pack
    /// takes one charge run back instead of a drip of short top-ups.
    public static let rearmBandPercent = 3

    public var limitPercent: Int

    public init(limitPercent: Int = 80) {
        self.limitPercent = limitPercent
        normalize()
    }

    public mutating func normalize() {
        limitPercent = min(max(limitPercent, Self.limitRange.lowerBound), Self.limitRange.upperBound)
    }

    public var rearmPercent: Int { max(0, limitPercent - Self.rearmBandPercent) }

    public func encodedJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    public static func decode(fromJSON text: String) -> BCLSettings? {
        guard let data = text.data(using: .utf8), var settings = try? JSONDecoder().decode(BCLSettings.self, from: data) else { return nil }
        settings.normalize()
        return settings
    }
}
