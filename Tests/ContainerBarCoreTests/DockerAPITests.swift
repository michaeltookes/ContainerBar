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

        // Permanent errors (don't retry)
        #expect(DockerAPIError.unauthorized.isTransient == false)
        #expect(DockerAPIError.notFound("test").isTransient == false)
        #expect(DockerAPIError.invalidURL.isTransient == false)
        #expect(DockerAPIError.socketNotFound("/path").isTransient == false)
    }

    @Test("HTTPRequest builds correct request string")
    func httpRequestString() {
        let request = HTTPRequest(
            method: "GET",
            path: "/v1.43/containers/json?all=true"
        )

        let httpString = request.toHTTPString()

        #expect(httpString.contains("GET /v1.43/containers/json?all=true HTTP/1.1"))
        #expect(httpString.contains("Host: localhost"))
        #expect(httpString.contains("Connection: keep-alive"))
    }

    @Test("HTTPRequest with POST method and body")
    func httpRequestWithBody() {
        let body = "test body".data(using: .utf8)!
        let request = HTTPRequest(
            method: "POST",
            path: "/v1.43/containers/abc/start",
            body: body
        )

        let httpString = request.toHTTPString()

        #expect(httpString.contains("POST"))
        #expect(httpString.contains("Content-Length: \(body.count)"))
        #expect(httpString.contains("test body"))
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
