import Foundation

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?
    let minimumRequestTimeout: TimeInterval?
    let disablesRequestTimeout: Bool
    let receiveInactivityTimeout: TimeInterval?
    let allowsRetryAfterSend: Bool

    init(
        method: String = "GET",
        path: String,
        headers: [String: String] = [:],
        body: Data? = nil,
        minimumRequestTimeout: TimeInterval? = nil,
        disablesRequestTimeout: Bool = false,
        receiveInactivityTimeout: TimeInterval? = nil,
        allowsRetryAfterSend: Bool? = nil
    ) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
        self.minimumRequestTimeout = minimumRequestTimeout
        self.disablesRequestTimeout = disablesRequestTimeout
        self.receiveInactivityTimeout = receiveInactivityTimeout
        self.allowsRetryAfterSend = allowsRetryAfterSend ?? Self.defaultAllowsRetryAfterSend(method: method)
    }

    var isIdempotent: Bool {
        switch method.uppercased() {
        case "GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE":
            return true
        default:
            return false
        }
    }

    func toHTTPData(resolvedHost: String? = nil) throws -> Data {
        try Self.validateHTTPComponent(method, name: "HTTP method")
        try Self.validateHTTPComponent(path, name: "HTTP path")

        var resolvedHeaders = headers

        if let resolvedHost,
           resolvedHeaders.keys.contains(where: { $0.caseInsensitiveCompare("Host") == .orderedSame }) == false {
            try Self.validateHTTPComponent(resolvedHost, name: "HTTP host")
            resolvedHeaders["Host"] = resolvedHost
        }

        if resolvedHeaders.keys.contains(where: { $0.caseInsensitiveCompare("Connection") == .orderedSame }) == false {
            resolvedHeaders["Connection"] = "keep-alive"
        }

        if let body {
            resolvedHeaders["Content-Length"] = "\(body.count)"
        }

        var requestData = Data()
        requestData.append(Data("\(method) \(path) HTTP/1.1\r\n".utf8))

        for (key, value) in resolvedHeaders {
            try Self.validateHTTPComponent(key, name: "HTTP header name")
            try Self.validateHTTPComponent(value, name: "HTTP header value")
            requestData.append(Data("\(key): \(value)\r\n".utf8))
        }

        requestData.append(Data("\r\n".utf8))

        if let body {
            requestData.append(body)
        }

        return requestData
    }

    private static func validateHTTPComponent(_ value: String, name: String) throws {
        let containsLineBreak = value.unicodeScalars.contains { scalar in
            scalar.value == 0x0D || scalar.value == 0x0A
        }
        guard containsLineBreak == false else {
            throw DockerAPIError.invalidConfiguration("\(name) contains an invalid line break")
        }
    }

    private static func defaultAllowsRetryAfterSend(method: String) -> Bool {
        switch method.uppercased() {
        case "GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE":
            return true
        default:
            return false
        }
    }
}

struct HTTPRequestNotSentError: Error, Sendable {}

struct HTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    var isSuccess: Bool {
        (200..<300).contains(statusCode)
    }
}
