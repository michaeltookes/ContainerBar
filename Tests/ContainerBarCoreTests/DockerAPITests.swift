import Foundation
import Testing
@testable import ContainerBarCore

@Suite("Docker API Tests")
struct DockerAPITests {

    @Test("DockerAPIError has correct descriptions")
    func errorDescriptions() {
        let connectionFailed = DockerAPIError.connectionFailed
        #expect(connectionFailed.errorDescription?.contains("Failed to connect") == true)

        let notFound = DockerAPIError.notFound("container abc")
        #expect(notFound.errorDescription?.contains("abc") == true)

        let socketNotFound = DockerAPIError.socketNotFound("/var/run/docker.sock")
        #expect(socketNotFound.errorDescription?.contains("not found") == true)
    }

    @Test("DockerAPIError isTransient identifies retryable errors")
    func errorIsTransient() {
        // Transient errors (can retry)
        #expect(DockerAPIError.connectionFailed.isTransient == true)
        #expect(DockerAPIError.networkTimeout.isTransient == true)
        #expect(DockerAPIError.serverError("test").isTransient == true)
        #expect(DockerAPIError.sshConnectionFailed("test").isTransient == true)
        #expect(DockerAPIError.tlsConnectionFailed("test").isTransient == true)

        // Permanent errors (don't retry)
        #expect(DockerAPIError.unauthorized.isTransient == false)
        #expect(DockerAPIError.notFound("test").isTransient == false)
        #expect(DockerAPIError.invalidURL.isTransient == false)
        #expect(DockerAPIError.socketNotFound("/path").isTransient == false)
    }

    @Test("HTTPRequest builds correct request data")
    func httpRequestString() throws {
        let request = HTTPRequest(
            method: "GET",
            path: "/v1.43/containers/json?all=true"
        )

        let httpString = String(decoding: try request.toHTTPData(), as: UTF8.self)

        #expect(httpString.contains("GET /v1.43/containers/json?all=true HTTP/1.1"))
        #expect(httpString.contains("Host:") == false)
        #expect(httpString.contains("Connection: keep-alive"))
    }

    @Test("HTTPRequest with POST method and body")
    func httpRequestWithBody() throws {
        let body = "test body".data(using: .utf8)!
        let request = HTTPRequest(
            method: "POST",
            path: "/v1.43/containers/abc/start",
            body: body
        )

        let httpString = String(decoding: try request.toHTTPData(), as: UTF8.self)

        #expect(httpString.contains("POST"))
        #expect(httpString.contains("Content-Length: \(body.count)"))
        #expect(httpString.contains("test body"))
    }

    @Test("HTTPRequest preserves explicit Host header")
    func httpRequestCustomHostHeader() throws {
        let request = HTTPRequest(
            method: "GET",
            path: "/_ping",
            headers: ["Host": "docker.example.com"]
        )

        let httpString = String(decoding: try request.toHTTPData(), as: UTF8.self)

        #expect(httpString.contains("Host: docker.example.com"))
        #expect(httpString.contains("Host: localhost") == false)
    }

    @Test("HTTPRequest uses resolved host when provided")
    func httpRequestResolvedHostHeader() throws {
        let request = HTTPRequest(
            method: "GET",
            path: "/_ping"
        )

        let httpString = String(decoding: try request.toHTTPData(resolvedHost: "docker.example.com"), as: UTF8.self)

        #expect(httpString.contains("Host: docker.example.com"))
    }

    @Test("HTTPRequest rejects CRLF injection")
    func httpRequestRejectsCRLFInjection() throws {
        let request = HTTPRequest(
            method: "GET",
            path: "/_ping",
            headers: ["X-Test": "good\r\nInjected: bad"]
        )

        do {
            _ = try request.toHTTPData()
            Issue.record("Expected toHTTPData to reject CRLF injection")
        } catch let error as DockerAPIError {
            #expect(error.errorDescription?.contains("invalid line break") == true)
        }
    }

    @Test("TLSConnection rejects half-configured client identity")
    func tlsConnectionRejectsPartialClientIdentity() {
        do {
            _ = try TLSConnection(
                host: "docker.example.com",
                caCertPath: nil,
                clientCertPath: "/tmp/client-cert.pem",
                clientKeyPath: nil
            )
            Issue.record("Expected TLSConnection to reject a partial client identity configuration")
        } catch let error as DockerAPIError {
            #expect(error.errorDescription?.contains("must both be provided") == true)
        } catch {
            Issue.record("Expected DockerAPIError.invalidConfiguration, got \(error)")
        }
    }

