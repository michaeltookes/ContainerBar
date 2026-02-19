import Foundation
import Testing
@testable import ContainerBarCore

@Suite("ConsecutiveFailureGate Tests")
struct ConsecutiveFailureGateTests {

    @Test("Default threshold is 2")
    func defaultThreshold() async {
        let gate = ConsecutiveFailureGate()

        // First failure with prior data - should NOT surface
        let shouldSurface1 = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(shouldSurface1 == false)

        // Second failure with prior data - should surface (threshold reached)
        let shouldSurface2 = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(shouldSurface2 == true)
    }

    @Test("Custom threshold is respected")
    func customThreshold() async {
        let gate = ConsecutiveFailureGate(threshold: 3)

        // Failures 1 and 2 should not surface
        let s1 = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(s1 == false)
        let s2 = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(s2 == false)

        // Failure 3 should surface
        let s3 = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(s3 == true)
    }

    @Test("Error surfaces immediately without prior data")
    func immediateErrorWithoutPriorData() async {
        let gate = ConsecutiveFailureGate(threshold: 5)

        // Even with high threshold, should surface immediately when no prior data
        let shouldSurface = await gate.shouldSurfaceError(onFailureWithPriorData: false)
        #expect(shouldSurface == true)
    }

    @Test("Success resets failure count")
    func successResetsCount() async {
        let gate = ConsecutiveFailureGate(threshold: 2)

        // One failure
        _ = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        let count1 = await gate.failureCount
        #expect(count1 == 1)

        // Success resets
        await gate.recordSuccess()
        let count2 = await gate.failureCount
        #expect(count2 == 0)

        // Next failure starts fresh
        let shouldSurface = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(shouldSurface == false)
        let count3 = await gate.failureCount
        #expect(count3 == 1)
    }

    @Test("Reset clears failure count")
    func resetClearsCount() async {
        let gate = ConsecutiveFailureGate(threshold: 2)

        // Accumulate failures
        _ = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        _ = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        let count1 = await gate.failureCount
        #expect(count1 == 2)

        // Reset
        await gate.reset()
        let count2 = await gate.failureCount
        #expect(count2 == 0)
    }

    @Test("Failure count tracks correctly")
    func failureCountTracks() async {
        let gate = ConsecutiveFailureGate(threshold: 5)

        let count0 = await gate.failureCount
        #expect(count0 == 0)

        _ = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        let count1 = await gate.failureCount
        #expect(count1 == 1)

        _ = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        let count2 = await gate.failureCount
        #expect(count2 == 2)

        _ = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        let count3 = await gate.failureCount
        #expect(count3 == 3)
    }

    @Test("Gate continues to surface after threshold")
    func continuesSurfacingAfterThreshold() async {
        let gate = ConsecutiveFailureGate(threshold: 2)

        // Reach threshold
        _ = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        let s1 = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(s1 == true)

        // Should continue surfacing
        let s2 = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(s2 == true)
        let s3 = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(s3 == true)
    }

    @Test("Threshold of 1 surfaces immediately with prior data")
    func thresholdOfOneSurfacesImmediately() async {
        let gate = ConsecutiveFailureGate(threshold: 1)

        let shouldSurface = await gate.shouldSurfaceError(onFailureWithPriorData: true)
        #expect(shouldSurface == true)
    }
}
