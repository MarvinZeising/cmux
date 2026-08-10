import XCTest
import AppKit

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Regression coverage for the split-pane active-border offset: a
/// `didChangeGeometry` notification resumes `scheduleGeometryRefresh`'s Task on
/// the next main-actor turn, which is not necessarily after AppKit has finished
/// laying out the newly split pane. Reading pane rects before that layout pass
/// settles reproduces the ~2-row (`topChromeHeight`) border offset, so the
/// refresh must force the pass to finish before invoking `stateProvider`.
@MainActor
final class WindowTmuxWorkspacePaneOverlayControllerGeometryRefreshTests: XCTestCase {
    private final class LayoutTrackingView: NSView {
        private(set) var layoutSubtreeIfNeededCallCount = 0

        override func layoutSubtreeIfNeeded() {
            layoutSubtreeIfNeededCallCount += 1
            super.layoutSubtreeIfNeeded()
        }
    }

    func testGeometryRefreshFlushesPendingLayoutBeforeReadingState() async {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let trackingView = LayoutTrackingView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = trackingView

        let controller = WindowTmuxWorkspacePaneOverlayController.controller(for: window, createIfNeeded: true)!

        var layoutCallCountWhenStateProviderRan: Int?
        controller.scheduleGeometryRefresh {
            layoutCallCountWhenStateProviderRan = trackingView.layoutSubtreeIfNeededCallCount
            return nil
        }

        // Let the Task scheduled by scheduleGeometryRefresh actually run.
        for _ in 0..<5 { await Task.yield() }

        XCTAssertEqual(
            layoutCallCountWhenStateProviderRan,
            1,
            "stateProvider must run after a layoutSubtreeIfNeeded() pass, not before it"
        )
    }
}
