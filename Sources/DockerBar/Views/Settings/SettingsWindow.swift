import SwiftUI
import DockerBarCore

/// Settings tab enumeration
enum SettingsTab: String, CaseIterable {
    case general = "General"
    case connections = "Connections"
    case about = "About"

    var icon: String {
        switch self {
        case .general: return "gear"
        case .connections: return "network"
        case .about: return "info.circle"
        }
    }
}

/// Main settings window with tabbed interface
struct SettingsWindow: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ContainerStore.self) private var containerStore

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar at top
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    TabButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        action: { selectedTab = tab }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            Divider()

            // Content area
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsPane()
                case .connections:
                    ConnectionSettingsPane()
                case .about:
                    AboutPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 550, height: 450)
        .environment(settings)
        .environment(containerStore)
    }
}

/// Individual tab button
struct TabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20))
                Text(tab.rawValue)
                    .font(.caption)
            }
            .frame(width: 80, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
    }
}

/// Window controller for managing the settings window
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func showSettings(settings: SettingsStore, containerStore: ContainerStore) {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsWindow()
            .environment(settings)
            .environment(containerStore)

        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "DockerBar Settings"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("SettingsWindow")

        // Ensure content doesn't go under title bar
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}

#if DEBUG
#Preview {
    SettingsWindow()
        .environment(SettingsStore())
        .environment(ContainerStore(settings: SettingsStore()))
}
#endif
