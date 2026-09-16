import Foundation
import Testing
@testable import ContainerBarCore

/// Framing/parse behavior of `IncrementalHTTPResponseParser`, exercised purely
/// against in-memory byte streams with arbitrary fragmentation (no socket).
@Suite("Incremental HTTP Response Parser")
struct IncrementalHTTPResponseParserTests {

    // MARK: - Helpers

    /// Drives the parser exactly like the transport loop: append each fragment,
    /// then `parse()`. Returns the response once complete, else `nil`.
    private func drive(_ fragments: [Data], parser: inout IncrementalHTTPResponseParser) throws -> HTTPResponse? {
        for fragment in fragments {
            parser.append(fragment)
            if let response = try parser.parse() {
                return response
            }
        }
        return nil
    }

    private func drive(_ fragments: [Data]) throws -> HTTPResponse? {
        var parser = IncrementalHTTPResponseParser()
        return try drive(fragments, parser: &parser)
    }

    /// Splits bytes into fixed-size fragments to simulate partial reads.
    private func fragments(_ string: String, size: Int) -> [Data] {
        let bytes = Array(Data(string.utf8))
        guard size > 0 else { return [Data(bytes)] }
        return stride(from: 0, to: bytes.count, by: size).map { start in
            Data(bytes[start..<min(start + size, bytes.count)])
        }
    }

    // MARK: - Status / headers

    @Test("Parses status code and lowercased headers")
    func parsesStatusAndHeaders() throws {
        let raw = "HTTP/1.1 201 Created\r\nContent-Type: application/json\r\nContent-Length: 0\r\n\r\n"
        let response = try #require(try drive([Data(raw.utf8)]))

        #expect(response.statusCode == 201)
        #expect(response.headers["content-type"] == "application/json")
        #expect(response.body.isEmpty)
    }

    @Test("Reassembles a header block delivered one byte at a time")
    func headersSplitAcrossReads() throws {
        let raw = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nX-Test: value\r\n\r\nhello"
        let response = try #require(try drive(fragments(raw, size: 1)))

        #expect(response.statusCode == 200)
        #expect(response.headers["x-test"] == "value")
        #expect(String(decoding: response.body, as: UTF8.self) == "hello")
    }

    @Test("No Content-Length and no chunked framing yields the buffered body")
    func noFramingCompletesImmediately() throws {
        let raw = "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"
        let response = try #require(try drive([Data(raw.utf8)]))

        #expect(response.statusCode == 204)
        #expect(response.body.isEmpty)
    }

    // MARK: - Content-Length

    @Test("Content-Length body reassembled from fragments")
    func contentLengthFragmented() throws {
        let raw = "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello world"
        let response = try #require(try drive(fragments(raw, size: 3)))

        #expect(String(decoding: response.body, as: UTF8.self) == "hello world")
    }

    @Test("Content-Length body that fits exactly")
    func contentLengthExactFit() throws {
        let raw = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello"
        let response = try #require(try drive([Data(raw.utf8)]))

        #expect(response.body.count == 5)
        #expect(String(decoding: response.body, as: UTF8.self) == "hello")
    }

    @Test("Extra bytes after a Content-Length body are ignored")
    func contentLengthReturnsExactlyContentLength() throws {
        let raw = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhelloEXTRA-DATA"
        let response = try #require(try drive([Data(raw.utf8)]))

        #expect(response.body.count == 5)
        #expect(String(decoding: response.body, as: UTF8.self) == "hello")
    }

    @Test("Content-Length of zero yields an empty body")
    func contentLengthZero() throws {
        let raw = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
        let response = try #require(try drive([Data(raw.utf8)]))

        #expect(response.body.isEmpty)
    }

    // MARK: - Chunked

    @Test("Chunked body with multiple chunks and empty trailer terminator")
    func chunkedMultipleChunks() throws {
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
            + "5\r\nhello\r\n"
            + "6\r\n world\r\n"
            + "0\r\n\r\n"
        let response = try #require(try drive([Data(raw.utf8)]))

        #expect(String(decoding: response.body, as: UTF8.self) == "hello world")
    }

    @Test("Chunked body reassembled one byte at a time")
    func chunkedFragmentedByteByByte() throws {
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
            + "4\r\nWiki\r\n"
            + "5\r\npedia\r\n"
            + "0\r\n\r\n"
        let response = try #require(try drive(fragments(raw, size: 1)))

        #expect(String(decoding: response.body, as: UTF8.self) == "Wikipedia")
    }

    @Test("Chunk size line and payload split across reads")
    func chunkedSizeLineSplit() throws {
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
            + "a\r\n0123456789\r\n"
            + "0\r\n\r\n"
        // Fragment at 4 bytes so the size line, CRLFs, and payload straddle reads.
        let response = try #require(try drive(fragments(raw, size: 4)))

        #expect(String(decoding: response.body, as: UTF8.self) == "0123456789")
    }

    @Test("Empty chunked body (immediate terminator)")
    func chunkedEmptyBody() throws {
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n"
        let response = try #require(try drive([Data(raw.utf8)]))

        #expect(response.body.isEmpty)
    }
}
