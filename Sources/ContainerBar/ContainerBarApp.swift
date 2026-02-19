import SwiftUI
import AppKit
import ContainerBarCore
import Logging

/// Main entry point for the ContainerBar application
///
/// UI lives entirely in AppDelegate/StatusItemController.
/// Settings are managed by SettingsWindowController (AppKit).
@main
struct ContainerBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
