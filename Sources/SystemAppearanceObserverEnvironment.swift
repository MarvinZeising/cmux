import AppKit
import Foundation

/// Wraps a `DistributedNotificationCenter` observer token so it can be
/// invalidated through the same `EffectiveAppearanceObservation` contract the
/// KVO-based observers use.
private final class DistributedNotificationObservation: EffectiveAppearanceObservation {
    private var token: NSObjectProtocol?

    init(token: NSObjectProtocol) {
        self.token = token
    }

    func invalidate() {
        guard let token else { return }
        DistributedNotificationCenter.default().removeObserver(token)
        self.token = nil
    }

    deinit {
        if let token {
            DistributedNotificationCenter.default().removeObserver(token)
        }
    }
}

extension SystemAppearanceObserver {
    struct Environment {
        let startEffectiveAppearanceObservation: @MainActor (@escaping @MainActor () -> Void) -> EffectiveAppearanceObservation?
        let startDistributedAppearanceObservation: @MainActor (@escaping @MainActor () -> Void) -> EffectiveAppearanceObservation?
        let currentAppearanceModeRawValue: @MainActor () -> String?
        let effectivePrefersDark: @MainActor () -> Bool
        let synchronizeTerminalTheme: @MainActor (Bool) -> Void
        let postSystemAppearanceDidChange: @MainActor () -> Void

        @MainActor
        static func live() -> Environment {
            Environment(
                startEffectiveAppearanceObservation: { handler in
                    guard let app = NSApp else { return nil }
                    return app.observe(\.effectiveAppearance, options: []) { _, _ in
                        Task { @MainActor in
                            handler()
                        }
                    }
                },
                // Wake-up trigger only (see SystemAppearanceObserver's doc
                // comment); the KVO watch above misses backgrounded toggles.
                startDistributedAppearanceObservation: { handler in
                    let token = DistributedNotificationCenter.default().addObserver(
                        forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                        object: nil,
                        queue: .main
                    ) { _ in
                        Task { @MainActor in
                            handler()
                        }
                    }
                    return DistributedNotificationObservation(token: token)
                },
                currentAppearanceModeRawValue: {
                    UserDefaults.standard.string(forKey: AppearanceSettings.appearanceModeKey)
                },
                effectivePrefersDark: {
                    // effectiveAppearance freezes while backgrounded (#8998);
                    // fall back to a synchronized AppleInterfaceStyle read.
                    if NSApp?.isActive == true, let appearance = NSApp?.effectiveAppearance {
                        return appearance.cmuxPrefersDark
                    }
                    UserDefaults.standard.synchronize()
                    return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
                },
                synchronizeTerminalTheme: { prefersDark in
                    // Use the just-resolved value, not effectiveAppearance,
                    // which can still be stale while backgrounded.
                    GhosttyApp.shared.synchronizeThemeWithAppearance(
                        NSAppearance(named: prefersDark ? .darkAqua : .aqua),
                        source: "systemAppearanceObserver"
                    )
                },
                postSystemAppearanceDidChange: {
                    NotificationCenter.default.post(name: .systemAppearanceDidChange, object: nil)
                }
            )
        }
    }
}
