import AppKit
import SwiftUI

/// NSHostingView subclass that automatically resizes its frame when
/// SwiftUI content changes, and notifies the enclosing NSMenu so the
/// menu item height updates to match.
final class AutoResizingHostingView<Content: View>: NSHostingView<Content> {
    private let maxHeight: CGFloat

    init(rootView: Content, maxHeight: CGFloat) {
        self.maxHeight = maxHeight
        super.init(rootView: rootView)
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

        let ideal = fittingSize.height
        let clamped = min(max(ideal, 300), maxHeight)

        guard abs(frame.size.height - clamped) > 1 else { return }
        frame.size.height = clamped

        // Tell the menu to recalculate on the next run-loop pass
        // to avoid recursive layout.
        DispatchQueue.main.async { [weak self] in
            self?.enclosingMenuItem?.menu?.update()
        }
    }
}
