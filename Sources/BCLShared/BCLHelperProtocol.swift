import Foundation

/// The ObjC-visible shape of the helper's XPC interface. Replies are JSON strings because Swift
/// tuple block signatures cannot be represented in the NSXPCInterface built from this protocol.
@objc(BCLHelperProtocol)
public protocol BCLHelperProtocol {
    func applySettings(_ settingsJSON: String, withReply reply: @escaping (String) -> Void)
    func telemetryJSON(withReply reply: @escaping (String) -> Void)
}
