import Foundation
import Testing
@testable import ContainerBarCore

/// Error and size-limit behavior of `IncrementalHTTPResponseParser`. The limit
/// paths use injected caps so they can be exercised cheaply; production defaults
/// are unchanged.
@Suite("Incremental HTTP Response Parser Limits")
struct IncrementalHTTPResponseParserLimitTests {

    // MARK: - Helpers

    /// Feeds fragments, then a clean stream close, returning the error thrown by
    /// `parse()` (mid-stream) or `finish()` (at close), or `nil` on success.
    private func captureError(
        _ fragments: [Data],
        parser: inout IncrementalHTTPResponseParser
    ) -> DockerAPIError? {
        do {
            for fragment in fragments {
                parser.append(fragment)
                if try parser.parse() != nil {
                    return nil
                }
            }
            _ = try parser.finish()
            return nil
        } catch let error as DockerAPIError {
            return error
        } catch {
            return nil
        }
    }

    private func captureError(_ fragments: [Data]) -> DockerAPIError? {
        var parser = IncrementalHTTPResponseParser()
        return captureError(fragments, parser: &parser)
    }

    private func isInvalidResponse(_ error: DockerAPIError?) -> Bool {
        if case .invalidResponse = error { return true }
        return false
    }

    private func isConnectionFailed(_ error: DockerAPIError?, containing text: String) -> Bool {
        if case .tlsConnectionFailed(let message) = error {
            return message.contains(text)
        }
        return false
    }

    // MARK: - Malformed status line

    @Test("Missing status code is rejected")
    func malformedStatusMissingCode() {
        let error = captureError([Data("HTTP/1.1\r\n\r\n".utf8)])
        #expect(isInvalidResponse(error))
    }

    @Test("Non-numeric status code is rejected")
    func malformedStatusNonNumeric() {
        let error = captureError([Data("HTTP/1.1 XX OK\r\n\r\n".utf8)])
        #expect(isInvalidResponse(error))
    }

    @Test("Empty status line is rejected")
    func malformedStatusEmpty() {
        let error = captureError([Data("\r\n\r\n".utf8)])
        #expect(isInvalidResponse(error))
    }

    // MARK: - Truncation / premature close

    @Test("Stream closing before the header block is invalidResponse")
    func prematureCloseDuringHeaders() {
        let error = captureError([Data("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n".utf8)])
        #expect(isInvalidResponse(error))
    }

    @Test("Content-Length body cut short maps to the connection-closed error")
    func contentLengthTruncated() {
        let error = captureError([Data("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhel".utf8)])
        #expect(isConnectionFailed(error, containing: "Connection closed before receiving complete HTTP body"))
    }

    @Test("Chunked body cut short maps to the connection-closed error")
    func chunkedTruncated() {
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhel"
        let error = captureError([Data(raw.utf8)])
        #expect(isConnectionFailed(error, containing: "Connection closed before receiving complete HTTP body"))
    }

    // MARK: - Ambiguous framing

    @Test("Content-Length together with chunked transfer encoding is rejected")
    func contentLengthAndChunkedRejected() {
        let raw = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\nhello"
        let error = captureError([Data(raw.utf8)])
        #expect(isInvalidResponse(error))
    }

    // MARK: - Preserved chunked-decode semantics

    @Test("Chunk extensions are rejected (preserved decode behavior)")
    func chunkExtensionsRejected() {
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
            + "5;name=value\r\nhello\r\n0\r\n\r\n"
        let error = captureError([Data(raw.utf8)])
        #expect(isInvalidResponse(error))
    }

    @Test("Non-empty chunk trailers are rejected (preserved decode behavior)")
    func nonEmptyTrailersRejected() {
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
            + "5\r\nhello\r\n0\r\nX-Trailer: value\r\n\r\n"
        let error = captureError([Data(raw.utf8)])
        #expect(isInvalidResponse(error))
    }

    @Test("Malformed chunk size is rejected")
    func malformedChunkSizeRejected() {
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nZZ\r\nhello\r\n0\r\n\r\n"
        let error = captureError([Data(raw.utf8)])
        #expect(isInvalidResponse(error))
    }

    @Test("Chunked trailer metadata over the cap raises the metadata-limit error")
    func chunkedTrailerMetadataOverLimit() {
        var parser = IncrementalHTTPResponseParser(maxHeaderSize: 80)
        let trailers = String(repeating: "X: y\r\n", count: 16)
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\(trailers)"
        let error = captureError([Data(raw.utf8)], parser: &parser)
        #expect(isConnectionFailed(error, containing: "HTTP chunk metadata exceeded"))
    }

    // MARK: - Size limits

    @Test("Header block over the cap raises the header-limit error")
    func headerBlockOverLimit() {
        var parser = IncrementalHTTPResponseParser(maxHeaderSize: 16)
        let raw = "HTTP/1.1 200 OK\r\nX-Long-Header: some-long-value\r\n\r\n"
        let error = captureError([Data(raw.utf8)], parser: &parser)
        #expect(isConnectionFailed(error, containing: "HTTP response headers exceeded"))
    }

