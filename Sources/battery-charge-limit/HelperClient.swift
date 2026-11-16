import Foundation
import BCLShared

/// NSXPC client for the privileged helper. Installing the helper is not this class's job: the tool
/// and its launchd job are put in place once by `Contents/Resources/install.sh`.
final class HelperClient {
    private let connections = ConnectionBox()

    var helperToolInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: BCLIdentity.helperToolPath)
    }

    /// Counts fresh XPC connections, so a helper that came back without a limit is visible to the model.
    var connectionGeneration: Int { connections.currentGeneration }

    var lastError: String? { connections.lastErrorText }

    func telemetryJSON() async -> BCLTelemetry? {
        guard let text = await send({ helper, reply in
            helper.telemetryJSON { reply.deliver($0, .ok($0)) }
        }) else { return nil }
        return BCLTelemetry.decode(fromJSON: text)
    }

    func applySettings(_ settings: BCLSettings) async -> BCLCallResult {
        let payload = settings.encodedJSON()
        guard let text = await send({ helper, reply in
            helper.applySettings(payload) { reply.deliver($0, .ok($0)) }
        }) else {
            return BCLCallResult(ok: false, message: lastError ?? "helper not reachable")
        }
        return BCLCallResult.decode(fromJSON: text)
    }

    func closeConnection() {
        connections.invalidate()
    }

    enum Outcome { case ok(String), failure(String) }

    /// Every exit path resumes the continuation exactly once: the XPC reply block, the XPC error
    /// handler, or a connection that cannot be created at all.
    private func send(_ body: (BCLHelperProtocol, ReplyBox) -> Void) async -> String? {
        await withCheckedContinuation { continuation in
            let reply = ReplyBox(continuation: continuation, connections: connections)
            guard let helper = connections.proxy(machService: BCLIdentity.helperMachService, failure: { error in
                reply.deliver("", .failure(error.localizedDescription))
            }) else {
                reply.deliver("", .failure("helper connection could not be created"))
                return
            }
            body(helper, reply)
        }
    }
}

/// Resolves the continuation exactly once, whichever reply path reaches it first.
private final class ReplyBox {
    private let lock = NSLock()
    private var settled = false
    private let continuation: CheckedContinuation<String?, Never>
    private let connections: ConnectionBox

    init(continuation: CheckedContinuation<String?, Never>, connections: ConnectionBox) {
        self.continuation = continuation
        self.connections = connections
    }

    func deliver(_ text: String, _ outcome: HelperClient.Outcome) {
        lock.lock()
        defer { lock.unlock() }
        guard !settled else { return }
        settled = true
        switch outcome {
        case .ok(let value):
            continuation.resume(returning: value)
        case .failure(let message):
            connections.setLastError(message)
            continuation.resume(returning: nil)
        }
    }
}

/// Calls start on the main actor while XPC replies and error handlers arrive on an XPC private
/// queue, so the connection and its error text sit behind a lock. A failed connection is dropped
/// so the next call builds a fresh one after the helper gets installed.
final class ConnectionBox {
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var lastError: String?
    private var generation = 0

    /// Counts the connections this process has built, so the model can tell that the helper on the
    /// other end is not the one it last pushed settings to.
    var currentGeneration: Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    var lastErrorText: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastError
    }

    func setLastError(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        lastError = text
    }

    func invalidate() {
        lock.lock()
        let existing = connection
        connection = nil
        lock.unlock()
        existing?.invalidate()
    }

    func proxy(machService: String, failure: @escaping (Error) -> Void) -> BCLHelperProtocol? {
        lock.lock()
        if connection == nil {
            let created = NSXPCConnection(machServiceName: machService, options: [.privileged])
            created.remoteObjectInterface = NSXPCInterface(with: BCLHelperProtocol.self)
            created.resume()
            connection = created
            generation += 1
        }
        guard let target = connection else {
            lock.unlock()
            return nil
        }
        lock.unlock()

        let proxy: Any = target.remoteObjectProxyWithErrorHandler { (error: Error) in
            self.setLastError(error.localizedDescription)
            self.invalidate()
            failure(error)
        }
        return proxy as? BCLHelperProtocol
    }
}
