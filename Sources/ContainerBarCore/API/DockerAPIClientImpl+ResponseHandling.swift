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
        decodeLogs(data, framing: .multiplexed)
    }

    func decodeLogs(_ data: Data, framing: LogStreamFraming) -> String {
        let result = LogStreamDecoder.decode(data, framing: framing)
        if result.truncated {
            logger.debug("Log stream ended inside a frame; returning the complete frames only")
        }
        return result.text
    }

    /// The container's `Config.Tty`, or nil when the inspect call fails.
    func containerUsesTTY(id: String) async -> Bool? {
        do {
            let response = try await performRequest(HTTPRequest(path: "/\(apiVersion)/containers/\(id)/json"))
            try validateResponse(response)
            return try JSONDecoder().decode(ContainerTTYInspect.self, from: response.body).config?.tty
        } catch {
            logger.debug("Could not read TTY mode for container \(id): \(error)")
            return nil
        }
    }

    public static func local() throws -> DockerAPIClientImpl {
        let host = DockerHost.local
        return try DockerAPIClientImpl(host: host)
    }
}

/// The slice of `GET /containers/{id}/json` that decides log framing.
private struct ContainerTTYInspect: Decodable {
    let config: ContainerTTYConfig?
    enum CodingKeys: String, CodingKey { case config = "Config" }
}

private struct ContainerTTYConfig: Decodable {
    let tty: Bool?
    enum CodingKeys: String, CodingKey { case tty = "Tty" }
}
