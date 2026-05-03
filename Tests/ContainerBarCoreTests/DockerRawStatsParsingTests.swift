import Foundation
import Testing
@testable import ContainerBarCore

@Suite("Docker Raw Stats Timestamp Parsing Tests")
struct DockerRawStatsTimestampParsingTests {

    @Test("ContainerStats init from raw stats parses fractional ISO8601 timestamp")
    func timestampParsing() throws {
        let raw = makeRawStats(read: "2026-01-17T12:00:00.123Z")
        let expected = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(secondsFromGMT: 0),
                    year: 2026,
                    month: 1,
                    day: 17,
                    hour: 12,
                    minute: 0,
                    second: 0,
                    nanosecond: 123_000_000
                )
            )
        )

        let stats = try ContainerStats(from: raw, containerId: "test")

        #expect(abs(stats.timestamp.timeIntervalSince(expected)) < 0.001)
    }

    @Test("ContainerStats init from raw stats rejects invalid timestamp")
    func invalidTimestampThrows() {
        let raw = makeRawStats(read: "not-a-date")

        #expect(throws: DockerRawStatsError.invalidTimestamp(containerId: "test", rawRead: "not-a-date")) {
            _ = try ContainerStats(from: raw, containerId: "test")
        }
    }

    private func makeRawStats(read: String) -> DockerRawStats {
        DockerRawStats(
            read: read,
            preread: "2026-01-17T11:59:59Z",
            cpuStats: DockerRawStats.CPUStats(
                cpuUsage: DockerRawStats.CPUStats.CPUUsage(
                    totalUsage: 1_000_000,
                    percpuUsage: nil,
                    usageInKernelmode: nil,
                    usageInUsermode: nil
                ),
                systemCpuUsage: 10_000_000,
                onlineCpus: 4
            ),
            precpuStats: DockerRawStats.CPUStats(
                cpuUsage: DockerRawStats.CPUStats.CPUUsage(
                    totalUsage: 900_000,
                    percpuUsage: nil,
                    usageInKernelmode: nil,
                    usageInUsermode: nil
                ),
                systemCpuUsage: 9_000_000,
                onlineCpus: 4
            ),
            memoryStats: DockerRawStats.MemoryStats(
                usage: 100_000_000,
                maxUsage: nil,
                stats: nil,
                limit: 1_000_000_000
            ),
            networks: nil,
            blkioStats: DockerRawStats.BlkioStats(ioServiceBytesRecursive: nil)
        )
    }
}
