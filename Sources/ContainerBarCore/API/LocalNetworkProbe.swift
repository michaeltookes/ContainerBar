import Foundation
import Network

/// What a Local Network probe learned about one endpoint (CB-115).
public enum LocalNetworkProbeResult: Equatable, Sendable {
    /// macOS reports the path as unsatisfied because Local Network access is
    /// denied for this app, or not yet granted while the prompt is pending.
    case denied
    /// The connection reached the endpoint, so access is not the problem.
    case reachable
    /// Anything else: a real routing failure, a refusal, or a timeout.
    case inconclusive
}

/// Probes whether macOS Local Network privacy blocks this app from an endpoint.
public protocol LocalNetworkProbing: Sendable {
    func probe(_ endpoint: NetworkEndpoint) async -> LocalNetworkProbeResult
}

/// A short TCP `NWConnection` from the app process to the endpoint. macOS offers
/// no query API for the Local Network grant; the connection's path reports
/// `unsatisfiedReason == .localNetworkDenied` when the grant is missing, which
/// separates a denial from a real routing failure.
public struct NWLocalNetworkProbe: LocalNetworkProbing {
    let timeout: Duration

    /// Builds the probe connection; tests inject one to observe it.
    let makeConnection: @Sendable (NWEndpoint.Host, NWEndpoint.Port) -> NWConnection

    public init(timeout: Duration = .seconds(3)) {
        self.init(timeout: timeout) { host, port in
            NWConnection(host: host, port: port, using: .tcp)
        }
    }

    init(timeout: Duration, makeConnection: @escaping @Sendable (NWEndpoint.Host, NWEndpoint.Port) -> NWConnection) {
        self.timeout = timeout
        self.makeConnection = makeConnection
    }

    /// Maps a path's unsatisfied reason to a probe result. Pure, for tests.
    static func result(forUnsatisfiedReason reason: NWPath.UnsatisfiedReason?) -> LocalNetworkProbeResult {
        reason == .localNetworkDenied ? .denied : .inconclusive
    }

    /// Probes `endpoint`. The connection is cancelled when the probe finishes,
    /// times out, or the calling task is cancelled (a host switch cancels the
    /// refresh), so a stale probe never keeps contacting the previous host.
    public func probe(_ endpoint: NetworkEndpoint) async -> LocalNetworkProbeResult {
        guard (1...65535).contains(endpoint.port),
              let port = NWEndpoint.Port(rawValue: UInt16(endpoint.port)) else {
            return .inconclusive
        }
        let connection = makeConnection(NWEndpoint.Host(endpoint.host), port)
        let once = ProbeCompletion(connection: connection)
        let timeout = self.timeout

        return await withTaskCancellationHandler {
            await withTaskGroup(of: LocalNetworkProbeResult?.self) { group in
                group.addTask {
                    await Self.run(connection, once: once)
                }
                group.addTask {
                    // A child of the probe: cancelled with it, or once the
                    // connection settles first.
                    try? await Task.sleep(for: timeout)
                    if !Task.isCancelled {
                        once.finish(.inconclusive)
                    }
                    return nil
                }
                var outcome: LocalNetworkProbeResult = .inconclusive
                while let next = await group.next() {
                    if let result = next {
                        outcome = result
                        break
                    }
                }
                group.cancelAll()
                return outcome
            }
        } onCancel: {
            once.finish(.inconclusive)
        }
    }

    private static func run(_ connection: NWConnection, once: ProbeCompletion) async -> LocalNetworkProbeResult {
        await withCheckedContinuation { continuation in
            guard once.install(continuation) else { return }

            connection.pathUpdateHandler = { path in
                if path.status == .unsatisfied, path.unsatisfiedReason == .localNetworkDenied {
                    once.finish(.denied)
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.finish(.reachable)
                case .waiting, .failed:
                    once.finish(Self.result(forUnsatisfiedReason: connection.currentPath?.unsatisfiedReason))
                case .cancelled:
                    once.finish(.inconclusive)
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        }
    }
}

/// Resumes the probe's continuation exactly once and cancels the connection.
/// A finish that arrives before the continuation is installed (the task was
/// already cancelled) is remembered and resumes it at install.
private final class ProbeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NWConnection
    private var continuation: CheckedContinuation<LocalNetworkProbeResult, Never>?
    private var finished: LocalNetworkProbeResult?

    init(connection: NWConnection) {
        self.connection = connection
    }

    /// Installs the continuation; returns `false` (after resuming it) when the
    /// probe already finished, so the caller must not start the connection.
    func install(_ continuation: CheckedContinuation<LocalNetworkProbeResult, Never>) -> Bool {
        let early: LocalNetworkProbeResult? = lock.withLock {
            if let finished { return finished }
            self.continuation = continuation
            return nil
        }
        if let early {
            continuation.resume(returning: early)
            return false
        }
        return true
    }

    func finish(_ result: LocalNetworkProbeResult) {
        let pending: CheckedContinuation<LocalNetworkProbeResult, Never>?? = lock.withLock {
            guard finished == nil else { return .none }
            finished = result
            defer { continuation = nil }
            return .some(continuation)
        }
        guard case .some(let waiting) = pending else { return }
        connection.stateUpdateHandler = nil
        connection.pathUpdateHandler = nil
        connection.cancel()
        waiting?.resume(returning: result)
    }
}
