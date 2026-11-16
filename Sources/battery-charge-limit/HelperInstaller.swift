import Foundation
import BCLShared

/// The app's single privileged action: one administrator-password prompt that runs the bundled
/// install.sh. Removal is a different bundle's job - see Sources/bcl-uninstaller.
enum HelperInstaller {
    static func run(sourceBundle: URL) -> BCLCallResult {
        PrivilegedScript.run(
            bundle: sourceBundle,
            script: "install.sh",
            arguments: [sourceBundle.path],
            prompt: "Battery Charge Limit needs root once, to install its charge-control helper."
        )
    }
}
