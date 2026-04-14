import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Handles raw HTTP communication over Unix domain sockets
///
/// Synchronization: `socketLock` protects `socketFD` lifecycle state while `ioLock`
/// serializes descriptor snapshots and rotation. Blocking socket I/O runs without
/// holding `ioLock` or `socketLock`; in-flight requests rely on the generation
/// token plus `shutdown()` on invalidation to fail promptly when the descriptor rotates.
final class UnixSocketConnection: @unchecked Sendable {

    private let socketPath: String
    private var socketFD: Int32 = -1
    private var socketGeneration: UInt64 = 0
    private let socketLock = NSLock()
    private let ioLock = NSLock()

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    deinit {
        disconnect()
    }

    // MARK: - Connection Management

    /// Connect to the Unix socket
    func connect() throws {
        let (generation, existingFD) = ioLock.withLock { () -> (UInt64, Int32) in
            socketLock.withLock { () -> (UInt64, Int32) in
                socketGeneration &+= 1
                let generation = socketGeneration
                let existingFD = socketFD
                socketFD = -1
                return (generation, existingFD)
            }
        }

        invalidateSocketDescriptor(existingFD)

        // Create socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw DockerAPIError.connectionFailed
        }

        // Set up address
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        // Copy socket path to sun_path
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            invalidateSocketDescriptor(fd)
            throw DockerAPIError.invalidConfiguration("Socket path too long")
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, byte) in pathBytes.enumerated() {
                    dest[i] = byte
                }
            }
        }

        // Connect
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            let errorCode = errno
            invalidateSocketDescriptor(fd)
            if errorCode == ENOENT {
                throw DockerAPIError.socketNotFound(socketPath)
            }
            throw DockerAPIError.connectionFailed
        }

        let adopted = ioLock.withLock { () -> Bool in
            socketLock.withLock { () -> Bool in
                guard socketGeneration == generation, socketFD == -1 else {
                    return false
                }
                socketFD = fd
                return true
            }
        }

        guard adopted else {
            invalidateSocketDescriptor(fd)
            throw DockerAPIError.connectionFailed
        }
    }

    /// Disconnect from the Unix socket
    func disconnect() {
        let fd = ioLock.withLock { () -> Int32 in
            socketLock.withLock { () -> Int32 in
                socketGeneration &+= 1
                let fd = socketFD
                socketFD = -1
                return fd
            }
        }

        invalidateSocketDescriptor(fd)
    }

    // MARK: - HTTP Operations

    /// Send an HTTP request and receive the response
    func sendRequest(_ request: HTTPRequest) throws -> HTTPResponse {
        let (fd, generation) = try snapshotSocketState()

        let requestData = try request.toHTTPData(resolvedHost: "localhost") // HTTP/1.1 requires a Host header; Unix sockets have no network host, so "localhost" is the appropriate local placeholder for Docker 28.x.

        // Send request
        var totalSent = 0
        try requestData.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw DockerAPIError.invalidConfiguration("Could not access request data")
            }

            while totalSent < buffer.count {
                try ensureSocketIsCurrent(expectedGeneration: generation)
                let sent = Darwin.send(
                    fd,
                    baseAddress.advanced(by: totalSent),
                    buffer.count - totalSent,
                    0
                )

                if sent <= 0 {
                    throw DockerAPIError.connectionFailed
                }

                totalSent += sent
            }
        }

        return try receiveResponse(socketFD: fd, expectedGeneration: generation)
    }

    private func receiveResponse(socketFD: Int32, expectedGeneration: UInt64) throws -> HTTPResponse {
        var responseData = Data()
        let bufferSize = 8192

        // Read headers first
        var headersComplete = false
        var headerEndIndex = 0

        while !headersComplete {
            let chunk = try receiveChunk(socketFD: socketFD, length: bufferSize, expectedGeneration: expectedGeneration)
            guard !chunk.isEmpty else {
                break
            }

            responseData.append(chunk)

            // Check for end of headers
            if let range = responseData.range(of: HTTPResponseParser.headerSeparator) {
                headersComplete = true
                headerEndIndex = range.upperBound
            }
        }

        // Parse headers
        guard headersComplete else {
            throw DockerAPIError.invalidResponse
        }

        let headerData = responseData[0..<headerEndIndex]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw DockerAPIError.invalidResponse
        }

        let (statusCode, headers) = try HTTPResponseParser.parseStatusAndHeaders(headerString)

        // Determine how to read body
        let bodyData = try HTTPResponseParser.readBody(
            headers: headers,
            initialBody: Data(responseData[headerEndIndex...])
        ) { length in
            try self.receiveChunk(socketFD: socketFD, length: length, expectedGeneration: expectedGeneration)
        }

        return HTTPResponse(statusCode: statusCode, headers: headers, body: bodyData)
    }

    private func snapshotSocketState() throws -> (fd: Int32, generation: UInt64) {
        let state = ioLock.withLock { () -> (Int32, UInt64) in
            socketLock.withLock { (socketFD, socketGeneration) }
        }

        guard state.0 >= 0 else {
            throw DockerAPIError.connectionFailed
        }

        return (state.0, state.1)
    }

    private func ensureSocketIsCurrent(expectedGeneration: UInt64) throws {
        let isCurrent = socketLock.withLock {
            socketGeneration == expectedGeneration
        }

        guard isCurrent else {
            throw DockerAPIError.connectionFailed
        }
    }

    private func receiveChunk(socketFD: Int32, length: Int, expectedGeneration: UInt64) throws -> Data {
        try ensureSocketIsCurrent(expectedGeneration: expectedGeneration)

        var buffer = [UInt8](repeating: 0, count: max(1, length))
        let bytesRead = Darwin.recv(socketFD, &buffer, buffer.count, 0)

        guard bytesRead >= 0 else {
            throw DockerAPIError.connectionFailed
        }

        try ensureSocketIsCurrent(expectedGeneration: expectedGeneration)
        guard bytesRead > 0 else {
            return Data()
        }

        return Data(buffer[0..<bytesRead])
    }

    private func invalidateSocketDescriptor(_ fd: Int32) {
        guard fd >= 0 else {
            return
        }

        _ = Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }
}
