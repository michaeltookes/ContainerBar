import SwiftUI
import AppKit
import DockerBarCore
import Logging

/// Main entry point for the DockerBar application
@main
struct DockerBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window accessed via menu bar
        Settings {
            SettingsView()
                .environment(appDelegate.settingsStore)
                .environment(appDelegate.containerStore)
        }
    }
}

/// Placeholder settings view - will be implemented in Day 10
struct SettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("DockerBar Settings")
                .font(.headline)

            Text("Settings will be available in a future update.")
                .foregroundStyle(.secondary)
        }
        .frame(width: 400, height: 300)
        .padding()
    }
}
