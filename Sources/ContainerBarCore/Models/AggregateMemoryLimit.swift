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
///   denominator is 0, so the figure is "unknown" (no fraction, health
///   `.unknown`) until `/info` answers. The reported limits alone cannot say
///   which value is an echoed host total and which is a real cap (two real
///   512 MiB caps look the same as two unconstrained containers on a 512 MiB
///   host), so any guess would either exaggerate usage or suppress the 95 %
///   warning. Usage is still summed and shown.
/// - With no stats at all the denominator is 0, which every consumer already
///   treats as "no figure" (no division, health `.unknown`).
///
/// Additions saturate at `UInt64.max` so no combination of reported values
/// (for example a `UInt64.max` "unlimited" sentinel) can trap on overflow.
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

        // Host total unknown: do not guess (see the type documentation).
        guard let host = hostMemoryTotal, host > 0 else { return 0 }

        let realLimits = limits.filter { isRealLimit($0, hostMemoryTotal: host) }
        if realLimits.count < limits.count {
            // At least one container is unconstrained.
            return host
        }
        return min(saturatingSum(realLimits), host)
    }

    static func saturatingSum(_ values: [UInt64]) -> UInt64 {
        values.reduce(UInt64(0)) { total, value in
            let (sum, overflow) = total.addingReportingOverflow(value)
            return overflow ? UInt64.max : sum
        }
    }
}
