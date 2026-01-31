import SwiftUI
import AppKit

/// About pane showing app information
struct AboutPane: View {
    private var appIcon: NSImage {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            return icon
        }
        return NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 20) {
            // App icon and name
            VStack(spacing: 12) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 96, height: 96)

                Text("ContainerBar")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Description
            Text("A lightweight macOS menu bar application for Docker container monitoring and management.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)

            Divider()
                .frame(maxWidth: 200)

            // Links
            VStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/michaeltookes/ContainerBar")!) {
                    HStack {
                        Image(systemName: "link")
                        Text("GitHub Repository")
                    }
                }

                Link(destination: URL(string: "https://docs.docker.com/engine/api/")!) {
                    HStack {
                        Image(systemName: "book")
                        Text("Docker API Documentation")
                    }
                }
            }

            Spacer()
                .frame(minHeight: 20)

            // Copyright
            VStack(spacing: 4) {
                Text("Made with Swift and SwiftUI")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text("\(copyrightYear) ContainerBar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var copyrightYear: String {
        let year = Calendar.current.component(.year, from: Date())
        return "\(year)"
    }
}

#if DEBUG
#Preview {
    AboutPane()
        .frame(width: 450, height: 400)
}
#endif
