import Testing
@testable import ContainerBar
import ContainerBarCore

/// CB-079: dual-stack bindings must render as one pill with a stable id, and
/// every popover row id must be unique.
@Suite("PortPresentation")
struct PortPresentationTests {

    private func port(_ publicPort: Int?, _ privatePort: Int, _ type: String = "tcp", ip: String? = "0.0.0.0") -> PortMapping {
        PortMapping(privatePort: privatePort, publicPort: publicPort, type: type, ip: ip)
    }

    @Test("Dual-stack 0.0.0.0 and :: binding renders one pill and one row")
    func dualStackCollapses() {
        let ports = [port(8080, 80, ip: "0.0.0.0"), port(8080, 80, ip: "::")]

        #expect(PortPresentation.cardLabel(for: ports) == ":8080")

        let rows = PortPresentation.rows(for: ports)
        #expect(rows.count == 1)
        #expect(rows[0].id == "*-8080-80/tcp")
        #expect(rows[0].hostAddress == "0.0.0.0")
    }

    @Test("Row id is stable across refreshes and address-family order")
    func dualStackIdIsStable() {
        let v4First = PortPresentation.rows(for: [port(8080, 80, ip: "0.0.0.0"), port(8080, 80, ip: "::")])
        let v6First = PortPresentation.rows(for: [port(8080, 80, ip: "::"), port(8080, 80, ip: "0.0.0.0")])
        let again = PortPresentation.rows(for: [port(8080, 80, ip: "0.0.0.0"), port(8080, 80, ip: "::")])

        #expect(v4First.map(\.id) == ["*-8080-80/tcp"])
        #expect(v6First.map(\.id) == v4First.map(\.id))
        #expect(again == v4First)
        #expect(v4First.map(\.hostAddress) == ["0.0.0.0"])
        #expect(v6First.map(\.hostAddress) == ["0.0.0.0"])
    }

    @Test("IPv6-only wildcard binding keeps its reported address")
    func ipv6OnlyWildcard() {
        let rows = PortPresentation.rows(for: [port(8080, 80, ip: "::")])

        #expect(rows.count == 1)
        #expect(rows[0].id == "*-8080-80/tcp")
        #expect(rows[0].hostAddress == "[::]")
        #expect(PortPresentation.cardLabel(for: [port(8080, 80, ip: "::")]) == ":8080")
    }

    @Test("Missing address still displays the IPv4 wildcard")
    func missingAddressDisplay() {
        let rows = PortPresentation.rows(for: [port(8080, 80, ip: nil), port(8080, 80, ip: "::")])
        #expect(rows.map(\.hostAddress) == ["0.0.0.0"])
    }

    @Test("tcp and udp on one port: one pill, two rows with distinct ids")
    func tcpAndUdpSamePort() {
        let ports = [port(18080, 80, "tcp"), port(18080, 80, "udp")]

        #expect(PortPresentation.cardLabel(for: ports) == ":18080")

        let rows = PortPresentation.rows(for: ports)
        #expect(rows.map(\.type) == ["tcp", "udp"])
        #expect(Set(rows.map(\.id)).count == 2)
    }

    @Test("+k counts distinct published ports only")
    func overflowCountsDistinctPorts() {
        // Seven distinct published ports, two of them reported dual-stack.
        let ports = [
            port(8001, 1), port(8001, 1, ip: "::"),
            port(8002, 2), port(8002, 2, ip: "::"),
            port(8003, 3), port(8004, 4), port(8005, 5), port(8006, 6), port(8007, 7)
        ]

        #expect(PortPresentation.distinctPublicPorts(ports) == [8001, 8002, 8003, 8004, 8005, 8006, 8007])
        #expect(PortPresentation.cardLabel(for: ports) == ":8001 +6")
        #expect(PortPresentation.rows(for: ports).count == 7)
    }

    @Test("Two distinct ports render side by side")
    func twoDistinctPorts() {
        let ports = [port(80, 80), port(80, 80, ip: "::"), port(443, 443), port(443, 443, ip: "::")]
        #expect(PortPresentation.cardLabel(for: ports) == ":80 :443")
    }

    @Test("No published ports renders no pill")
    func noPublishedPorts() {
        #expect(PortPresentation.cardLabel(for: []) == nil)
        #expect(PortPresentation.cardLabel(for: [port(nil, 5432, ip: nil)]) == nil)
    }

    @Test("Unpublished ports keep one row each without an address")
    func unpublishedRows() {
        let rows = PortPresentation.rows(for: [port(nil, 5432, ip: nil), port(nil, 6379, ip: nil)])
        #expect(rows.map(\.id) == ["*---5432/tcp", "*---6379/tcp"])
        #expect(rows.allSatisfy { $0.hostAddress == nil })
    }

    @Test("Explicit host addresses stay separate rows; IPv6 is bracketed")
    func explicitAddresses() {
        let ports = [port(8080, 80, ip: "127.0.0.1"), port(8080, 80, ip: "::1")]
        let rows = PortPresentation.rows(for: ports)

        #expect(rows.map(\.hostAddress) == ["127.0.0.1", "[::1]"])
        #expect(Set(rows.map(\.id)).count == 2)
        #expect(PortPresentation.cardLabel(for: ports) == ":8080")
    }
}
