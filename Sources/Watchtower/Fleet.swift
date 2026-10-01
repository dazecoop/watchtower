import Foundation
import SwiftUI
import AppKit

/// Does all the filesystem work. Lives on a single background queue.
final class FleetEngine {
    private let usageReader = UsageReader()
    private var tails: [String: TranscriptTail] = [:]
    private var transcriptIndex: [String: URL] = [:]
    private var indexedAt = Date.distantPast

    private let home = URL(fileURLWithPath: NSHomeDirectory())
    private var sessionsDir: URL { home.appendingPathComponent(".claude/sessions") }
    private var projectsDir: URL { home.appendingPathComponent(".claude/projects") }

    func usage() -> UsageSnapshot? { usageReader.poll() }

    func collect() -> [SessionSnapshot] {
        let entries = loadRegistry()

        // Forget tails whose session has exited.
        let live = Set(entries.map(\.sessionID))
        tails = tails.filter { live.contains($0.key) }

        return entries.map { entry in
            let url = transcriptURL(for: entry)
            if let url {
                if tails[entry.sessionID]?.url != url {
                    tails[entry.sessionID] = TranscriptTail(url: url)
                }
                tails[entry.sessionID]?.poll()
            }
            let parsed = tails[entry.sessionID]?.state ?? ParsedTranscript()
            return SessionSnapshot(reg: entry, parsed: parsed, transcript: url)
        }
    }

    // MARK: - ~/.claude/sessions/<pid>.json

    private func loadRegistry() -> [RegistryEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: sessionsDir,
                                                                  includingPropertiesForKeys: nil)) ?? []
        var out: [RegistryEntry] = []
        var seen = Set<String>()

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let sessionID = obj["sessionId"] as? String,
                  let pidValue = obj["pid"] as? Int else { continue }

            let pid = Int32(pidValue)
            guard processAlive(pid) else { continue }
            guard !seen.contains(sessionID) else { continue }
            seen.insert(sessionID)

            let cwd = obj["cwd"] as? String ?? ""
            let fallbackName = (cwd as NSString).lastPathComponent
            out.append(RegistryEntry(
                pid: pid,
                sessionID: sessionID,
                name: obj["name"] as? String ?? (fallbackName.isEmpty ? "session \(pid)" : fallbackName),
                cwd: cwd,
                startedAt: millis(obj["startedAt"]),
                status: obj["status"] as? String ?? "unknown",
                statusUpdatedAt: millis(obj["statusUpdatedAt"] ?? obj["updatedAt"]),
                version: obj["version"] as? String ?? "",
                entrypoint: obj["entrypoint"] as? String ?? ""
            ))
        }
        return out
    }

    private func processAlive(_ pid: Int32) -> Bool {
        // Signal 0 tests existence without touching the process.
        kill(pid, 0) == 0 || errno == EPERM
    }

    private func millis(_ value: Any?) -> Date {
        guard let ms = value as? Double ?? (value as? Int).map(Double.init), ms > 0 else {
            return .distantPast
        }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    // MARK: - Locating transcripts

    /// Claude Code slugifies the cwd for the project folder name, but the exact
    /// rule has changed over releases. Try the slug, then fall back to an index
    /// of every transcript on disk keyed by session id.
    private func transcriptURL(for entry: RegistryEntry) -> URL? {
        let slug = slugify(entry.cwd)
        let direct = projectsDir
            .appendingPathComponent(slug)
            .appendingPathComponent(entry.sessionID + ".jsonl")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

        if let hit = transcriptIndex[entry.sessionID] { return hit }
        rebuildIndexIfStale()
        return transcriptIndex[entry.sessionID]
    }

    private func slugify(_ path: String) -> String {
        var s = ""
        for ch in path {
            s.append(ch == "/" || ch == "." || ch == "_" || ch == " " ? "-" : ch)
        }
        return s
    }

    private func rebuildIndexIfStale() {
        guard Date().timeIntervalSince(indexedAt) > 10 else { return }
        indexedAt = Date()

        var index: [String: URL] = [:]
        let dirs = (try? FileManager.default.contentsOfDirectory(at: projectsDir,
                                                                 includingPropertiesForKeys: nil)) ?? []
        for dir in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                      includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "jsonl" {
                index[file.deletingPathExtension().lastPathComponent] = file
            }
        }
        transcriptIndex = index
    }
}

