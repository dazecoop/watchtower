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

/// Reads a stored integer, falling back to a default when never set.
private func storedInt(_ key: String, _ fallback: Int) -> Int {
    UserDefaults.standard.object(forKey: key) == nil
        ? fallback
        : UserDefaults.standard.integer(forKey: key)
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

    var symbol: String {
        switch self {
        case .status: return "circle.lefthalf.filled"
        case .recent: return "clock"
        case .project: return "folder"
        }
    }
}

@MainActor
final class FleetStore: ObservableObject {
    @Published private(set) var sessions: [SessionSnapshot] = []
    private(set) var lastRefresh = Date()
    /// Pausing stops `refresh`, and with it every reassessment of whether
    /// anything is still working — so the sleep guard (and the edge glow)
    /// have to be let go here or they'd hold on against a fleet that has
    /// stopped being watched.
    @Published var paused = false {
        didSet {
            applySleepGuard()
            applyEdgeGlow()
        }
    }
    @Published var activeOnly = false { didSet { recomputeOrder(force: true) } }
    @Published var sortMode: SortMode = .status { didSet { recomputeOrder(force: true) } }

    /// Tiles hold their slot while anything is happening, so the grid doesn't
    /// churn under you. Order is only rewritten once the fleet goes quiet.
    @Published private(set) var visible: [SessionSnapshot] = []
    private var displayOrder: [String] = []
    private let quietPeriod: TimeInterval = 30

    /// Sessions cleaned up out of the way, against the activity timestamp they
    /// carried when they were dismissed. Watchtower only reads Claude's files,
    /// so this hides a session here and nothing more — the session itself is
    /// untouched, and stirring again brings it straight back (see `listed`).
    /// Deliberately not persisted: a tidy-up applies to the fleet in front of
    /// you, not to every launch from here on.
    private var dismissed: [String: Date] = [:]

    /// Everything the app shows before sorting and the other filters: the
    /// fleet, less whatever is still sitting cleaned up.
    var listed: [SessionSnapshot] {
        dismissed.isEmpty ? sessions : sessions.filter { !isDismissed($0) }
    }

    /// How many sessions a tidy-up would clear right now, which is what decides
    /// whether offering one makes any sense. Counted off `listed` rather than
    /// `visible` because the overlay lists sessions the app's own filters have
    /// nothing to say about.
    var cleanableCount: Int {
        listed.filter { $0.state == .dormant }.count
    }

    /// Hides every idle session. Ones that wake up, and ones that appear later,
    /// are unaffected.
    func cleanUp() {
        for session in listed where session.state == .dormant {
            dismissed[session.id] = session.lastActivity
        }
        recomputeOrder(force: true)
    }

    /// Hides one idle session, on the same terms as a clean-up: it comes back
    /// the moment it stirs.
    func hide(_ session: SessionSnapshot) {
        guard session.state == .dormant else { return }
        dismissed[session.id] = session.lastActivity
        recomputeOrder(force: true)
    }

    /// Brings everything cleaned up back.
    func restoreCleanedUp() {
        guard !dismissed.isEmpty else { return }
        dismissed.removeAll()
        recomputeOrder(force: true)
    }

    var hasCleanedUp: Bool { !dismissed.isEmpty }

    /// Why there is nothing on screen, so the empty state can say what to do
    /// about it rather than blame the wrong filter.
    enum EmptyReason {
        case noSessions, cleanedUp, filtered

        var symbol: String {
            switch self {
            case .noSessions: return "binoculars"
            case .cleanedUp: return "sparkles"
            case .filtered: return "bolt.slash"
            }
        }

        var title: String {
            switch self {
            case .noSessions: return "No Claude sessions running"
            case .cleanedUp: return "All cleaned up"
            case .filtered: return "No active sessions"
            }
        }

        var detail: String {
            switch self {
            case .noSessions:
                return "Start Claude Code in a project and it will appear here within a second."
            case .cleanedUp:
                return "The idle sessions are hidden here only, and still running. Show all brings them back, as will any of them stirring."
            case .filtered:
                return "Everything is idle. Turn off the bolt filter to see them all."
            }
        }
    }

    var emptyReason: EmptyReason {
        if sessions.isEmpty { return .noSessions }
        if listed.isEmpty { return .cleanedUp }
        return .filtered
    }

    /// A dismissal lasts only as long as the session stays as it was. Anything
    /// new in its transcript, or any state other than idle, and it is back.
    private func isDismissed(_ session: SessionSnapshot) -> Bool {
        guard let at = dismissed[session.id] else { return false }
        return session.state == .dormant && session.lastActivity <= at
    }

    /// Drops dismissals that no longer hold, so a session that has woken up is
    /// not quietly re-hidden if it later goes idle again.
    private func pruneDismissed() {
        guard !dismissed.isEmpty else { return }
        let live = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        dismissed = dismissed.filter { id, at in
            guard let session = live[id] else { return false }
            return session.state == .dormant && session.lastActivity <= at
        }
    }

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

