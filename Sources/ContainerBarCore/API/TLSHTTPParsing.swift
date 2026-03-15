import Foundation

func parseTLSHeaders(_ headerString: String) -> [String: String] {
    (try? HTTPResponseParser.parseStatusAndHeaders(headerString))?.1 ?? [:]
}

func parseTLSHTTPResponse(_ data: Data) throws -> HTTPResponse {
    guard let headerEnd = data.range(of: HTTPResponseParser.headerSeparator) else {
        throw DockerAPIError.invalidResponse
    }

    let headerData = data[..<headerEnd.lowerBound]
    guard let headerString = String(data: headerData, encoding: .utf8) else {
        throw DockerAPIError.invalidResponse
    }

    let (statusCode, headers) = try HTTPResponseParser.parseStatusAndHeaders(headerString)
    var body = Data(data[headerEnd.upperBound...])

    if headers["transfer-encoding"]?.lowercased() == "chunked" {
        body = try decodeTLSChunkedBody(body)
    }

    return HTTPResponse(statusCode: statusCode, headers: headers, body: body)
}

func decodeTLSChunkedBody(_ data: Data) throws -> Data {
    try HTTPResponseParser.decodeChunkedBody(data)
}
