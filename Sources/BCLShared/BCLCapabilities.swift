import Foundation

public struct BCLCapabilities: Codable {
    public var helperVersion: String
    public var protocolVersion: Int
    public var runningAsRoot: Bool
    public var chargeControlKeyGroup: String?
    public var chargeControlWritable: Bool
    public var notes: [String]

    public init(
        helperVersion: String,
        protocolVersion: Int,
        runningAsRoot: Bool,
        chargeControlKeyGroup: String?,
        chargeControlWritable: Bool,
        notes: [String]
    ) {
        self.helperVersion = helperVersion
        self.protocolVersion = protocolVersion
        self.runningAsRoot = runningAsRoot
        self.chargeControlKeyGroup = chargeControlKeyGroup
        self.chargeControlWritable = chargeControlWritable
        self.notes = notes
    }

    public func encodedJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