    /// Off until asked for: polling reads the login Claude Code has stored, and
    /// that is not something to start doing uninvited.
    @Published var pollUsage = storedBool("pollUsage", false) {
        didSet {
            UserDefaults.standard.set(pollUsage, forKey: "pollUsage")
            applyUsagePolling()
        }
    }

    @Published var usagePollMinutes = storedInt("usagePollMinutes", 5) {
        didSet {
            UserDefaults.standard.set(usagePollMinutes, forKey: "usagePollMinutes")
            applyUsagePolling()
        }
    }

    /// Off until asked for: it is the only thing in Watchtower that opens a
    /// socket, and the app's whole claim is that it does not.
    @Published var checkInternet = storedBool("checkInternet", false) {
        didSet {
            UserDefaults.standard.set(checkInternet, forKey: "checkInternet")
            applyReachability()
        }
    }

    /// Whether to hold the Mac awake while a session is mid-turn. The guard
    /// itself is still conditional on there being one — see `refresh`.
    @Published var keepAwake = storedBool("keepAwake", false) {
        didSet {
            UserDefaults.standard.set(keepAwake, forKey: "keepAwake")
            applySleepGuard()
        }
    }

    /// Glows the edge of every screen while a session is mid-turn — the
    /// ambient, glanceable version of a tile's own working indicator. Off by
    /// default; purely decorative, so there's no reason to force it on anyone.
    @Published var edgeGlow = storedBool("edgeGlow", false) {
        didSet {
            UserDefaults.standard.set(edgeGlow, forKey: "edgeGlow")
            applyEdgeGlow()
        }
    }

    @Published var notifyOnAttention = storedBool("notifyOnAttention", true) {
        didSet {
            UserDefaults.standard.set(notifyOnAttention, forKey: "notifyOnAttention")
            if notifyOnAttention { AttentionNotifier.requestAuthorization() }
            checkNotificationAccess()
        }
    }

    /// Whether macOS has notifications for Watchtower switched off, so the
    /// settings page can say why the alert toggle is doing nothing.
    @Published private(set) var notificationsDenied = false

    func checkNotificationAccess() {
        guard notifyOnAttention else { notificationsDenied = false; return }
        AttentionNotifier.authorizationDenied { [weak self] denied in
            Task { @MainActor in self?.notificationsDenied = denied }
        }
    }

    /// A number on the Dock icon for sessions waiting on you — the quietest
    /// way macOS has of saying something needs attention, and the one people
    /// already know how to read.
    @Published var badgeDock = storedBool("badgeDock", true) {
        didSet {
            UserDefaults.standard.set(badgeDock, forKey: "badgeDock")
            applyDockBadge()
        }
    }

    private func applyDockBadge() {
        let wanted = badgeDock && waitingCount > 0 ? "\(waitingCount)" : nil
        guard NSApp.dockTile.badgeLabel != wanted else { return }
        NSApp.dockTile.badgeLabel = wanted
    }

    /// Mirrors `SMAppService` rather than a stored flag: the system owns this
    /// setting, and the user can change it in System Settings → Login Items
    /// behind the app's back.
    @Published var launchAtLogin = LoginItem.isEnabled {
        didSet {
            guard launchAtLogin != LoginItem.isEnabled else { return }
            if let problem = LoginItem.set(launchAtLogin) {
                loginItemProblem = problem
                launchAtLogin = LoginItem.isEnabled
            } else {
                loginItemProblem = nil
            }
        }
    }

    @Published private(set) var loginItemProblem: String?

