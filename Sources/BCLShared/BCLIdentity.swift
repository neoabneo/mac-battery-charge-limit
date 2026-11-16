import Foundation

/// The helper's runtime identity. These must match CFBundleIdentifier in Support/app-Info.plist:
/// the build script and the installer derive their copies from that plist rather than keeping a
/// second literal, so a rename only has to be made here and there.
public enum BCLIdentity {
    public static let appBundleID = "com.abneo.batterycharge.limit"
    public static let helperMachService = "\(appBundleID).helper"
    public static let helperToolPath = "/Library/PrivilegedHelperTools/\(helperMachService)"
    public static let installedAppPath = "/Applications/Battery Charge Limit.app"
    public static let helperVersion = "1"
    public static let protocolVersion = 1
}
