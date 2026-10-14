import ContainerBarCore

/// Pure formatting of a container's port bindings for the dashboard card pill
/// and the detail popover (CB-079).
///
/// Docker with IPv6 enabled reports one `PortMapping` per address family for
/// the same binding (`0.0.0.0:8080->80/tcp` and `[::]:8080->80/tcp`), and tcp
/// plus udp on one port share `privatePort`. These helpers collapse the
/// dual-stack duplicates and give every popover row a stable, unique id.
enum PortPresentation {
    /// Maximum number of rows the detail popover lists before "+ N more".
    static let maxPopoverRows = 5

    /// One popover row: a distinct binding after dual-stack collapsing.
    struct Row: Identifiable, Equatable, Sendable {
        /// Composite key `address-publicPort-privatePort/type`; unique per row.
        let id: String
        /// Host address to display (IPv6 bracketed), nil when unpublished.
        let hostAddress: String?
        let publicPort: Int?
        let privatePort: Int
        let type: String
    }

    /// Distinct bindings in first-seen order. Wildcard addresses (`0.0.0.0`,
    /// `::`, missing) are one binding, so a dual-stack pair yields one row;
    /// explicit addresses and different protocols stay separate rows.
    static func rows(for ports: [PortMapping]) -> [Row] {
        var indexById: [String: Int] = [:]
        var rows: [Row] = []
        for port in ports {
            let addressKey = isWildcard(port.ip) ? "*" : (port.ip ?? "*")
            let publicKey = port.publicPort.map(String.init) ?? "-"
            let id = "\(addressKey)-\(publicKey)-\(port.privatePort)/\(port.type)"
            let address = port.publicPort == nil ? nil : displayAddress(port.ip)
            if let index = indexById[id] {
                // A collapsed dual-stack pair shows the IPv4 wildcard when one
                // is present, whatever order the runtime listed them in.
                if rows[index].hostAddress == "[::]", address == "0.0.0.0" {
                    rows[index] = Row(
                        id: id,
                        hostAddress: address,
                        publicPort: port.publicPort,
                        privatePort: port.privatePort,
                        type: port.type
                    )
                }
                continue
            }
            indexById[id] = rows.count
            rows.append(Row(
                id: id,
                hostAddress: address,
                publicPort: port.publicPort,
                privatePort: port.privatePort,
                type: port.type
            ))
        }
        return rows
    }

    /// Distinct published host ports in first-seen order.
    static func distinctPublicPorts(_ ports: [PortMapping]) -> [Int] {
        var seen = Set<Int>()
        return ports.compactMap(\.publicPort).filter { seen.insert($0).inserted }
    }

    /// Card pill text: nil with no published ports, `:a` or `:a :b` for one or
    /// two distinct ports, `:a +k` (k distinct others) beyond that.
    static func cardLabel(for ports: [PortMapping]) -> String? {
        let publicPorts = distinctPublicPorts(ports)
        switch publicPorts.count {
        case 0:
            return nil
        case 1, 2:
            return publicPorts.map { ":\($0)" }.joined(separator: " ")
        default:
            return ":\(publicPorts[0]) +\(publicPorts.count - 1)"
        }
    }

    static func isWildcard(_ ip: String?) -> Bool {
        guard let ip, !ip.isEmpty else { return true }
        return ip == "0.0.0.0" || ip == "::"
    }

    /// The reported binding address, IPv6 bracketed so `addr:port` stays
    /// readable (`::` shows as `[::]`). A missing address shows `0.0.0.0`,
    /// the pre-CB-079 default.
    static func displayAddress(_ ip: String?) -> String {
        guard let ip, !ip.isEmpty else { return "0.0.0.0" }
        return ip.contains(":") ? "[\(ip)]" : ip
    }
}
