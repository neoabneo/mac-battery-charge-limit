import AppKit
import BCLShared

/// The GUI entry for Scripts/uninstall.sh, shipped next to the app inside the DMG. Removing the helper
/// and the app is not something the app itself offers: this bundle carries the script, asks once for
/// root, and has no other job.
@MainActor
final class Uninstaller: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Uninstalling reaches /Library and nothing here can put it back, so it is confirmed before the
        // password prompt, and Return is kept away from the destructive button.
        let confirmation = NSAlert()
        confirmation.messageText = "Uninstall Battery Charge Limit?"
        confirmation.informativeText = "This removes the privileged helper, its launchd job, the app in "
            + "/Applications and the saved limit. Charging goes back to what macOS does by default."
        confirmation.alertStyle = .warning
        confirmation.addButton(withTitle: "Uninstall")
        confirmation.addButton(withTitle: "Cancel")
        confirmation.buttons.first?.keyEquivalent = ""
        NSApp.activate(ignoringOtherApps: true)
        guard confirmation.runModal() == .alertFirstButtonReturn else {
            NSApp.terminate(nil)
            return
        }

        let result = PrivilegedScript.run(
            bundle: Bundle.main.bundleURL,
            script: "uninstall.sh",
            arguments: [BCLIdentity.appBundleID],
            prompt: "Battery Charge Limit needs root once, to remove its helper, its launchd job and the app."
        )
        if !result.ok {
            let failure = NSAlert()
            failure.messageText = "Uninstall did not finish"
            failure.informativeText = result.message
            failure.alertStyle = .warning
            failure.runModal()
        }
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
let uninstaller = MainActor.assumeIsolated { Uninstaller() }
application.delegate = uninstaller
application.setActivationPolicy(.accessory)
application.run()
