import Foundation
import Network
@testable import ContainerBarCore

/// Minimal in-process TCP server on loopback for hermetic transport tests.
final class InProcessTCPServer: @unchecked Sendable {
    enum Behavior {
        /// Accept the connection and start it, but never send a byte back.
        case blackHole
        /// Accept the connection and, on the first inbound read, send `data`.
        case respond(Data)
        /// Accept the connection and send chunks with a fixed delay between each
        /// chunk once the request bytes arrive.
        case respondChunks([Data], interval: TimeInterval)
    }

    private let listener: NWListener
    private let behavior: Behavior
    private let queue = DispatchQueue(label: "com.containerbar.test.tcpserver")
    private let lock = NSLock()
    private var connections: [NWConnection] = []

    init(behavior: Behavior) throws {
        self.behavior = behavior
        self.listener = try NWListener(using: .tcp)
    }

    /// Starts the listener and resolves with its OS-assigned port once ready.
    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    listener?.stateUpdateHandler = nil
                    if let port = listener?.port?.rawValue {
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: DockerAPIError.connectionFailed)
                    }
                case .failed(let error):
                    listener?.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        lock.withLock {
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
        listener.cancel()
    }

    /// Fully tears the listener down and waits for `.cancelled`, so a port
    /// reserved this way reliably refuses subsequent connects (no accept race).
    func closeAndWait() async {
        lock.withLock {
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
        await withCheckedContinuation { continuation in
            listener.stateUpdateHandler = { [weak listener] state in
                if case .cancelled = state {
                    listener?.stateUpdateHandler = nil
                    continuation.resume()
                }
            }
            listener.cancel()
        }
    }

    private func handle(_ connection: NWConnection) {
        lock.withLock { connections.append(connection) }
        connection.start(queue: queue)

        switch behavior {
        case .blackHole:
            // Intentionally never send; the client's receive should hit its deadline.
            break
        case .respond(let data):
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                connection.send(content: data, completion: .contentProcessed { _ in })
            }
        case .respondChunks(let chunks, let interval):
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] _, _, _, _ in
                guard let server = self else { return }
                server.send(chunks, to: connection, interval: interval, index: 0)
            }
        }
    }

    private func send(_ chunks: [Data], to connection: NWConnection, interval: TimeInterval, index: Int) {
        guard index < chunks.count else { return }

        let milliseconds = Int((interval * 1000).rounded())
        queue.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) { [weak self] in
            guard let server = self else { return }
            connection.send(content: chunks[index], completion: .contentProcessed { _ in
                server.send(chunks, to: connection, interval: interval, index: index + 1)
            })
        }
    }
}