    @Test("TLS chunked decoder rejects malformed payloads")
    func tlsChunkedDecoderRejectsMalformedPayload() {
        let malformed = Data("5\r\nhello".utf8)

        do {
            _ = try decodeTLSChunkedBody(malformed)
            Issue.record("Expected malformed chunked payload to throw")
        } catch let error as DockerAPIError {
            if case .invalidResponse = error {
                #expect(true)
            } else {
                Issue.record("Expected DockerAPIError.invalidResponse, got \(error)")
            }
        } catch {
            Issue.record("Expected DockerAPIError.invalidResponse, got \(error)")
        }
    }

    @Test("TLS content length parser rejects malformed or oversized values")
    func tlsContentLengthParserRejectsInvalidValues() throws {
        #expect(try parseTLSContentLength("0") == 0)
        #expect(try parseTLSContentLength("42") == 42)

        for invalidValue in ["", "-1", "1.5", "abc", "134217729", "999999999999999999999999"] {
            do {
                _ = try parseTLSContentLength(invalidValue)
                Issue.record("Expected invalid Content-Length value to throw: \(invalidValue)")
            } catch let error as DockerAPIError {
                if case .invalidResponse = error {
                    continue
                }
                Issue.record("Expected DockerAPIError.invalidResponse, got \(error)")
            }
        }
    }

    @Test("HTTPResponse success detection")
    func httpResponseSuccess() {
        let success = HTTPResponse(statusCode: 200, headers: [:], body: Data())
        #expect(success.isSuccess == true)

        let created = HTTPResponse(statusCode: 201, headers: [:], body: Data())
        #expect(created.isSuccess == true)

        let noContent = HTTPResponse(statusCode: 204, headers: [:], body: Data())
        #expect(noContent.isSuccess == true)

        let notFound = HTTPResponse(statusCode: 404, headers: [:], body: Data())
        #expect(notFound.isSuccess == false)

        let serverError = HTTPResponse(statusCode: 500, headers: [:], body: Data())
        #expect(serverError.isSuccess == false)
    }

    @Test("Remote socket path sanitization validates configured SSH socket path")
    func remoteSocketPathSanitization() {
        let fallback = "/var/run/docker.sock"

        #expect(
            DockerAPIClientImpl.validatedRemoteSocketPath(
                configuredPath: nil,
                fallbackPath: fallback
            ) == fallback
        )
        #expect(
            DockerAPIClientImpl.validatedRemoteSocketPath(
                configuredPath: "   ",
                fallbackPath: fallback
            ) == fallback
        )
        #expect(
            DockerAPIClientImpl.validatedRemoteSocketPath(
                configuredPath: " /run/user/1000/podman/podman.sock ",
                fallbackPath: fallback
            ) == "/run/user/1000/podman/podman.sock"
        )
        #expect(
            DockerAPIClientImpl.validatedRemoteSocketPath(
                configuredPath: "var/run/docker.sock",
                fallbackPath: fallback
            ) == fallback
        )
        #expect(
            DockerAPIClientImpl.validatedRemoteSocketPath(
                configuredPath: "/var/run/../docker.sock",
                fallbackPath: fallback
            ) == fallback
        )
        #expect(
            DockerAPIClientImpl.validatedRemoteSocketPath(
                configuredPath: "/var/run/docker.sock\0evil",
                fallbackPath: fallback
            ) == fallback
        )
    }
}

@Suite("Mock Docker API Client Tests")
struct MockDockerAPIClientTests {

    @Test("Mock client returns configured containers")
    func mockReturnsContainers() async throws {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "test1", name: "container1"),
            DockerContainer.mock(id: "test2", name: "container2"),
        ]

        let containers = try await mock.listContainers(all: true)

        #expect(containers.count == 2)
        #expect(mock.callCount == 1)
        #expect(mock.lastCalledMethod == "listContainers")
    }

    @Test("Mock client throws when configured to fail")
    func mockThrowsOnFailure() async {
        let mock = MockDockerAPIClient()
        mock.shouldFail = true
        mock.failureError = DockerAPIError.connectionFailed

        do {
            _ = try await mock.listContainers(all: true)
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is DockerAPIError)
        }
    }

    @Test("Mock client ping succeeds when not failing")
    func mockPingSucceeds() async throws {
        let mock = MockDockerAPIClient()

        try await mock.ping()

        #expect(mock.callCount == 1)
        #expect(mock.lastCalledMethod == "ping")
    }

    @Test("Mock client returns stats for configured container")
    func mockReturnsStats() async throws {
        let mock = MockDockerAPIClient()
        let mockStats = ContainerStats.mock(containerId: "test1", cpuPercent: 5.0)
        mock.mockStats["test1"] = mockStats

        let stream = try await mock.getContainerStats(id: "test1", stream: false)

        var receivedStats: ContainerStats?
        for try await stats in stream {
            receivedStats = stats
        }

        #expect(receivedStats?.cpuPercent == 5.0)
    }
}

@Suite("Retry Config Tests")
struct RetryConfigTests {

