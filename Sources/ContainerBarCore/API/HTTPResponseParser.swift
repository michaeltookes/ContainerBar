import Foundation

enum HTTPResponseParser {
    static let headerSeparator = Data("\r\n\r\n".utf8)
    private static let lineSeparator = Data("\r\n".utf8)

    static func parseStatusAndHeaders(_ headerString: String) throws -> (Int, [String: String]) {
        let lines = headerString.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else {
            throw DockerAPIError.invalidResponse
        }

        let statusParts = statusLine.split(separator: " ", maxSplits: 2)
        guard statusParts.count >= 2,
              let statusCode = Int(statusParts[1]) else {
            throw DockerAPIError.invalidResponse
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            guard let colonIndex = line.firstIndex(of: ":") else {
                throw DockerAPIError.invalidResponse
            }

            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            headers[key.lowercased()] = value
        }

        return (statusCode, headers)
    }

    static func decodeChunkedBody(_ data: Data) throws -> Data {
        var remaining = data
        var result = Data()

        while true {
            guard let lineEnd = remaining.range(of: lineSeparator) else {
                throw DockerAPIError.invalidResponse
            }

            let sizeLine = remaining[..<lineEnd.lowerBound]
            guard let sizeString = String(data: sizeLine, encoding: .utf8),
                  let chunkSize = Int(sizeString.trimmingCharacters(in: .whitespaces), radix: 16) else {
                throw DockerAPIError.invalidResponse
            }

            remaining = Data(remaining[lineEnd.upperBound...])

            if chunkSize == 0 {
                guard remaining.starts(with: lineSeparator) else {
                    throw DockerAPIError.invalidResponse
                }
                return result
            }

            guard remaining.count >= chunkSize else {
                throw DockerAPIError.invalidResponse
            }

            let chunkEnd = remaining.index(remaining.startIndex, offsetBy: chunkSize)
            result.append(remaining[..<chunkEnd])

            guard remaining.count >= chunkSize + lineSeparator.count else {
                throw DockerAPIError.invalidResponse
            }

            let trailerEnd = remaining.index(chunkEnd, offsetBy: lineSeparator.count)
            guard remaining[chunkEnd..<trailerEnd] == lineSeparator else {
                throw DockerAPIError.invalidResponse
            }

            remaining = Data(remaining[trailerEnd...])
        }
    }

    static func readBody(
        headers: [String: String],
        initialBody: Data,
        readChunk: (_ length: Int) throws -> Data
    ) throws -> Data {
        if let contentLength = headers["content-length"],
           let length = Int(contentLength) {
            var body = initialBody
            while body.count < length {
                let chunk = try readChunk(min(8192, length - body.count))
                guard !chunk.isEmpty else {
                    throw DockerAPIError.invalidResponse
                }
                body.append(chunk)
            }
            return body
        }

        if headers["transfer-encoding"]?.lowercased() == "chunked" {
            return try readChunkedBody(initialData: initialBody, readChunk: readChunk)
        }

        return initialBody
    }

    private static func readChunkedBody(
        initialData: Data,
        readChunk: (_ length: Int) throws -> Data
    ) throws -> Data {
        var remaining = initialData
        var result = Data()

        while true {
            while remaining.range(of: lineSeparator) == nil {
                let chunk = try readChunk(8192)
                guard !chunk.isEmpty else {
                    throw DockerAPIError.invalidResponse
                }
                remaining.append(chunk)
            }

            guard let lineEnd = remaining.range(of: lineSeparator) else {
                throw DockerAPIError.invalidResponse
            }

            let sizeLine = remaining[..<lineEnd.lowerBound]
            guard let sizeString = String(data: sizeLine, encoding: .utf8),
                  let chunkSize = Int(sizeString.trimmingCharacters(in: .whitespaces), radix: 16) else {
                throw DockerAPIError.invalidResponse
            }

            remaining = Data(remaining[lineEnd.upperBound...])

            if chunkSize == 0 {
                while remaining.starts(with: lineSeparator) == false {
                    let chunk = try readChunk(8192)
                    guard !chunk.isEmpty else {
                        throw DockerAPIError.invalidResponse
                    }
                    remaining.append(chunk)
                }

                return result
            }

            while remaining.count < chunkSize + lineSeparator.count {
                let chunk = try readChunk(8192)
                guard !chunk.isEmpty else {
                    throw DockerAPIError.invalidResponse
                }
                remaining.append(chunk)
            }

            let chunkEnd = remaining.index(remaining.startIndex, offsetBy: chunkSize)
            result.append(remaining[..<chunkEnd])

            let trailerEnd = remaining.index(chunkEnd, offsetBy: lineSeparator.count)
            guard remaining[chunkEnd..<trailerEnd] == lineSeparator else {
                throw DockerAPIError.invalidResponse
            }

            remaining = Data(remaining[trailerEnd...])
        }
    }
}
