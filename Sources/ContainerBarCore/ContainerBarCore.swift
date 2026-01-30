/// ContainerBarCore
///
/// Core business logic for ContainerBar - a macOS menu bar Docker monitoring app.
/// This module contains all Docker API communication, data models, and services.
/// It has no UI dependencies and can be used independently.
///
/// ## Overview
///
/// ContainerBarCore provides:
/// - **Models**: Data structures for containers, stats, hosts, and errors
/// - **API**: Docker API client protocol and implementations
/// - **Services**: Business logic for fetching and managing containers
/// - **Strategies**: Connection strategies for different Docker endpoints
///
/// ## Usage
///
/// ```swift
/// import ContainerBarCore
///
/// // Create a local Docker host configuration
/// let host = DockerHost.local
///
/// // Use a fetch strategy to create a client
/// let strategy = UnixSocketStrategy()
/// let client = try strategy.createClient(host: host)
///
/// // Fetch containers
/// let containers = try await client.listContainers(all: true)
/// ```

import Foundation
import Logging

/// Logger for ContainerBarCore operations
public let coreLogger = Logger(label: "com.containerbar.core")

/// ContainerBarCore version information
public enum ContainerBarCoreVersion {
    public static let major = 1
    public static let minor = 0
    public static let patch = 0
    public static let string = "\(major).\(minor).\(patch)"
}