    /// The Accessibility banner can be put away. Declining the permission is a
    /// legitimate choice, and a strip nagging about it forever is not.
    @Published var hidePermissionBanner = storedBool("hidePermissionBanner", false) {
        didSet { UserDefaults.standard.set(hidePermissionBanner, forKey: "hidePermissionBanner") }
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

    private let reachability = ReachabilityMonitor()
    private let sleepGuard = SleepGuard()
    private let edgeGlowController = EdgeGlowController()

    /// Mirrored out of the monitor so views observe the store alone.
    @Published private(set) var netStatus: NetStatus = .unknown

    /// Whether the Mac is currently being held awake. Not merely the setting:
    /// the guard is only taken while something is actually working.
    var isHoldingAwake: Bool { sleepGuard.held }

    private let usagePoller = UsagePoller()

    /// The last figures fetched directly, kept beside the cached ones so the
    /// fresher of the two can win on every refresh.
    private var polled: UsageSnapshot?

    private func applyUsagePolling() {
        guard pollUsage else {
            usagePoller.stop()
            polled = nil
            refresh()
            return
        }
        usagePoller.start(everyMinutes: usagePollMinutes) { [weak self] snapshot in
            guard let self else { return }
            self.polled = snapshot
            self.refresh()
        }
    }

    /// Why the last direct poll came back empty, for the settings page.
    var usagePollProblem: String? { pollUsage ? usagePoller.lastProblem : nil }

    /// Whichever account of the limits is newer. Polling can fail — an expired
    /// login, a dropped connection — and when it does the cache is still the
    /// best thing available, so this falls back rather than going blank.
    private func freshestUsage(_ cached: UsageSnapshot?) -> UsageSnapshot? {
        guard let polled else { return cached }
        guard let cached else { return aged(polled) }
        let cachedAt = cached.fetchedAt ?? .distantPast
        let polledAt = polled.fetchedAt ?? .distantPast
        return polledAt >= cachedAt ? aged(polled) : cached
    }

    /// A polled snapshot goes stale on the same clock as a cached one — if
    /// polling stops working, its figures must not stay bright forever.
    private func aged(_ snapshot: UsageSnapshot) -> UsageSnapshot {
        var out = snapshot
        let age = Date().timeIntervalSince(snapshot.fetchedAt ?? .distantPast)
        out.stale = age > UsageSnapshot.staleAfter
        out.limits = out.limits.map {
            var limit = $0
            limit.expired = $0.resetsAt.map { $0 <= Date() } ?? false
            return limit
        }
        return out
    }

    private func applyReachability() {
        reachability.onChange = { [weak self] status in self?.netStatus = status }
        checkInternet ? reachability.start() : reachability.stop()
        netStatus = reachability.status
    }

    /// When the last check landed, for the settings page to show.
    var netCheckedAt: Date? { reachability.checkedAt }

    /// Nothing working means nothing to stay awake for, whatever the setting
    /// says. This is the only place the assertion is decided, so there is no
    /// path that leaves it held over an idle fleet.
    private func applySleepGuard() {
        sleepGuard.apply(keepAwake && !paused && workingCount > 0)
    }

    /// Same shape as `applySleepGuard`: nothing working means nothing to
    /// glow for, whatever the setting says, decided in this one place.
    /// Stands aside while the Settings demo is running — that's a manual
    /// preview the person asked for, and the once-a-second refresh tick
    /// re-evaluating this would turn it straight back off.
    private func applyEdgeGlow() {
        guard !edgeGlowDemoRunning else { return }
        edgeGlowController.apply(edgeGlow && !paused && workingCount > 0)
    }

    // MARK: Screen glow demo

    static let edgeGlowDemoDuration = 8

    @Published private(set) var edgeGlowDemoRunning = false
    @Published private(set) var edgeGlowDemoRemaining = 0
    private var edgeGlowDemoTimer: Timer?

    /// Forces the glow on for a fixed stretch regardless of whether anything
    /// is actually working or the setting is even on — Settings offers this
    /// so trying it doesn't mean waiting for a session to start a turn.
    func startEdgeGlowDemo() {
        edgeGlowDemoTimer?.invalidate()
        edgeGlowDemoRunning = true
        edgeGlowDemoRemaining = Self.edgeGlowDemoDuration
        edgeGlowController.apply(true)

        edgeGlowDemoTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickEdgeGlowDemo() }
        }
    }

    private func tickEdgeGlowDemo() {
        edgeGlowDemoRemaining -= 1
        if edgeGlowDemoRemaining <= 0 { stopEdgeGlowDemo() }
    }

    /// Ends the preview early, or at its natural end — either way, control
    /// of the glow goes back to whatever the real state should be rather
    /// than just snapping it off.
    func stopEdgeGlowDemo() {
        edgeGlowDemoTimer?.invalidate()
        edgeGlowDemoTimer = nil
        edgeGlowDemoRunning = false
        edgeGlowDemoRemaining = 0
        applyEdgeGlow()
    }

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
        pruneDismissed()
        let shown = listed
        var pool = activeOnly ? shown.filter { $0.state != .dormant } : shown
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
        // Clicking a "needs you" notification jumps to that session's editor
        // window — the same thing the tile's reveal button does.
        AttentionNotifier.shared.onActivate = { [weak self] sessionID in
            guard let self, let session = self.sessions.first(where: { $0.id == sessionID }) else { return }
            self.focus(session)
        }
        if notifyOnAttention { AttentionNotifier.requestAuthorization() }
        checkNotificationAccess()
        refresh()
        refreshWindows()
        startTimer()
        observeVisibility()
        applyReachability()
        applyUsagePolling()
        applyEdgeGlow()
    }

    /// The nth tile on screen, for the ⌘1–⌘9 shortcuts.
    func focus(index: Int) {
        guard visible.indices.contains(index) else { return }
        focus(visible[index])
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
            applyDockBadge()
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
                let merged = self.freshestUsage(usage)
                if self.usage != merged { self.usage = merged }
                if changed || self.ticks % 10 == 0 { self.recomputeOrder() }
                self.applySleepGuard()
                self.applyEdgeGlow()
                if changed { self.applyDockBadge() }
                self.lastRefresh = Date()
            }
        }
    }
}
