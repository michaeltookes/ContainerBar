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
            if error is HTTPRequestNotSentError {
                try await ensureTLSConnected()
                return try await tls.sendRequest(request)
            }
            guard shouldRetryTLSRequest(after: error) else {
                throw error
            }
            guard request.allowsRetryAfterSend else {
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
        try await ensureConnected(
            isConnected: {
                try await tls.isConnectedState()
            },
            connect: {
                try await tls.connect()
            }
        )
    }

    func reconnect(_ tls: TLSConnection) async throws {
        try await reconnect(
            disconnect: {
                try await tls.disconnect()
            },
            connect: {
                try await tls.connect()
            }
        )
    }

    func ensureConnected(
        isConnected: @escaping @Sendable () async throws -> Bool,
        connect: @escaping @Sendable () async throws -> Void
    ) async throws {
        guard try await !isConnected() else {
            return
        }

        try await runConnectTask(taskID: UUID(), allowReuse: true, connect)
    }

    func reconnect(
        disconnect: @escaping @Sendable () async throws -> Void,
        connect: @escaping @Sendable () async throws -> Void
    ) async throws {
        if let connectTask {
            return try await connectTask.value
        }

        try await runConnectTask(taskID: UUID(), allowReuse: false) {
            try await disconnect()
            try await connect()
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
