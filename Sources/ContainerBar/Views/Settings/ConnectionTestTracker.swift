import Foundation

/// Connection-test state for `ConnectionSettingsPane`, scoped per host (CB-080).
///
/// The pane used to hold one `testResult` and one `isTestingConnection` for
/// whichever host happened to be selected, so a result for host A showed under
/// host B after a selection change, and a test still in flight for A wrote its
/// result under B. Here every result and every in-flight test is keyed by the
/// host id it ran against, and each run carries a token: a completion is
/// accepted only if its run is still the current one for that host, so a run
/// that was restarted, or invalidated by an edit or removal, is dropped.
struct ConnectionTestTracker: Equatable {
    private var results: [UUID: ConnectionTestResult] = [:]
    private var inFlight: [UUID: UUID] = [:]

    /// The last completed result for `hostId`, or nil if it was never tested,
    /// is being tested now, or was edited since its last test.
    func result(for hostId: UUID) -> ConnectionTestResult? {
        results[hostId]
    }

    /// Whether a test for `hostId` is in flight.
    func isTesting(_ hostId: UUID) -> Bool {
        inFlight[hostId] != nil
    }

    /// Starts a run for `hostId`: clears that host's previous result and
    /// returns the token the completion must present to `finish`.
    mutating func begin(hostId: UUID) -> UUID {
        let token = UUID()
        results[hostId] = nil
        inFlight[hostId] = token
        return token
    }

    /// Records `result` for `hostId` if `token` is still that host's current
    /// run. Returns false, and changes nothing, for a superseded run.
    @discardableResult
    mutating func finish(hostId: UUID, token: UUID, result: ConnectionTestResult) -> Bool {
        guard inFlight[hostId] == token else { return false }
        inFlight[hostId] = nil
        results[hostId] = result
        return true
    }

    /// Drops the result and any in-flight run for `hostId`, for when the host
    /// is edited (the old result no longer describes it) or removed.
    mutating func invalidate(hostId: UUID) {
        results[hostId] = nil
        inFlight[hostId] = nil
    }
}
