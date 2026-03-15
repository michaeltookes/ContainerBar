import Foundation

extension DockerAPIClientImpl {
    func validateResponse(_ response: HTTPResponse, allowedCodes: Set<Int> = [200]) throws {
        guard allowedCodes.contains(response.statusCode) else {
            logger.error("HTTP error: \(response.statusCode)")

            switch response.statusCode {
            case 401:
                throw DockerAPIError.unauthorized
            case 404:
                throw DockerAPIError.notFound("Resource not found")
            case 409:
                throw DockerAPIError.conflict("Container is already in requested state")
            case 500...599:
                if let errorMessage = String(data: response.body, encoding: .utf8) {
                    throw DockerAPIError.serverError(errorMessage)
                }
                throw DockerAPIError.serverError("Docker daemon error")
            default:
                throw DockerAPIError.unexpectedStatus(response.statusCode)
            }
        }
    }

    func parseMultiplexedLogs(_ data: Data) -> String {
        var result = ""
        var offset = 0

        while offset + 8 <= data.count {
            let sizeBytes = data.subdata(in: (offset + 4)..<(offset + 8))
            let size = sizeBytes.withUnsafeBytes { buffer in
                buffer.load(as: UInt32.self).bigEndian
            }

            offset += 8

            guard offset + Int(size) <= data.count else {
                break
            }

            let payload = data.subdata(in: offset..<(offset + Int(size)))
            if let text = String(data: payload, encoding: .utf8) {
                result += text
            }

            offset += Int(size)
        }

        return result
    }

    public static func local() throws -> DockerAPIClientImpl {
        let host = DockerHost.local
        return try DockerAPIClientImpl(host: host)
    }
}
