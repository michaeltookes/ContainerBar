# DockerBar Design Document

## Comprehensive Design Specification for macOS Docker Container Monitoring Application

**Version**: 1.0
**Date**: January 2026
**Based On**: CodexBar Architecture Analysis

---

# Table of Contents

1. [Executive Summary](#section-1-executive-summary)
2. [Architecture Overview](#section-2-architecture-overview)
3. [Technical Stack](#section-3-technical-stack)
4. [Data Models](#section-4-data-models)
5. [User Interface Design](#section-5-user-interface-design)
6. [API Integration Layer](#section-6-api-integration-layer)
7. [Real-time Updates](#section-7-real-time-updates)
8. [Settings & Configuration](#section-8-settings--configuration)
9. [Build & Development Setup](#section-9-build--development-setup)
10. [Implementation Roadmap](#section-10-implementation-roadmap)
11. [Key Design Decisions](#section-11-key-design-decisions)
12. [Security Considerations](#section-12-security-considerations)
13. [User Experience Guidelines](#section-13-user-experience-guidelines)
14. [Testing & Validation](#section-14-testing--validation)
15. [Documentation Requirements](#section-15-documentation-requirements)

---

# Section 1: Executive Summary

## Product Vision

DockerBar is a lightweight macOS menu bar application that provides instant access to Docker container monitoring and management directly from the macOS menu bar. Inspired by CodexBar's elegant approach to AI tool usage monitoring, DockerBar eliminates the need to keep browser-based tools like Portainer or Docker Desktop open, providing developers and DevOps engineers with quick container insights at a glance.

The application follows CodexBar's proven architecture patterns: a hybrid SwiftUI + AppKit approach for native macOS integration, the Provider Descriptor pattern for extensible data source management, and Swift 6's strict concurrency model for thread-safe operation. DockerBar translates these patterns from AI tool monitoring to container infrastructure monitoring.

## Key Objectives

1. **Instant Visibility**: Display container status in the macOS menu bar with at-a-glance health indicators
2. **Quick Management**: Enable start/stop/restart of containers without leaving the current workflow
3. **Real-time Metrics**: Show CPU, memory, and network I/O statistics with configurable refresh intervals
4. **Secure Remote Access**: Connect to remote Docker daemons via TLS or SSH tunnels with credentials stored securely in macOS Keychain
5. **Native Experience**: Deliver a polished, responsive macOS-native application under 50MB memory footprint

## Target User

**Primary User**: A developer or DevOps engineer managing Docker containers on a remote server (e.g., a Beelink home server) who wants quick monitoring and basic management without opening a full browser-based UI.

**Use Case**: Quick checks on container health, restarting a crashed service, viewing logs for debugging—all from the menu bar with minimal context switching.

## Success Criteria

- Menu opens in <100ms with container list displayed
- Stats update with <1 second latency
- Memory footprint under 50MB
- CPU usage <1% when idle
- Successful connection to remote Docker daemon via TLS
- Graceful handling of network interruptions

---

# Section 2: Architecture Overview

## 2.1 Application Architecture

DockerBar follows a layered architecture inspired by CodexBar's modular design, with clear separation between UI, business logic, and data access layers.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            DockerBar Application                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                       UI Layer (SwiftUI + AppKit)                   │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────────┐ │    │
│  │  │StatusItem    │  │ContainerMenu │  │SettingsWindow              │ │    │
│  │  │Controller    │  │CardView      │  │(Connection, Preferences)   │ │    │
│  │  └──────────────┘  └──────────────┘  └────────────────────────────┘ │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                      │                                      │
│                                      ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                   State Management Layer (@Observable)              │    │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐   │    │
│  │  │ContainerStore    │  │SettingsStore     │  │ConnectionStore   │   │    │
│  │  │(Metrics, List)   │  │(Preferences)     │  │(Host Status)     │   │    │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘   │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                      │                                      │
│                                      ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        Service Layer (DockerBarCore)                │    │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐   │    │
│  │  │ContainerFetcher  │  │DockerAPIClient   │  │CredentialManager │   │    │
│  │  │(Strategy-based)  │  │(HTTP/Socket)     │  │(Keychain)        │   │    │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘   │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                      │                                      │
│                                      ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    Docker Engine API (External)                     │    │
│  │           Unix Socket / TCP+TLS / SSH Tunnel                        │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 2.2 Architecture Patterns from CodexBar

### Pattern Mapping Table

| CodexBar Pattern | Applicability | Adaptation for DockerBar |
|------------------|---------------|--------------------------|
| **Provider Descriptor** | Direct adaptation | `DockerSourceDescriptor` defines connection methods and branding |
| **Fetch Strategy** | Direct adaptation | Strategies for Unix Socket, TCP+TLS, SSH Tunnel |
| **Observable Store** | Direct reuse | `@Observable ContainerStore` with `@MainActor` isolation |
| **Menu Card View** | Direct adaptation | Container card with metrics instead of usage percentages |
| **Icon Renderer** | Adaptation needed | Render container health indicators instead of usage bars |
| **Settings Persistence** | Direct reuse | UserDefaults with `didSet` pattern |
| **Failure Gate** | Direct reuse | Ignore transient connection failures |
| **Progress Bar** | Direct reuse | CPU/Memory utilization bars |
| **Widget Snapshot** | Future phase | Share data with WidgetKit extension |

### Source Descriptor Pattern

Following CodexBar's Provider Descriptor pattern:

```swift
public struct DockerSourceDescriptor: Sendable {
    public let id: DockerSource
    public let metadata: SourceMetadata
    public let branding: SourceBranding
    public let fetchPlan: SourceFetchPlan
}

public enum DockerSource: String, CaseIterable, Sendable {
    case dockerLocal    // Unix socket
    case dockerRemote   // TCP + TLS
    case dockerSSH      // SSH tunnel
}

// Example descriptor
let localDockerDescriptor = DockerSourceDescriptor(
    id: .dockerLocal,
    metadata: SourceMetadata(
        displayName: "Docker (Local)",
        connectionLabel: "Unix Socket",
        resourceLabel: "Containers"
    ),
    branding: SourceBranding(
        iconName: "docker-whale",
        color: SourceColor(red: 0.13, green: 0.59, blue: 0.95)
    ),
    fetchPlan: SourceFetchPlan(
        strategies: [DockerUnixSocketStrategy()]
    )
)
```

## 2.3 Data Flow

```
┌─────────────┐     ┌─────────────────┐     ┌────────────────┐     ┌──────────┐
│ Timer/User  │────▶│ ContainerStore  │────▶│ ContainerFetcher│────▶│ Docker   │
│ Action      │     │ .refresh()      │     │ .fetch()        │     │ API      │
└─────────────┘     └─────────────────┘     └────────────────┘     └──────────┘
                            │                        │
                            │                        ▼
                            │               ┌────────────────┐
                            │               │ FetchStrategy  │
                            │               │ (Socket/TLS/   │
                            │               │  SSH)          │
                            │               └────────────────┘
                            │                        │
                            ▼                        ▼
                    ┌─────────────────┐     ┌────────────────┐
                    │ @Observable     │◀────│ ContainerList  │
                    │ State Update    │     │ + Stats        │
                    └─────────────────┘     └────────────────┘
                            │
                            ▼
                    ┌─────────────────┐
                    │ SwiftUI View    │
                    │ Re-render       │
                    └─────────────────┘
```

---

# Section 3: Technical Stack

## 3.1 Core Technologies

| Component | Technology | Version | Rationale |
|-----------|------------|---------|-----------|
| **Language** | Swift | 6.0+ | Strict concurrency, modern async/await |
| **UI Framework** | SwiftUI + AppKit | macOS 14+ | Native menu bar requires AppKit; SwiftUI for views |
| **Build System** | Swift Package Manager | 6.0+ | No Xcode project dependency, reproducible builds |
| **Minimum OS** | macOS 14 (Sonoma) | - | Required for Observation framework |
| **Concurrency** | Swift Concurrency | - | `@MainActor`, `Sendable`, async/await |

## 3.2 Third-Party Dependencies

| Library | Purpose | Source |
|---------|---------|--------|
| **swift-log** | Structured logging | Apple |
| **KeyboardShortcuts** | Global hotkey support | sindresorhus/KeyboardShortcuts |
| **Sparkle** | Auto-update framework | sparkle-project/Sparkle |
| **swift-nio** | Async networking (optional) | apple/swift-nio |

### Package.swift Configuration

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockerBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DockerBar", targets: ["DockerBar"]),
        .library(name: "DockerBarCore", targets: ["DockerBarCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "DockerBar",
            dependencies: [
                "DockerBarCore",
                .product(name: "Logging", package: "swift-log"),
                "KeyboardShortcuts",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "DockerBarCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DockerBarTests",
            dependencies: ["DockerBarCore"]
        ),
    ]
)
```

## 3.3 Networking Stack

For Docker API communication:

- **Foundation URLSession**: Primary HTTP client with custom URLProtocol for Unix sockets
- **Security.framework**: TLS certificate handling
- **Network.framework**: SSH tunnel support (optional, for Phase 2)

---

# Section 4: Data Models

## 4.1 Core Data Structures

### Container Models

```swift
/// Represents a Docker container
public struct DockerContainer: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let names: [String]
    public let image: String
    public let imageID: String
    public let command: String
    public let created: Date
    public let state: ContainerState
    public let status: String  // Human-readable status (e.g., "Up 2 hours")
    public let ports: [PortMapping]
    public let labels: [String: String]
    public let networkMode: String?

    /// Primary container name (without leading slash)
    public var displayName: String {
        names.first?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? id.prefix(12).description
    }
}

/// Container state enumeration
public enum ContainerState: String, Codable, Sendable, Equatable {
    case running
    case paused
    case restarting
    case exited
    case created
    case dead
    case removing

    public var isActive: Bool {
        self == .running || self == .paused || self == .restarting
    }

    public var displayColor: String {
        switch self {
        case .running: return "green"
        case .paused: return "yellow"
        case .restarting: return "orange"
        case .exited, .dead: return "red"
        case .created, .removing: return "gray"
        }
    }
}

/// Port mapping configuration
public struct PortMapping: Codable, Sendable, Equatable {
    public let privatePort: Int
    public let publicPort: Int?
    public let type: String  // "tcp" or "udp"
    public let ip: String?
}
```

### Container Statistics Models

```swift
/// Real-time container statistics
public struct ContainerStats: Codable, Sendable, Equatable {
    public let containerId: String
    public let timestamp: Date

    // CPU metrics
    public let cpuPercent: Double
    public let cpuSystemUsage: UInt64
    public let cpuContainerUsage: UInt64
    public let onlineCPUs: Int

    // Memory metrics
    public let memoryUsageBytes: UInt64
    public let memoryLimitBytes: UInt64
    public let memoryPercent: Double
    public let memoryCache: UInt64?

    // Network metrics
    public let networkRxBytes: UInt64
    public let networkTxBytes: UInt64
    public let networkRxPackets: UInt64
    public let networkTxPackets: UInt64

    // Block I/O metrics
    public let blockReadBytes: UInt64
    public let blockWriteBytes: UInt64

    // Computed properties
    public var memoryUsedMB: Double {
        Double(memoryUsageBytes) / 1_048_576.0
    }

    public var memoryLimitMB: Double {
        Double(memoryLimitBytes) / 1_048_576.0
    }

    public var networkRxMB: Double {
        Double(networkRxBytes) / 1_048_576.0
    }

    public var networkTxMB: Double {
        Double(networkTxBytes) / 1_048_576.0
    }
}

/// Aggregated metrics snapshot for all containers
public struct ContainerMetricsSnapshot: Codable, Sendable, Equatable {
    public let containers: [ContainerStats]
    public let totalCPUPercent: Double
    public let totalMemoryUsedBytes: UInt64
    public let totalMemoryLimitBytes: UInt64
    public let runningCount: Int
    public let stoppedCount: Int
    public let pausedCount: Int
    public let totalCount: Int
    public let updatedAt: Date

    public var overallHealth: HealthStatus {
        if runningCount == 0 && totalCount > 0 { return .critical }
        if totalCPUPercent > 90 || (Double(totalMemoryUsedBytes) / Double(totalMemoryLimitBytes)) > 0.95 {
            return .warning
        }
        return .healthy
    }
}

public enum HealthStatus: String, Codable, Sendable {
    case healthy
    case warning
    case critical
    case unknown
}
```

### Host Configuration Models

```swift
/// Docker host connection configuration
public struct DockerHost: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var connectionType: ConnectionType
    public var isDefault: Bool

    // Connection details vary by type
    public var socketPath: String?      // For Unix socket
    public var host: String?            // For TCP/SSH
    public var port: Int?               // For TCP
    public var tlsEnabled: Bool
    public var sshUser: String?         // For SSH
    public var sshPort: Int?            // For SSH (default 22)

    public init(
        id: UUID = UUID(),
        name: String,
        connectionType: ConnectionType,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.connectionType = connectionType
        self.isDefault = isDefault
        self.socketPath = connectionType == .unixSocket ? "/var/run/docker.sock" : nil
        self.tlsEnabled = connectionType == .tcpTLS
    }
}

/// Connection type enumeration
public enum ConnectionType: String, Codable, Sendable, CaseIterable {
    case unixSocket = "unix"
    case tcpTLS = "tcp+tls"
    case ssh = "ssh"

    public var displayName: String {
        switch self {
        case .unixSocket: return "Unix Socket (Local)"
        case .tcpTLS: return "TCP + TLS (Remote)"
        case .ssh: return "SSH Tunnel (Remote)"
        }
    }
}
```

## 4.2 State Management

Following CodexBar's `@Observable` pattern:

```swift
@MainActor
@Observable
final class ContainerStore {
    // Container data
    var containers: [DockerContainer] = []
    var stats: [String: ContainerStats] = [:]  // Keyed by container ID
    var metricsSnapshot: ContainerMetricsSnapshot?

    // Connection state
    var isConnected: Bool = false
    var connectionError: String?
    var lastRefreshAt: Date?

    // Refresh state
    var isRefreshing: Bool = false
    var refreshingContainers: Set<String> = []

    // Failure tracking (CodexBar pattern)
    @ObservationIgnored private var failureGate = ConsecutiveFailureGate()
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    // Dependencies
    private let fetcher: ContainerFetcher
    private let settings: SettingsStore

    init(fetcher: ContainerFetcher, settings: SettingsStore) {
        self.fetcher = fetcher
        self.settings = settings
        self.startTimer()
    }

    func refresh(force: Bool = false) async {
        guard !isRefreshing || force else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await fetcher.fetchAll()
            self.containers = result.containers
            self.stats = result.stats
            self.metricsSnapshot = result.metrics
            self.isConnected = true
            self.connectionError = nil
            self.lastRefreshAt = Date()
            self.failureGate.recordSuccess()
        } catch {
            let hadPriorData = !containers.isEmpty
            if failureGate.shouldSurfaceError(onFailureWithPriorData: hadPriorData) {
                self.connectionError = error.localizedDescription
                self.isConnected = false
            }
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        guard let interval = settings.refreshInterval.seconds else { return }

        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self else { return }
                await self.refresh()
            }
        }
    }
}
```

### Settings Store

```swift
@MainActor
@Observable
final class SettingsStore {
    private let userDefaults: UserDefaults

    // Refresh settings
    var refreshInterval: RefreshInterval {
        didSet { userDefaults.set(refreshInterval.rawValue, forKey: "refreshInterval") }
    }

    // Docker hosts
    private(set) var hosts: [DockerHost] = []
    var selectedHostId: UUID? {
        didSet { userDefaults.set(selectedHostId?.uuidString, forKey: "selectedHostId") }
    }

    // Display preferences
    var showStoppedContainers: Bool {
        didSet { userDefaults.set(showStoppedContainers, forKey: "showStoppedContainers") }
    }

    var launchAtLogin: Bool {
        didSet {
            userDefaults.set(launchAtLogin, forKey: "launchAtLogin")
            LaunchAtLoginManager.setEnabled(launchAtLogin)
        }
    }

    // Icon preferences
    var iconStyle: IconStyle {
        didSet { userDefaults.set(iconStyle.rawValue, forKey: "iconStyle") }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.refreshInterval = RefreshInterval(rawValue: userDefaults.string(forKey: "refreshInterval") ?? "") ?? .seconds5
        self.showStoppedContainers = userDefaults.bool(forKey: "showStoppedContainers")
        self.launchAtLogin = userDefaults.bool(forKey: "launchAtLogin")
        self.iconStyle = IconStyle(rawValue: userDefaults.string(forKey: "iconStyle") ?? "") ?? .containerCount
        loadHosts()
    }

    func addHost(_ host: DockerHost) {
        hosts.append(host)
        saveHosts()
    }

    func removeHost(id: UUID) {
        hosts.removeAll { $0.id == id }
        saveHosts()
    }

    private func loadHosts() {
        guard let data = userDefaults.data(forKey: "dockerHosts"),
              let decoded = try? JSONDecoder().decode([DockerHost].self, from: data) else {
            return
        }
        hosts = decoded
    }

    private func saveHosts() {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        userDefaults.set(data, forKey: "dockerHosts")
    }
}

enum RefreshInterval: String, CaseIterable, Sendable {
    case seconds5 = "5s"
    case seconds10 = "10s"
    case seconds30 = "30s"
    case minute1 = "1m"
    case minutes5 = "5m"
    case manual = "manual"

    var seconds: TimeInterval? {
        switch self {
        case .seconds5: return 5
        case .seconds10: return 10
        case .seconds30: return 30
        case .minute1: return 60
        case .minutes5: return 300
        case .manual: return nil
        }
    }

    var displayName: String {
        switch self {
        case .seconds5: return "5 seconds"
        case .seconds10: return "10 seconds"
        case .seconds30: return "30 seconds"
        case .minute1: return "1 minute"
        case .minutes5: return "5 minutes"
        case .manual: return "Manual only"
        }
    }
}

enum IconStyle: String, CaseIterable, Sendable {
    case containerCount
    case cpuMemoryBars
    case healthIndicator

    var displayName: String {
        switch self {
        case .containerCount: return "Container Count"
        case .cpuMemoryBars: return "CPU + Memory Bars"
        case .healthIndicator: return "Health Indicator"
        }
    }
}
```

---

# Section 5: User Interface Design

## 5.1 Menu Bar Icon

### Design Specifications

**Size**: 18×18 points at 2x resolution (36×36 pixels)
**Style**: Template image (monochrome, system-tinted)

### Icon States

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│      🐳 12       │     │  ████████░░░░░░  │     │       ●          │
│                  │     │  ██████░░░░░░░░  │     │     (green)      │
└──────────────────┘     └──────────────────┘     └──────────────────┘
   Container Count         CPU + Memory Bars        Health Indicator
```

### Icon Rendering

```swift
enum DockerIconRenderer {
    private static let baseSize = NSSize(width: 18, height: 18)
    private static let outputScale: CGFloat = 2

    static func icon(
        style: IconStyle,
        containerCount: Int,
        runningCount: Int,
        cpuPercent: Double?,
        memoryPercent: Double?,
        health: HealthStatus,
        isRefreshing: Bool
    ) -> NSImage {
        switch style {
        case .containerCount:
            return renderCountIcon(running: runningCount, total: containerCount, refreshing: isRefreshing)
        case .cpuMemoryBars:
            return renderBarsIcon(cpu: cpuPercent, memory: memoryPercent, refreshing: isRefreshing)
        case .healthIndicator:
            return renderHealthIcon(health: health, refreshing: isRefreshing)
        }
    }

    private static func renderCountIcon(running: Int, total: Int, refreshing: Bool) -> NSImage {
        // Docker whale icon with count badge
        // Animate whale tail during refresh
    }

    private static func renderBarsIcon(cpu: Double?, memory: Double?, refreshing: Bool) -> NSImage {
        // Dual horizontal bars (similar to CodexBar)
        // Top bar: CPU usage
        // Bottom bar: Memory usage
    }

    private static func renderHealthIcon(health: HealthStatus, refreshing: Bool) -> NSImage {
        // Simple circle with health color
        // Green: healthy, Yellow: warning, Red: critical
    }
}
```

## 5.2 Dropdown Menu Structure

```
┌─────────────────────────────────────────────────────┐
│ DockerBar                              ⟳ Refreshing │
├─────────────────────────────────────────────────────┤
│ Connected to: beelink-server                        │
│ ● 8 running  ○ 2 stopped  ○ 2 paused               │
├─────────────────────────────────────────────────────┤
│ Overview                                            │
│ ┌─────────────────────────────────────────────────┐ │
│ │ CPU Usage                                       │ │
│ │ ████████████████░░░░░░░░░░░░░░░░░░  45%        │ │
│ │ Memory Usage                                    │ │
│ │ ██████████████████████░░░░░░░░░░░░  62%        │ │
│ │ 4.9 GB / 8 GB                                   │ │
│ └─────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────┤
│ Containers                                          │
│ ┌─────────────────────────────────────────────────┐ │
│ │ ● nginx-proxy                        Running    │ │
│ │   CPU: 2.3%  MEM: 128 MB  Up 2 hours           │ │
│ ├─────────────────────────────────────────────────┤ │
│ │ ● postgres-db                        Running    │ │
│ │   CPU: 5.1%  MEM: 512 MB  Up 3 days            │ │
│ ├─────────────────────────────────────────────────┤ │
│ │ ● redis-cache                        Running    │ │
│ │   CPU: 0.1%  MEM: 64 MB   Up 3 days            │ │
│ ├─────────────────────────────────────────────────┤ │
│ │ ○ backup-service                     Stopped    │ │
│ │   Exited (0) 12 hours ago                       │ │
│ └─────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────┤
│ ⟳ Refresh Now                              ⌘R      │
│ ⚙️ Settings...                             ⌘,      │
├─────────────────────────────────────────────────────┤
│ Quit DockerBar                             ⌘Q      │
└─────────────────────────────────────────────────────┘
```

### Container Row Actions (Click to Expand)

```
│ ● nginx-proxy                          Running    │
│   CPU: 2.3%  MEM: 128 MB  Up 2 hours             │
│   ┌─────────────────────────────────────────────┐ │
│   │ ■ Stop                                      │ │
│   │ ⟳ Restart                                   │ │
│   │ 📋 Copy Container ID                         │ │
│   │ 📄 View Logs...                             │ │
│   │ ──────────────────────                      │ │
│   │ 🗑 Remove Container...                      │ │
│   └─────────────────────────────────────────────┘ │
```

## 5.3 Container Card View (SwiftUI)

```swift
struct ContainerMenuCardView: View {
    struct Model {
        let sourceName: String
        let connectionStatus: String
        let metrics: OverviewMetrics
        let containers: [ContainerRow]
    }

    struct OverviewMetrics {
        let cpuPercent: Double
        let memoryUsedMB: Double
        let memoryLimitMB: Double
        let runningCount: Int
        let stoppedCount: Int
        let pausedCount: Int
    }

    struct ContainerRow: Identifiable {
        let id: String
        let name: String
        let state: ContainerState
        let cpuPercent: Double?
        let memoryMB: Double?
        let uptime: String
    }

    let model: Model
    let onAction: (ContainerAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(model.sourceName)
                    .font(.headline)
                Spacer()
                Text(model.connectionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Overview metrics
            VStack(alignment: .leading, spacing: 8) {
                MetricProgressBar(
                    title: "CPU Usage",
                    percent: model.metrics.cpuPercent,
                    tint: .blue
                )
                MetricProgressBar(
                    title: "Memory Usage",
                    percent: (model.metrics.memoryUsedMB / model.metrics.memoryLimitMB) * 100,
                    subtitle: "\(formatted(model.metrics.memoryUsedMB)) / \(formatted(model.metrics.memoryLimitMB))",
                    tint: .purple
                )
            }
            .padding(.vertical, 8)

            Divider()

            // Container list
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.containers) { container in
                    ContainerRowView(
                        container: container,
                        onAction: onAction
                    )
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
```

## 5.4 Settings Window

### Tab Structure

| Tab | Purpose | Components |
|-----|---------|------------|
| **Connection** | Docker host management | Host list, Add/Edit host, Test connection |
| **General** | App preferences | Refresh interval, Launch at login, Icon style |
| **Advanced** | Power user options | Log level, Cache settings, Debug mode |
| **About** | App info | Version, Check for updates, Links |

### Connection Settings Pane

```swift
struct ConnectionSettingsPane: View {
    @Bindable var settings: SettingsStore
    @State private var selectedHost: DockerHost?
    @State private var isAddingHost = false
    @State private var testResult: ConnectionTestResult?

    var body: some View {
        HSplitView {
            // Host list (left)
            VStack {
                List(settings.hosts, selection: $selectedHost) { host in
                    HostRowView(host: host, isSelected: host.id == settings.selectedHostId)
                }

                HStack {
                    Button(action: { isAddingHost = true }) {
                        Image(systemName: "plus")
                    }
                    Button(action: removeSelectedHost) {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedHost == nil)
                }
            }
            .frame(width: 200)

            // Host details (right)
            if let host = selectedHost {
                HostDetailsView(
                    host: binding(for: host),
                    testResult: $testResult,
                    onTest: testConnection
                )
            } else {
                Text("Select or add a Docker host")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isAddingHost) {
            AddHostSheet(onSave: addHost)
        }
    }
}
```

---

# Section 6: API Integration Layer

## 6.1 Docker API Client Design

```swift
/// Protocol defining Docker API operations
public protocol DockerAPIClient: Sendable {
    func ping() async throws
    func listContainers(all: Bool) async throws -> [DockerContainer]
    func getContainer(id: String) async throws -> DockerContainer
    func getContainerStats(id: String, stream: Bool) async throws -> AsyncThrowingStream<ContainerStats, Error>
    func startContainer(id: String) async throws
    func stopContainer(id: String, timeout: Int?) async throws
    func restartContainer(id: String, timeout: Int?) async throws
    func removeContainer(id: String, force: Bool, volumes: Bool) async throws
    func getContainerLogs(id: String, tail: Int?, timestamps: Bool) async throws -> String
    func getSystemInfo() async throws -> DockerSystemInfo
}

/// Concrete implementation
public final class DockerAPIClientImpl: DockerAPIClient, @unchecked Sendable {
    private let session: URLSession
    private let baseURL: URL
    private let connectionType: ConnectionType

    public init(host: DockerHost) throws {
        self.connectionType = host.connectionType

        switch host.connectionType {
        case .unixSocket:
            let config = URLSessionConfiguration.default
            config.protocolClasses = [UnixSocketURLProtocol.self]
            self.session = URLSession(configuration: config)
            self.baseURL = URL(string: "http://localhost")!

        case .tcpTLS:
            guard let hostName = host.host, let port = host.port else {
                throw DockerAPIError.invalidConfiguration("Missing host or port for TCP connection")
            }
            let config = URLSessionConfiguration.default
            // Configure TLS if certificates are provided
            self.session = URLSession(configuration: config)
            self.baseURL = URL(string: "https://\(hostName):\(port)")!

        case .ssh:
            // SSH tunnel setup handled separately
            throw DockerAPIError.notImplemented("SSH tunnel support in Phase 2")
        }
    }

    public func ping() async throws {
        let url = baseURL.appendingPathComponent("_ping")
        let (_, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DockerAPIError.connectionFailed
        }
    }

    public func listContainers(all: Bool = false) async throws -> [DockerContainer] {
        var components = URLComponents(url: baseURL.appendingPathComponent("containers/json"), resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "all", value: all ? "true" : "false")]

        guard let url = components?.url else {
            throw DockerAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode([DockerContainer].self, from: data)
    }

    public func getContainerStats(id: String, stream: Bool = false) async throws -> AsyncThrowingStream<ContainerStats, Error> {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("containers/\(id)/stats"),
            resolvingAgainstBaseURL: true
        )
        components?.queryItems = [URLQueryItem(name: "stream", value: stream ? "true" : "false")]

        guard let url = components?.url else {
            throw DockerAPIError.invalidURL
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await session.bytes(from: url)
                    try validateResponse(response)

                    for try await line in bytes.lines {
                        guard !line.isEmpty else { continue }
                        if let data = line.data(using: .utf8) {
                            let rawStats = try JSONDecoder().decode(DockerRawStats.self, from: data)
                            let stats = ContainerStats(from: rawStats, containerId: id)
                            continuation.yield(stats)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func startContainer(id: String) async throws {
        let url = baseURL.appendingPathComponent("containers/\(id)/start")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (_, response) = try await session.data(for: request)
        try validateResponse(response, allowedCodes: [204, 304])
    }

    public func stopContainer(id: String, timeout: Int? = nil) async throws {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("containers/\(id)/stop"),
            resolvingAgainstBaseURL: true
        )
        if let timeout {
            components?.queryItems = [URLQueryItem(name: "t", value: String(timeout))]
        }

        guard let url = components?.url else {
            throw DockerAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (_, response) = try await session.data(for: request)
        try validateResponse(response, allowedCodes: [204, 304])
    }

    public func restartContainer(id: String, timeout: Int? = nil) async throws {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("containers/\(id)/restart"),
            resolvingAgainstBaseURL: true
        )
        if let timeout {
            components?.queryItems = [URLQueryItem(name: "t", value: String(timeout))]
        }

        guard let url = components?.url else {
            throw DockerAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (_, response) = try await session.data(for: request)
        try validateResponse(response, allowedCodes: [204])
    }

    public func removeContainer(id: String, force: Bool = false, volumes: Bool = false) async throws {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("containers/\(id)"),
            resolvingAgainstBaseURL: true
        )
        components?.queryItems = [
            URLQueryItem(name: "force", value: force ? "true" : "false"),
            URLQueryItem(name: "v", value: volumes ? "true" : "false")
        ]

        guard let url = components?.url else {
            throw DockerAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await session.data(for: request)
        try validateResponse(response, allowedCodes: [204])
    }

    public func getContainerLogs(id: String, tail: Int? = 100, timestamps: Bool = false) async throws -> String {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("containers/\(id)/logs"),
            resolvingAgainstBaseURL: true
        )
        var queryItems = [
            URLQueryItem(name: "stdout", value: "true"),
            URLQueryItem(name: "stderr", value: "true"),
            URLQueryItem(name: "timestamps", value: timestamps ? "true" : "false")
        ]
        if let tail {
            queryItems.append(URLQueryItem(name: "tail", value: String(tail)))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw DockerAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        try validateResponse(response)

        // Docker logs have a multiplexed format with 8-byte headers
        return parseMultiplexedLogs(data)
    }

    // MARK: - Helpers

    private func validateResponse(_ response: URLResponse, allowedCodes: Set<Int> = [200]) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DockerAPIError.invalidResponse
        }

        guard allowedCodes.contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401: throw DockerAPIError.unauthorized
            case 404: throw DockerAPIError.notFound("Resource")
            case 409: throw DockerAPIError.conflict("Container is already in requested state")
            case 500...599: throw DockerAPIError.serverError("Docker daemon error")
            default: throw DockerAPIError.unexpectedStatus(httpResponse.statusCode)
            }
        }
    }

    private func parseMultiplexedLogs(_ data: Data) -> String {
        // Docker multiplexed stream format:
        // [8-byte header][payload]
        // Header: [stream_type(1)][0(3)][size(4 big-endian)]
        var result = ""
        var offset = 0

        while offset + 8 <= data.count {
            let size = data.subdata(in: (offset + 4)..<(offset + 8))
                .withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            offset += 8

            guard offset + Int(size) <= data.count else { break }

            if let text = String(data: data.subdata(in: offset..<(offset + Int(size))), encoding: .utf8) {
                result += text
            }
            offset += Int(size)
        }

        return result
    }
}
```

## 6.2 Error Handling

```swift
/// Docker API error types
public enum DockerAPIError: Error, LocalizedError, Sendable {
    case connectionFailed
    case unauthorized
    case notFound(String)
    case conflict(String)
    case serverError(String)
    case invalidURL
    case invalidResponse
    case invalidConfiguration(String)
    case unexpectedStatus(Int)
    case networkTimeout
    case notImplemented(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to Docker daemon"
        case .unauthorized:
            return "Unauthorized: Check your credentials"
        case .notFound(let resource):
            return "\(resource) not found"
        case .conflict(let message):
            return message
        case .serverError(let message):
            return "Docker daemon error: \(message)"
        case .invalidURL:
            return "Invalid Docker host URL"
        case .invalidResponse:
            return "Invalid response from Docker daemon"
        case .invalidConfiguration(let message):
            return "Configuration error: \(message)"
        case .unexpectedStatus(let code):
            return "Unexpected HTTP status: \(code)"
        case .networkTimeout:
            return "Connection timed out"
        case .notImplemented(let feature):
            return "\(feature) is not yet implemented"
        }
    }
}
```

## 6.3 Fetch Strategy Pattern

Following CodexBar's strategy pattern:

```swift
/// Protocol for container fetch strategies
public protocol ContainerFetchStrategy: Sendable {
    var id: String { get }
    var kind: ConnectionType { get }
    func isAvailable(host: DockerHost) async -> Bool
    func createClient(host: DockerHost) throws -> DockerAPIClient
}

/// Unix socket strategy (local Docker)
public struct UnixSocketStrategy: ContainerFetchStrategy {
    public let id = "unix-socket"
    public let kind = ConnectionType.unixSocket

    public func isAvailable(host: DockerHost) async -> Bool {
        guard let path = host.socketPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    public func createClient(host: DockerHost) throws -> DockerAPIClient {
        try DockerAPIClientImpl(host: host)
    }
}

/// TCP + TLS strategy (remote Docker)
public struct TcpTlsStrategy: ContainerFetchStrategy {
    public let id = "tcp-tls"
    public let kind = ConnectionType.tcpTLS

    public func isAvailable(host: DockerHost) async -> Bool {
        host.host != nil && host.port != nil
    }

    public func createClient(host: DockerHost) throws -> DockerAPIClient {
        try DockerAPIClientImpl(host: host)
    }
}

/// Container fetcher with strategy-based fallback
public final class ContainerFetcher: Sendable {
    private let strategies: [ContainerFetchStrategy]
    private let credentialManager: CredentialManager

    public init(
        strategies: [ContainerFetchStrategy] = [UnixSocketStrategy(), TcpTlsStrategy()],
        credentialManager: CredentialManager
    ) {
        self.strategies = strategies
        self.credentialManager = credentialManager
    }

    public func fetchAll(for host: DockerHost) async throws -> ContainerFetchResult {
        for strategy in strategies where strategy.kind == host.connectionType {
            guard await strategy.isAvailable(host: host) else { continue }

            let client = try strategy.createClient(host: host)
            try await client.ping()

            let containers = try await client.listContainers(all: true)
            var stats: [String: ContainerStats] = [:]

            // Fetch stats for running containers in parallel
            await withTaskGroup(of: (String, ContainerStats?).self) { group in
                for container in containers where container.state == .running {
                    group.addTask {
                        do {
                            var latestStats: ContainerStats?
                            for try await stat in try await client.getContainerStats(id: container.id, stream: false) {
                                latestStats = stat
                                break  // Only need one snapshot when not streaming
                            }
                            return (container.id, latestStats)
                        } catch {
                            return (container.id, nil)
                        }
                    }
                }

                for await (id, stat) in group {
                    if let stat {
                        stats[id] = stat
                    }
                }
            }

            let metrics = buildMetricsSnapshot(containers: containers, stats: stats)
            return ContainerFetchResult(containers: containers, stats: stats, metrics: metrics)
        }

        throw DockerAPIError.connectionFailed
    }

    private func buildMetricsSnapshot(
        containers: [DockerContainer],
        stats: [String: ContainerStats]
    ) -> ContainerMetricsSnapshot {
        let statsList = Array(stats.values)
        let totalCPU = statsList.reduce(0.0) { $0 + $1.cpuPercent }
        let totalMemUsed = statsList.reduce(UInt64(0)) { $0 + $1.memoryUsageBytes }
        let totalMemLimit = statsList.reduce(UInt64(0)) { $0 + $1.memoryLimitBytes }

        return ContainerMetricsSnapshot(
            containers: statsList,
            totalCPUPercent: totalCPU,
            totalMemoryUsedBytes: totalMemUsed,
            totalMemoryLimitBytes: totalMemLimit,
            runningCount: containers.filter { $0.state == .running }.count,
            stoppedCount: containers.filter { $0.state == .exited }.count,
            pausedCount: containers.filter { $0.state == .paused }.count,
            totalCount: containers.count,
            updatedAt: Date()
        )
    }
}

public struct ContainerFetchResult: Sendable {
    public let containers: [DockerContainer]
    public let stats: [String: ContainerStats]
    public let metrics: ContainerMetricsSnapshot
}
```

---

# Section 7: Real-time Updates

## 7.1 Update Strategy

### Polling-based Updates

DockerBar uses a polling approach with configurable intervals:

| Setting | Interval | Use Case |
|---------|----------|----------|
| Fast | 5 seconds | Active monitoring |
| Normal | 10 seconds | Default |
| Slow | 30 seconds | Background awareness |
| Idle | 1-5 minutes | Low-priority monitoring |
| Manual | On-demand | Battery conservation |

### Streaming Stats (Optional Enhancement)

For real-time metrics, the Docker API supports streaming stats:

```swift
func startStatsStreaming(containerId: String) async {
    statsStreamTask = Task {
        do {
            for try await stats in try await client.getContainerStats(id: containerId, stream: true) {
                await MainActor.run {
                    self.containerStore.stats[containerId] = stats
                }
            }
        } catch {
            // Handle stream disconnection
            await retryStreaming(containerId: containerId)
        }
    }
}
```

## 7.2 Efficient Delta Updates

```swift
@MainActor
func applyDelta(newContainers: [DockerContainer]) {
    let oldSet = Set(containers.map(\.id))
    let newSet = Set(newContainers.map(\.id))

    // Removed containers
    let removed = oldSet.subtracting(newSet)
    containers.removeAll { removed.contains($0.id) }
    stats = stats.filter { !removed.contains($0.key) }

    // Added containers
    let added = newSet.subtracting(oldSet)
    let addedContainers = newContainers.filter { added.contains($0.id) }
    containers.append(contentsOf: addedContainers)

    // Updated containers
    for newContainer in newContainers {
        if let index = containers.firstIndex(where: { $0.id == newContainer.id }) {
            if containers[index] != newContainer {
                containers[index] = newContainer
            }
        }
    }
}
```

## 7.3 Background vs Foreground Behavior

```swift
func handleAppStateChange(isActive: Bool) {
    if isActive {
        // Resume normal refresh rate
        startTimer()
        Task { await refresh(force: true) }
    } else {
        // Reduce refresh rate in background
        timerTask?.cancel()
        startBackgroundTimer()  // 5 minute interval
    }
}
```

---

# Section 8: Settings & Configuration

## 8.1 Configuration Data Model

```swift
struct AppConfiguration: Codable {
    var dockerHosts: [DockerHost]
    var selectedHostId: UUID?
    var refreshInterval: RefreshInterval
    var showStoppedContainers: Bool
    var launchAtLogin: Bool
    var iconStyle: IconStyle
    var globalHotkeyEnabled: Bool
    var globalHotkey: KeyboardShortcut?
    var debugModeEnabled: Bool
}
```

## 8.2 Persistence Strategy

| Data Type | Storage Location | Rationale |
|-----------|------------------|-----------|
| App preferences | UserDefaults | Fast access, automatic sync |
| Docker hosts (non-sensitive) | UserDefaults | Simple structure |
| TLS certificates | Keychain | Security-sensitive |
| SSH private keys | Keychain | Security-sensitive |
| Passwords | Keychain | Never stored in plain text |

### Credential Manager

```swift
final class CredentialManager: @unchecked Sendable {
    private let keychain = Keychain(service: "com.dockerbar")

    func storeTLSCertificate(_ cert: Data, for hostId: UUID) throws {
        try keychain.set(cert, key: "tls-cert-\(hostId.uuidString)")
    }

    func getTLSCertificate(for hostId: UUID) throws -> Data? {
        try keychain.getData("tls-cert-\(hostId.uuidString)")
    }

    func storeSSHKey(_ key: Data, for hostId: UUID) throws {
        try keychain.set(key, key: "ssh-key-\(hostId.uuidString)")
    }

    func getSSHKey(for hostId: UUID) throws -> Data? {
        try keychain.getData("ssh-key-\(hostId.uuidString)")
    }

    func deleteCredentials(for hostId: UUID) throws {
        try? keychain.remove("tls-cert-\(hostId.uuidString)")
        try? keychain.remove("tls-key-\(hostId.uuidString)")
        try? keychain.remove("tls-ca-\(hostId.uuidString)")
        try? keychain.remove("ssh-key-\(hostId.uuidString)")
    }
}
```

---

# Section 9: Build & Development Setup

## 9.1 Development Environment

### Prerequisites

```bash
# Required
xcode-select --install  # Xcode Command Line Tools 15.0+
swift --version         # Swift 6.0+

# Recommended
brew install swiftformat swiftlint

# For releases
brew install sparkle    # For sign_update, generate_appcast
```

### Build Commands

```bash
# Development build (single architecture)
swift build

# Release build (universal binary)
swift build -c release --arch arm64
swift build -c release --arch x86_64

# Run tests
swift test

# Format code
swiftformat .

# Lint
swiftlint
```

## 9.2 Project Structure

```
DockerBar/
├── Package.swift
├── Sources/
│   ├── DockerBar/                    # Main macOS app
│   │   ├── DockerBarApp.swift        # App entry point
│   │   ├── AppDelegate.swift         # NSApplicationDelegate
│   │   ├── StatusItemController.swift # Menu bar management
│   │   ├── ContainerStore.swift      # State management
│   │   ├── SettingsStore.swift       # Preferences
│   │   ├── IconRenderer.swift        # Menu bar icon rendering
│   │   ├── Views/
│   │   │   ├── ContainerMenuCardView.swift
│   │   │   ├── MetricProgressBar.swift
│   │   │   ├── ContainerRowView.swift
│   │   │   ├── SettingsWindow.swift
│   │   │   ├── ConnectionSettingsPane.swift
│   │   │   └── GeneralSettingsPane.swift
│   │   └── Resources/
│   │       ├── Assets.xcassets
│   │       └── Localizable.strings
│   ├── DockerBarCore/                # Business logic (shared)
│   │   ├── Models/
│   │   │   ├── DockerContainer.swift
│   │   │   ├── ContainerStats.swift
│   │   │   ├── DockerHost.swift
│   │   │   └── Errors.swift
│   │   ├── API/
│   │   │   ├── DockerAPIClient.swift
│   │   │   ├── UnixSocketURLProtocol.swift
│   │   │   └── DockerRawStats.swift
│   │   ├── Services/
│   │   │   ├── ContainerFetcher.swift
│   │   │   ├── CredentialManager.swift
│   │   │   └── ConsecutiveFailureGate.swift
│   │   └── Strategies/
│   │       ├── ContainerFetchStrategy.swift
│   │       ├── UnixSocketStrategy.swift
│   │       └── TcpTlsStrategy.swift
│   └── DockerBarCLI/                 # CLI tool (future)
│       └── main.swift
├── Tests/
│   ├── DockerBarTests/
│   │   ├── ContainerStoreTests.swift
│   │   ├── DockerAPIClientTests.swift
│   │   └── Mocks/
│   │       └── MockDockerAPIClient.swift
│   └── DockerBarCoreTests/
│       ├── ContainerParsingTests.swift
│       └── StatsParsingTests.swift
├── Scripts/
│   ├── compile_and_run.sh
│   ├── package_app.sh
│   ├── sign-and-notarize.sh
│   └── version.env
└── docs/
    └── DESIGN_DOCUMENT.md
```

## 9.3 Build Scripts

### compile_and_run.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-debug}"
source "$(dirname "$0")/version.env"

echo "Building DockerBar ($CONFIG)..."
swift build -c "$CONFIG"

echo "Packaging app..."
./Scripts/package_app.sh "$CONFIG"

echo "Signing (ad-hoc)..."
codesign --force --sign - "DockerBar.app"

echo "Launching..."
open "DockerBar.app"
```

### version.env

```bash
MARKETING_VERSION=1.0.0
BUILD_NUMBER=1
BUNDLE_ID=com.yourcompany.dockerbar
```

---

# Section 10: Implementation Roadmap

## Phase 1: MVP Foundation (Weeks 1-2)

### Sprint 1: Core Infrastructure

- [ ] Create Swift package structure with DockerBar and DockerBarCore targets
- [ ] Implement basic menu bar status item with NSStatusItem
- [ ] Create DockerAPIClient with Unix socket support
- [ ] Implement container listing (`/containers/json`)
- [ ] Build ContainerStore with @Observable pattern
- [ ] Create basic container list view in dropdown menu

### Sprint 2: Container Management

- [ ] Implement container stats retrieval (`/containers/{id}/stats`)
- [ ] Add start/stop/restart container actions
- [ ] Build container detail card with metrics
- [ ] Implement SettingsStore with UserDefaults persistence
- [ ] Create connection settings pane for host configuration
- [ ] Add Keychain integration for credential storage

## Phase 2: Polish & Remote Support (Weeks 3-4)

### Sprint 3: Remote Docker

- [ ] Implement TCP + TLS connection type
- [ ] Add TLS certificate management in Keychain
- [ ] Build connection test functionality
- [ ] Implement auto-refresh timer with configurable interval
- [ ] Add ConsecutiveFailureGate for error resilience

### Sprint 4: UI Polish

- [ ] Implement dynamic menu bar icon rendering
- [ ] Add container log viewing (open in window)
- [ ] Create remove container action with confirmation
- [ ] Build preferences window with all settings panes
- [ ] Add keyboard shortcuts (global hotkey, in-app shortcuts)
- [ ] Implement launch at login functionality

## Phase 3: Testing & Release (Weeks 5-6)

### Sprint 5: Quality Assurance

- [ ] Write unit tests for API client
- [ ] Create mock Docker API responses
- [ ] Test with real Docker daemon (local and remote)
- [ ] Performance testing (memory, CPU, latency)
- [ ] Error handling edge cases

### Sprint 6: Release Preparation

- [ ] Set up code signing with Developer ID
- [ ] Implement Apple notarization workflow
- [ ] Create Sparkle appcast for auto-updates
- [ ] Write README and user documentation
- [ ] Prepare for initial release

## Future Phases

### Phase 4: Enhanced Features

- Multi-host support (manage multiple Docker servers)
- SSH tunnel connection type
- Container creation from images
- Image management (pull/list/remove)

### Phase 5: Advanced Features

- Kubernetes cluster monitoring
- Podman support
- WidgetKit extension
- Alerts and notifications

---

# Section 11: Key Design Decisions

## Decision 1: Swift/Native vs. Electron

**Choice**: Native Swift + SwiftUI/AppKit

**Rationale**:
- CodexBar demonstrates excellent native macOS integration
- Menu bar applications require tight AppKit integration
- Better performance (<50MB memory vs. 200MB+ for Electron)
- Native Keychain access for secure credential storage
- macOS design language consistency

**Trade-offs**: Platform-specific (macOS only), but this is the target platform

## Decision 2: Direct Docker API vs. Docker CLI

**Choice**: Direct Docker Engine API (REST over HTTP/Unix socket)

**Rationale**:
- Full control over requests and responses
- Real-time streaming stats support
- No dependency on Docker CLI installation
- Consistent behavior across environments

**Trade-offs**: More implementation effort, but more reliable

## Decision 3: Polling vs. Streaming

**Choice**: Polling with optional streaming for stats

**Rationale**:
- Polling is simpler and sufficient for container list updates
- Streaming stats useful for real-time metrics (optional enhancement)
- Configurable refresh interval balances freshness vs. resources
- Following CodexBar's proven polling pattern

**Trade-offs**: Slight latency (5-30 seconds) acceptable for monitoring use case

## Decision 4: SwiftUI + AppKit Hybrid

**Choice**: AppKit for menu bar, SwiftUI for views

**Rationale**:
- NSStatusItem requires AppKit
- SwiftUI provides modern, declarative UI for menu content and settings
- Same hybrid approach as CodexBar, proven to work well
- Best of both worlds

## Decision 5: Observable Pattern for State

**Choice**: Swift Observation framework (@Observable)

**Rationale**:
- Modern Swift pattern, matches CodexBar's approach
- Automatic UI updates on state changes
- Thread-safe with @MainActor isolation
- Clean separation of concerns

---

# Section 12: Security Considerations

## 12.1 Credential Storage

All sensitive credentials are stored in macOS Keychain:

| Credential Type | Keychain Service | Keychain Account |
|-----------------|------------------|------------------|
| TLS Certificate | com.dockerbar | tls-cert-{hostId} |
| TLS Private Key | com.dockerbar | tls-key-{hostId} |
| TLS CA Bundle | com.dockerbar | tls-ca-{hostId} |
| SSH Private Key | com.dockerbar | ssh-key-{hostId} |

**Never Stored**:
- Passwords in UserDefaults
- Certificates in plain files
- Private keys in memory longer than needed

## 12.2 Network Security

### TLS Requirements

```swift
// Enforce minimum TLS 1.2
let config = URLSessionConfiguration.default
config.tlsMinimumSupportedProtocolVersion = .TLSv12

// Certificate validation
func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
) {
    guard let serverTrust = challenge.protectionSpace.serverTrust,
          let expectedCert = loadExpectedCertificate() else {
        completionHandler(.cancelAuthenticationChallenge, nil)
        return
    }

    // Pin to expected certificate
    if validateCertificate(serverTrust, against: expectedCert) {
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    } else {
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
```

### SSH Tunnel (Phase 2)

- Use libssh2 or Network.framework NWProtocolSSH
- Verify host key fingerprint
- Support Ed25519 and RSA keys

## 12.3 App Sandbox Considerations

DockerBar requires:
- Network access (com.apple.security.network.client)
- Keychain access (automatic for signed apps)
- File system access for Unix socket (/var/run/docker.sock)

**Note**: Full sandbox may not be possible due to Unix socket access. Consider hardened runtime without full sandbox.

---

# Section 13: User Experience Guidelines

## 13.1 Interaction Patterns

### Quick Access

- **Single click**: Open dropdown menu with container list
- **Right-click** (or Control-click): Context menu for quick actions
- **Keyboard shortcut**: Global hotkey to open menu (configurable)

### Visual Feedback

```swift
// Loading state
func showRefreshing() {
    statusItem.button?.image = IconRenderer.icon(isRefreshing: true)
    // Animate icon or show spinner
}

// Success
func showConnected() {
    statusItem.button?.image = IconRenderer.icon(health: .healthy)
}

// Error
func showConnectionError() {
    statusItem.button?.image = IconRenderer.icon(health: .critical)
    // Show error badge or dimmed icon
}
```

### Confirmation Dialogs

Required for destructive actions:

```swift
func confirmRemoveContainer(name: String) async -> Bool {
    let alert = NSAlert()
    alert.messageText = "Remove Container?"
    alert.informativeText = "Are you sure you want to remove '\(name)'? This action cannot be undone."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Remove")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()
    return response == .alertFirstButtonReturn
}
```

## 13.2 Visual Design

### Color Coding

| State | Color | Hex |
|-------|-------|-----|
| Running | Green | #34C759 |
| Stopped | Red | #FF3B30 |
| Paused | Yellow | #FFCC00 |
| Restarting | Orange | #FF9500 |
| Created | Gray | #8E8E93 |

### Typography (Following macOS HIG)

| Element | Font | Size |
|---------|------|------|
| Container name | SF Pro Text Semibold | 13pt |
| Status label | SF Pro Text Regular | 11pt |
| Metrics | SF Pro Text Mono | 11pt |
| Section header | SF Pro Text Medium | 12pt |

## 13.3 Accessibility

```swift
ContainerRowView(container: container)
    .accessibilityLabel("\(container.displayName), \(container.state.rawValue)")
    .accessibilityHint("Double-click to show actions")
    .accessibilityValue(container.state == .running ?
        "CPU \(stats?.cpuPercent ?? 0) percent, Memory \(stats?.memoryPercent ?? 0) percent" :
        "Not running")
```

### VoiceOver Support

- All interactive elements labeled
- State changes announced
- Keyboard navigation for all menu items

---

# Section 14: Testing & Validation

## 14.1 Test Environment

### Local Testing

```bash
# Start local Docker daemon
docker info

# Create test containers
docker run -d --name test-nginx nginx
docker run -d --name test-redis redis
docker run -d --name test-postgres -e POSTGRES_PASSWORD=test postgres
```

### Remote Testing

- Configure remote Docker daemon with TLS
- Test with 12 containers on Beelink server
- Verify across network conditions

## 14.2 Test Scenarios

### Functional Tests

| # | Scenario | Expected Result |
|---|----------|-----------------|
| 1 | Connect to local Docker | Shows container list |
| 2 | Connect to remote Docker via TLS | Successful connection |
| 3 | Display all containers | Correct count and states |
| 4 | Start stopped container | State changes to running |
| 5 | Stop running container | State changes to exited |
| 6 | Restart container | Brief restart, back to running |
| 7 | View container logs | Log window opens with content |
| 8 | Remove container (with confirmation) | Container removed from list |
| 9 | Handle connection loss | Error message, retry option |
| 10 | Auto-refresh | Stats update at interval |

### Edge Cases

- Docker daemon restart during connection
- Container crash while monitoring
- Network timeout during API call
- Invalid TLS certificate
- Large number of containers (100+)
- Long container names

## 14.3 Performance Benchmarks

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Menu open latency | <100ms | Time from click to render |
| Stats update latency | <1s | Time from API response to UI |
| Memory footprint | <50MB | Activity Monitor |
| CPU idle | <1% | Activity Monitor |
| CPU during refresh | <5% | Activity Monitor |

### Unit Test Examples

```swift
final class ContainerStoreTests: XCTestCase {
    var store: ContainerStore!
    var mockFetcher: MockContainerFetcher!

    override func setUp() {
        mockFetcher = MockContainerFetcher()
        store = ContainerStore(fetcher: mockFetcher, settings: SettingsStore())
    }

    func testRefreshUpdatesContainers() async {
        mockFetcher.mockContainers = [
            DockerContainer.mock(id: "abc123", name: "test", state: .running)
        ]

        await store.refresh()

        XCTAssertEqual(store.containers.count, 1)
        XCTAssertEqual(store.containers.first?.id, "abc123")
        XCTAssertTrue(store.isConnected)
    }

    func testRefreshHandlesError() async {
        mockFetcher.shouldFail = true

        await store.refresh()

        XCTAssertFalse(store.isConnected)
        XCTAssertNotNil(store.connectionError)
    }

    func testFailureGateIgnoresFirstFailure() async {
        // First successful fetch
        mockFetcher.mockContainers = [DockerContainer.mock()]
        await store.refresh()
        XCTAssertTrue(store.isConnected)

        // First failure - should keep old data
        mockFetcher.shouldFail = true
        await store.refresh()

        // Old data preserved, no error surfaced yet
        XCTAssertEqual(store.containers.count, 1)
        XCTAssertNil(store.connectionError)

        // Second failure - now surface error
        await store.refresh()
        XCTAssertNotNil(store.connectionError)
    }
}
```

---

# Section 15: Documentation Requirements

## 15.1 Code Documentation

### Required Documentation

- All public types and functions have doc comments
- Complex algorithms explained inline
- Non-obvious design decisions documented

### Example

```swift
/// Fetches container data using the configured fetch strategy.
///
/// This method implements a fallback pattern similar to CodexBar's provider fetch system.
/// It tries each configured strategy in order until one succeeds.
///
/// - Parameters:
///   - host: The Docker host configuration to connect to
/// - Returns: A `ContainerFetchResult` containing containers, stats, and aggregated metrics
/// - Throws: `DockerAPIError` if all strategies fail
public func fetchAll(for host: DockerHost) async throws -> ContainerFetchResult {
    // Implementation...
}
```

## 15.2 User Documentation

### README.md

```markdown
# DockerBar

A lightweight macOS menu bar application for Docker container monitoring.

## Features

- Real-time container status in your menu bar
- Start, stop, restart containers with one click
- View CPU, memory, and network metrics
- Secure remote Docker connections via TLS

## Installation

### Homebrew

```bash
brew install --cask dockerbar
```

### Manual

1. Download the latest release from GitHub
2. Move DockerBar.app to /Applications
3. Launch and configure your Docker host

## Configuration

### Local Docker

DockerBar automatically connects to `/var/run/docker.sock` for local Docker.

### Remote Docker (TLS)

1. Open Settings (⌘,)
2. Click "Add Host"
3. Enter host details and TLS certificates
4. Click "Test Connection"
5. Save

## Keyboard Shortcuts

- ⌘R: Refresh
- ⌘,: Open Settings
- ⌘Q: Quit
```

### Troubleshooting Guide

```markdown
# Troubleshooting

## Connection Issues

### "Failed to connect to Docker daemon"

**Local Docker:**
- Ensure Docker Desktop is running
- Check socket permissions: `ls -la /var/run/docker.sock`

**Remote Docker:**
- Verify host is reachable: `ping <host>`
- Check TLS certificates are valid
- Ensure Docker daemon is listening on configured port

### "Unauthorized"

- TLS certificates may be expired
- Regenerate certificates on Docker host

## Performance Issues

### High CPU Usage

- Increase refresh interval in Settings
- Check number of running containers

### Slow Menu Opening

- Reduce number of displayed containers
- Check network latency to remote host
```

---

# Appendix A: CodexBar Pattern Mapping Summary

| CodexBar Component | DockerBar Equivalent | Adaptation Notes |
|--------------------|----------------------|------------------|
| `UsageProvider` enum | `DockerSource` enum | Simplified to Unix/TLS/SSH |
| `ProviderDescriptor` | `DockerSourceDescriptor` | Same structure, different metadata |
| `ProviderFetchStrategy` | `ContainerFetchStrategy` | Same pattern, Docker API calls |
| `UsageSnapshot` | `ContainerMetricsSnapshot` | Containers instead of usage percentages |
| `RateWindow` | N/A | Not applicable to container metrics |
| `UsageStore` | `ContainerStore` | Same @Observable pattern |
| `SettingsStore` | `SettingsStore` | Same persistence pattern |
| `StatusItemController` | `StatusItemController` | Same menu bar management |
| `IconRenderer` | `DockerIconRenderer` | Container-specific visuals |
| `MenuCardView` | `ContainerMenuCardView` | Containers instead of providers |
| `UsageProgressBar` | `MetricProgressBar` | Same component, different labels |
| `ConsecutiveFailureGate` | `ConsecutiveFailureGate` | Direct reuse |
| `KeychainCacheStore` | `CredentialManager` | Same Keychain integration |

---

# Appendix B: Docker API Reference

## Required Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/_ping` | Health check |
| GET | `/containers/json` | List containers |
| GET | `/containers/{id}/json` | Container details |
| GET | `/containers/{id}/stats` | Container statistics |
| POST | `/containers/{id}/start` | Start container |
| POST | `/containers/{id}/stop` | Stop container |
| POST | `/containers/{id}/restart` | Restart container |
| DELETE | `/containers/{id}` | Remove container |
| GET | `/containers/{id}/logs` | Container logs |
| GET | `/info` | System information |

## API Version

Target Docker Engine API v1.43+ (Docker 24.0+)

Add header: `Api-Version: 1.43`

---

**Document End**

This design document provides a complete blueprint for implementing DockerBar. An implementing agent should be able to build the entire application using only this document as reference, following the patterns and specifications described herein.
