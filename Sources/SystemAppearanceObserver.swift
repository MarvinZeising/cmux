import AppKit
import Foundation

extension Notification.Name {
    /// Posted by SystemAppearanceObserver when NSApp.effectiveAppearance changes (#6385).
    static let systemAppearanceDidChange = Notification.Name("cmux.systemAppearanceDidChange")
}

extension NSAppearance {
    /// True when this appearance resolves to a dark variant.
    var cmuxPrefersDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// Keeps the app chrome in sync with live macOS appearance changes while the
/// appearance mode is `system`.
///
/// With `NSApplication.appearance == nil`, AppKit updates `effectiveAppearance`
/// when the OS switches Light/Dark, but the SwiftUI hosting layer does not
/// reliably re-resolve the ambient `colorScheme` for already-visible windows
/// (visible when the switch is triggered by Shortcuts' "Set Appearance" or the
/// scheduled Auto switch, #6385). This observer is detect-and-notify only: it
/// KVO-watches `NSApp.effectiveAppearance` and, in system mode, diffs the
/// freshly resolved value against the last-resolved one, and — only on an
/// actual change — posts `.systemAppearanceDidChange` so interested views
/// (see `AppearanceColorSchemeModifier`) can re-resolve their color scheme
/// directly from `NSApp.effectiveAppearance` and force a body recomputation.
///
/// The KVO watch alone misses OS appearance flips while cmux is not the
/// frontmost app: `NSApp.effectiveAppearance` only re-resolves (and fires its
/// KVO) once this process becomes active again, so a toggle made while cmux
/// sits in the background is silently dropped — worse, it also poisons
/// `lastResolvedPrefersDark`, so the *next* real toggle can look like a no-op
/// too (confirmed live: toggling twice while backgrounded produced zero KVO
/// fires and left the terminal panes on the launch-time theme, #8998). To
/// catch background toggles this observer also listens for the system-wide
/// distributed `AppleInterfaceThemeChangedNotification`, which macOS posts to
/// every process regardless of activation state, and re-runs the same
/// resolve-and-diff path from that trigger.
///
/// It is intentionally separate from `AppIconAppearanceObserver`, which observes
/// the same key path but is torn down whenever the app icon isn't in automatic
/// mode, so it cannot be relied upon to refresh app chrome. The two observers
/// own different lifecycles on purpose: the icon observer's teardown is keyed
/// to icon mode, while chrome refresh must stay armed for the whole app
/// lifetime — a single shared observer would couple those lifecycles.
///
/// The AppleInterfaceStyle default is NOT a reliable fresh source while cmux
/// is active: on scripted appearance changes (Shortcuts "Set Appearance"),
/// this process's CFPreferences view of the global domain can remain stale
/// long after AppKit has resolved the new effectiveAppearance — runtime
/// traces show both the direct and globalDomain reads returning the
/// pre-toggle value. effectiveAppearance is the ground truth while active;
/// only while backgrounded, where effectiveAppearance itself never
/// recomputes, does `effectivePrefersDark` fall back to a synchronized read
/// of that same default (see `SystemAppearanceObserverEnvironment`).
@MainActor
final class SystemAppearanceObserver {
    private let environment: Environment
    private var observation: EffectiveAppearanceObservation?
    private var distributedObservation: EffectiveAppearanceObservation?
    private var lastResolvedPrefersDark: Bool?
    private var isObserving = false

    init() {
        environment = .live()
    }

    init(environment: Environment) {
        self.environment = environment
    }

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        lastResolvedPrefersDark = environment.effectivePrefersDark()
        observation = environment.startEffectiveAppearanceObservation { [weak self] in
            self?.handleEffectiveAppearanceChange()
        }
        distributedObservation = environment.startDistributedAppearanceObservation { [weak self] in
            self?.handleEffectiveAppearanceChange()
        }
    }

    // The concrete `NSKeyValueObservation` self-invalidates at deallocation.
    func stopObserving() {
        isObserving = false
        observation?.invalidate()
        observation = nil
        distributedObservation?.invalidate()
        distributedObservation = nil
    }

    private func handleEffectiveAppearanceChange() {
        // Stale-fire guard: the KVO handler can still be in flight (or
        // re-entrantly triggered, see below) after `stopObserving()` has run.
        guard isObserving else { return }
        guard AppearanceSettings.mode(for: environment.currentAppearanceModeRawValue()) == .system else {
            lastResolvedPrefersDark = nil
            return
        }
        let prefersDark = environment.effectivePrefersDark()
        guard prefersDark != lastResolvedPrefersDark else { return }
        lastResolvedPrefersDark = prefersDark
#if DEBUG
        cmuxDebugLog("systemAppearance.observer.change prefersDark=\(prefersDark)")
#endif
        environment.synchronizeTerminalTheme(prefersDark)
        environment.postSystemAppearanceDidChange()
    }
}
