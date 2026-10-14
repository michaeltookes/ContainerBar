import Foundation
import Testing
@testable import ContainerBarCore

/// The aggregate memory denominator rule (CB-069), tested directly.
@Suite("AggregateMemoryLimit Tests")
struct AggregateMemoryLimitTests {

    private static let gib: UInt64 = 1024 * 1024 * 1024
    private static let mib: UInt64 = 1024 * 1024
    private static let host: UInt64 = 16 * gib

    @Test("Docker shape: unconstrained containers report the host total, denominator is the host once")
    func dockerUnconstrainedUsesHostTotal() {
        let limits = [Self.host, Self.host, Self.host]
        #expect(AggregateMemoryLimit.denominator(limits: limits, hostMemoryTotal: Self.host) == Self.host)
    }

    @Test("Podman shape: unconstrained containers report 0, denominator is the host")
    func podmanZeroLimitUsesHostTotal() {
        let limits: [UInt64] = [0, 0, 0]
        #expect(AggregateMemoryLimit.denominator(limits: limits, hostMemoryTotal: Self.host) == Self.host)
    }

    @Test("Mixed limited and unconstrained (either shape) gives the host total")
    func mixedLimitedAndUnconstrained() {
        let dockerMixed = [256 * Self.mib, Self.host, Self.host]
        let podmanMixed = [256 * Self.mib, 0, 0]
        #expect(AggregateMemoryLimit.denominator(limits: dockerMixed, hostMemoryTotal: Self.host) == Self.host)
        #expect(AggregateMemoryLimit.denominator(limits: podmanMixed, hostMemoryTotal: Self.host) == Self.host)
    }

    @Test("All containers limited: denominator is the sum of their limits")
    func allLimitedSumsLimits() {
        let limits = [256 * Self.mib, 512 * Self.mib, Self.gib]
        let expected = 256 * Self.mib + 512 * Self.mib + Self.gib
        #expect(AggregateMemoryLimit.denominator(limits: limits, hostMemoryTotal: Self.host) == expected)
    }

    @Test("All containers limited but the limits overcommit the host: capped at the host total")
    func allLimitedCappedAtHost() {
        let limits = [10 * Self.gib, 10 * Self.gib]
        #expect(AggregateMemoryLimit.denominator(limits: limits, hostMemoryTotal: Self.host) == Self.host)
    }

    @Test("A limit above the host total (unclamped 'max') counts as unconstrained")
    func limitAboveHostIsUnconstrained() {
        let limits = [UInt64.max, 256 * Self.mib]
        #expect(AggregateMemoryLimit.denominator(limits: limits, hostMemoryTotal: Self.host) == Self.host)
    }

    @Test("No stats gives a zero denominator")
    func emptyIsZero() {
        #expect(AggregateMemoryLimit.denominator(limits: [], hostMemoryTotal: Self.host) == 0)
        #expect(AggregateMemoryLimit.denominator(limits: [], hostMemoryTotal: nil) == 0)
    }

    @Test("Host total unknown: the echoed host value is counted once, smaller limits are added")
    func fallbackDeduplicatesLargestLimit() {
        let limits = [Self.host, Self.host, Self.host, 256 * Self.mib]
        let expected = Self.host + 256 * Self.mib
        #expect(AggregateMemoryLimit.denominator(limits: limits, hostMemoryTotal: nil) == expected)
        #expect(AggregateMemoryLimit.denominator(limits: limits, hostMemoryTotal: 0) == expected)
    }

    @Test("Host total unknown and every limit 0: denominator is 0, no trap")
    func fallbackAllZero() {
        #expect(AggregateMemoryLimit.denominator(limits: [0, 0], hostMemoryTotal: nil) == 0)
    }

    @Test("Sentinel limits saturate instead of overflowing")
    func saturatesOnOverflow() {
        #expect(AggregateMemoryLimit.saturatingSum([UInt64.max, 1, UInt64.max]) == UInt64.max)
    }

    @Test("Host total unknown: UInt64.max and other >1 PiB sentinels are excluded from the fallback")
    func fallbackExcludesSentinels() {
        let limits = [UInt64.max, Self.host, 256 * Self.mib, UInt64(1) << 62]
        #expect(AggregateMemoryLimit.denominator(limits: limits, hostMemoryTotal: nil) == Self.host + 256 * Self.mib)
        #expect(AggregateMemoryLimit.denominator(limits: [UInt64.max, 5], hostMemoryTotal: nil) == 5)
    }

    @Test("Host total unknown and every container reports a sentinel: 0, so health stays unknown")
    func fallbackAllSentinelsIsZero() {
        #expect(AggregateMemoryLimit.denominator(limits: [UInt64.max, UInt64.max], hostMemoryTotal: nil) == 0)
        #expect(AggregateMemoryLimit.denominator(limits: [UInt64.max, 0], hostMemoryTotal: 0) == 0)
    }
}
