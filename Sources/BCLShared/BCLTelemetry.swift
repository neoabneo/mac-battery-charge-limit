import Foundation

public struct BCLTelemetry: Codable {
    public var socPercent: Int?
    public var acAttached: Bool?

    public var chargeRequest: String?
    public var chargeKeyActualRaw: String?
    public var enforcementActive: Bool?
    public var appliedLimitPercent: Int?

    public var chargeControlWritable: Bool?
    public var lastSMCError: String?

    public init() {}

    public func encodedJSON() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    public static func decode(fromJSON text: String) -> BCLTelemetry? {
        guard let data = text.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BCLTelemetry.self, from: data)
    }
}
