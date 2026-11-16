import Foundation
import Security

/// Validates the process on the other end of an XPC connection against the requirement the installer
/// recorded for this build. NSXPC only exposes a pid, so the peer is resolved by pid and then checked.
struct ClientValidator {
    let requirementText: String

    init(requirementText: String) {
        self.requirementText = requirementText
    }

    func validate(clientPID: pid_t) -> (accepted: Bool, detail: String) {
        var guest: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: clientPID)] as CFDictionary
        let lookup = SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &guest)
        guard lookup == errSecSuccess, let guest else {
            return (false, "could not identify client process pid \(clientPID) (OSStatus \(lookup))")
        }

        var requirement: SecRequirement?
        let compiled = SecRequirementCreateWithString(requirementText as CFString, SecCSFlags(), &requirement)
        guard compiled == errSecSuccess, let requirement else {
            return (false, "client requirement did not compile (OSStatus \(compiled))")
        }

        var error: Unmanaged<CFError>?
        let validity = SecCodeCheckValidityWithErrors(guest, SecCSFlags(), requirement, &error)
        guard validity != errSecSuccess else { return (true, "client signature accepted") }

        let described = error?.takeRetainedValue().localizedDescription ?? "no detail"
        return (false, "client pid \(clientPID) failed code-signing validation: \(described) (OSStatus \(validity))")
    }
}
