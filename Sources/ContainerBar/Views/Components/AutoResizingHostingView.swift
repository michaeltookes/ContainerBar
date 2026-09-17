import AppKit
import SwiftUI

/// NSHostingView subclass that lets AppKit drive vertical sizing natively
/// via `sizingOptions = [.intrinsicContentSize]`, bounded by Auto Layout
/// height constraints (min 300, max `maxHeight`). When the resulting height
/// changes it notifies the enclosing NSMenu so the menu item row re-measures.
final class AutoResizingHostingView<Content: View>: NSHostingView<Content> {
    /// Last height we notified the menu about, to avoid redundant updates.
    private var lastNotifiedHeight: CGFloat = 0

    init(rootView: Content, maxHeight: CGFloat) {
        super.init(rootView: rootView)

        // Let the hosting view report and track its SwiftUI content's ideal
        // size instead of hand-rolling frame math in `layout()`.
        sizingOptions = [.intrinsicContentSize]

        // Re-express the clamp that the old manual `layout()` enforced:
        // never shorter than 300pt, never taller than the available screen.
        // `.intrinsicContentSize` supplies the natural height; these bound it.
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            heightAnchor.constraint(lessThanOrEqualToConstant: maxHeight)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @available(*, unavailable)
    required init(rootView: Content) {
        fatalError("Use init(rootView:maxHeight:)")
    }

    override func layout() {
        super.layout()

        // Native intrinsic sizing + constraints drive the frame height now;
        // we no longer compute or set it here. But the enclosing NSMenu may
        // still need a nudge to re-lay-out the item row when the height
        // changes. Kept conservatively — this cannot be verified over SSH,
        // so the Prowl menu-smoke/settings-window gate confirms it.
        let currentHeight = frame.size.height
        guard abs(currentHeight - lastNotifiedHeight) > 1 else { return }
        lastNotifiedHeight = currentHeight

        // Defer to the next run-loop pass to avoid recursive layout.
        DispatchQueue.main.async { [weak self] in
            self?.enclosingMenuItem?.menu?.update()
        }
    }
}
