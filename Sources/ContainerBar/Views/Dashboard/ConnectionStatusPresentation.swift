import Foundation
import SwiftUI

@MainActor
struct ConnectionStatusPresentation: Equatable {
    enum State: Equatable {
        case connecting
        case connected
        case failed
    }

    let state: State
    let title: String
    let detail: String?

    /// One spoken/automation string for the status element: the title (which names
    /// the host) followed by the error detail when there is one.
    var accessibilityLabel: String {
        guard let detail, !detail.isEmpty else { return title }
        return "\(title). \(detail)"
    }

    /// Whether the detail is the Local Network guidance, so the bar offers the
    /// "Open Local Network Settings" button under it (CB-115).
    var showsLocalNetworkSettingsButton: Bool {
        state == .failed && LocalNetworkGuidance.isGuidance(detail)
    }

    var indicatorColor: Color {
        switch state {
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .failed:
            return .red
        }
    }

    var indicatorShadowColor: Color {
        indicatorColor.opacity(0.5)
    }

    static func make(
        hostName: String,
        isConnected: Bool,
        isRefreshing: Bool,
        connectionError: String?
    ) -> ConnectionStatusPresentation {
        if isConnected {
            return ConnectionStatusPresentation(
                state: .connected,
                title: "Connected to \(hostName)",
                detail: nil
            )
        }

        if isRefreshing {
            return ConnectionStatusPresentation(
                state: .connecting,
                title: "Connecting to \(hostName)",
                detail: nil
            )
        }

        if let connectionError {
            let trimmedConnectionError = connectionError.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedConnectionError.isEmpty {
                return ConnectionStatusPresentation(
                    state: .failed,
                    title: "Connection failed for \(hostName)",
                    detail: trimmedConnectionError
                )
            }
        }

        return ConnectionStatusPresentation(
            state: .failed,
            title: "Disconnected from \(hostName)",
            detail: nil
        )
    }
}
