import Foundation
import IOKit
import BCLShared
import BCLCore
import BCLSMC

final class ChargeDaemon {
    private let queue = DispatchQueue(label: "com.abneo.batterycharge.limit.daemon")
    private let smc = SMCConnection()
    private let powerSource = PowerSourceReader()
    private var engine = ChargePolicyEngine()
    private var settings = BCLSettings()
    private var mode: ChargeControlMode = .unsupported
    private var writable = false
    private var enforcementActive = false
    private var appliedLimitPercent: Int?
    private var lastError: String?
    private var capabilities = BCLCapabilities(
        helperVersion: BCLIdentity.helperVersion,
        protocolVersion: BCLIdentity.protocolVersion,
        runningAsRoot: false,
        chargeControlKeyGroup: nil,
        chargeControlWritable: false,
        notes: []
    )
    private var timer: DispatchSourceTimer?

    func start() {
        queue.sync { bootstrap() }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 1, repeating: .seconds(3), leeway: .milliseconds(500))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        queue.sync {
            releaseLocked()
            smc.close()
        }
    }

    func applySettings(_ candidate: BCLSettings) -> (Bool, String) {
        var result: (Bool, String) = (false, "enforcement not applied")
        queue.sync {
            var normalized = candidate
            normalized.normalize()
            settings = normalized
            appliedLimitPercent = normalized.limitPercent
            engine = ChargePolicyEngine()
            if !writable {
                enforcementActive = false
                result.0 = false
                result.1 = lastError ?? "SMC charge-control writes are not permitted for this process"
                return
            }
            if mode == .unsupported {
                enforcementActive = false
                result.0 = false
                result.1 = "no charge-control keys found on this machine"
                return
            }
            enforcementActive = true
            result.0 = true
            result.1 = "limit \(normalized.limitPercent)%, charging resumes below \(normalized.rearmPercent)%"
            tick()
        }
        return (result.0, result.1)
    }

    /// Automatic release: helper shutting down or the UI client disconnecting.
    func releaseEnforcement() { queue.sync { releaseLocked() } }

    private func releaseLocked() {
        guard enforcementActive else { return }
        enforcementActive = false
        appliedLimitPercent = nil
        engine = ChargePolicyEngine()
        if writable, mode != .unsupported {
            lastError = ChargeControlKeys.setCharging(smc, mode: mode, enabled: true)
        }
    }

    func telemetrySnapshot() -> BCLTelemetry {
        queue.sync { assembleTelemetry() }
    }

    /// Read-only path used by the developer `--probe` mode and by status prints.
    func probe() -> (capabilities: BCLCapabilities, telemetry: BCLTelemetry) {
        queue.sync { bootstrap() }
        return probeSnapshot()
    }

    func probeSnapshot() -> (capabilities: BCLCapabilities, telemetry: BCLTelemetry) {
        queue.sync { (capabilities, assembleTelemetry()) }
    }

    private func bootstrap() {
        capabilities.runningAsRoot = (geteuid() == 0)
        do {
            try smc.open()
        } catch let error as SMCError {
            lastError = error.description
            capabilities.notes.append("SMC: \(error.description)")
            return
        } catch {
            lastError = "\(error)"
            capabilities.notes.append("SMC: \(error)")
            return
        }

        mode = ChargeControlKeys.detect(smc)
        capabilities.chargeControlKeyGroup = mode.rawValue

        let probe = ChargeControlKeys.probeWritable(smc, mode: mode)
        capabilities.chargeControlWritable = probe.writable
        writable = probe.writable
        if let error = probe.error {
            lastError = error
            capabilities.notes.append("write probe: \(error)")
        }
        if mode == .unsupported {
            capabilities.notes.append("no charge-control keys (CH0B/CH0C or CHTE) present")
        }
        if ChargeControlKeys.readGate(smc, mode: mode) == .inhibited {
            capabilities.notes.append("charge gate already inhibited before this helper wrote anything")
        }
    }

    private func tick() {
        guard mode != .unsupported, enforcementActive else { return }
        guard let soc = powerSource.read().socPercent ?? readStateOfChargeFromSMC() else { return }

        let request = engine.evaluate(settings: settings, socPercent: soc)
        let gate = ChargeControlKeys.readGate(smc, mode: mode)
        switch request {
        case .inhibit:
            if gate != .inhibited { writeCharging(enabled: false) }
        case .allow:
            // Anything that is not the explicit allow byte (including the firmware's 0x01
            // default) gets 0x00 written, which is what resumes charging.
            if gate != .allowed { writeCharging(enabled: true) }
        }
    }

    private func writeCharging(enabled: Bool) {
        if let message = ChargeControlKeys.setCharging(smc, mode: mode, enabled: enabled) {
            lastError = message
            capabilities.chargeControlWritable = false
            writable = false
        } else {
            lastError = nil
        }
    }

    private func readStateOfChargeFromSMC() -> Int? {
        guard smc.exists(ChargeControlKeys.stateOfChargeKey) else { return nil }
        return Int((try? smc.read(ChargeControlKeys.stateOfChargeKey))?.first ?? 0)
    }

    private func assembleTelemetry() -> BCLTelemetry {
        let battery = powerSource.read()
        var telemetry = BCLTelemetry()
        telemetry.socPercent = battery.socPercent ?? readStateOfChargeFromSMC()
        telemetry.acAttached = battery.acPresent
        telemetry.enforcementActive = enforcementActive
        telemetry.appliedLimitPercent = appliedLimitPercent
        telemetry.chargeControlWritable = writable
        telemetry.lastSMCError = lastError

        if let limit = appliedLimitPercent, let soc = telemetry.socPercent {
            // Reported through a copy so a UI poll cannot advance the control loop's hysteresis.
            var reporter = engine
            telemetry.chargeRequest = reporter.evaluate(settings: BCLSettings(limitPercent: limit), socPercent: soc).rawValue
        }
        if telemetry.chargeRequest == nil {
            switch ChargeControlKeys.readGate(smc, mode: mode) {
            case .allowed: telemetry.chargeRequest = ChargeRequest.allow.rawValue
            case .inhibited: telemetry.chargeRequest = ChargeRequest.inhibit.rawValue
            case .firmwareDefault, .none: break
            }
        }
        if let raw = try? smc.read(mode == .chargeStateWord ? "CHTE" : "CH0B") {
            telemetry.chargeKeyActualRaw = raw.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
        return telemetry
    }
}
