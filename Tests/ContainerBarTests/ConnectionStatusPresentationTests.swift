import Foundation
import SwiftUI
import Testing
@testable import ContainerBar

/// Covers the full decision table of `ConnectionStatusPresentation.make` and
/// the pure `state -> color` mappings. The type is `@MainActor`, so the suite
/// is annotated accordingly.
@Suite("ConnectionStatusPresentation")
@MainActor
struct ConnectionStatusPresentationTests {

    // MARK: - make() decision table

    @Test("Connected wins over refreshing and an error")
    func connectedTakesPrecedence() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "beelink",
            isConnected: true,
            isRefreshing: true,
            connectionError: "boom"
        )

        #expect(presentation.state == .connected)
        #expect(presentation.title == "Connected to beelink")
        #expect(presentation.detail == nil)
    }

    @Test("Refreshing while not connected reports connecting")
    func refreshingWhenNotConnected() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "beelink",
            isConnected: false,
            isRefreshing: true,
            connectionError: "ignored while refreshing"
        )

        #expect(presentation.state == .connecting)
        #expect(presentation.title == "Connecting to beelink")
        #expect(presentation.detail == nil)
    }

    @Test("A non-empty error is trimmed and surfaced as the failure detail")
    func nonEmptyErrorBecomesFailedWithDetail() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "beelink",
            isConnected: false,
            isRefreshing: false,
            connectionError: "  connection refused  "
        )

        #expect(presentation.state == .failed)
        #expect(presentation.title == "Connection failed for beelink")
        #expect(presentation.detail == "connection refused")
    }

    @Test("A whitespace-only error falls back to a detail-less Disconnected state")
    func whitespaceOnlyErrorBecomesDisconnected() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "beelink",
            isConnected: false,
            isRefreshing: false,
            connectionError: "   \n\t "
        )

        #expect(presentation.state == .failed)
        #expect(presentation.title == "Disconnected from beelink")
        #expect(presentation.detail == nil)
    }

    @Test("A nil error falls back to a detail-less Disconnected state")
    func nilErrorBecomesDisconnected() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "beelink",
            isConnected: false,
            isRefreshing: false,
            connectionError: nil
        )

        #expect(presentation.state == .failed)
        #expect(presentation.title == "Disconnected from beelink")
        #expect(presentation.detail == nil)
    }

    @Test("Titles embed the host name in every state")
    func titlesEmbedHostName() {
        let host = "docker-host-42"

        #expect(
            ConnectionStatusPresentation.make(
                hostName: host, isConnected: true, isRefreshing: false, connectionError: nil
            ).title.contains(host)
        )
        #expect(
            ConnectionStatusPresentation.make(
                hostName: host, isConnected: false, isRefreshing: true, connectionError: nil
            ).title.contains(host)
        )
        #expect(
            ConnectionStatusPresentation.make(
                hostName: host, isConnected: false, isRefreshing: false, connectionError: "bad"
            ).title.contains(host)
        )
        #expect(
            ConnectionStatusPresentation.make(
                hostName: host, isConnected: false, isRefreshing: false, connectionError: nil
            ).title.contains(host)
        )
    }

    // MARK: - Indicator colors

    @Test("Connecting state is orange")
    func connectingColorIsOrange() {
        let presentation = ConnectionStatusPresentation(state: .connecting, title: "", detail: nil)
        #expect(presentation.indicatorColor == .orange)
    }

    @Test("Connected state is green")
    func connectedColorIsGreen() {
        let presentation = ConnectionStatusPresentation(state: .connected, title: "", detail: nil)
        #expect(presentation.indicatorColor == .green)
    }

    @Test("Failed state is red")
    func failedColorIsRed() {
        let presentation = ConnectionStatusPresentation(state: .failed, title: "", detail: nil)
        #expect(presentation.indicatorColor == .red)
    }

    @Test("Shadow color is the indicator color at half opacity")
    func shadowColorIsIndicatorAtHalfOpacity() {
        for state in [ConnectionStatusPresentation.State.connecting, .connected, .failed] {
            let presentation = ConnectionStatusPresentation(state: state, title: "", detail: nil)
            #expect(presentation.indicatorShadowColor == presentation.indicatorColor.opacity(0.5))
        }
    }
}
