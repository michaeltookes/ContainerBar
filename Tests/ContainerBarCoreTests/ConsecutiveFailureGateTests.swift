import Foundation
import Testing
@testable import ContainerBarCore

@Suite("ConsecutiveFailureGate Tests")
struct ConsecutiveFailureGateTests {

    @Test("Default threshold is 2")
    func defaultThreshold() {
        let gate = ConsecutiveFailureGate()

        // First failure with prior data - should NOT surface
        let shouldSurface1 = gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(shouldSurface1 == false)

        // Second failure with prior data - should surface (threshold reached)
        let shouldSurface2 = gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(shouldSurface2 == true)
    }

    @Test("Custom threshold is respected")
    func customThreshold() {
        let gate = ConsecutiveFailureGate(threshold: 3)

        // Failures 1 and 2 should not surface
        #expect(gate.shouldSurfaceError(onFailureWithPriorData: true) == false)
        #expect(gate.shouldSurfaceError(onFailureWithPriorData: true) == false)

        // Failure 3 should surface
        #expect(gate.shouldSurfaceError(onFailureWithPriorData: true) == true)
    }

    @Test("Error surfaces immediately without prior data")
    func immediateErrorWithoutPriorData() {
        let gate = ConsecutiveFailureGate(threshold: 5)

        // Even with high threshold, should surface immediately when no prior data
        let shouldSurface = gate.shouldSurfaceError(onFailureWithPriorData: false)
        #expect(shouldSurface == true)
    }

    @Test("Success resets failure count")
    func successResetsCount() {
        let gate = ConsecutiveFailureGate(threshold: 2)

        // One failure
        _ = gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(gate.failureCount == 1)

        // Success resets
        gate.recordSuccess()
        #expect(gate.failureCount == 0)

        // Next failure starts fresh
        let shouldSurface = gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(shouldSurface == false)
        #expect(gate.failureCount == 1)
    }

    @Test("Reset clears failure count")
    func resetClearsCount() {
        let gate = ConsecutiveFailureGate(threshold: 2)

        // Accumulate failures
        _ = gate.shouldSurfaceError(onFailureWithPriorData: true)
        _ = gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(gate.failureCount == 2)

        // Reset
        gate.reset()
        #expect(gate.failureCount == 0)
    }

    @Test("Failure count tracks correctly")
    func failureCountTracks() {
        let gate = ConsecutiveFailureGate(threshold: 5)

        #expect(gate.failureCount == 0)

        _ = gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(gate.failureCount == 1)

        _ = gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(gate.failureCount == 2)

        _ = gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(gate.failureCount == 3)
    }

    @Test("Gate continues to surface after threshold")
    func continuesSurfacingAfterThreshold() {
        let gate = ConsecutiveFailureGate(threshold: 2)

        // Reach threshold
        _ = gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(gate.shouldSurfaceError(onFailureWithPriorData: true) == true)

        // Should continue surfacing
        #expect(gate.shouldSurfaceError(onFailureWithPriorData: true) == true)
        #expect(gate.shouldSurfaceError(onFailureWithPriorData: true) == true)
    }

    @Test("Threshold of 1 surfaces immediately with prior data")
    func thresholdOfOneSurfacesImmediately() {
        let gate = ConsecutiveFailureGate(threshold: 1)

        let shouldSurface = gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(shouldSurface == true)
    }
}
