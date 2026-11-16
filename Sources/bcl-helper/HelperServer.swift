import Foundation
import IOKit
import Security
import BCLShared
import BCLCore
import BCLSMC

final class HelperExportedObject: NSObject, BCLHelperProtocol {
    private let daemon: ChargeDaemon

    init(daemon: ChargeDaemon) {
        self.daemon = daemon
    }

    func applySettings(_ settingsJSON: String, withReply reply: @escaping (String) -> Void) {
        guard let settings = BCLSettings.decode(fromJSON: settingsJSON) else {
            reply(BCLCallResult(ok: false, message: "settings payload could not be decoded").encodedJSON())
            return
        }
        let result = daemon.applySettings(settings)
        reply(BCLCallResult(ok: result.0, message: result.1).encodedJSON())
    }

    func telemetryJSON(withReply reply: @escaping (String) -> Void) {
        reply(daemon.telemetrySnapshot().encodedJSON())
    }
}

final class HelperServer: NSObject, NSXPCListenerDelegate {
    private let listener: NSXPCListener
    private let daemon = ChargeDaemon()

    /// Absent means the helper accepts no client at all, so a helper installed without a recorded
    /// requirement can never be driven by an unnamed process.
    private let clientValidator: ClientValidator?

    init(clientRequirement: String?) {
        listener = NSXPCListener(machServiceName: BCLIdentity.helperMachService)
        clientValidator = clientRequirement.map { ClientValidator(requirementText: $0) }
        super.init()
    }

    func run() {
        listener.delegate = self
        daemon.start()
        installSignalHandlers()
        listener.resume()
        RunLoop.main.run()
    }

    private func installSignalHandlers() {
        let daemon = self.daemon
        for sig in [SIGTERM, SIGINT] {
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                daemon.stop()
                exit(0)
            }
            source.resume()
            Darwin.signal(sig, SIG_IGN)
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard let clientValidator else {
            NSLog("Battery Charge Limit helper accepts no clients: started without --allow-requirement")
            return false
        }
        let check = clientValidator.validate(clientPID: newConnection.processIdentifier)
        guard check.accepted else {
            NSLog("Battery Charge Limit helper rejected a connection: %@", check.detail)
            return false
        }
        let daemon = self.daemon
        newConnection.exportedInterface = NSXPCInterface(with: BCLHelperProtocol.self)
        newConnection.exportedObject = HelperExportedObject(daemon: daemon)
        newConnection.invalidationHandler = { daemon.releaseEnforcement() }
        newConnection.resume()
        return true
    }
}
