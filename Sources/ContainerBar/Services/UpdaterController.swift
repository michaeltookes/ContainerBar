@preconcurrency import Sparkle
import Logging

/// Manages Sparkle auto-update functionality
///
/// Wraps SPUStandardUpdaterController and provides a clean interface
/// for the rest of the app to interact with the updater.
@MainActor
final class UpdaterController: NSObject {
    static let shared = UpdaterController()

    private let logger = Logger(label: "com.containerbar.updater")

    /// The underlying Sparkle updater controller
    private let updaterController: SPUStandardUpdaterController

    /// Whether the updater can currently check for updates
    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    /// Whether automatic update checks are enabled
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    /// The date of the last update check
    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }

    private override init() {
        #if DEBUG
        let shouldStart = false
        #else
        let shouldStart = true
        #endif
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: shouldStart,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
        logger.info("Sparkle updater initialized (startingUpdater: \(shouldStart))")
    }

    /// Explicitly check for updates (user-initiated)
    func checkForUpdates() {
        logger.info("User-initiated update check")
        updaterController.checkForUpdates(nil)
    }
}
