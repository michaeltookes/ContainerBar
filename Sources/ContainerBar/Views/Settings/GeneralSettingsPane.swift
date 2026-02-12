import SwiftUI
import ServiceManagement
import ContainerBarCore
import KeyboardShortcuts

/// General app preferences pane
struct GeneralSettingsPane: View {
    @Environment(SettingsStore.self) private var settings

    private var launchAtLoginRequiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    private func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Refresh Interval", selection: $settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases, id: \.self) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Show Stopped Containers", isOn: $settings.showStoppedContainers)
            } header: {
                Text("Display")
            }

            Section {
                Picker("Menu Bar Icon Style", selection: $settings.iconStyle) {
                    ForEach(IconStyle.allCases, id: \.self) { style in
                        HStack {
                            iconPreview(for: style)
                            Text(style.displayName)
                        }
                        .tag(style)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Choose how the menu bar icon displays container status.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)

                if launchAtLoginRequiresApproval {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Requires approval in System Settings")
                            .font(.caption)
                        Spacer()
                        Button("Open Settings") {
                            openLoginItemsSettings()
                        }
                        .font(.caption)
                    }
                }

                Toggle("Automatically Check for Updates", isOn: Binding(
                    get: { UpdaterController.shared.automaticallyChecksForUpdates },
                    set: { UpdaterController.shared.automaticallyChecksForUpdates = $0 }
                ))

                Button("Check for Updates...") {
                    UpdaterController.shared.checkForUpdates()
                }
            } header: {
                Text("Startup")
            } footer: {
                Text("ContainerBar can start at login and check for updates automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Toggle Menu")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .toggleMenu)
                }
            } header: {
                Text("Keyboard Shortcut")
            } footer: {
                Text("Set a global keyboard shortcut to quickly open ContainerBar from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func iconPreview(for style: IconStyle) -> some View {
        switch style {
        case .containerCount:
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.secondary)
        case .cpuMemoryBars:
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.secondary)
        case .healthIndicator:
            Image(systemName: "circle.fill")
                .foregroundStyle(.green)
        }
    }
}

#if DEBUG
#Preview {
    GeneralSettingsPane()
        .environment(SettingsStore())
        .frame(width: 450, height: 350)
}
#endif
