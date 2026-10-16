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

    public init(timeout: Duration = .seconds(3)) {
        self.timeout = timeout
    }

    /// Maps a path's unsatisfied reason to a probe result. Pure, for tests.
    static func result(forUnsatisfiedReason reason: NWPath.UnsatisfiedReason?) -> LocalNetworkProbeResult {
        reason == .localNetworkDenied ? .denied : .inconclusive
    }

    public func probe(_ endpoint: NetworkEndpoint) async -> LocalNetworkProbeResult {
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: endpoint.port)), endpoint.port > 0 else {
            return .inconclusive
        }
        let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: .tcp)
        let once = ProbeCompletion(connection: connection)
        let timeout = self.timeout

        return await withCheckedContinuation { continuation in
            once.install(continuation)

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

            Task.detached {
                try? await Task.sleep(for: timeout)
                once.finish(.inconclusive)
            }
        }
    }
}

/// Resumes the probe's continuation exactly once and cancels the connection.
private final class ProbeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NWConnection
    private var continuation: CheckedContinuation<LocalNetworkProbeResult, Never>?

    init(connection: NWConnection) {
        self.connection = connection
    }

    func install(_ continuation: CheckedContinuation<LocalNetworkProbeResult, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    func finish(_ result: LocalNetworkProbeResult) {
        let pending: CheckedContinuation<LocalNetworkProbeResult, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        guard let pending else { return }
        connection.stateUpdateHandler = nil
        connection.pathUpdateHandler = nil
        connection.cancel()
        pending.resume(returning: result)
    }
}
