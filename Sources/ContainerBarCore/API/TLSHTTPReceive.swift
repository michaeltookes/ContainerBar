import Foundation
import Network

private let maxTLSHTTPHeaderSize = 64 * 1024
private let maxTLSHTTPBodySize = 128 * 1024 * 1024

/// Reads a complete HTTP/1.1 response off an `NWConnection`, honoring either
/// `Content-Length` or `Transfer-Encoding: chunked` framing.
func receiveHTTPResponse(conn: NWConnection) async throws -> Data {
    var accumulated = Data()
    let headerSeparator = Data("\r\n\r\n".utf8)
    var receiveError: Error?

    while true {
        let chunk: Data
        do {
            chunk = try await receiveChunk(conn: conn, length: 8192)
        } catch {
            receiveError = error
            break
        }

        guard !chunk.isEmpty else { break }
        accumulated.append(chunk)

        if let headerEnd = accumulated.range(of: headerSeparator) {
            guard headerEnd.lowerBound <= maxTLSHTTPHeaderSize else {
                throw DockerAPIError.tlsConnectionFailed("HTTP response headers exceeded \(maxTLSHTTPHeaderSize) bytes")
            }
            break
        }

        guard accumulated.count <= maxTLSHTTPHeaderSize else {
            throw DockerAPIError.tlsConnectionFailed("HTTP response headers exceeded \(maxTLSHTTPHeaderSize) bytes")
        }
    }

    guard let headerEnd = accumulated.range(of: headerSeparator) else {
        if let receiveError {
            throw receiveError
        }
        throw DockerAPIError.invalidResponse
    }

    let headerData = accumulated[..<headerEnd.lowerBound]
    guard headerData.count <= maxTLSHTTPHeaderSize else {
        throw DockerAPIError.tlsConnectionFailed("HTTP response headers exceeded \(maxTLSHTTPHeaderSize) bytes")
    }

    guard let headerString = String(data: headerData, encoding: .utf8) else {
        throw DockerAPIError.invalidResponse
    }

    let headers = try parseStrictTLSHeaders(headerString)
    let bodyStart = accumulated[headerEnd.upperBound...]

    if let contentLengthStr = headers["content-length"] {
        let contentLength = try parseTLSContentLength(contentLengthStr)
        var body = Data(bodyStart)

        guard body.count <= maxTLSHTTPBodySize else {
            throw DockerAPIError.tlsConnectionFailed("HTTP response body exceeded \(maxTLSHTTPBodySize) bytes")
        }

        while body.count < contentLength {
            let remaining = contentLength - body.count
            let chunk = try await receiveChunk(conn: conn, length: min(remaining, 8192))
            guard !chunk.isEmpty else {
                throw DockerAPIError.tlsConnectionFailed("Connection closed before receiving complete HTTP body")
            }
            body.append(chunk)
            guard body.count <= maxTLSHTTPBodySize else {
                throw DockerAPIError.tlsConnectionFailed("HTTP response body exceeded \(maxTLSHTTPBodySize) bytes")
            }
        }

        if body.count > contentLength {
            body = Data(body.prefix(contentLength))
        }

        return Data(accumulated[..<headerEnd.upperBound]) + body
    } else if headers["transfer-encoding"]?.lowercased() == "chunked" {
        let endMarker = Data("0\r\n\r\n".utf8)
        var body = Data(bodyStart)
        guard body.count <= maxTLSHTTPBodySize else {
            throw DockerAPIError.tlsConnectionFailed("HTTP response body exceeded \(maxTLSHTTPBodySize) bytes")
        }

        while body.range(of: endMarker) == nil {
            let chunk = try await receiveChunk(conn: conn, length: 8192)
            guard !chunk.isEmpty else {
                throw DockerAPIError.tlsConnectionFailed("Connection closed before receiving complete HTTP body")
            }
            body.append(chunk)
            guard body.count <= maxTLSHTTPBodySize else {
                throw DockerAPIError.tlsConnectionFailed("HTTP response body exceeded \(maxTLSHTTPBodySize) bytes")
            }
        }

        return Data(accumulated[..<headerEnd.upperBound]) + body
    }

    return accumulated
}

func receiveChunk(conn: NWConnection, length: Int) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
        conn.receive(minimumIncompleteLength: 1, maximumLength: length) { data, _, _, error in
            if let error {
                continuation.resume(throwing: DockerAPIError.tlsConnectionFailed("Receive failed: \(error.localizedDescription)"))
            } else {
                continuation.resume(returning: data ?? Data())
            }
        }
    }
}

func parseStrictTLSHeaders(_ headerString: String) throws -> [String: String] {
    do {
        return try HTTPResponseParser.parseStatusAndHeaders(headerString).1
    } catch {
        throw DockerAPIError.invalidResponse
    }
}

func parseTLSContentLength(_ value: String) throws -> Int {
    guard !value.isEmpty,
          value.allSatisfy({ $0.isNumber }),
          let contentLength = Int(value),
          (0...maxTLSHTTPBodySize).contains(contentLength) else {
        throw DockerAPIError.invalidResponse
    }

    return contentLength
}
