import Foundation
import ContainerBarCore
import Logging

/// Offline QA mode for Prowl hunts and headless verification.
///
/// Active when `CONTAINERBAR_HUNT_MODE=1` is in the environment or the app was
/// built into the `.prowl/DerivedData` path the Prowl QA workflow uses. In hunt
/// mode the app talks to `FixtureDockerAPIClient` instead of any real daemon,
/// and preferences live in a throwaway `UserDefaults` suite that is wiped on
/// every launch, so real hosts, sections, and credentials are never touched.
enum HuntMode {
    static let environmentKey = "CONTAINERBAR_HUNT_MODE"
    static let derivedDataMarker = "/.prowl/DerivedData/"
    static let defaultsSuite = "com.tookes.ContainerBar.hunt"

    private static let logger = Logger(label: "com.containerbar.huntmode")

    enum Failure: LocalizedError, Equatable {
        case defaultsSuiteUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .defaultsSuiteUnavailable(let suiteName):
                "Could not create isolated hunt defaults suite '\(suiteName)'"
            }
        }
    }

    static let isActive: Bool = {
        let env = ProcessInfo.processInfo.environment[environmentKey] == "1"
        let path = Bundle.main.bundlePath.contains(derivedDataMarker)
        if env || path {
            logger.info("Hunt mode active (env: \(env), derivedData: \(path))")
        }
        return env || path
    }()

    /// Fresh, isolated defaults for this launch.
    static func makeUserDefaults(
        suiteName: String = defaultsSuite,
        makeSuite: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) }
    ) throws -> UserDefaults {
        guard let defaults = makeSuite(suiteName) else {
            logger.critical("Could not create hunt defaults suite; refusing to use standard defaults")
            throw Failure.defaultsSuiteUnavailable(suiteName)
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// Fetcher factory that ignores the requested host and serves fixtures.
    static func makeFetcher(for host: DockerHost?) throws -> ContainerFetcher {
        ContainerFetcher.fixture()
    }

    /// Replace whatever hosts the defaults seeded with the single fixture host.
    @MainActor
    static func seed(_ settings: SettingsStore) {
        let fixture = DockerHost.fixture
        if !settings.hosts.contains(where: { $0.id == fixture.id }) {
            settings.addHost(fixture)
        }
        for host in settings.hosts where host.id != fixture.id {
            settings.removeHost(id: host.id)
        }
        settings.selectedHostId = fixture.id
    }
}
