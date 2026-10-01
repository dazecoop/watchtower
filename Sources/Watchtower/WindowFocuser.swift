import AppKit
import ApplicationServices

struct EditorWindow: Identifiable, Hashable {
    let appPID: pid_t
    let appName: String
    let title: String

    var id: String { "\(appPID):\(title)" }
}

/// Focuses a specific editor window, including one sitting on another Space.
///
/// The Accessibility API only reports windows on the *active* Space, so raising
/// an AXWindow directly cannot reach a window on another desktop. The app's
/// Window menu does list every window regardless of Space, and pressing one of
/// those items makes macOS switch Spaces and focus it — without opening
/// anything new. That is the mechanism used here.
enum WindowFocuser {

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to System Settings.
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func editorApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular else { return false }
            let bid = (app.bundleIdentifier ?? "").lowercased()
            if bid.contains("vscode") || bid.contains("vscodium") || bid.contains("code.oss") {
                return true
            }
            // Cursor, Windsurf and other forks don't share a predictable bundle id.
            return ["cursor", "windsurf", "positron"].contains((app.localizedName ?? "").lowercased())
        }
    }

    static func windows() -> [EditorWindow] {
        guard isTrusted else { return [] }
        return editorApps().flatMap { app in
            windowMenuTitles(pid: app.processIdentifier).map {
                EditorWindow(appPID: app.processIdentifier,
                             appName: app.localizedName ?? "Editor",
                             title: $0)
            }
        }
    }

    static func focus(_ window: EditorWindow) {
        guard let app = NSRunningApplication(processIdentifier: window.appPID) else { return }

        // The menu item only takes effect once its app is frontmost.
        app.activate(options: [])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard let item = windowMenuItem(pid: window.appPID, title: window.title) else { return }
            AXUIElementPerformAction(item, kAXPressAction as CFString)
        }
    }

    // MARK: - Menu walking

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
              let kids = raw as? [AXUIElement] else { return [] }
        return kids
    }

    private static func title(_ element: AXUIElement) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &raw) == .success
        else { return nil }
        return raw as? String
    }

    /// The window list lives after the final separator of the Window menu.
    private static func windowMenuItems(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)

        var barRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &barRaw) == .success,
              let menuBar = barRaw.map({ $0 as! AXUIElement }) else { return [] }

        guard let windowMenuBarItem = children(menuBar).first(where: { title($0) == "Window" }),
              let menu = children(windowMenuBarItem).first else { return [] }

        let items = children(menu)
        var lastSeparator = -1
        for (i, item) in items.enumerated() where (title(item) ?? "").isEmpty {
            lastSeparator = i
        }
        guard lastSeparator >= 0, lastSeparator + 1 < items.count else { return [] }

        return items[(lastSeparator + 1)...].filter { !(title($0) ?? "").isEmpty }
    }

    private static func windowMenuTitles(pid: pid_t) -> [String] {
        windowMenuItems(pid: pid).compactMap { title($0) }
    }

    private static func windowMenuItem(pid: pid_t, title wanted: String) -> AXUIElement? {
        windowMenuItems(pid: pid).first { title($0) == wanted }
    }
}
