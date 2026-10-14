import Foundation

/// Validates the SSH user and host before they reach the `ssh` command line.
///
/// `ssh` parses any argument that begins with `-` as an option, so a user or
/// host such as `-oProxyCommand=…` would run an arbitrary command. The tunnel
/// launcher already passes the user with `-l` and ends option parsing with `--`;
/// this validator is the second layer, applied when a host is saved from a form
/// and again when a client is created from saved settings (CB-072).
public enum SSHTargetValidator {
    public enum ValidationError: LocalizedError, Equatable, Sendable {
        case invalidUser
        case invalidHost

        /// One message for both fields so the form and the connect-time error read the same.
        public static let message = "Host and user cannot start with '-' or contain spaces."

        public var errorDescription: String? {
            Self.message
        }
    }

    /// Upper bound for either value; a DNS name is at most 253 characters.
    static let maximumLength = 255

    /// Throws if `user` or `host` could be misread by `ssh` or is not a plausible value.
    public static func validate(host: String, user: String) throws {
        try validateUser(user)
        try validateHost(host)
    }

    /// The user must match `[A-Za-z0-9._][A-Za-z0-9._-]*`.
    public static func validateUser(_ user: String) throws {
        guard isUser(user) else {
            throw ValidationError.invalidUser
        }
    }

    /// The host must be a hostname, an `~/.ssh/config` alias, an IPv4 address,
    /// or a bracket-free IPv6 literal (optionally with a `%zone` suffix).
    public static func validateHost(_ host: String) throws {
        guard isHost(host) else {
            throw ValidationError.invalidHost
        }
    }

    private static func isUser(_ user: String) -> Bool {
        guard let first = user.unicodeScalars.first,
              user.unicodeScalars.count <= maximumLength,
              first != "-" else {
            return false
        }
        return user.unicodeScalars.allSatisfy { isNameCharacter($0) }
    }

    private static func isHost(_ host: String) -> Bool {
        guard let first = host.unicodeScalars.first,
              host.unicodeScalars.count <= maximumLength,
              first != "-" else {
            return false
        }

        if host.contains(":") {
            return isIPv6Literal(host)
        }
        return host.unicodeScalars.allSatisfy { isNameCharacter($0) }
    }

    /// Hex groups, colons, and dots (for an embedded IPv4 tail), then an optional
    /// `%zone` made of name characters, e.g. `fe80::1%en0`.
    private static func isIPv6Literal(_ host: String) -> Bool {
        let parts = host.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
        let address = parts[0]
        guard address.filter({ $0 == ":" }).count >= 2 else {
            return false
        }
        let addressIsValid = address.unicodeScalars.allSatisfy { scalar in
            scalar == ":" || scalar == "." || isHexDigit(scalar)
        }
        guard addressIsValid else {
            return false
        }
        guard parts.count == 2 else {
            return true
        }
        let zone = parts[1]
        return !zone.isEmpty && zone.unicodeScalars.allSatisfy { isNameCharacter($0) }
    }

    private static func isNameCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", ".", "_", "-":
            return true
        default:
            return false
        }
    }

    private static func isHexDigit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."f", "A"..."F", "0"..."9":
            return true
        default:
            return false
        }
    }
}
