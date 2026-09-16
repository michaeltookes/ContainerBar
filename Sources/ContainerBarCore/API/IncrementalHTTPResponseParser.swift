import Foundation

/// Default maximum size of an HTTP response header block (status line + headers).
let defaultMaxHTTPHeaderSize = 64 * 1024
/// Default maximum size of an assembled HTTP response body.
let defaultMaxHTTPBodySize = 128 * 1024 * 1024

/// Incremental HTTP/1.1 response parser that turns a stream of byte fragments
/// into an `HTTPResponse`, independent of any transport.
///
/// Feed fragments with `append(_:)` then call `parse()`; it returns the parsed
/// response once the response is fully buffered, or `nil` when more bytes are
/// required. Call `finish()` when the byte stream ends to turn a premature end
/// into the appropriate error.
///
/// All framing lives here so it can be unit-tested without a socket:
/// header-boundary detection, status/header parsing, `Content-Length` and
/// chunked body assembly, the 64KB header / 128MB body size limits, and the
/// ambiguous `Content-Length` + `Transfer-Encoding: chunked` rejection.
///
/// Behavior note: for a chunked body the parser detects the frame boundary and
/// then decodes the complete raw bytes via `decodeTLSChunkedBody`, which is the
/// same decoder the previous socket-driven path used. This intentionally
/// preserves that path's observable behavior (including rejecting chunk
/// extensions and non-empty trailers as `invalidResponse`).
struct IncrementalHTTPResponseParser {
    private static let lineSeparator = Data("\r\n".utf8)
    private static let headerSeparator = Data("\r\n\r\n".utf8)

    private let maxHeaderSize: Int
    private let maxBodySize: Int

    private var buffer = Data()

    private enum BodyFraming {
        case unframed
        case contentLength(Int)
        case chunked
    }

    private var statusCode: Int?
    private var headers: [String: String] = [:]
    private var bodyStart: Data.Index?
    private var framing: BodyFraming?

    /// Chunked-body scan state carried across `parse()` calls so each new
    /// fragment only re-examines bytes after the last complete chunk frame.
    private var chunkCursor: Data.Index?
    private var chunkTrailerStart: Data.Index?
    private var chunkTrailerCursor: Data.Index?
    private var chunkDecodedTotal = 0

    /// - Parameters:
    ///   - maxHeaderSize: Header-block byte cap. Defaults to the production limit.
    ///   - maxBodySize: Assembled-body byte cap. Defaults to the production limit.
    ///     These seams exist so the limit paths can be exercised cheaply in tests;
    ///     the production defaults are unchanged.
    init(maxHeaderSize: Int = defaultMaxHTTPHeaderSize, maxBodySize: Int = defaultMaxHTTPBodySize) {
        self.maxHeaderSize = maxHeaderSize
        self.maxBodySize = maxBodySize
    }

    /// Appends a received fragment to the internal buffer.
    mutating func append(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
    }

    /// Returns the complete response if it is fully buffered, or `nil` when more
    /// bytes are needed. Throws on malformed framing or an exceeded size limit.
    mutating func parse() throws -> HTTPResponse? {
        if framing == nil {
            guard try parseHeaders() else { return nil }
        }

        guard let framing, let bodyStart, let statusCode else { return nil }
        let available = buffer[bodyStart...]

        switch framing {
        case .unframed:
            return HTTPResponse(statusCode: statusCode, headers: headers, body: Data(available))
        case .contentLength(let length):
            guard available.count >= length else { return nil }
            return HTTPResponse(statusCode: statusCode, headers: headers, body: Data(available.prefix(length)))
        case .chunked:
            guard let bodyEnd = try scanChunkedBodyEnd(available) else { return nil }
            let rawChunked = Data(available[..<bodyEnd])
            let decoded = try decodeTLSChunkedBody(rawChunked)
            return HTTPResponse(statusCode: statusCode, headers: headers, body: decoded)
        }
    }

    /// Converts the end of the byte stream into a result or the matching error:
    /// a complete response if one is buffered, `invalidResponse` if the stream
    /// ended before a full header block, otherwise the truncated-body error.
    mutating func finish() throws -> HTTPResponse {
        if let response = try parse() {
            return response
        }
        if framing == nil {
            throw DockerAPIError.invalidResponse
        }
        throw DockerAPIError.tlsConnectionFailed("Connection closed before receiving complete HTTP body")
    }

    // MARK: - Headers

