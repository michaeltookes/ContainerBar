import Foundation

/// Computes the denominator for the aggregate "used / limit" memory figure
/// shown in the dashboard RAM tile, the status-icon memory gauge, and
/// `ContainerMetricsSnapshot.overallHealth` (CB-069).
///
/// ## Why not just sum the per-container limits
///
/// A container with no cgroup memory limit has no limit of its own to report.
/// Docker reports the host's `MemTotal` as `memory_stats.limit` for such a
/// container; Podman reports either the host total or 0 (unverified, so both
/// shapes are handled). Summing those values makes three unconstrained
/// containers on a 16 GiB host read "/ 48 GB", so the gauge shows a third of
/// the real pressure and the 95 % warning can never trip.
///
/// ## The rule
///
/// A reported limit counts as a *real* cgroup limit only when it is above 0
/// and strictly below the host's total memory. Anything else (0, equal to the
/// host total, or larger, such as an unclamped "max") means the container is
/// unconstrained and can grow until the host runs out.
///
/// - With the host total known (`/info` `MemTotal` > 0):
///   - if any container is unconstrained, the denominator is the host total,
///     because those containers' ceiling is the whole host;
///   - if every container has a real limit, the denominator is the sum of
///     those limits, capped at the host total (the containers together can
///     never use more memory than the host has).
///   Usage is always counted for every container, constrained or not.
/// - With the host total unknown (`/info` failed or reported 0): the
///   denominator is the de-duplicated sum of the reported limits. The largest
///   reported value is presumed to be the host total that unconstrained
///   containers echo, so it is counted once however many containers report
///   it; every smaller value is added individually. Zero limits and
///   "unlimited" sentinels above `maxPlausibleLimit` (1 PiB, e.g.
///   `UInt64.max`) are excluded; if nothing is left the denominator is 0, so
///   health reads `.unknown` instead of a false "fine".
///   This is a degraded path: it can only undercount (never inflate) the
///   denominator, so the gauge errs toward showing more pressure, not less.
/// - With no stats at all the denominator is 0, which every consumer already
///   treats as "no figure" (no division, health `.unknown`).
///
/// Additions saturate at `UInt64.max` so no combination of reported values
/// can trap on overflow.
public enum AggregateMemoryLimit {

    /// Whether `limit` is a real cgroup limit given the host's total memory.
    public static func isRealLimit(_ limit: UInt64, hostMemoryTotal: UInt64) -> Bool {
        limit > 0 && limit < hostMemoryTotal
    }

    /// The aggregate memory denominator for `limits` (one per container with
    /// stats). `hostMemoryTotal` is `/info` `MemTotal`; pass `nil` or 0 when
    /// it is unavailable.
    public static func denominator(limits: [UInt64], hostMemoryTotal: UInt64?) -> UInt64 {
        guard !limits.isEmpty else { return 0 }

        guard let host = hostMemoryTotal, host > 0 else {
            return deduplicatedSum(limits)
        }

        let realLimits = limits.filter { isRealLimit($0, hostMemoryTotal: host) }
        if realLimits.count < limits.count {
            // At least one container is unconstrained.
            return host
        }
        return min(saturatingSum(realLimits), host)
    }

    /// Fallback when the host total is unknown: count the largest reported
    /// limit once (presumed host total echoed by unconstrained containers)
    /// and add every smaller non-zero limit.
    static func deduplicatedSum(_ limits: [UInt64]) -> UInt64 {
        let plausible = limits.filter { $0 > 0 && $0 <= maxPlausibleLimit }
        guard let largest = plausible.max() else { return 0 }
        let smaller = plausible.filter { $0 < largest }
        return saturatingSum(smaller + [largest])
    }

    /// Limits above this (1 PiB) are "unlimited" sentinels such as
    /// `UInt64.max` or a page-rounded `Int64.max`, never real memory. Only
    /// the host-unknown fallback needs it; with the host total known, any
    /// limit at or above it already counts as unconstrained.
    public static let maxPlausibleLimit: UInt64 = 1 << 50

    static func saturatingSum(_ values: [UInt64]) -> UInt64 {
        values.reduce(UInt64(0)) { total, value in
            let (sum, overflow) = total.addingReportingOverflow(value)
            return overflow ? UInt64.max : sum
        }
    }
}
