# Changelog

All notable changes to ContainerBar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-02-11

### Added
- **Podman Support**: Full Podman container runtime support alongside Docker
  - Auto-detection of runtime-specific defaults (socket paths, API compatibility)
  - Runtime selector in host configuration for Docker or Podman
  - SSH connections use correct remote socket path per runtime
- **Service Icons**: Visual service type icons (database, web server, cache, etc.) displayed on container cards
- **Host Picker**: Quick host switching directly from the dashboard without navigating to Settings
- **Sparkle Auto-Updates**: Automatic update checking with in-app update notifications
- **MIT License**: Project is now open source under the MIT License

### Changed
- "Check for Updates" moved from dropdown menu to Settings > General
- Connection settings now support runtime-specific socket path defaults
- Updated General Stats card styling
- Documentation updated to reflect Docker and Podman support

### Fixed
- Service icon loading from bundled resources
- Reduced icon sizes for better visual consistency
- SSH socket path saving now persists correctly between sessions
- Force unwrap replaced with safe optional binding in SSH connection setup
- Sparkle updater disabled in debug builds to prevent signing errors

## [1.1.0] - 2025-01-31

### Added
- **New Dashboard UI**: Completely redesigned menu interface with modern card-based layout
- **Real-time Metrics Sparklines**: Visual history graphs for CPU, memory, network, and disk I/O using Swift Charts
- **Container Search**: Quick search functionality to filter containers by name, image, or ID
- **Slide-out Logs Panel**: Easy access to container logs from the bottom action bar
- **Slide-out Host Panel**: Quick host switching without navigating to settings
- **Custom Container Sections**: Organize containers into custom groups with drag-and-drop reordering
- **Connection Status Bar**: Visual indicator showing current host and container counts
- **Quick Action Bar**: Bottom toolbar with Refresh, Hosts, Logs, and Settings buttons
- **Container Cards**: Rich container display with hover effects, inline stats, and quick actions
- **New App Logo**: Fresh branding with updated application icon

### Changed
- Redesigned Settings window with native macOS toolbar style
- Container detail popover is now info-only (actions moved to hover buttons and panels)
- Menu stays open when performing Start/Stop/Restart actions
- Improved color-coded hover effects for container state indication
- Enhanced metrics tracking with historical data for sparkline visualizations

### Fixed
- Container action buttons now work reliably (moved from popover to card hover)
- Fixed potential counter underflow when calculating network/disk rates
- Improved JSON error handling in settings persistence
- Added proper accessibility labels to header buttons
- Fixed inconsistent memory limit formatting in stats display
- Added input validation for host configuration form
- Handle paused and restarting container states correctly in quick actions

## [1.0.0] - 2025-01-30

### Added
- Initial public release
- Menu bar container monitoring with real-time CPU and memory metrics
- Container actions: start, stop, restart, view logs, remove
- Container detail popover with image, ports, network info
- Local Docker Desktop support via Unix socket
- Remote Docker host support via SSH tunnel
- Multiple host management with easy switching
- Configurable refresh interval (5 seconds to 5 minutes)
- Three menu bar icon styles: Container Count, CPU/Memory Bars, Health Indicator
- Global keyboard shortcut support
- Launch at login option
- Native macOS 14+ application built with Swift and SwiftUI

[2.0.0]: https://github.com/michaeltookes/ContainerBar/releases/tag/v2.0.0
[1.1.0]: https://github.com/michaeltookes/ContainerBar/releases/tag/v1.1.0
[1.0.0]: https://github.com/michaeltookes/ContainerBar/releases/tag/v1.0.0
