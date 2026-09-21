import Foundation
import Testing
@testable import ContainerBarCore

@Suite("Transport Request Timeout Tests")
struct TransportRequestTimeoutTests {

    @Test("HTTPRequest can carry a per-request minimum timeout")
    func httpRequestMinimumTimeout() {
        let request = HTTPRequest(
            method: "POST",
            path: "/v1.43/containers/abc/stop?t=60",
            minimumRequestTimeout: 70
        )

        #expect(request.minimumRequestTimeout == 70)
    }

    @Test("Lifecycle actions request enough time for Docker timeout plus response grace")
    func lifecycleActionMinimumRequestTimeout() {
        let longTimeout = DockerAPIClientImpl.lifecycleActionMinimumRequestTimeout(for: 60)

        #expect(longTimeout == 70)
        #expect(longTimeout ?? 0 > 60)
        #expect(DockerAPIClientImpl.lifecycleActionMinimumRequestTimeout(for: nil) == nil)
        #expect(DockerAPIClientImpl.lifecycleActionMinimumRequestTimeout(for: 0) == nil)
    }

    @Test("Transport request timeout honors longer request minimum without shortening defaults")
    func transportRequestTimeoutResolution() {
        #expect(NWConnectionTransport.resolvedRequestTimeout(
            defaultTimeout: 30,
            minimumRequestTimeout: nil
        ) == 30)
        #expect(NWConnectionTransport.resolvedRequestTimeout(
            defaultTimeout: 30,
            minimumRequestTimeout: 15
        ) == 30)
        #expect(NWConnectionTransport.resolvedRequestTimeout(
            defaultTimeout: 30,
            minimumRequestTimeout: 70
        ) == 70)
    }
}
