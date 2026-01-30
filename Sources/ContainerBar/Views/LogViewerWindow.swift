import SwiftUI
import ContainerBarCore

/// Window for viewing container logs
struct LogViewerView: View {
    let containerId: String
    let containerName: String
    let fetcher: ContainerFetcher

    @State private var logs: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var tailLines: Int = 100
    @State private var autoScroll = true

    private let tailOptions = [50, 100, 200, 500, 1000]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Log content
            logContent
        }
        .frame(minWidth: 600, minHeight: 400)
        .task {
            await fetchLogs()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            // Container info
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.secondary)
                Text(containerName)
                    .font(.headline)
            }

            Spacer()

            // Tail lines picker
            HStack(spacing: 4) {
                Text("Lines:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $tailLines) {
                    ForEach(tailOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
                .onChange(of: tailLines) { _, _ in
                    Task { await fetchLogs() }
                }
            }

            // Auto-scroll toggle
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)
                .font(.caption)

            // Refresh button
            Button(action: { Task { await fetchLogs() } }) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    // MARK: - Log Content

    @ViewBuilder
    private var logContent: some View {
        if let error = errorMessage {
            errorView(error)
        } else if isLoading && logs.isEmpty {
            loadingView
        } else if logs.isEmpty {
            emptyLogsView
        } else {
            logTextView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading logs...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red)
            Text("Failed to load logs")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await fetchLogs() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyLogsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No logs available")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("This container has not produced any log output yet.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var logTextView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(logs)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .id("logBottom")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: logs) { _, _ in
                if autoScroll {
                    withAnimation {
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Data Fetching

    private func fetchLogs() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetchedLogs = try await fetcher.getContainerLogs(id: containerId, tail: tailLines)
            await MainActor.run {
                logs = fetchedLogs
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - Window Controller

@MainActor
final class LogViewerWindowController {
    static let shared = LogViewerWindowController()

    private var windows: [String: NSWindow] = [:]

    private init() {}

    func showLogs(
        containerId: String,
        containerName: String,
        fetcher: ContainerFetcher
    ) {
        // If window already exists for this container, bring it to front
        if let existingWindow = windows[containerId] {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let logView = LogViewerView(
            containerId: containerId,
            containerName: containerName,
            fetcher: fetcher
        )

        let hostingController = NSHostingController(rootView: logView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Logs: \(containerName)"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("LogViewer-\(containerId.prefix(12))")

        // Handle window close
        window.isReleasedWhenClosed = false

        // Store reference
        windows[containerId] = window

        // Set up close notification
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.windows.removeValue(forKey: containerId)
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

#if DEBUG
#Preview {
    LogViewerView(
        containerId: "abc123",
        containerName: "nginx-proxy",
        fetcher: try! ContainerFetcher.local()
    )
    .frame(width: 700, height: 500)
}
#endif
