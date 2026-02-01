import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Handles raw HTTP communication over Unix domain sockets
///
/// This is a low-level implementation that handles the socket connection
/// and HTTP request/response parsing for the Docker API.
final class UnixSocketConnection: @unchecked Sendable {

    private let socketPath: String
    private var socketFD: Int32 = -1

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    deinit {
        disconnect()
    }

    // MARK: - Connection Management

    /// Connect to the Unix socket
    func connect() throws {
        // Create socket
        socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw DockerAPIError.connectionFailed
        }

        // Set up address
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        // Copy socket path to sun_path
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(socketFD)
            socketFD = -1
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
                Darwin.connect(socketFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            let errorCode = errno
            Darwin.close(socketFD)
            socketFD = -1
            if errorCode == ENOENT {
                throw DockerAPIError.socketNotFound(socketPath)
            }
            throw DockerAPIError.connectionFailed
        }
    }

    /// Disconnect from the Unix socket
    func disconnect() {
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
    }

    // MARK: - HTTP Operations

    /// Send an HTTP request and receive the response
    func sendRequest(_ request: HTTPRequest) throws -> HTTPResponse {
        guard socketFD >= 0 else {
            throw DockerAPIError.connectionFailed
        }

        // Build HTTP request string
        let httpRequest = request.toHTTPString()
        guard let requestData = httpRequest.data(using: .utf8) else {
            throw DockerAPIError.invalidConfiguration("Could not encode request")
        }

        // Send request
        var totalSent = 0
        try requestData.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw DockerAPIError.invalidConfiguration("Could not access request data")
            }

            while totalSent < buffer.count {
                let sent = Darwin.send(
                    socketFD,
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

        // Receive response
        let response = try receiveResponse()
        return response
    }

    private func receiveResponse() throws -> HTTPResponse {
        var responseData = Data()
        let bufferSize = 8192
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        // Read headers first
        var headersComplete = false
        var headerEndIndex = 0

        while !headersComplete {
            let bytesRead = Darwin.recv(socketFD, &buffer, bufferSize, 0)

            if bytesRead < 0 {
                throw DockerAPIError.connectionFailed
            }

            if bytesRead == 0 {
                break
            }

            responseData.append(contentsOf: buffer[0..<bytesRead])

            // Check for end of headers
            if let range = responseData.range(of: Data("\r\n\r\n".utf8)) {
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

        let (statusCode, headers) = try parseHeaders(headerString)

        // Determine how to read body
        var bodyData = Data(responseData[headerEndIndex...])

        if let contentLength = headers["content-length"],
           let length = Int(contentLength) {
            // Read until we have content-length bytes
            while bodyData.count < length {
                let bytesRead = Darwin.recv(socketFD, &buffer, min(bufferSize, length - bodyData.count), 0)
                if bytesRead <= 0 { break }
                bodyData.append(contentsOf: buffer[0..<bytesRead])
            }
        } else if headers["transfer-encoding"]?.lowercased() == "chunked" {
            // Read chunked response
            bodyData = try readChunkedBody(initialData: bodyData)
        }

        return HTTPResponse(statusCode: statusCode, headers: headers, body: bodyData)
    }

    private func parseHeaders(_ headerString: String) throws -> (Int, [String: String]) {
        let lines = headerString.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else {
            throw DockerAPIError.invalidResponse
        }

        // Parse status line: "HTTP/1.1 200 OK"
        let statusParts = statusLine.split(separator: " ", maxSplits: 2)
        guard statusParts.count >= 2,
              let statusCode = Int(statusParts[1]) else {
            throw DockerAPIError.invalidResponse
        }

        // Parse headers
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key.lowercased()] = value
            }
        }

        return (statusCode, headers)
    }

    private func readChunkedBody(initialData: Data) throws -> Data {
        var result = Data()
        var remaining = initialData
        let bufferSize = 8192
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while true {
            // Find chunk size line
            guard let lineEnd = remaining.range(of: Data("\r\n".utf8)) else {
                // Need more data
                let bytesRead = Darwin.recv(socketFD, &buffer, bufferSize, 0)
                if bytesRead <= 0 { break }
                remaining.append(contentsOf: buffer[0..<bytesRead])
                continue
            }

            let sizeLine = remaining[..<lineEnd.lowerBound]
            guard let sizeString = String(data: sizeLine, encoding: .utf8),
                  let chunkSize = Int(sizeString.trimmingCharacters(in: .whitespaces), radix: 16) else {
                throw DockerAPIError.invalidResponse
            }

            // Move past size line
            remaining = Data(remaining[lineEnd.upperBound...])

            // End of chunks
            if chunkSize == 0 {
                break
            }

            // Read chunk data
            while remaining.count < chunkSize {
                let bytesRead = Darwin.recv(socketFD, &buffer, bufferSize, 0)
                if bytesRead <= 0 { break }
                remaining.append(contentsOf: buffer[0..<bytesRead])
            }

            // Append chunk to result
            result.append(remaining[0..<chunkSize])

            // Move past chunk data and CRLF
            if remaining.count > chunkSize + 2 {
                remaining = Data(remaining[(chunkSize + 2)...])
            } else {
                remaining = Data()
            }
        }

        return result
    }
}

// MARK: - HTTP Request/Response Types

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?

    init(method: String = "GET", path: String, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    func toHTTPString() -> String {
        var request = "\(method) \(path) HTTP/1.1\r\n"
        request += "Host: localhost\r\n"
        request += "Connection: keep-alive\r\n"

        for (key, value) in headers {
            request += "\(key): \(value)\r\n"
        }

        if let body, !body.isEmpty {
            request += "Content-Length: \(body.count)\r\n"
        }

        request += "\r\n"

        if let body, let bodyString = String(data: body, encoding: .utf8) {
            request += bodyString
        }

        return request
    }
}

struct HTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    var isSuccess: Bool {
        (200..<300).contains(statusCode)
    }
}