/// Reads a stored flag, falling back to a default when never set.
private func storedBool(_ key: String, _ fallback: Bool) -> Bool {
    UserDefaults.standard.object(forKey: key) == nil
        ? fallback
        : UserDefaults.standard.bool(forKey: key)
}

/// Reads a stored number, falling back to a default when never set.
private func storedDouble(_ key: String, _ fallback: Double) -> Double {
    UserDefaults.standard.object(forKey: key) == nil
        ? fallback
        : UserDefaults.standard.double(forKey: key)
}

/// The notch used to be sized by a small/medium/large picker. Carry an
/// existing choice over to the slider rather than resetting it.
private func migratedOverlayScale() -> Double {
    if UserDefaults.standard.object(forKey: "overlayScale") != nil {
        return UserDefaults.standard.double(forKey: "overlayScale")
    }
    switch UserDefaults.standard.string(forKey: "overlaySize") {
    case "small": return 0.85
    case "large": return 1.2
    default: return 1
    }
}

/// What a swelled notch turns into.
enum OverlayExpandStyle: String, CaseIterable, Identifiable {
    /// A compact readout: counts, a line per session, plan usage.
    case summary
    /// The whole grid, tiles and all, inside the notch rather than in a window.
    case app

    var id: String { rawValue }

    var label: String {
        switch self {
        case .summary: return "Summary"
        case .app: return "Full app"
        }
    }
}

/// What makes a swelled notch open.
enum OverlayExpandTrigger: String, CaseIterable, Identifiable {
    case click, hover

    var id: String { rawValue }

    var label: String {
        switch self {
        case .click: return "Click"
        case .hover: return "Hover"
        }
    }
}

enum SortMode: String, CaseIterable, Identifiable {
    case status = "Status"
    case recent = "Recent"
    case project = "Project"
    var id: String { rawValue }
}

@MainActor
final class FleetStore: ObservableObject {
    @Published private(set) var sessions: [SessionSnapshot] = []
    private(set) var lastRefresh = Date()
    @Published var paused = false
    @Published var activeOnly = false { didSet { recomputeOrder(force: true) } }
    @Published var sortMode: SortMode = .status { didSet { recomputeOrder(force: true) } }

    /// Tiles hold their slot while anything is happening, so the grid doesn't
    /// churn under you. Order is only rewritten once the fleet goes quiet.
    @Published private(set) var visible: [SessionSnapshot] = []
    private var displayOrder: [String] = []
    private let quietPeriod: TimeInterval = 30

    // MARK: Preferences

