import Foundation
import Testing
@testable import ContainerBarCore

/// Docker/Podman log-stream framing (CB-070). Non-TTY containers return an
/// 8-byte header per frame (`[stream, 0, 0, 0, size(4, big-endian)]`); TTY
/// containers return the raw stream.
@Suite("Log Stream Decoder")
struct LogStreamDecoderTests {

    // MARK: - Helpers

    static func frame(_ stream: UInt8, _ payload: Data) -> Data {
        let size = UInt32(payload.count)
        var data = Data([
            stream, 0, 0, 0,
            UInt8(size >> 24), UInt8((size >> 16) & 0xFF), UInt8((size >> 8) & 0xFF), UInt8(size & 0xFF)
        ])
        data.append(payload)
        return data
    }

    static func frame(_ stream: UInt8, _ text: String) -> Data {
        frame(stream, Data(text.utf8))
    }

    /// The `cbqa-logs` fixture shape: stdout and stderr lines, short enough
    /// that every header byte is ASCII, which is the case where the old
    /// "try UTF-8 first" path returned the headers verbatim.
    static var capturedShortLinePayload: Data {
        var data = Data()
        data.append(frame(1, "cbqa-line-1\n"))
        data.append(frame(1, "cbqa-line-2\n"))
        data.append(frame(0x01, Data()))
        data.append(frame(1, "cbqa-line-3\n"))
        data.append(frame(2, "cbqa-err-1\n"))
        return data
    }

