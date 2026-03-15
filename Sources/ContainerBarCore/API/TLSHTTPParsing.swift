import Foundation

func parseTLSHeaders(_ headerString: String) -> [String: String] {
    var headers: [String: String] = [:]
    let lines = headerString.components(separatedBy: "\r\n")
    for line in lines.dropFirst() {
        guard !line.isEmpty, let colonIndex = line.firstIndex(of: ":") else { continue }
        let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        headers[key.lowercased()] = value
    }
    return headers
}

func parseTLSHTTPResponse(_ data: Data) throws -> HTTPResponse {
    let headerSeparator = Data("\r\n\r\n".utf8)
    guard let headerEnd = data.range(of: headerSeparator) else {
        throw DockerAPIError.invalidResponse
    }

    let headerData = data[..<headerEnd.lowerBound]
    guard let headerString = String(data: headerData, encoding: .utf8) else {
        throw DockerAPIError.invalidResponse
    }

    let lines = headerString.components(separatedBy: "\r\n")
    guard let statusLine = lines.first else {
        throw DockerAPIError.invalidResponse
    }
    let statusParts = statusLine.split(separator: " ", maxSplits: 2)
    guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else {
        throw DockerAPIError.invalidResponse
    }

    let headers = parseTLSHeaders(headerString)
    var body = Data(data[headerEnd.upperBound...])

    if headers["transfer-encoding"]?.lowercased() == "chunked" {
        body = decodeTLSChunkedBody(body)
    }

    return HTTPResponse(statusCode: statusCode, headers: headers, body: body)
}

func decodeTLSChunkedBody(_ data: Data) -> Data {
    var result = Data()
    var remaining = data

    while true {
        guard let lineEnd = remaining.range(of: Data("\r\n".utf8)) else { break }

        let sizeLine = remaining[..<lineEnd.lowerBound]
        guard let sizeString = String(data: sizeLine, encoding: .utf8),
              let chunkSize = Int(sizeString.trimmingCharacters(in: .whitespaces), radix: 16) else {
            break
        }

        remaining = Data(remaining[lineEnd.upperBound...])

        if chunkSize == 0 { break }

        guard remaining.count >= chunkSize else { break }

        result.append(remaining[..<remaining.index(remaining.startIndex, offsetBy: chunkSize)])

        if remaining.count > chunkSize + 2 {
            remaining = Data(remaining[remaining.index(remaining.startIndex, offsetBy: chunkSize + 2)...])
        } else {
            break
        }
    }

    return result
}