    @Published var theme: Theme =
        Theme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .system {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "theme")
            applyTheme()
        }
    }

    @Published var renderMarkdown = storedBool("renderMarkdown", true) {
        didSet { UserDefaults.standard.set(renderMarkdown, forKey: "renderMarkdown") }
    }

    @Published var showThinking = storedBool("showThinking", true) {
        didSet { UserDefaults.standard.set(showThinking, forKey: "showThinking") }
    }

    @Published var notifyOnAttention = storedBool("notifyOnAttention", true) {
        didSet {
            UserDefaults.standard.set(notifyOnAttention, forKey: "notifyOnAttention")
            if notifyOnAttention { AttentionNotifier.requestAuthorization() }
        }
    }

    /// 0 means "fit as many as the width allows".
    @Published var columnCount = UserDefaults.standard.integer(forKey: "columnCount") {
        didSet { UserDefaults.standard.set(columnCount, forKey: "columnCount") }
    }

    @Published var query = "" {
        didSet { recomputeOrder(force: true) }
    }

    // MARK: Overlay

    @Published var showOverlay = storedBool("showOverlay", false) {
        didSet {
            UserDefaults.standard.set(showOverlay, forKey: "showOverlay")
            // The overlay is a live readout, so it needs the poll timer even
            // when the main window is hidden or covered.
            if showOverlay { startTimer() } else if !onScreen { stopTimer() }
            applyActivationPolicy()
        }
    }

    @Published var overlayEdge: OverlayEdge =
        OverlayEdge(rawValue: UserDefaults.standard.string(forKey: "overlayEdge") ?? "") ?? .top {
        didSet { UserDefaults.standard.set(overlayEdge.rawValue, forKey: "overlayEdge") }
    }

    /// 0…1 along the chosen edge. Set by the slider or by dragging the overlay.
    @Published var overlayOffset = storedDouble("overlayOffset", 0.5) {
        didSet { UserDefaults.standard.set(overlayOffset, forKey: "overlayOffset") }
    }

    /// Drives both the sweep out of the screen edge and the inner corner
    /// radius, in points before the size scale is applied.
    @Published var overlayRounding = storedDouble("overlayRounding", 17) {
        didSet { UserDefaults.standard.set(overlayRounding, forKey: "overlayRounding") }
    }

    @Published var hideDockIcon = storedBool("hideDockIcon", false) {
        didSet {
            UserDefaults.standard.set(hideDockIcon, forKey: "hideDockIcon")
            applyActivationPolicy()
        }
    }

    /// Hiding the Dock icon also takes away the app menu, so something else
    /// has to be able to summon the window. The notch or the menu bar item
    /// will do; with neither, the app would be unreachable.
    var canHideDockIcon: Bool {
        showOverlay || UserDefaults.standard.bool(forKey: "showMenuBarExtra")
    }

    /// Enforced here rather than only in Settings: turning the notch and the
    /// menu bar off afterwards would otherwise strand the app.
    func applyActivationPolicy() {
        let wanted: NSApplication.ActivationPolicy =
            (hideDockIcon && canHideDockIcon) ? .accessory : .regular
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
        if wanted == .regular { NSApp.activate(ignoringOtherApps: true) }
    }

    @Published var overlaySweep = storedBool("overlaySweep", true) {
        didSet { UserDefaults.standard.set(overlaySweep, forKey: "overlaySweep") }
    }

    /// Click the notch to swell it into a panel in place, rather than bringing
    /// the main window forward. Only reachable while the notch itself is on —
    /// `SettingsView` disables the toggle, and `OverlayController` collapses
    /// anything open if the notch is switched off underneath it.
    @Published var overlayExpands = storedBool("overlayExpands", false) {
        didSet { UserDefaults.standard.set(overlayExpands, forKey: "overlayExpands") }
    }

    @Published var overlayExpandTrigger: OverlayExpandTrigger =
        OverlayExpandTrigger(rawValue: UserDefaults.standard.string(forKey: "overlayExpandTrigger") ?? "") ?? .click {
        didSet { UserDefaults.standard.set(overlayExpandTrigger.rawValue, forKey: "overlayExpandTrigger") }
    }

    /// Seconds the pointer must rest on the notch before it opens. Zero is
    /// instant; the slider stops at one second.
    @Published var overlayHoverDelay = storedDouble("overlayHoverDelay", 0.25) {
        didSet { UserDefaults.standard.set(overlayHoverDelay, forKey: "overlayHoverDelay") }
    }

    /// How much of Watchtower the open notch shows.
    @Published var overlayExpandStyle: OverlayExpandStyle =
        OverlayExpandStyle(rawValue: UserDefaults.standard.string(forKey: "overlayExpandStyle") ?? "") ?? .summary {
        didSet { UserDefaults.standard.set(overlayExpandStyle.rawValue, forKey: "overlayExpandStyle") }
    }

    /// Set by `OverlayController`: whether the notch has reached the screen
    /// corner at either end of its edge, in which case that end squares off so
    /// it can sit right into the corner instead of curving away from it.
    @Published private(set) var overlayFlushStart = false
    @Published private(set) var overlayFlushEnd = false

    func setOverlayFlush(start: Bool, end: Bool) {
        guard start != overlayFlushStart || end != overlayFlushEnd else { return }
        overlayFlushStart = start
        overlayFlushEnd = end
    }

    @Published var overlayScale = migratedOverlayScale() {
        didSet { UserDefaults.standard.set(overlayScale, forKey: "overlayScale") }
    }

    @Published private(set) var usage: UsageSnapshot?
    @Published private(set) var editorWindows: [EditorWindow] = []
    @Published private(set) var axTrusted = WindowFocuser.isTrusted

    /// cwd -> window title, chosen by the user when auto-matching is ambiguous.
    @Published private var bindings: [String: String] =
        UserDefaults.standard.dictionary(forKey: "windowBindings") as? [String: String] ?? [:]

    @Published private(set) var onScreen = true

    private let engine = FleetEngine()
    private let queue = DispatchQueue(label: "watchtower.io", qos: .utility)
    /// Walking another app's Window menu is synchronous IPC into that app and
    /// can block for tens of milliseconds. It has no business on the main
    /// thread, where it stalled a frame every four seconds.
    private let axQueue = DispatchQueue(label: "watchtower.ax", qos: .utility)
    private var timer: Timer?
    fileprivate var ticks = 0

    private func idealOrder(_ pool: [SessionSnapshot]) -> [SessionSnapshot] {
        switch sortMode {
        case .status:
            return pool.sorted {
                $0.state == $1.state ? $0.lastActivity > $1.lastActivity : $0.state < $1.state
            }
        case .recent:
            return pool.sorted { $0.lastActivity > $1.lastActivity }
        case .project:
            return pool.sorted {
                $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending
            }
        }
    }

    /// Re-sorts only when nothing has moved for `quietPeriod`, or when the user
    /// explicitly changes how the grid is sorted or filtered. Otherwise tiles
    /// keep their slots; new sessions are appended rather than inserted.
    func recomputeOrder(force: Bool = false) {
        var pool = activeOnly ? sessions.filter { $0.state != .dormant } : sessions
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !needle.isEmpty {
            pool = pool.filter {
                $0.name.lowercased().contains(needle)
                    || $0.projectName.lowercased().contains(needle)
                    || $0.headline.lowercased().contains(needle)
            }
        }
        let ideal = idealOrder(pool).map(\.id)
        let now = Date()
        let quiet = !sessions.contains { now.timeIntervalSince($0.lastActivity) < quietPeriod }

        if force || displayOrder.isEmpty || quiet {
            displayOrder = ideal
        } else {
            let surviving = Set(ideal)
            var next = displayOrder.filter { surviving.contains($0) }
            next.append(contentsOf: ideal.filter { !next.contains($0) })
            displayOrder = next
        }

        let byID = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        visible = displayOrder.compactMap { byID[$0] }
    }

    /// Compact text for the menu bar item.
    var menuBarSummary: String {
        if workingCount > 0 && waitingCount > 0 { return "\(workingCount)▶ \(waitingCount)◐" }
        if workingCount > 0 { return "\(workingCount)▶" }
        if waitingCount > 0 { return "\(waitingCount)◐" }
        return "\(sessions.count)"
    }

    var workingCount: Int { sessions.filter { $0.state == .working }.count }
    var waitingCount: Int { sessions.filter { $0.state == .waiting }.count }

    func applyTheme() {
        NSApp.appearance = theme.nsAppearance
    }

    func start() {
        applyTheme()
        applyActivationPolicy()
        refresh()
        refreshWindows()
        startTimer()
        observeVisibility()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// There is no point polling or animating for a window nobody can see.
    /// Occlusion covers minimising and being fully covered by another window,
    /// not just hiding the app.
    private func observeVisibility() {
        let centre = NotificationCenter.default
        let app = NSApplication.shared

        centre.addObserver(forName: NSApplication.didHideNotification, object: app, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setOnScreen(false) }
        }
        centre.addObserver(forName: NSApplication.didUnhideNotification, object: app, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setOnScreen(true) }
        }
        centre.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow, window.contentView != nil else { return }
            let visible = window.occlusionState.contains(.visible)
            Task { @MainActor in self?.setOnScreen(visible) }
        }
    }

    private func setOnScreen(_ visible: Bool) {
        guard visible != onScreen else { return }
        onScreen = visible
        if visible {
            refresh()
            refreshWindows()
            startTimer()
        } else if !showOverlay {
            stopTimer()
        }
    }

    private func tick() {
        guard !paused else { return }
        refresh()

        // Trust is cheap to check, so notice a granted permission immediately.
        let trusted = WindowFocuser.isTrusted
        let gained = trusted != axTrusted
        if gained { axTrusted = trusted }

        // Menu walking is comparatively slow, so poll it far less often.
        ticks += 1
        if trusted, gained || ticks % 4 == 0 { refreshWindows() }
    }

    // MARK: - Editor windows

    /// Off the main thread, and only published when the list actually differs —
    /// reassigning an identical list re-rendered the whole grid every four
    /// seconds for nothing.
    func refreshWindows() {
        let trusted = WindowFocuser.isTrusted
        if trusted != axTrusted { axTrusted = trusted }
        guard trusted else {
            if !editorWindows.isEmpty { editorWindows = [] }
            return
        }
        axQueue.async { [weak self] in
            let found = WindowFocuser.windows()
            Task { @MainActor in
                guard let self, self.editorWindows != found else { return }
                self.editorWindows = found
            }
        }
    }

    func requestAccessibility() {
        WindowFocuser.requestTrust()
    }

    /// An explicit binding wins; otherwise match the folder name against window
    /// titles, and fall back to the only window when there is just one.
    func resolvedWindow(for session: SessionSnapshot) -> EditorWindow? {
        if let title = bindings[session.cwd],
           let hit = editorWindows.first(where: { $0.title == title }) {
            return hit
        }
        guard !editorWindows.isEmpty else { return nil }
        if editorWindows.count == 1 { return editorWindows[0] }

        let needle = session.projectName.lowercased()
        guard !needle.isEmpty else { return nil }
        let matches = editorWindows.filter { $0.title.lowercased().contains(needle) }
        return matches.count == 1 ? matches[0] : nil
    }

    func isBound(_ session: SessionSnapshot) -> Bool {
        bindings[session.cwd] != nil
    }

    func bind(_ session: SessionSnapshot, to window: EditorWindow) {
        bindings[session.cwd] = window.title
        UserDefaults.standard.set(bindings, forKey: "windowBindings")
        WindowFocuser.focus(window)
    }

    func unbind(_ session: SessionSnapshot) {
        bindings.removeValue(forKey: session.cwd)
        UserDefaults.standard.set(bindings, forKey: "windowBindings")
    }

    func focus(_ session: SessionSnapshot) {
        guard let window = resolvedWindow(for: session) else { return }
        WindowFocuser.focus(window)
    }

    func refresh() {
        if DemoData.isEnabled {
            sessions = DemoData.sessions
            usage = DemoData.usage
            recomputeOrder()
            return
        }

        queue.async { [engine] in
            let snaps = engine.collect()
            let usage = engine.usage()
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.notifyOnAttention {
                    AttentionNotifier.shared.evaluate(snaps)
                } else {
                    AttentionNotifier.shared.prime(snaps)
                }
                // Publishing identical snapshots re-lays out the whole grid
                // once a second for no reason.
                let changed = self.sessions != snaps
                if changed { self.sessions = snaps }
                if self.usage != usage { self.usage = usage }
                if changed || self.ticks % 10 == 0 { self.recomputeOrder() }
                self.lastRefresh = Date()
            }
        }
    }
}