    private func withClient(_ body: (DockerAPIClientImpl) throws -> Void) throws {
        let socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("containerbar-\(UUID().uuidString).sock")
        _ = FileManager.default.createFile(atPath: socketURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: socketURL) }
        try body(DockerAPIClientImpl(
            host: DockerHost(name: "Local Docker", connectionType: .unixSocket, socketPath: socketURL.path)
        ))
    }

    // MARK: - Demultiplexing

    @Test("Short-line multiplexed payload is valid UTF-8 (the leak precondition) and decodes without headers")
    func shortLinePayloadDecodesClean() {
        let payload = Self.capturedShortLinePayload
        #expect(String(data: payload, encoding: .utf8) != nil)

        let text = LogStreamDecoder.decode(payload, framing: .multiplexed).text
        #expect(text == "cbqa-line-1\ncbqa-line-2\ncbqa-line-3\ncbqa-err-1\n")
        #expect(text.unicodeScalars.allSatisfy { $0 == "\n" || $0.value >= 0x20 })
    }

    @Test("parseMultiplexedLogs keeps frames after a zero-length frame")
    func zeroLengthFrameDoesNotStopParsing() throws {
        try withClient { client in
            let text = client.parseMultiplexedLogs(Self.capturedShortLinePayload)
            #expect(text == "cbqa-line-1\ncbqa-line-2\ncbqa-line-3\ncbqa-err-1\n")
        }
    }

    @Test("Frame larger than one 8 KB transport read is decoded whole")
    func frameLargerThanOneRead() {
        let big = String(repeating: "y", count: 20_000) + "\n"
        var payload = Self.frame(1, "cbqa-line-1\n")
        payload.append(Self.frame(1, big))
        payload.append(Self.frame(2, "cbqa-err-1\n"))

        let result = LogStreamDecoder.decode(payload, framing: .multiplexed)
        #expect(result.text == "cbqa-line-1\n" + big + "cbqa-err-1\n")
        #expect(result.truncated == false)
    }

    @Test("Multibyte character split across two frames is reassembled")
    func multibyteCharacterSplitAcrossFrames() {
        let bytes = Array("caf\u{E9}\n".utf8) // é is 0xC3 0xA9
        var payload = Self.frame(1, Data(bytes[0..<4]))
        payload.append(Self.frame(1, Data(bytes[4...])))
        #expect(LogStreamDecoder.decode(payload, framing: .multiplexed).text == "caf\u{E9}\n")
    }

    @Test("Truncated last frame keeps every complete frame and reports truncation")
    func truncatedLastFrame() {
        var payload = Self.frame(1, "cbqa-line-1\n")
        payload.append(Self.frame(2, "cbqa-err-1\n"))
        let partial = Self.frame(1, "cbqa-line-2 is cut off\n")
        payload.append(partial.prefix(12))

        let result = LogStreamDecoder.decode(payload, framing: .multiplexed)
        #expect(result.text == "cbqa-line-1\ncbqa-err-1\n")
        #expect(result.truncated)
    }

    @Test("Trailing bytes shorter than a header are reported as truncation")
    func trailingPartialHeader() {
        var payload = Self.frame(1, "cbqa-line-1\n")
        payload.append(Data([1, 0, 0]))
        let result = LogStreamDecoder.decode(payload, framing: .multiplexed)
        #expect(result.text == "cbqa-line-1\n")
        #expect(result.truncated)
    }

    @Test("Empty body decodes to empty text")
    func emptyBody() {
        let result = LogStreamDecoder.decode(Data(), framing: .multiplexed)
        #expect(result.text.isEmpty)
        #expect(result.truncated == false)
    }

    // MARK: - Framing decision

    @Test("TTY container returns the raw stream even when it looks like a frame header")
    func ttyStreamReturnedRaw() {
        let raw = Self.frame(1, "cbqa-tty\n")
        let framing = LogStreamDecoder.framing(tty: true, contentType: nil, body: raw)
        #expect(framing == .raw)
        #expect(LogStreamDecoder.decode(raw, framing: framing).text == String(decoding: raw, as: UTF8.self))
    }

    @Test("Non-TTY container is demultiplexed regardless of content type")
    func nonTTYDemultiplexed() {
        let framing = LogStreamDecoder.framing(
            tty: false,
            contentType: "application/vnd.docker.raw-stream",
            body: Self.capturedShortLinePayload
        )
        #expect(framing == .multiplexed)
    }

    @Test("Without TTY info the content type decides")
    func contentTypeDecidesWithoutTTY() {
        let payload = Self.capturedShortLinePayload
        #expect(LogStreamDecoder.framing(
            tty: nil, contentType: "application/vnd.docker.multiplexed-stream", body: Data("plain\n".utf8)
        ) == .multiplexed)
        #expect(LogStreamDecoder.framing(
            tty: nil, contentType: "application/vnd.docker.raw-stream", body: payload
        ) == .raw)
    }

    @Test("Without TTY info or a stream content type the first header is probed")
    func probeFallback() {
        #expect(LogStreamDecoder.framing(
            tty: nil, contentType: "text/plain", body: Self.capturedShortLinePayload
        ) == .multiplexed)
        #expect(LogStreamDecoder.framing(
            tty: nil, contentType: nil, body: Data("2026-10-14 plain log line\n".utf8)
        ) == .raw)
        #expect(LogStreamDecoder.framing(tty: nil, contentType: nil, body: Data([1, 0, 0])) == .raw)
    }

    // MARK: - Through the HTTP layer

    @Test("Frames split across HTTP chunk boundaries and small reads decode cleanly")
    func framesSplitAcrossChunksAndReads() throws {
        var body = Self.capturedShortLinePayload
        body.append(Self.frame(1, String(repeating: "z", count: 9_000) + "\n"))

        // Chunked transfer encoding with chunk boundaries inside headers and payloads.
        var raw = Data("HTTP/1.1 200 OK\r\nContent-Type: application/vnd.docker.multiplexed-stream\r\n".utf8)
        raw.append(Data("Transfer-Encoding: chunked\r\n\r\n".utf8))
        var offset = 0
        for size in [3, 5, 13, 7, 4_000] where offset < body.count {
            let end = min(offset + size, body.count)
            raw.append(Data(String(end - offset, radix: 16).utf8) + Data("\r\n".utf8))
            raw.append(body[offset..<end])
            raw.append(Data("\r\n".utf8))
            offset = end
        }
        if offset < body.count {
            raw.append(Data(String(body.count - offset, radix: 16).utf8) + Data("\r\n".utf8))
            raw.append(body[offset...])
            raw.append(Data("\r\n".utf8))
        }
        raw.append(Data("0\r\n\r\n".utf8))

        // Feed it in 11-byte reads, so no read lines up with a frame.
        var parser = IncrementalHTTPResponseParser()
        var response: HTTPResponse?
        var index = 0
        while response == nil, index < raw.count {
            parser.append(raw[index..<min(index + 11, raw.count)])
            response = try parser.parse()
            index += 11
        }
        let parsed = try #require(response)
        #expect(parsed.body == body)

        let framing = LogStreamDecoder.framing(tty: nil, contentType: parsed.headers["content-type"], body: parsed.body)
        let text = LogStreamDecoder.decode(parsed.body, framing: framing).text
        #expect(text == "cbqa-line-1\ncbqa-line-2\ncbqa-line-3\ncbqa-err-1\n" + String(repeating: "z", count: 9_000) + "\n")
    }
}
