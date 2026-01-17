import SwiftUI
import DockerBarCore

/// General app preferences pane
struct GeneralSettingsPane: View {
    @Environment(SettingsStore.self) private var settings

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
            } header: {
                Text("Startup")
            } footer: {
                Text("Automatically start DockerBar when you log in to your Mac.")
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
