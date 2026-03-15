import Foundation

/// Resolves app resource bundles without relying on SwiftPM's fatal `Bundle.module` accessor.
///
/// In release `.app` packaging, resources may live under `Contents/Resources`.
/// This helper provides resilient lookup paths for app-owned resources.
enum AppResourceBundle {
    private static let bundleName = "ContainerBar_ContainerBar.bundle"

    private static let resolvedBundle: Bundle = {
        // Standard app layout: MyApp.app/Contents/Resources/<bundleName>
        if let resourcesURL = Bundle.main.resourceURL?
            .appendingPathComponent(bundleName),
           let bundle = Bundle(url: resourcesURL) {
            return bundle
        }

        // SwiftPM accessor expectation for executables: MyApp.app/<bundleName>
        let appRootURL = Bundle.main.bundleURL.appendingPathComponent(bundleName)
        if let bundle = Bundle(url: appRootURL) {
            return bundle
        }

        // Development fallback for command-line runs from the executable directory.
        if let executablePath = Bundle.main.executablePath {
            let executableDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
            let siblingBundle = executableDir.appendingPathComponent(bundleName)
            if let bundle = Bundle(url: siblingBundle) {
                return bundle
            }
        }

        // Graceful fallback: avoids startup/menu-open crashes if resources are unavailable.
        return Bundle.main
    }()

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        resolvedBundle.url(forResource: name, withExtension: ext)
    }
}
