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
}
