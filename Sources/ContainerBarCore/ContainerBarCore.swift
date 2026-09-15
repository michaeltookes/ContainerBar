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
/// // Connect to the local Docker daemon over its Unix socket
/// let client = try DockerAPIClientImpl.local()
///
/// // Fetch containers
/// let containers = try await client.listContainers(all: true)
/// ```

import Foundation
