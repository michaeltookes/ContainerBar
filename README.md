# DockerBar

A lightweight macOS menu bar application for Docker container monitoring and management.

## Overview

DockerBar provides instant access to Docker container status directly from your macOS menu bar. Monitor running containers, view real-time CPU and memory metrics, and perform quick management actions—all without opening a browser or terminal.

## Features

- **Menu Bar Access**: View container status at a glance from your menu bar
- **Real-time Metrics**: Monitor CPU, memory, and network I/O statistics
- **Quick Actions**: Start, stop, and restart containers with one click
- **Multiple Hosts**: Connect to local or remote Docker daemons
- **Secure Connections**: Support for TLS-encrypted remote connections
- **Native Experience**: Built with Swift for a true macOS-native feel

## Requirements

- macOS 14 (Sonoma) or later
- Docker Desktop or Docker daemon accessible via Unix socket
- For remote connections: Docker daemon with TLS enabled

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/yourusername/DockerBar.git
cd DockerBar

# Build the application
swift build -c release

# Run
swift run DockerBar
```

### Homebrew (Coming Soon)

```bash
brew install --cask dockerbar
```

## Usage

### Local Docker

DockerBar automatically connects to the local Docker daemon via `/var/run/docker.sock`. Simply launch the app and your containers will appear in the menu bar dropdown.

### Remote Docker (TLS)

1. Open Settings (`Cmd + ,`)
2. Click "Add Host"
3. Enter connection details and TLS certificates
4. Click "Test Connection" to verify
5. Save and select the host

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd + R` | Refresh container list |
| `Cmd + ,` | Open Settings |
| `Cmd + Q` | Quit DockerBar |

## Development

### Prerequisites

- Xcode 15.0+ (for Swift 6.0)
- Swift 6.0+
- SwiftLint (recommended)
- SwiftFormat (recommended)

### Building

```bash
# Development build
swift build

# Release build
swift build -c release

# Run tests
swift test

# Run tests with coverage
swift test --enable-code-coverage
```

### Project Structure

```
DockerBar/
├── Package.swift                 # Swift Package Manager configuration
├── Sources/
│   ├── DockerBar/               # macOS application
│   │   ├── DockerBarApp.swift   # App entry point
│   │   ├── AppDelegate.swift    # Application delegate
│   │   ├── StatusItemController.swift  # Menu bar management
│   │   ├── Stores/              # State management
│   │   └── Views/               # SwiftUI views
│   └── DockerBarCore/           # Business logic library
│       ├── Models/              # Data structures
│       ├── API/                 # Docker API client
│       ├── Services/            # Business services
│       └── Strategies/          # Connection strategies
├── Tests/
│   ├── DockerBarTests/          # App tests
│   └── DockerBarCoreTests/      # Core library tests
└── docs/
    └── DESIGN_DOCUMENT.md       # Technical specification
```

## Architecture

DockerBar follows a layered architecture:

- **UI Layer**: SwiftUI views + AppKit for menu bar integration
- **State Layer**: `@Observable` stores for reactive state management
- **Service Layer**: Business logic and Docker API abstraction
- **API Layer**: Direct Docker Engine API communication

Key patterns used:
- Provider Descriptor pattern for connection management
- Strategy pattern for different connection types
- Consecutive Failure Gate for error resilience

## Contributing

Contributions are welcome! Please read the design document at `docs/DESIGN_DOCUMENT.md` before submitting changes.

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests (`swift test`)
5. Submit a pull request

## License

[License to be determined]

## Acknowledgments

- Inspired by CodexBar's elegant menu bar architecture
- Built with Swift 6 and modern Apple frameworks
