import Foundation

// Settings option value types persisted by `SettingsStore`. Kept in their own
// file so the store body stays focused on state and persistence.

/// Refresh interval options
public enum RefreshInterval: String, CaseIterable, Sendable {
    case seconds5 = "5s"
    case seconds10 = "10s"
    case seconds30 = "30s"
    case minute1 = "1m"
    case minutes5 = "5m"
    case manual = "manual"

    public var seconds: TimeInterval? {
        switch self {
        case .seconds5: return 5
        case .seconds10: return 10
        case .seconds30: return 30
        case .minute1: return 60
        case .minutes5: return 300
        case .manual: return nil
        }
    }

    public var displayName: String {
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

/// Menu bar icon display styles
public enum IconStyle: String, CaseIterable, Sendable {
    case containerCount
    case cpuMemoryBars
    case healthIndicator

    public var displayName: String {
        switch self {
        case .containerCount: return "Container Count"
        case .cpuMemoryBars: return "CPU + Memory Bars"
        case .healthIndicator: return "Health Indicator"
        }
    }
}
