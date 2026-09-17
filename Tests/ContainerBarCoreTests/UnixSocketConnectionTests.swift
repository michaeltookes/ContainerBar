import Foundation
import Network
import Testing
@testable import ContainerBarCore

@Suite("Unix Socket Connection Tests")
struct UnixSocketConnectionTests {

    @Test("Connect failure cleanup is limited to the failed NWConnection")
    func connectFailureCleanupRequiresSameConnectionInstance() {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let failedPath = temporaryDirectory.appendingPathComponent("containerbar-failed.sock").path
        let replacementPath = temporaryDirectory.appendingPathComponent("containerbar-replacement.sock").path
        let failedConnection = NWConnection(to: .unix(path: failedPath), using: .tcp)
        let replacementConnection = NWConnection(to: .unix(path: replacementPath), using: .tcp)

        #expect(UnixSocketConnection.shouldCleanupFailedConnection(
            current: failedConnection,
            failed: failedConnection
        ))
        #expect(!UnixSocketConnection.shouldCleanupFailedConnection(
            current: replacementConnection,
            failed: failedConnection
        ))
        #expect(!UnixSocketConnection.shouldCleanupFailedConnection(
            current: nil,
            failed: failedConnection
        ))
    }

    @Test("Start-error mapping surfaces socketNotFound only for ENOENT")
    func mapStartErrorSurfacesSocketNotFoundForENOENT() {
        let path = "/var/run/docker.sock"

        let missing = UnixSocketConnection.mapStartError(.posix(.ENOENT), socketPath: path)
        guard case .socketNotFound(let mappedPath) = missing else {
            Issue.record("Expected .socketNotFound, got \(missing)")
            return
        }
        #expect(mappedPath == path)

        let refused = UnixSocketConnection.mapStartError(.posix(.ECONNREFUSED), socketPath: path)
        guard case .connectionFailed = refused else {
            Issue.record("Expected .connectionFailed for a non-ENOENT POSIX error, got \(refused)")
            return
        }
    }
}
