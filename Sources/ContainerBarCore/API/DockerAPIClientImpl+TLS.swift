import Foundation

extension DockerAPIClientImpl {
    func performTLSRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let tls = tlsConnection else {
            throw DockerAPIError.invalidConfiguration("TLS connection not configured")
        }

        try await ensureTLSConnected()

        do {
            return try await tls.sendRequest(request)
        } catch {
            logger.warning("TLS request failed before retry: \(error.localizedDescription)")
            guard shouldRetryTLSRequest(after: error) else {
                throw error
            }
            guard request.isIdempotent else {
                throw error
            }

            try await reconnectTLSConnection()
            return try await tls.sendRequest(request)
        }
    }

    func ensureTLSConnected() async throws {
        guard let tls = tlsConnection else {
            return
        }
        try await tlsConnectCoordinator.ensureConnected(tls)
    }

    func reconnectTLSConnection() async throws {
        guard let tls = tlsConnection else {
            throw DockerAPIError.invalidConfiguration("TLS connection not configured")
        }
        try await tlsConnectCoordinator.reconnect(tls)
    }

    func shouldRetryTLSRequest(after error: Error) -> Bool {
        guard let dockerError = error as? DockerAPIError else {
            return false
        }

        switch dockerError {
        case .connectionFailed, .networkTimeout, .tlsConnectionFailed:
            return true
        default:
            return false
        }
    }
}

actor TLSConnectCoordinator {
    private var connectTask: Task<Void, Error>?
    private var connectTaskID: UUID?

    func ensureConnected(_ tls: TLSConnection) async throws {
        guard !tls.isConnected else {
            return
        }

        try await runConnectTask(taskID: UUID(), allowReuse: true) {
            try await tls.connect()
        }
    }

    func reconnect(_ tls: TLSConnection) async throws {
        if let connectTask {
            _ = try? await connectTask.value
        }
        let reconnectTaskID = UUID()

        try await runConnectTask(taskID: reconnectTaskID, allowReuse: false) {
            tls.disconnect()
            try await tls.connect()
        }
    }

    private func runConnectTask(
        taskID: UUID,
        allowReuse: Bool,
        _ operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        if allowReuse,
           let connectTask,
           connectTaskID != nil {
            return try await connectTask.value
        }

        let task = Task {
            try await operation()
        }
        connectTask = task
        connectTaskID = taskID

        do {
            try await task.value
            if connectTaskID == taskID {
                connectTask = nil
                connectTaskID = nil
            }
        } catch {
            if connectTaskID == taskID {
                connectTask = nil
                connectTaskID = nil
            }
            throw error
        }
    }
}
