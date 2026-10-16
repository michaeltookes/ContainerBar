import SwiftUI
import AppKit
import ContainerBarCore

/// Settings tab enumeration
enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case sections = "Sections"
    case connections = "Connections"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .sections: return "folder"
        case .connections: return "network"
        case .about: return "info.circle"
        }
    }

    var toolbarItemIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue)
    }
}

/// Main settings content view
struct SettingsContentView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ContainerStore.self) private var containerStore

    let selectedTab: SettingsTab
    private let fetcherFactory: ContainerStore.FetcherFactory

    init(
        selectedTab: SettingsTab,
        fetcherFactory: @escaping ContainerStore.FetcherFactory = ContainerStore.defaultFetcherFactory
    ) {
        self.selectedTab = selectedTab
        self.fetcherFactory = fetcherFactory
    }

    var body: some View {
        Group {
            switch selectedTab {
            case .general:
                GeneralSettingsPane()
            case .sections:
                SectionsSettingsPane()
            case .connections:
                ConnectionSettingsPane(fetcherFactory: fetcherFactory)
            case .about:
                AboutPane()
            }
        }
        .frame(width: 550, height: 400)
        .environment(settings)
        .environment(containerStore)
    }
}

/// Window controller for managing the settings window with native toolbar
@MainActor
final class SettingsWindowController: NSObject, NSToolbarDelegate, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var selectedTab: SettingsTab = .general
    private var settingsStore: SettingsStore?
    private var containerStore: ContainerStore?
    private var fetcherFactory: ContainerStore.FetcherFactory = ContainerStore.defaultFetcherFactory
    /// One-shot requests to the hosted panes, such as presenting the Add Host
    /// sheet (CB-078). Lives as long as the controller so a request set before
    /// the window exists is still there when the pane first appears.
    private let navigation = SettingsNavigation()

    private override init() {
        super.init()
    }

    /// Shows the settings window, creating it only if none is open.
    ///
    /// With a `route`, the window switches to the route's tab (an open window
    /// is reused and brought to the front, never duplicated) and, for
    /// `.connections(addHost: true)`, the Connections pane presents the Add
    /// Host sheet. Without one, the window keeps whichever tab it last showed.
    func showSettings(
        settings: SettingsStore,
        containerStore: ContainerStore,
        fetcherFactory: @escaping ContainerStore.FetcherFactory = ContainerStore.defaultFetcherFactory,
        route: SettingsRoute? = nil
    ) {
        self.settingsStore = settings
        self.containerStore = containerStore
        self.fetcherFactory = fetcherFactory

        if let route {
            // Set the request before the pane is swapped in so its onAppear
            // (new or switched pane) or onChange (pane already showing) sees it.
            if let request = route.addHostRequest {
                navigation.requestAddHost(request)
            }
            selectedTab = route.tab
        }

        if let existingWindow = window {
            if route != nil {
                existingWindow.toolbar?.selectedItemIdentifier = selectedTab.toolbarItemIdentifier
                updateContent(for: selectedTab)
            }
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = selectedTab.rawValue
        window.delegate = self
        // Stable handle for UI automation; the title changes per tab.
        window.setAccessibilityIdentifier("settingsWindow")

        // Create and configure the toolbar
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = selectedTab.toolbarItemIdentifier
        window.toolbar = toolbar
        window.toolbarStyle = .preference

        // Set up the content
        updateContent(for: selectedTab)
        if let hostingController = hostingController {
            window.contentViewController = hostingController
            hostingController.view.frame = NSRect(x: 0, y: 0, width: 550, height: 350)
        }

        window.setContentSize(NSSize(width: 550, height: 350))
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.isReleasedWhenClosed = false

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateContent(for tab: SettingsTab) {
        guard let settings = settingsStore, let containerStore = containerStore else { return }

        let contentView = SettingsContentView(
            selectedTab: tab,
            fetcherFactory: fetcherFactory
        )
            .environment(settings)
            .environment(containerStore)
            .environment(navigation)

        if let hostingController = hostingController {
            hostingController.rootView = AnyView(contentView)
        } else {
            hostingController = NSHostingController(rootView: AnyView(contentView))
        }

        window?.title = tab.rawValue
    }

    func close() {
        window?.close()
        window = nil
        hostingController = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window = nil
        hostingController = nil
    }

    // MARK: - NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map { $0.toolbarItemIdentifier }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map { $0.toolbarItemIdentifier }
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map { $0.toolbarItemIdentifier }
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = SettingsTab.allCases.first(where: { $0.toolbarItemIdentifier == itemIdentifier }) else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.rawValue
        item.image = NSImage(systemSymbolName: tab.icon, accessibilityDescription: tab.rawValue)
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        item.isNavigational = false

        return item
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab.allCases.first(where: { $0.toolbarItemIdentifier == sender.itemIdentifier }) else {
            return
        }

        selectedTab = tab
        window?.toolbar?.selectedItemIdentifier = tab.toolbarItemIdentifier
        updateContent(for: tab)
    }
}

#if DEBUG
#Preview {
    SettingsContentView(selectedTab: .general)
        .environment(SettingsStore())
        .environment(ContainerStore(settings: SettingsStore()))
        .frame(width: 550, height: 400)
}
#endif
