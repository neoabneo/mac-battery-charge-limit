import Foundation

/// Uniform reply envelope for every helper call. Plain JSON strings cross the XPC boundary
/// because block signatures with Swift tuples are not representable in the ObjC protocol
/// NSXPCInterface is built from.
public struct BCLCallResult: Codable {
    public var ok: Bool
    public var message: String

    public init(ok: Bool, message: String) {
        self.ok = ok
        self.message = message
    }

    public func encodedJSON() -> String {
        guard let data = try? JSONEncoder().encode(self), let text = String(data: data, encoding: .utf8) else {
            return "{\"ok\":false,\"message\":\"result could not be encoded\"}"
        }
        return text
    }

    public static func decode(fromJSON text: String) -> BCLCallResult {
        guard let data = text.data(using: .utf8),
              let result = try? JSONDecoder().decode(BCLCallResult.self, from: data) else {
            return BCLCallResult(ok: false, message: "malformed helper reply")
        }
        return result
    }
}
