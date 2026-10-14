import Foundation

/// Validates the SSH user and host before they reach the `ssh` command line.
///
/// `ssh` parses any argument that begins with `-` as an option, so a user or
/// host such as `-oProxyCommand=…` would run an arbitrary command. The tunnel
/// launcher already passes the user with `-l` and ends option parsing with `--`,
/// and `ssh` is exec'd directly with no shell, so this is a denylist of what can
/// still go wrong rather than an allowlist: logins such as `alice@EXAMPLE.COM`
/// and `~/.ssh/config` aliases such as `prod+vpn` must keep working. It is
/// applied when a host is saved from a form, when a client is created from
/// saved settings, and again before launch (CB-072).
public enum SSHTargetValidator {
    public enum ValidationError: LocalizedError, Equatable, Sendable {
        case invalidUser
        case invalidHost

        /// One message for both fields so the form and the connect-time error read the same.
        public static let message = "Host and user cannot be empty, start with '-', or contain spaces or control characters."

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

    public static func validateUser(_ user: String) throws {
        guard isAcceptable(user) else {
            throw ValidationError.invalidUser
        }
    }

    public static func validateHost(_ host: String) throws {
        guard isAcceptable(host) else {
            throw ValidationError.invalidHost
        }
    }

    /// Non-empty, within the length cap, no leading `-`, and no whitespace or
    /// control characters (NUL included). Everything else is left to `ssh`.
    private static func isAcceptable(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        guard let first = scalars.first,
              first != "-",
              scalars.count <= maximumLength else {
            return false
        }
        return !scalars.contains { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar)
        }
    }
}
