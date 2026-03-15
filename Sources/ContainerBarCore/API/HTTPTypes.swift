import Foundation

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?

    init(method: String = "GET", path: String, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    var isIdempotent: Bool {
        switch method.uppercased() {
        case "GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE":
            return true
        default:
            return false
        }
    }

    func toHTTPData() -> Data {
        var resolvedHeaders = headers

        if resolvedHeaders.keys.contains(where: { $0.caseInsensitiveCompare("Host") == .orderedSame }) == false {
            resolvedHeaders["Host"] = "localhost"
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
            requestData.append(Data("\(key): \(value)\r\n".utf8))
        }

        requestData.append(Data("\r\n".utf8))

        if let body {
            requestData.append(body)
        }

        return requestData
    }

    func toHTTPString() -> String {
        String(decoding: toHTTPData(), as: UTF8.self)
    }
}

struct HTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    var isSuccess: Bool {
        (200..<300).contains(statusCode)
    }
}
