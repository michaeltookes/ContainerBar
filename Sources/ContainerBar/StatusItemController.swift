import AppKit
import SwiftUI
import ContainerBarCore
import Logging
import KeyboardShortcuts

/// Controller managing the menu bar status item and dropdown menu
///
/// Uses NSHostingView to embed SwiftUI content in NSMenu items,
/// following the SWIFT_EXPERT pattern for hybrid AppKit/SwiftUI.
///
/// Functionality is split across extension files:
/// - `StatusItemController+MenuBuilding.swift` — menu construction and NSMenuDelegate
/// - `StatusItemController+Actions.swift` — container actions, host management, dialogs
@MainActor
final class StatusItemController: NSObject {
    /// The system status item in the menu bar
    let statusItem: NSStatusItem

    /// Reference to the container store
    let containerStore: ContainerStore

    /// Reference to settings store
    let settingsStore: SettingsStore

    /// Logger for status item operations
    let logger = Logger(label: "com.containerbar.statusitem")

    /// Task for observing store changes
    private var observationTask: Task<Void, Never>?

    init(containerStore: ContainerStore, settingsStore: SettingsStore) {
        self.containerStore = containerStore
        self.settingsStore = settingsStore

        // Create status item with variable width
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        setupStatusItem()
        setupMenu()
        startObservation()
        setupGlobalHotkey()

        logger.info("StatusItemController initialized")
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        guard let button = statusItem.button else {
            logger.error("Failed to get status item button")
            return
        }

        // Use SF Symbol for menu bar icon
        if let image = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "Docker") {
            image.isTemplate = true
            button.image = image
        }

        // Set accessibility
        button.toolTip = "ContainerBar - Docker Container Monitor"
        button.setAccessibilityLabel("ContainerBar")
        button.setAccessibilityHelp("Click to view Docker containers")
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    private func startObservation() {
        observationTask?.cancel()

        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

                withObservationTracking {
                    // Track relevant properties
                    _ = self.containerStore.containers
                    _ = self.containerStore.isConnected
                    _ = self.containerStore.isRefreshing
                    _ = self.containerStore.connectionError
                    _ = self.settingsStore.iconStyle
                } onChange: {
                    Task { @MainActor [weak self] in
                        self?.updateIcon()
                    }
                }

                // Small delay to batch updates
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    // MARK: - Global Hotkey

    private func setupGlobalHotkey() {
        KeyboardShortcuts.onKeyUp(for: .toggleMenu) { [weak self] in
            Task { @MainActor in
                self?.toggleMenu()
            }
        }
        logger.info("Global hotkey registered")
    }

    /// Toggle the menu bar dropdown open/closed
    func toggleMenu() {
        guard let button = statusItem.button else { return }

        // Check if menu is currently open
        if let menu = statusItem.menu, menu.highlightedItem != nil {
            // Menu is open, close it
            menu.cancelTracking()
        } else {
            // Menu is closed, open it
            button.performClick(nil)
        }
    }

    func closeMenuIfOpen() {
        statusItem.menu?.cancelTracking()
    }

    // MARK: - Icon Updates

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let runningCount = containerStore.containers.filter { $0.state == .running }.count
        let totalCount = containerStore.containers.count

        // Calculate CPU and memory percentages from metrics
        let cpuPercent = containerStore.metricsSnapshot?.totalCPUPercent ?? 0
        let memoryPercent: Double
        if let metrics = containerStore.metricsSnapshot,
           metrics.totalMemoryLimitBytes > 0 {
            memoryPercent = Double(metrics.totalMemoryUsedBytes) / Double(metrics.totalMemoryLimitBytes) * 100
        } else {
            memoryPercent = 0
        }

        // Build renderer config
        let config = DockerIconRenderer.Config(
            style: settingsStore.iconStyle,
            runningCount: runningCount,
            totalCount: totalCount,
            cpuPercent: cpuPercent,
            memoryPercent: memoryPercent,
            isRefreshing: containerStore.isRefreshing,
            isConnected: containerStore.isConnected,
            hasError: containerStore.connectionError != nil
        )

        // Render the icon
        let image = DockerIconRenderer.render(config: config)
        button.image = image

        // Show running count as title (for container count style only)
        if settingsStore.iconStyle == .containerCount && totalCount > 0 && containerStore.isConnected {
            button.title = " \(runningCount)"
        } else {
            button.title = ""
        }

        // Update accessibility
        let stateDescription: String
        if containerStore.connectionError != nil {
            stateDescription = "Error connecting to Docker"
        } else if containerStore.isRefreshing {
            stateDescription = "Refreshing"
        } else if containerStore.isConnected {
            stateDescription = "\(runningCount) of \(totalCount) containers running"
        } else {
            stateDescription = "Connecting to Docker"
        }
        button.setAccessibilityValue(stateDescription)
    }
}
