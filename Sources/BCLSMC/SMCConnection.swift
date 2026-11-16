import Foundation
import IOKit

/// Fixed-layout payload understood by the AppleSMC user client.
public typealias SMCByteTuple = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

private struct SMCVersion { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
private struct SMCPLimitData { var version: UInt16 = 0; var length: UInt16 = 0; var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
private struct SMCKeyInfoData { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes = SMCByteTuple(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private enum SMCCommand: UInt8 {
    case handleYPCEvent = 2
    case readKey = 5
    case writeKey = 6
    case getKeyFromIndex = 8
    case getKeyInfo = 9
}

private enum SMCResultCode: UInt8 {
    case success = 0
    case error = 1
    case keyNotFound = 132
}

public struct SMCKeyInfo {
    public var type: String
    public var size: Int
    public var attributes: UInt8

    public init(type: String, size: Int, attributes: UInt8) {
        self.type = type
        self.size = size
        self.attributes = attributes
    }
}

public enum SMCError: Error, CustomStringConvertible {
    case serviceNotFound
    case openFailed(kern_return_t)
    case invalidKey(String)
    case keyNotFound(String)
    case notPrivileged(String)
    case failed(key: String, kern: kern_return_t, smc: UInt8)

    public var description: String {
        switch self {
        case .serviceNotFound: return "AppleSMC service not found"
        case .openFailed(let code): return "could not open AppleSMC (IOReturn 0x\(String(code, radix: 16)))"
        case .invalidKey(let key): return "invalid SMC key name: \(key)"
        case .keyNotFound(let key): return "SMC key \(key) does not exist on this machine"
        case .notPrivileged(let key): return "SMC key \(key) refused the write: kIOReturnNotPrivileged"
        case .failed(let key, let kern, let smc): return "SMC operation on \(key) failed (IOReturn 0x\(String(kern, radix: 16)), SMC result \(smc))"
        }
    }
}

public final class SMCConnection {
    private var connection: io_connect_t = 0
    private let structSize = MemoryLayout<SMCParamStruct>.stride

    public init() {}

    deinit { close() }

    public func open() throws {
        guard structSize == 80 else { throw SMCError.failed(key: "#layout", kern: kIOReturnBadArgument, smc: 255) }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw SMCError.openFailed(result) }
    }

    public func close() {
        guard connection != 0 else { return }
        IOServiceClose(connection)
        connection = 0
    }

    private func call(_ build: (inout SMCParamStruct) -> Void, keyName: String) throws -> SMCParamStruct {
        guard connection != 0 else { throw SMCError.serviceNotFound }
        var input = SMCParamStruct()
        build(&input)
        var output = SMCParamStruct()
        var outputSize = structSize
        let result = IOConnectCallStructMethod(connection, UInt32(SMCCommand.handleYPCEvent.rawValue), &input, structSize, &output, &outputSize)

        if result == kIOReturnNotPrivileged { throw SMCError.notPrivileged(keyName) }
        if result == kIOReturnBadArgument { throw SMCError.invalidKey(keyName) }
        if result != kIOReturnSuccess { throw SMCError.failed(key: keyName, kern: result, smc: output.result) }
        if output.result == SMCResultCode.keyNotFound.rawValue { throw SMCError.keyNotFound(keyName) }
        if output.result != SMCResultCode.success.rawValue { throw SMCError.failed(key: keyName, kern: result, smc: output.result) }
        return output
    }

    public func keyInfo(_ key: String) throws -> SMCKeyInfo {
        guard let code = Self.fourCC(key) else { throw SMCError.invalidKey(key) }
        let output = try call({ input in
            input.key = code
            input.data8 = SMCCommand.getKeyInfo.rawValue
        }, keyName: key)
        return SMCKeyInfo(type: Self.unCC(output.keyInfo.dataType), size: Int(output.keyInfo.dataSize), attributes: output.keyInfo.dataAttributes)
    }

    public func exists(_ key: String) -> Bool {
        (try? keyInfo(key)) != nil
    }

    public func read(_ key: String) throws -> [UInt8] {
        guard let code = Self.fourCC(key) else { throw SMCError.invalidKey(key) }
        let size = try keyInfo(key).size
        let output = try call({ input in
            input.key = code
            input.keyInfo.dataSize = UInt32(size)
            input.data8 = SMCCommand.readKey.rawValue
        }, keyName: key)
        return Array(Self.bytes(of: output.bytes).prefix(size))
    }

    public func write(_ key: String, rawBytes: [UInt8]) throws {
        guard let code = Self.fourCC(key) else { throw SMCError.invalidKey(key) }
        let info = try keyInfo(key)
        guard rawBytes.count == info.size else { throw SMCError.invalidKey("\(key) (want \(info.size) bytes, got \(rawBytes.count))") }
        let payload = Self.paddedTuple(rawBytes)
        _ = try call({ input in
            input.key = code
            input.bytes = payload
            input.keyInfo.dataSize = UInt32(info.size)
            input.data8 = SMCCommand.writeKey.rawValue
        }, keyName: key)
    }

    public func writeByte(_ key: String, _ value: UInt8) throws {
        try write(key, rawBytes: [value])
    }

    public static func fourCC(_ key: String) -> UInt32? {
        let bytes = Array(key.utf8)
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    public static func unCC(_ value: UInt32) -> String {
        let bytes: [UInt8] = [UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    private static func bytes(of tuple: SMCByteTuple) -> [UInt8] {
        withUnsafeBytes(of: tuple) { Array($0) }
    }

    private static func paddedTuple(_ raw: [UInt8]) -> SMCByteTuple {
        var filled = Array(raw.prefix(32))
        while filled.count < 32 { filled.append(0) }
        // Array.withUnsafeBytes exposes the element buffer; withUnsafeBytes(of:) would expose
        // the array's 24-byte header instead.
        return filled.withUnsafeBytes { buffer in
            (buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
             buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
             buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
             buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31])
        }
    }
}
