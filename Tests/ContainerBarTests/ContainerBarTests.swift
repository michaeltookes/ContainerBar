import Testing
@testable import ContainerBar
@testable import ContainerBarCore

@MainActor
@Suite("ContainerBar App Tests")
struct ContainerBarTests {

    @Test("App can be initialized")
    func appInitialization() {
        // Basic smoke test - more comprehensive tests will be added
        // once we have the actual Docker API client
        #expect(true, "ContainerBar app module compiles and links successfully")
    }

    @Test("Connection status shows connecting before the first refresh completes")
    func connectionStatusShowsConnectingDuringInitialLoad() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "Beelink Server",
            isConnected: false,
            isRefreshing: true,
            connectionError: nil
        )

        #expect(presentation.state == .connecting)
        #expect(presentation.title == "Connecting to Beelink Server")
        #expect(presentation.detail == nil)
    }

    @Test("ConnectionStatusPresentation.make returns connected presentation for connected hosts")
    func connectionStatusPresentationMakeReturnsConnectedState() {
        let hostName = "Beelink Server"
        let presentation = ConnectionStatusPresentation.make(
            hostName: hostName,
            isConnected: true,
            isRefreshing: false,
            connectionError: nil
        )

        #expect(presentation.state == .connected)
        #expect(presentation.title == "Connected to \(hostName)")
        #expect(presentation.detail == nil)
    }

    @Test("Connection status surfaces host-specific errors")
    func connectionStatusShowsErrorDetails() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "Beelink Server",
            isConnected: false,
            isRefreshing: false,
            connectionError: "Failed to connect to Docker daemon"
        )

        #expect(presentation.state == .failed)
        #expect(presentation.title == "Connection failed for Beelink Server")
        #expect(presentation.detail == "Failed to connect to Docker daemon")
    }

    @Test("Connection status prefers connecting state over stale errors during refresh")
    func connectionStatusPrefersRefreshingStateOverPreviousError() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "Beelink Server",
            isConnected: false,
            isRefreshing: true,
            connectionError: "Failed to connect to Docker daemon"
        )

        #expect(presentation.state == .connecting)
        #expect(presentation.title == "Connecting to Beelink Server")
        #expect(presentation.detail == nil)
    }

    @Test("Connection status ignores whitespace-only connection errors and trims displayed details")
    func connectionStatusNormalizesConnectionErrors() {
        let whitespaceOnlyPresentation = ConnectionStatusPresentation.make(
            hostName: "Beelink Server",
            isConnected: false,
            isRefreshing: false,
            connectionError: "  \n\t  "
        )

        #expect(whitespaceOnlyPresentation.state == .failed)
        #expect(whitespaceOnlyPresentation.title == "Disconnected from Beelink Server")
        #expect(whitespaceOnlyPresentation.detail == nil)

        let trimmedPresentation = ConnectionStatusPresentation.make(
            hostName: "Beelink Server",
            isConnected: false,
            isRefreshing: false,
            connectionError: "  Failed to connect to Docker daemon \n"
        )

        #expect(trimmedPresentation.state == .failed)
        #expect(trimmedPresentation.title == "Connection failed for Beelink Server")
        #expect(trimmedPresentation.detail == "Failed to connect to Docker daemon")
    }

    @Test("Connection status stays disconnected when idle in manual mode")
    func connectionStatusDoesNotShowConnectingWithoutRefresh() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "Beelink Server",
            isConnected: false,
            isRefreshing: false,
            connectionError: nil
        )

        #expect(presentation.state == .failed)
        #expect(presentation.title == "Disconnected from Beelink Server")
        #expect(presentation.detail == nil)
    }
}

