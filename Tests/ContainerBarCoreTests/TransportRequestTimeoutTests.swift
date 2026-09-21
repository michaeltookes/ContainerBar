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
        #expect(request.disablesRequestTimeout == false)
    }

    @Test("HTTPRequest can disable the request timeout")
    func httpRequestCanDisableRequestTimeout() {
        let request = HTTPRequest(
            method: "POST",
            path: "/v1.43/containers/abc/stop?t=-1",
            disablesRequestTimeout: true
        )

        #expect(request.disablesRequestTimeout)
    }

    @Test("Lifecycle actions request enough time for Docker timeout plus response grace")
    func lifecycleActionMinimumRequestTimeout() {
        let longTimeout = DockerAPIClientImpl.lifecycleActionMinimumRequestTimeout(for: 60)

        #expect(longTimeout == 70)
        #expect(longTimeout ?? 0 > 60)
        #expect(DockerAPIClientImpl.lifecycleActionMinimumRequestTimeout(for: nil) == nil)
        #expect(DockerAPIClientImpl.lifecycleActionMinimumRequestTimeout(for: 0) == nil)
        #expect(DockerAPIClientImpl.lifecycleActionMinimumRequestTimeout(for: -1) == nil)
        #expect(DockerAPIClientImpl.lifecycleActionDisablesRequestTimeout(for: -1))
        #expect(!DockerAPIClientImpl.lifecycleActionDisablesRequestTimeout(for: nil))
        #expect(!DockerAPIClientImpl.lifecycleActionDisablesRequestTimeout(for: 60))
    }

    @Test("Transport request timeout honors longer request minimum without shortening defaults")
    func transportRequestTimeoutResolution() {
        #expect(NWConnectionTransport.resolvedRequestTimeout(
            defaultTimeout: 30,
            minimumRequestTimeout: nil
        ) == .some(30))
        #expect(NWConnectionTransport.resolvedRequestTimeout(
            defaultTimeout: 30,
            minimumRequestTimeout: 15
        ) == .some(30))
        #expect(NWConnectionTransport.resolvedRequestTimeout(
            defaultTimeout: 30,
            minimumRequestTimeout: 70
        ) == .some(70))
        #expect(NWConnectionTransport.resolvedRequestTimeout(
            defaultTimeout: 30,
            minimumRequestTimeout: 70,
            disablesRequestTimeout: true
        ) == nil)
    }

    @Test("Container log requests have a larger response budget")
    func containerLogsMinimumRequestTimeout() {
        #expect(DockerAPIClientImpl.containerLogsMinimumRequestTimeout > 30)
        #expect(NWConnectionTransport.resolvedRequestTimeout(
            defaultTimeout: 30,
            minimumRequestTimeout: DockerAPIClientImpl.containerLogsMinimumRequestTimeout
        ) == .some(DockerAPIClientImpl.containerLogsMinimumRequestTimeout))
    }

    @Test("Unix socket retry policy does not replay non-idempotent sends")
    func unixSocketRetryPolicyDoesNotReplayNonIdempotentSends() {
        let restart = HTTPRequest(
            method: "POST",
            path: "/v1.44/containers/abc/restart"
        )
        let remove = HTTPRequest(
            method: "DELETE",
            path: "/v1.44/containers/abc?force=true&v=false",
            allowsRetryAfterSend: false
        )
        let list = HTTPRequest(
            method: "GET",
            path: "/v1.44/containers/json"
        )

        #expect(DockerAPIClientImpl.shouldRetryUnixSocketRequest(
            restart,
            after: DockerAPIError.networkTimeout,
            sendWasAttempted: false
        ))
        #expect(!DockerAPIClientImpl.shouldRetryUnixSocketRequest(
            restart,
            after: DockerAPIError.networkTimeout,
            sendWasAttempted: true
        ))
        #expect(DockerAPIClientImpl.shouldRetryUnixSocketRequest(
            restart,
            after: HTTPRequestNotSentError(),
            sendWasAttempted: true
        ))
        #expect(!DockerAPIClientImpl.shouldRetryUnixSocketRequest(
            remove,
            after: DockerAPIError.networkTimeout,
            sendWasAttempted: true
        ))
        #expect(DockerAPIClientImpl.shouldRetryUnixSocketRequest(
            list,
            after: DockerAPIError.networkTimeout,
            sendWasAttempted: true
        ))
    }
}
