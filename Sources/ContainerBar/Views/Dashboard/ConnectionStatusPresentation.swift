import Foundation
import SwiftUI

@MainActor
struct ConnectionStatusPresentation: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case connecting
        case connected
        case failed
    }

    let state: State
    let title: String
    let detail: String?

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

        if isRefreshing {
            return ConnectionStatusPresentation(
                state: .connecting,
                title: "Connecting to \(hostName)",
                detail: nil
            )
        }

        return ConnectionStatusPresentation(
            state: .failed,
            title: "Disconnected from \(hostName)",
            detail: nil
        )
    }
}
