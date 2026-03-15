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

    func toHTTPString() -> String {
        var request = "\(method) \(path) HTTP/1.1\r\n"
        request += "Host: localhost\r\n"
        request += "Connection: keep-alive\r\n"

        for (key, value) in headers {
            request += "\(key): \(value)\r\n"
        }

        if let body, !body.isEmpty {
            request += "Content-Length: \(body.count)\r\n"
        }

        request += "\r\n"

        if let body, let bodyString = String(data: body, encoding: .utf8) {
            request += bodyString
        }

        return request
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
