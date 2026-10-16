import AppKit
import SwiftUI

/// Opens System Settings on the Local Network list, or on Privacy & Security
/// when the deep link does not open (CB-115).
struct OpenLocalNetworkSettingsButton: View {
    var body: some View {
        Button(LocalNetworkGuidance.buttonTitle) {
            Self.openSettings()
        }
        .controlSize(.small)
        .accessibilityIdentifier(QAAccessibilityID.openLocalNetworkSettings)
    }

    @MainActor
    static func openSettings() {
        if let url = LocalNetworkGuidance.settingsURL, NSWorkspace.shared.open(url) {
            return
        }
        if let url = LocalNetworkGuidance.fallbackURL {
            NSWorkspace.shared.open(url)
        }
    }
}
