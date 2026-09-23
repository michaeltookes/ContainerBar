import Testing
@testable import ContainerBarCore

@Suite("SSH Tunnel Connection Tests")
struct SSHTunnelConnectionTests {

    @Test("adoption miss remains retryable when superseded")
    func adoptionMissRemainsRetryableWhenSuperseded() throws {
        let connection = SSHTunnelConnection(host: "example.com", user: "root")
        let error = try connection.supersededConnectionError()

        guard case .sshConnectionFailed(let message) = error else {
            Issue.record("Expected .sshConnectionFailed, got \(error)")
            return
        }
        #expect(message.contains("superseded"))
    }

    @Test("adoption miss preserves deliberate disconnect cancellation")
    func adoptionMissPreservesDeliberateDisconnectCancellation() async {
        let connection = SSHTunnelConnection(host: "example.com", user: "root")
        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return try connection.supersededConnectionError()
        }

        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }
}
