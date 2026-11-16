import Foundation

/// Runs one script bundled at Contents/Resources through the standard administrator-password dialog.
/// Both bundles reach /Library this way and this way only, so the password prompt looks identical
/// whichever one the user clicked.
public enum PrivilegedScript {
    public static func run(bundle: URL, script: String, arguments: [String], prompt: String) -> BCLCallResult {
        let scriptPath = bundle.appendingPathComponent("Contents/Resources/\(script)").path
        guard FileManager.default.isExecutableFile(atPath: scriptPath) else {
            return BCLCallResult(ok: false, message: "\(script) is missing from this bundle")
        }
        // The paths land inside a quoted shell command embedded in an AppleScript string, so a single
        // quote would end an argument early. Refuse rather than try to escape it.
        let paths = [scriptPath] + arguments
        guard !paths.contains(where: { $0.contains("'") || $0.contains("\"") }) else {
            return BCLCallResult(ok: false, message: "a path contains a quote the script will not interpolate")
        }
        let command = paths.map { "'\($0)'" }.joined(separator: " ")

        let source = "do shell script \"/bin/bash \(command)\" "
            + "with administrator privileges with prompt \"\(prompt)\""
        var failure: NSDictionary?
        guard let output = NSAppleScript(source: source)?.executeAndReturnError(&failure) else {
            return BCLCallResult(ok: false, message: "the script could not start")
        }
        if let failure {
            let text = (failure[NSAppleScript.errorMessage] as? String) ?? "the request was refused"
            return BCLCallResult(ok: false, message: text)
        }
        let reported = (output.stringValue ?? "").split(separator: "\n").last.map(String.init) ?? "\(script) finished"
        return BCLCallResult(ok: true, message: reported)
    }
}