    @Test("Default config has expected values")
    func defaultConfig() {
        let config = RetryConfig.default

        #expect(config.maxAttempts == 3)
        #expect(config.initialDelay == 1.0)
        #expect(config.maxDelay == 10.0)
        #expect(config.multiplier == 2.0)
    }

    @Test("Custom config preserves values")
    func customConfig() {
        let config = RetryConfig(
            maxAttempts: 5,
            initialDelay: 0.5,
            maxDelay: 30.0,
            multiplier: 3.0
        )

        #expect(config.maxAttempts == 5)
        #expect(config.initialDelay == 0.5)
        #expect(config.maxDelay == 30.0)
        #expect(config.multiplier == 3.0)
    }

    @Test("withRetry propagates cancellation during backoff")
    func retryCancellation() async throws {
        let task = Task {
            let _: Void = try await withRetry(
                config: RetryConfig(maxAttempts: 2, initialDelay: 1.0, maxDelay: 1.0, multiplier: 2.0)
            ) {
                throw DockerAPIError.connectionFailed
            }
        }

        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation to propagate from withRetry")
        } catch is CancellationError {
            // Expected.
        }
    }
}

@Suite("Async Serial Gate Tests")
struct AsyncSerialGateTests {

    @Test("Cancelled waiter does not run after the gate is released")
    func cancelledWaiterDoesNotRun() async throws {
        let gate = AsyncSerialGate()

        let blocker = Task {
            try await gate.withExclusiveAccess {
                try await Task.sleep(for: .milliseconds(200))
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        let cancelledWaiter = Task {
            try await gate.withExclusiveAccess {
                Issue.record("Cancelled waiter should not have executed")
            }
        }

        cancelledWaiter.cancel()

        _ = try await blocker.value

        do {
            _ = try await cancelledWaiter.value
            Issue.record("Expected cancelled waiter to throw CancellationError")
        } catch is CancellationError {
            // Expected.
        }
    }
}

@Suite("Docker Raw Stats Parsing Tests")
struct DockerRawStatsTests {

    @Test("ContainerStats init from raw stats calculates CPU correctly")
    func cpuCalculation() {
        // Create mock raw stats with known values
        let raw = createMockRawStats(
            cpuUsage: 1_000_000,
            preCpuUsage: 900_000,
            systemUsage: 10_000_000,
            preSystemUsage: 9_000_000,
            onlineCpus: 4
        )

        let stats = ContainerStats(from: raw, containerId: "test")

        // CPU delta = 100,000
        // System delta = 1,000,000
        // CPU percent = (100,000 / 1,000,000) * 4 * 100 = 40%
        #expect(stats.cpuPercent == 40.0)
    }

    @Test("ContainerStats init from raw stats handles memory")
    func memoryStats() {
        let raw = createMockRawStats(
            memoryUsage: 134_217_728,  // 128 MB
            memoryLimit: 536_870_912   // 512 MB
        )

        let stats = ContainerStats(from: raw, containerId: "test")

        #expect(stats.memoryUsageBytes == 134_217_728)
        #expect(stats.memoryLimitBytes == 536_870_912)
        #expect(stats.memoryPercent == 25.0)
    }

    // Helper to create mock raw stats
    private func createMockRawStats(
        cpuUsage: UInt64 = 1_000_000,
        preCpuUsage: UInt64 = 0,
        systemUsage: UInt64 = 10_000_000,
        preSystemUsage: UInt64 = 0,
        onlineCpus: Int = 4,
        memoryUsage: UInt64 = 100_000_000,
        memoryLimit: UInt64 = 1_000_000_000
    ) -> DockerRawStats {
        DockerRawStats(
            read: "2026-01-17T12:00:00Z",
            preread: "2026-01-17T11:59:59Z",
            cpuStats: DockerRawStats.CPUStats(
                cpuUsage: DockerRawStats.CPUStats.CPUUsage(
                    totalUsage: cpuUsage,
                    percpuUsage: nil,
                    usageInKernelmode: nil,
                    usageInUsermode: nil
                ),
                systemCpuUsage: systemUsage,
                onlineCpus: onlineCpus
            ),
            precpuStats: DockerRawStats.CPUStats(
                cpuUsage: DockerRawStats.CPUStats.CPUUsage(
                    totalUsage: preCpuUsage,
                    percpuUsage: nil,
                    usageInKernelmode: nil,
                    usageInUsermode: nil
                ),
                systemCpuUsage: preSystemUsage,
                onlineCpus: onlineCpus
            ),
            memoryStats: DockerRawStats.MemoryStats(
                usage: memoryUsage,
                maxUsage: nil,
                stats: nil,
                limit: memoryLimit
            ),
            networks: nil,
            blkioStats: DockerRawStats.BlkioStats(ioServiceBytesRecursive: nil)
        )
    }
}