    private mutating func parseHeaders() throws -> Bool {
        guard let headerRange = buffer.range(of: Self.headerSeparator) else {
            if buffer.count > maxHeaderSize {
                throw DockerAPIError.tlsConnectionFailed("HTTP response headers exceeded \(maxHeaderSize) bytes")
            }
            return false
        }

        guard headerRange.lowerBound <= maxHeaderSize else {
            throw DockerAPIError.tlsConnectionFailed("HTTP response headers exceeded \(maxHeaderSize) bytes")
        }

        let headerData = buffer[..<headerRange.lowerBound]
        guard let headerString = String(data: Data(headerData), encoding: .utf8) else {
            throw DockerAPIError.invalidResponse
        }

        let (code, parsedHeaders) = try HTTPResponseParser.parseStatusAndHeaders(headerString)
        try validateTLSHTTPFraming(parsedHeaders)

        statusCode = code
        headers = parsedHeaders
        bodyStart = headerRange.upperBound

        if let contentLength = parsedHeaders["content-length"] {
            framing = .contentLength(try parseTLSContentLength(contentLength, maxBodySize: maxBodySize))
        } else if parsedHeaders["transfer-encoding"]?.lowercased() == "chunked" {
            framing = .chunked
        } else {
            framing = .unframed
        }

        return true
    }

    // MARK: - Chunked framing

    /// Scans a chunked body for its terminating boundary, returning the index in
    /// `data` just past the final empty trailer line, or `nil` when more bytes
    /// are needed. Mirrors the strict framing the socket path used (hex chunk
    /// sizes, 64KB chunk-metadata cap, 128MB assembled-body cap). Resumes from
    /// the last complete frame or trailer line so repeated calls stay linear.
    private mutating func scanChunkedBodyEnd(_ data: Data) throws -> Data.Index? {
        if chunkTrailerCursor != nil {
            return try scanChunkedTrailers(in: data)
        }

        var cursor = chunkCursor ?? data.startIndex
        var decodedTotal = chunkDecodedTotal

        while true {
            guard let sizeLineEnd = data.range(of: Self.lineSeparator, in: cursor..<data.endIndex) else {
                try enforceChunkMetadataLimit(from: cursor, to: data.endIndex, in: data)
                return nil
            }

            let chunkSize = try scanChunkSize(data[cursor..<sizeLineEnd.lowerBound])
            cursor = sizeLineEnd.upperBound

            if chunkSize == 0 {
                chunkTrailerStart = cursor
                chunkTrailerCursor = cursor
                return try scanChunkedTrailers(in: data)
            }

            let need = chunkSize + Self.lineSeparator.count
            guard data.distance(from: cursor, to: data.endIndex) >= need else {
                return nil
            }

            let payloadEnd = data.index(cursor, offsetBy: chunkSize)
            let frameEnd = data.index(payloadEnd, offsetBy: Self.lineSeparator.count)
            guard data[payloadEnd..<frameEnd] == Self.lineSeparator else {
                throw DockerAPIError.invalidResponse
            }

            decodedTotal += chunkSize
            guard decodedTotal <= maxBodySize else {
                throw DockerAPIError.tlsConnectionFailed("HTTP response body exceeded \(maxBodySize) bytes")
            }

            cursor = frameEnd
            chunkCursor = cursor
            chunkDecodedTotal = decodedTotal
        }
    }

    private mutating func scanChunkedTrailers(in data: Data) throws -> Data.Index? {
        var cursor = chunkTrailerCursor ?? data.startIndex
        while true {
            guard let lineEnd = data.range(of: Self.lineSeparator, in: cursor..<data.endIndex) else {
                try enforceChunkMetadataLimit(from: chunkTrailerStart ?? cursor, to: data.endIndex, in: data)
                chunkTrailerCursor = cursor
                return nil
            }

            try enforceChunkMetadataLimit(from: chunkTrailerStart ?? cursor, to: lineEnd.upperBound, in: data)

            let isEmptyLine = lineEnd.lowerBound == cursor
            cursor = lineEnd.upperBound
            chunkTrailerCursor = cursor
            if isEmptyLine {
                return cursor
            }
        }
    }

    private func enforceChunkMetadataLimit(from start: Data.Index, to end: Data.Index, in data: Data) throws {
        if data.distance(from: start, to: end) > maxHeaderSize {
            throw DockerAPIError.tlsConnectionFailed("HTTP chunk metadata exceeded \(maxHeaderSize) bytes")
        }
    }

    private func scanChunkSize(_ lineData: Data) throws -> Int {
        guard let line = String(data: Data(lineData), encoding: .utf8) else {
            throw DockerAPIError.invalidResponse
        }

        let sizeToken = line
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !sizeToken.isEmpty,
              sizeToken.allSatisfy(\.isHexDigit),
              let chunkSize = UInt64(sizeToken, radix: 16),
              chunkSize <= UInt64(Int.max) else {
            throw DockerAPIError.invalidResponse
        }

        return Int(chunkSize)
    }
}
