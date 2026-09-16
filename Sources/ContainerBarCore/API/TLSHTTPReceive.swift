import Foundation
import Network

/// Reads a complete HTTP/1.1 response off an `NWConnection`.
///
/// This is a thin transport driver: it pulls bytes with `receiveChunk` and
/// feeds them into `IncrementalHTTPResponseParser`, which owns all framing and
/// parsing. A clean connection close is mapped to the parser's `finish()`,
/// which yields a buffered response or the matching truncation error.
///
/// Shared by both the Unix-socket and TLS transports despite the `TLS`-prefixed
/// helper names in this layer.
func receiveHTTPResponse(conn: NWConnection) async throws -> HTTPResponse {
    var parser = IncrementalHTTPResponseParser()

    while true {
        let chunk = try await receiveChunk(conn: conn, length: 8192)

        if chunk.isEmpty {
            return try parser.finish()
        }

        parser.append(chunk)
        if let response = try parser.parse() {
            return response
        }
    }
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

func validateTLSHTTPFraming(_ headers: [String: String]) throws {
    if headers["content-length"] != nil,
       headers["transfer-encoding"]?.lowercased() == "chunked" {
        throw DockerAPIError.invalidResponse
    }
}

func parseTLSContentLength(_ value: String, maxBodySize: Int = defaultMaxHTTPBodySize) throws -> Int {
    guard !value.isEmpty,
          value.allSatisfy({ $0.isNumber }),
          let contentLength = Int(value),
          maxBodySize >= 0,
          contentLength <= maxBodySize else {
        throw DockerAPIError.invalidResponse
    }

    return contentLength
}
