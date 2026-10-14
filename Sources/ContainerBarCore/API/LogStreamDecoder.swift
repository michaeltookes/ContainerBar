import Foundation

/// How a `/containers/{id}/logs` body is framed.
enum LogStreamFraming: Sendable, Equatable {
    /// Non-TTY container: each frame is an 8-byte header
    /// `[stream, 0, 0, 0, size(4, big-endian)]` followed by `size` payload bytes.
    case multiplexed
    /// TTY container: the body is the raw terminal stream.
    case raw
}

/// Decodes container log bodies (CB-070).
///
/// The framing is decided from the container's `Config.Tty` when it is known,
/// then from the response `Content-Type` (Docker API 1.42+ sends
/// `application/vnd.docker.multiplexed-stream` or `application/vnd.docker.raw-stream`),
/// and only then by probing the first 8 bytes. It is never decided by whether
/// the body happens to be valid UTF-8: frame headers whose size bytes are all
/// below 0x80 (for example every line shorter than 128 bytes) are valid UTF-8.
enum LogStreamDecoder {
    static let headerSize = 8
    static let maxFrameSize = 10 * 1024 * 1024

    static let multiplexedContentType = "application/vnd.docker.multiplexed-stream"
    static let rawContentType = "application/vnd.docker.raw-stream"

    struct Result: Sendable, Equatable {
        let text: String
        /// True when the body ended inside a frame header or payload, or a
        /// header was malformed; every complete frame before it is kept.
        let truncated: Bool
    }

    static func framing(tty: Bool?, contentType: String?, body: Data) -> LogStreamFraming {
        if let tty {
            return tty ? .raw : .multiplexed
        }
        if let mediaType = contentType?.split(separator: ";").first?
            .trimmingCharacters(in: .whitespaces).lowercased() {
            if mediaType == multiplexedContentType { return .multiplexed }
            if mediaType == rawContentType { return .raw }
        }
        return looksMultiplexed(body) ? .multiplexed : .raw
    }

    /// True when the body starts with a plausible frame header: stream type
    /// 0, 1 or 2 and the three reserved bytes zero.
    static func looksMultiplexed(_ data: Data) -> Bool {
        guard data.count >= headerSize else { return false }
        let start = data.startIndex
        return data[start] <= 2 && data[start + 1] == 0 && data[start + 2] == 0 && data[start + 3] == 0
    }

    static func decode(_ data: Data, framing: LogStreamFraming) -> Result {
        switch framing {
        case .raw:
            return Result(text: utf8Text(data), truncated: false)
        case .multiplexed:
            return demultiplex(data)
        }
    }

    /// Concatenates the payloads of every complete frame in order, then decodes
    /// them as UTF-8 once, so a character split across two frames survives.
    static func demultiplex(_ data: Data) -> Result {
        var payload = Data()
        var offset = data.startIndex
        var truncated = false

        while offset < data.endIndex {
            guard data.endIndex - offset >= headerSize else {
                truncated = true
                break
            }
            let header = data[offset..<(offset + headerSize)]
            guard looksMultiplexed(header) else {
                truncated = true
                break
            }
            let size = header.dropFirst(4).reduce(0) { ($0 << 8) | Int($1) }
            offset += headerSize

            if size == 0 { continue }
            guard size <= maxFrameSize, data.endIndex - offset >= size else {
                truncated = true
                break
            }
            payload.append(data[offset..<(offset + size)])
            offset += size
        }

        return Result(text: utf8Text(payload), truncated: truncated)
    }

    /// Decodes UTF-8, replacing invalid sequences with U+FFFD instead of
    /// dropping the whole text. Lossy on purpose, so the failable initializer
    /// the lint rule prefers would be wrong here.
    static func utf8Text(_ data: Data) -> String {
        // swiftlint:disable:next optional_data_string_conversion
        data.withUnsafeBytes { String(decoding: $0.bindMemory(to: UInt8.self), as: UTF8.self) }
    }
}
