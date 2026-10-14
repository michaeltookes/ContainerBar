import Testing
@testable import ContainerBar

@Suite("RemoteHostDraftBuilder Tests")
struct RemoteHostDraftTests {
    @Test("Rejects malformed inline host ports")
    func rejectsMalformedInlinePorts() {
        #expect(
            (try? RemoteHostDraftBuilder.build(nameInput: "", hostInput: "host:", userInput: "")) == nil
        )
        #expect(
            (try? RemoteHostDraftBuilder.build(nameInput: "", hostInput: "host:abc", userInput: "")) == nil
        )
        #expect(
            (try? RemoteHostDraftBuilder.build(nameInput: "", hostInput: "[::1]extra", userInput: "")) == nil
        )
    }

    @Test("Parses valid bracketed host and port")
    func parsesBracketedHostAndPort() throws {
        let draft = try RemoteHostDraftBuilder.build(
            nameInput: "Server",
            hostInput: "[::1]:2222",
            userInput: "root"
        )

        #expect(draft.host == "::1")
        #expect(draft.sshPort == 2222)
    }
}

@Suite("RemoteHostDraftBuilder SSH target validation (CB-072)")
struct RemoteHostDraftSSHTargetTests {
    private static let message = "Host and user cannot start with '-' or contain spaces."

    @Test("Refuses a user that ssh would parse as an option", arguments: [
        "-oProxyCommand=touch /tmp/cbqa-pwned", "-l", "-lroot", "alice@evil", "alice smith"
    ])
    func refusesHostileUser(user: String) {
        do {
            _ = try RemoteHostDraftBuilder.build(nameInput: "QA", hostInput: "cbqa-invalid.invalid", userInput: user)
            Issue.record("Expected build to throw for user \(user)")
        } catch {
            #expect(error.localizedDescription == Self.message)
        }
        #expect(!RemoteHostDraftBuilder.isValid(nameInput: "QA", hostInput: "cbqa-invalid.invalid", userInput: user))
        #expect(RemoteHostDraftBuilder.sshTargetMessage(hostInput: "cbqa-invalid.invalid", userInput: user) == Self.message)
    }

    @Test("Refuses a host that ssh would parse as an option", arguments: [
        "-oProxyCommand=sh", "-oProxyCommand=sh:22", "-v"
    ])
    func refusesHostileHost(host: String) {
        do {
            _ = try RemoteHostDraftBuilder.build(nameInput: "QA", hostInput: host, userInput: "root")
            Issue.record("Expected build to throw for host \(host)")
        } catch {
            #expect(error.localizedDescription == Self.message)
        }
        #expect(RemoteHostDraftBuilder.sshTargetMessage(hostInput: host, userInput: "root") == Self.message)
    }

    @Test("Accepts an ssh config alias, IPv4, and bracketed IPv6", arguments: [
        ("cbqa-tunnel", "cbqa-tunnel"), ("192.168.1.10:2222", "192.168.1.10"), ("[fe80::1%en0]:22", "fe80::1%en0")
    ])
    func acceptsValidHosts(input: String, expectedHost: String) throws {
        let draft = try RemoteHostDraftBuilder.build(nameInput: "", hostInput: input, userInput: "")
        #expect(draft.host == expectedHost)
        #expect(draft.sshUser == "root")
        #expect(RemoteHostDraftBuilder.sshTargetMessage(hostInput: input, userInput: "") == nil)
    }

    @Test("No inline message while the host field is still empty")
    func noMessageForEmptyHost() {
        #expect(RemoteHostDraftBuilder.sshTargetMessage(hostInput: "", userInput: "root") == nil)
    }
}
