import AppKit
import SwiftUI

/// NSHostingView subclass whose height follows its SwiftUI content.
///
/// `sizingOptions = [.intrinsicContentSize]` makes AppKit keep
/// `intrinsicContentSize` in step with the content's ideal size and
/// invalidate layout when it changes. The frame is still written here rather
/// than left to Auto Layout: a menu item view is sized from its frame, and its
/// autoresizing-mask constraints pin that frame at required priority, so
/// intrinsic-size constraints alone could never change the height.
final class AutoResizingHostingView<Content: View>: NSHostingView<Content> {
    private static var minHeight: CGFloat { 300 }

    private let maxHeight: CGFloat

    init(rootView: Content, maxHeight: CGFloat) {
        self.maxHeight = maxHeight
        super.init(rootView: rootView)
        sizingOptions = [.intrinsicContentSize]
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

        let intrinsic = intrinsicContentSize.height
        let ideal = intrinsic == NSView.noIntrinsicMetric ? fittingSize.height : intrinsic
        let clamped = min(max(ideal, Self.minHeight), maxHeight)

        guard abs(frame.size.height - clamped) > 1 else { return }
        frame.size.height = clamped

        // Tell the menu to recalculate on the next run-loop pass
        // to avoid recursive layout.
        DispatchQueue.main.async { [weak self] in
            self?.enclosingMenuItem?.menu?.update()
        }
    }
}
