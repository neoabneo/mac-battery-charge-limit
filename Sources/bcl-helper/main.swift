import Foundation
import BCLShared
import BCLSMC

enum HelperMode {
    case daemon(clientRequirement: String?)
    case probe
    case keys([String])
}

func parseArguments(_ arguments: [String]) -> HelperMode {
    guard let command = arguments.first else { return .daemon(clientRequirement: nil) }

    switch command {
    case "--allow-requirement":
        return .daemon(clientRequirement: arguments.count > 1 ? arguments[1] : nil)
    case "--probe":
        return .probe
    case "--keys":
        return .keys(Array(arguments.dropFirst(1)))
    default:
        return .daemon(clientRequirement: nil)
    }
}

func describe(_ snapshot: (capabilities: BCLCapabilities, telemetry: BCLTelemetry)) -> String {
    let capabilities = snapshot.capabilities
    let telemetry = snapshot.telemetry
    var lines: [String] = []
    lines.append("helper \(capabilities.helperVersion) root=\(capabilities.runningAsRoot) charge-keys=\(capabilities.chargeControlKeyGroup ?? "none") writable=\(capabilities.chargeControlWritable)")
    lines.append("soc=\(telemetry.socPercent.map { "\($0)%" } ?? "n/a") ac=\(telemetry.acAttached.map { String($0) } ?? "n/a")")
    lines.append("charge-request=\(telemetry.chargeRequest ?? "n/a") key-bytes=\(telemetry.chargeKeyActualRaw ?? "n/a") enforcing=\(telemetry.enforcementActive.map { String($0) } ?? "n/a") limit=\(telemetry.appliedLimitPercent.map { "\($0)%" } ?? "n/a")")
    if let error = telemetry.lastSMCError { lines.append("smc-error: \(error)") }
    capabilities.notes.forEach { lines.append("note: \($0)") }
    return lines.joined(separator: "\n")
}

func runKeys(_ keys: [String]) {
    let smc = SMCConnection()
    do { try smc.open() } catch { FileHandle.standardError.write(Data("SMC: \(error)\n".utf8)); exit(1) }
    for key in keys {
        guard let info = try? smc.keyInfo(key) else { print("\(key) -> absent"); continue }
        let raw = (try? smc.read(key)) ?? []
        let hex = raw.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("\(key) -> type=\(info.type) size=\(info.size) attrs=0x\(String(info.attributes, radix: 16)) raw=\(hex)")
    }
    smc.close()
}

switch parseArguments(Array(CommandLine.arguments.dropFirst())) {
case .daemon(let clientRequirement):
    let server = HelperServer(clientRequirement: clientRequirement)
    server.run()
case .probe:
    let result = ChargeDaemon().probe()
    print(describe(result))
    print("---")
    print(result.capabilities.encodedJSON())
    print(result.telemetry.encodedJSON())
case .keys(let keys):
    runKeys(keys)
}