    @Test("Growing header stream with no boundary raises the header-limit error")
    func headerStreamOverLimitWithoutBoundary() {
        var parser = IncrementalHTTPResponseParser(maxHeaderSize: 8)
        let error = captureError([Data("HTTP/1.1 200 OK and still going".utf8)], parser: &parser)
        #expect(isConnectionFailed(error, containing: "HTTP response headers exceeded"))
    }

    @Test("Chunked body over the cap raises the body-limit error")
    func chunkedBodyOverLimit() {
        var parser = IncrementalHTTPResponseParser(maxBodySize: 4)
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n"
        let error = captureError([Data(raw.utf8)], parser: &parser)
        #expect(isConnectionFailed(error, containing: "HTTP response body exceeded"))
    }

    @Test("Content-Length over the injected body cap is rejected")
    func contentLengthOverInjectedCapRejected() {
        var parser = IncrementalHTTPResponseParser(maxBodySize: 4)
        let raw = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello"
        let error = captureError([Data(raw.utf8)], parser: &parser)
        #expect(isInvalidResponse(error))
    }

    @Test("Content-Length over the production cap is rejected as invalidResponse")
    func contentLengthOverProductionCapRejected() {
        // 128 MiB + 1, rejected by parseContentLength without allocating.
        let oversize = defaultMaxHTTPBodySize + 1
        let raw = "HTTP/1.1 200 OK\r\nContent-Length: \(oversize)\r\n\r\n"
        let error = captureError([Data(raw.utf8)])
        #expect(isInvalidResponse(error))
    }

    // MARK: - Chunk-size overflow / declared-size body cap (CB-063)

    @Test("Chunk-size line at Int.max is rejected without trapping")
    func chunkSizeAtIntMaxRejectedNoTrap() {
        // `7fffffffffffffff` == Int.max. Before the fix, `chunkSize + lineSeparator.count`
        // overflowed Int and trapped (crashing the process). It must now be rejected
        // by the declared-size body-budget guard as a thrown DockerAPIError instead.
        var parser = IncrementalHTTPResponseParser(maxBodySize: 1024)
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n7fffffffffffffff\r\n"
        let error = captureError([Data(raw.utf8)], parser: &parser)
        #expect(isConnectionFailed(error, containing: "HTTP response body exceeded"))
    }

    @Test("Chunk-size line above Int.max is rejected as invalidResponse")
    func chunkSizeAboveIntMaxRejected() {
        // `ffffffffffffffff` exceeds UInt64(Int.max); caught by the existing guard
        // in scanChunkSize before it ever reaches the body-budget check.
        var parser = IncrementalHTTPResponseParser(maxBodySize: 1024)
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nffffffffffffffff\r\n"
        let error = captureError([Data(raw.utf8)], parser: &parser)
        #expect(isInvalidResponse(error))
    }

    @Test("Single oversized chunk is rejected on the size line, before its payload is buffered")
    func oversizedChunkRejectedBeforeBuffering() {
        // maxBodySize 1024; the chunk declares 0x2000 == 8192 bytes. Feed only the
        // size line plus a few payload bytes — far fewer than the declared size.
        // The cap must fire on the declared size, not on the buffered bytes, so the
        // parse throws without ever seeing the full 8192-byte payload.
        var parser = IncrementalHTTPResponseParser(maxBodySize: 1024)
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2000\r\nabc"
        let error = captureError([Data(raw.utf8)], parser: &parser)
        #expect(isConnectionFailed(error, containing: "HTTP response body exceeded"))
    }

    @Test("Cumulative in-budget chunks are rejected at the chunk that crosses the cap")
    func cumulativeChunksOverCapRejected() {
        // maxBodySize 12. Three 5-byte chunks: 5 + 5 = 10 (ok), the third crosses 12.
        // Guards the `remaining = maxBodySize - decodedTotal` subtraction and the
        // loop invariant that decodedTotal never exceeds maxBodySize.
        var parser = IncrementalHTTPResponseParser(maxBodySize: 12)
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
            + "5\r\nhello\r\n5\r\nworld\r\n5\r\nagain\r\n0\r\n\r\n"
        let error = captureError([Data(raw.utf8)], parser: &parser)
        #expect(isConnectionFailed(error, containing: "HTTP response body exceeded"))
    }

    @Test("Normal multi-chunk body under the cap still decodes to the assembled bytes")
    func multiChunkUnderCapStillDecodes() throws {
        var parser = IncrementalHTTPResponseParser(maxBodySize: 1024)
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
            + "5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n"
        parser.append(Data(raw.utf8))
        let response = try parser.parse()
        #expect(response?.statusCode == 200)
        #expect(response?.body == Data("hello world".utf8))
    }
}
