import Foundation

public enum ChargeControlMode: String {
    case chargeStatePair = "CH0B+CH0C"
    case chargeStateWord = "CHTE"
    case unsupported = "none"
}

/// The charge gate as the SMC reports it. `firmwareDefault` covers values that are neither
/// the enable nor the inhibit byte — CH0B sits at 0x01 until something deliberately writes
/// 0x00 or 0x02, and the inhibit byte written (0x02) reads back as 0x03.
public enum ChargeGate: Equatable {
    case allowed
    case inhibited
    case firmwareDefault(raw: UInt8)
}

public struct ChargeControlKeys {
    public static let stateOfChargeKey = "BUIC"

    public static let pairAllowValue: UInt8 = 0
    public static let pairInhibitValue: UInt8 = 2
    public static let wordAllowByte: UInt8 = 0
    public static let wordInhibitByte: UInt8 = 1

    /// On the machines that have CHTE the flag sits in the first byte, not the big-endian
    /// position the `ui32` type implies.
    public static let chargeStateWordInhibitBytes: [UInt8] = [1, 0, 0, 0]
    public static let chargeStateWordAllowBytes: [UInt8] = [0, 0, 0, 0]

    public static func detect(_ smc: SMCConnection) -> ChargeControlMode {
        if smc.exists("CH0B") && smc.exists("CH0C") { return .chargeStatePair }
        if smc.exists("CHTE") { return .chargeStateWord }
        return .unsupported
    }

    public static func readGate(_ smc: SMCConnection, mode: ChargeControlMode) -> ChargeGate? {
        switch mode {
        case .chargeStatePair:
            guard let first = (try? smc.read("CH0B"))?.first else { return nil }
            switch first {
            case pairAllowValue: return .allowed
            case pairInhibitValue: return .inhibited
            default: return .firmwareDefault(raw: first)
            }
        case .chargeStateWord:
            guard let first = (try? smc.read("CHTE"))?.first else { return nil }
            switch first {
            case wordAllowByte: return .allowed
            case wordInhibitByte: return .inhibited
            default: return .firmwareDefault(raw: first)
            }
        case .unsupported:
            return nil
        }
    }

    /// Writes the same bytes the key already holds, which reveals whether the kernel
    /// grants this process privileged SMC writes without changing the charge state.
    public static func probeWritable(_ smc: SMCConnection, mode: ChargeControlMode) -> (writable: Bool, error: String?) {
        switch mode {
        case .chargeStatePair:
            guard let raw = try? smc.read("CH0B") else { return (false, "could not read CH0B") }
            do { try smc.write("CH0B", rawBytes: raw); return (true, nil) }
            catch let error as SMCError { return (false, error.description) }
            catch { return (false, String(describing: error)) }
        case .chargeStateWord:
            guard let raw = try? smc.read("CHTE") else { return (false, "could not read CHTE") }
            do { try smc.write("CHTE", rawBytes: raw); return (true, nil) }
            catch let error as SMCError { return (false, error.description) }
            catch { return (false, String(describing: error)) }
        case .unsupported:
            return (false, "no charge-control keys on this machine")
        }
    }

    /// Returns nil when the write succeeded, otherwise the failure message.
    public static func setCharging(_ smc: SMCConnection, mode: ChargeControlMode, enabled: Bool) -> String? {
        switch mode {
        case .chargeStatePair:
            let value = enabled ? pairAllowValue : pairInhibitValue
            do {
                try smc.writeByte("CH0B", value)
                try smc.writeByte("CH0C", value)
                return nil
            } catch let error as SMCError {
                return error.description
            } catch {
                return String(describing: error)
            }
        case .chargeStateWord:
            do {
                try smc.write("CHTE", rawBytes: enabled ? chargeStateWordAllowBytes : chargeStateWordInhibitBytes)
                return nil
            } catch let error as SMCError {
                return error.description
            } catch {
                return String(describing: error)
            }
        case .unsupported:
            return "no charge-control keys on this machine"
        }
    }
}
