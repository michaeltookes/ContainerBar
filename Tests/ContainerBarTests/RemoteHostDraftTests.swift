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
