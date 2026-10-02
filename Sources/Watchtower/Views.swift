import SwiftUI

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var store: FleetStore

    @Environment(\.openWindow) private var openWindow

    private var columns: [GridItem] {
        if store.columnCount > 0 {
            return Array(repeating: GridItem(.flexible(minimum: 220), spacing: 14),
                         count: store.columnCount)
        }
        return [GridItem(.adaptive(minimum: 320, maximum: 620), spacing: 14)]
    }

    var body: some View {
        ZStack {
            if let style = store.theme.style {
                style.window.ignoresSafeArea()
            } else {
                VisualEffectBackground().ignoresSafeArea()
            }

            VStack(spacing: 0) {
                if !store.axTrusted && !store.hidePermissionBanner {
                    PermissionBanner()
                    Divider().opacity(0.4)
                }

                if store.visible.isEmpty {
                    EmptyState(reason: store.emptyReason)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(store.visible) { session in
                                SessionTile(session: session)
                            }
                        }
                        .padding(16)
                        .animation(.easeInOut(duration: 0.25), value: store.visible.map(\.id))
                    }
                }

                if let usage = store.usage, !usage.limits.isEmpty {
                    Divider().opacity(0.4)
                    UsageBar(usage: usage)
                }
            }
        }
        .frame(minWidth: 340, minHeight: 300)
        .environment(\.theme, store.theme)
        .environment(\.renderMarkdown, store.renderMarkdown)
        .environment(\.liveTicking, store.onScreen)
        .background(WindowSurface(theme: store.theme))
        .onAppear { AppWindow.reopen = { openWindow(id: AppWindow.id) } }
        .toolbar { toolbarItems }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .searchable(text: $store.query, placement: .toolbar, prompt: "Filter")
    }

    /// Everything lives in the title bar row, so no vertical space is spent on
    /// a second header. Items collapse into the overflow menu when narrow.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                if store.workingCount > 0 {
                    CountPill(count: store.workingCount, label: "working", color: .workingGreen)
                        .help("\(store.workingCount) session\(store.workingCount == 1 ? " is" : "s are") mid-turn")
                }
                if store.waitingCount > 0 {
                    CountPill(count: store.waitingCount, label: "your turn", color: .waitingAmber)
                        .help("\(store.waitingCount) session\(store.waitingCount == 1 ? " is" : "s are") waiting on you")
                }
                if store.workingCount == 0 && store.waitingCount == 0 {
                    Text("\(store.sessions.count) session\(store.sessions.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                // Pausing is easy to forget. A dormant-looking grid with no
                // sign it has stopped updating is a grid you stop trusting.
                if store.paused {
                    CountPill(count: nil, label: "paused", color: .dormantGray)
                        .help("Live updates are paused — press ⌘P to resume")
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                if store.checkInternet {
                    NetDot(status: store.netStatus)
                        .padding(.leading, 2)
                }

                // Shown whenever the setting is on, dimmed while nothing is
                // working: "armed" and "holding" are different things, and
                // hiding the icon entirely would make the second look broken.
                if store.keepAwake {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(store.isHoldingAwake ? Color.workingGreen : .secondary)
                        .opacity(store.isHoldingAwake ? 1 : 0.45)
                        .help(store.isHoldingAwake
                              ? "Keeping this Mac awake while a session is working"
                              : "Will keep this Mac awake once a session starts working")
                }
            }
            .animation(.easeOut(duration: 0.2), value: store.paused)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            // A menu with a checkmark rather than a pop-up button: the toolbar
            // is icons, and a text pop-up sat among them like a form control.
            Menu {
                Picker("Sort by", selection: $store.sortMode) {
                    ForEach(SortMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .help("Sort tiles by \(store.sortMode.rawValue.lowercased())")

            Toggle(isOn: $store.activeOnly) {
                Image(systemName: "bolt.fill")
            }
            .toggleStyle(.button)
            .help(store.activeOnly ? "Showing active sessions only" : "Hide idle sessions")

            // Clears idle sessions out of the app only — nothing is sent to
            // the sessions themselves, and any that stirs comes back on its own.
            // Pointless alongside the bolt filter, which hides them all anyway.
            if !store.activeOnly {
                Button {
                    if store.hasCleanedUp { store.restoreCleanedUp() } else { store.cleanUp() }
                } label: {
                    Image(systemName: store.hasCleanedUp ? "arrow.uturn.backward" : "sparkles")
                }
                .disabled(!store.hasCleanedUp && store.cleanableCount == 0)
                .help(store.hasCleanedUp
                      ? "Bring back the sessions you cleaned up"
                      : "Clean up: hide \(store.cleanableCount) idle session\(store.cleanableCount == 1 ? "" : "s") from Watchtower")
            }

            Menu {
                Picker("Theme", selection: $store.theme) {
                    ForEach(Theme.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: store.theme == .light ? "sun.max.fill" : "moon.fill")
            }
            .help("Theme: \(store.theme.label)")

            Button {
                store.paused.toggle()
            } label: {
                Image(systemName: store.paused ? "play.fill" : "pause.fill")
            }
            .help(store.paused ? "Resume live updates" : "Pause live updates")

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
    }
}

private struct CountPill: View {
    let count: Int?
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(count.map { "\($0) \(label)" } ?? label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.10), in: Capsule())
    }
}

// MARK: - Tile

struct SessionTile: View {
    let session: SessionSnapshot

    @EnvironmentObject private var store: FleetStore
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.renderMarkdown) private var markdown
    @Environment(\.inspectorEnabled) private var inspectorEnabled

    @State private var hovering = false
    @State private var inspecting = false

    private var events: [ActivityEvent] { session.parsed.events }

    /// The highlighted box shows Claude's own words rather than whatever record
    /// happens to be newest. Without this it often lands on a raw tool result —
    /// the first line of a `gh pr checks` dump, say — which reads as a mismatch
    /// against what the editor's chat panel is showing.
    private var newest: ActivityEvent? {
        events.last(where: isSpotlight) ?? events.last
    }

    private var prior: [ActivityEvent] {
        let spotlighted = newest?.id
        return Array(events.filter { $0.id != spotlighted }.suffix(isThinking ? 3 : 4))
    }

    /// "says" reads as a closing statement; while the turn is still running
    /// this is only the latest thing said, not the last.
    private func spotlightTag(_ event: ActivityEvent) -> String {
        if session.state == .working, case .say = event.kind { return "so far" }
        return event.tag
    }

    private func isSpotlight(_ event: ActivityEvent) -> Bool {
        switch event.kind {
        case .say, .prompt, .question: return true
        default: return false
        }
    }

    /// Any working session shows the indicator, matching Claude Code itself —
    /// the timer counts from whatever it last did, so a tile is never a dead
    /// block of text while Claude is mid-turn.
    private var isThinking: Bool { session.state == .working && store.showThinking }

    private var thinkingSince: Date { events.last?.at ?? session.statusUpdatedAt }

    private var seed: Int {
        abs(session.sessionID.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff })
    }

    private var borderColor: Color {
        if session.state == .working { return Color.workingGreen.opacity(hovering ? 0.65 : 0.50) }
        let resting = theme.style?.border ?? Color.primary.opacity(0.13)
        return hovering ? Color.primary.opacity(0.26) : resting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            headline

            if isThinking {
                ThinkingStrip(since: thinkingSince, seed: seed, pending: session.parsed.pendingTool)
                    .padding(.leading, 2)
            }

            nowBox

            if !prior.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(prior.reversed()) { event in
                        FeedLine(event: event, dim: true)
                    }
                }
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(14)
        .frame(height: 300, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.style?.card ?? Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .background {
                    if theme.style == nil {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.regularMaterial)
                    }
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .shadow(color: .black.opacity(hovering ? 0.16 : 0.12), radius: hovering ? 9 : 7, y: 2)
        .shadow(color: session.state == .working ? Color.workingGreen.opacity(0.18) : .clear,
                radius: 12, y: 0)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .modifier(AgeFade(session: session))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { if inspectorEnabled { inspecting = true } }
        .popover(isPresented: $inspecting, arrowEdge: .bottom) {
            SessionInspector(sessionID: session.id)
                .environmentObject(store)
                .environment(\.theme, theme)
                .environment(\.renderMarkdown, markdown)
        }
        .contextMenu { contextMenu }
        .help(inspectorEnabled ? "Click for the full feed" : "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilitySummary: String {
        var parts = ["\(session.name), \(session.state.label)", session.headline]
        if let newest { parts.append(newest.detail) }
        return parts.joined(separator: ". ")
    }

    @ViewBuilder
    private var contextMenu: some View {
        if inspectorEnabled {
            Button("Show Details") { inspecting = true }
        }
        if store.axTrusted, store.resolvedWindow(for: session) != nil {
            Button("Focus Editor Window") { store.focus(session) }
        }
        Divider()
        Button("Reveal Folder in Finder") { SessionActions.revealFolder(session) }
        Button("Open in Terminal") { SessionActions.openInTerminal(session) }
        Button("Reveal Transcript in Finder") { SessionActions.revealTranscript(session) }
            .disabled(session.transcript == nil)
        Divider()
        Button("Copy Project Path") { SessionActions.copy(session.cwd) }
        Button("Copy Session ID") { SessionActions.copy(session.sessionID) }
        Divider()
        // Only an idle session stays hidden; anything else would be back on
        // the next refresh, which is a button that appears to do nothing.
        Button("Hide Until It Stirs") { store.hide(session) }
            .disabled(session.state != .dormant)
    }

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(state: session.state)

            Text(session.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)

            StatePill(state: session.state)

            Spacer(minLength: 4)

            RelativeAge(since: session.lastActivity)

            FocusButton(session: session)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.headline)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary.opacity(0.92))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 9))
                Text(session.prettyPath)
                    .lineLimit(1)
                    .truncationMode(.head)
                if !session.parsed.gitBranch.isEmpty {
                    Text("·")
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                    Text(session.parsed.gitBranch)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var nowBox: some View {
        if let newest {
            let tint = eventColor(newest.kind, scheme)
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: newest.glyph)
                    .font(.system(size: 10))
                    .foregroundStyle(newest.isError ? Color.errorRed : tint)
                    .frame(width: 13)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    if !spotlightTag(newest).isEmpty {
                        Text(spotlightTag(newest))
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(tint)
                    }
                    eventText(newest.detail.isEmpty ? "—" : newest.detail,
                              markdown: markdown && newest.isProse)
                        .font(newest.isProse ? .system(size: 11.5) : .system(size: 11, design: .monospaced))
                        .foregroundStyle(newest.isError ? Color.errorRed.opacity(0.9) : .primary.opacity(0.85))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .modifier(Shimmer(active: session.state == .working))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !session.parsed.model.isEmpty {
                Label(prettyModel(session.parsed.model), systemImage: "cpu")
                    .help("Model: \(session.parsed.model)")
            }
            if session.parsed.contextTokens > 0 {
                HStack(spacing: 4) {
                    ContextRing(fraction: session.parsed.contextFraction, level: session.contextLevel)
                    Text(compactCount(session.parsed.contextTokens))
                        .foregroundStyle(Color.forSeverity(session.contextLevel).map { AnyShapeStyle($0) }
                                         ?? AnyShapeStyle(.tertiary))
                }
                .help("Context: \(session.contextSummary) (\(Int(session.parsed.contextFraction * 100))%)"
                      + (session.contextLevel > 0 ? " — close to automatic compaction" : ""))
            }
            if session.parsed.toolCalls > 0 {
                Label("\(session.parsed.toolCalls)", systemImage: "wrench.and.screwdriver")
                    .help("\(session.parsed.toolCalls) tool call\(session.parsed.toolCalls == 1 ? "" : "s") this session")
            }
            Spacer(minLength: 0)
            Text(session.surface)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.07), in: Capsule())
                .help("Running in \(session.surface)" + (session.version.isEmpty ? "" : " · Claude Code \(session.version)"))
        }
        .font(.system(size: 9.5))
        .foregroundStyle(.tertiary)
        .labelStyle(.titleAndIcon)
        .monospacedDigit()
    }
}

// MARK: - Pieces

/// Sweeps a soft highlight across a block to signal it is still in progress.
/// `ShimmerSweep` is a Core Animation layer — see `Animations.swift` for why
/// none of these loops is a SwiftUI animation.
struct Shimmer: ViewModifier {
    let active: Bool

    @Environment(\.liveTicking) private var live

    func body(content: Content) -> some View {
        content
            .overlay { if active, live { ShimmerSweep() } }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Recedes a tile in proportion to how long it has been quiet, so a glance at
/// the grid sorts live work from this morning's leftovers without reading a
/// single timestamp.
///
/// Only dormant tiles carry a timeline, and it ticks once a minute: the fade
/// spans hours, so there is nothing to see at a finer grain, and the closure
/// re-applies one modifier to an already-built tile rather than rebuilding it.
struct AgeFade: ViewModifier {
    let session: SessionSnapshot

    @Environment(\.liveTicking) private var live

    func body(content: Content) -> some View {
        Group {
            if session.state == .dormant, live {
                TimelineView(.periodic(from: wholeSecond(after: .now), by: 60)) { context in
                    content.opacity(session.fade(at: context.date))
                }
            } else {
                content.opacity(session.fade(at: Date()))
            }
        }
    }
}

struct RelativeAge: View {
    let since: Date

    @Environment(\.liveTicking) private var live

    var body: some View {
        Group {
            if live {
                TimelineView(AgeSchedule(since: since)) { context in
                    label(context.date)
                }
            } else {
                label(Date())
            }
        }
        .help("Last activity \(since.formatted(date: .abbreviated, time: .shortened))")
    }

    private func label(_ now: Date) -> some View {
        Text(shortDuration(now.timeIntervalSince(since)))
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
    }
}

/// Ticks once a second while the label is still counting seconds, then on each
/// minute boundary. `shortDuration` drops to whole minutes after the first
/// minute, so a tile that has been quiet for five hours was redrawing 3,600
/// times an hour to change nothing — and with most of a fleet idle, those
/// redraws were the bulk of what was left after the animations were fixed.
struct AgeSchedule: TimelineSchedule {
    let since: Date

    func entries(from start: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next = wholeSecond(after: start)
        return AnyIterator {
            let entry = next
            let age = next.timeIntervalSince(since)
            if age < 60 {
                next = next.addingTimeInterval(1)
            } else {
                // Land on the minute so the label flips as it increments
                // rather than up to a minute later.
                next = since.addingTimeInterval((age / 60).rounded(.down) * 60 + 60)
            }
            return entry
        }
    }
}

/// The next whole second on the shared clock.
///
/// Every per-second label in the app starts from this rather than from its own
/// `.now`, so they all tick on the same instant. Scattered phases cost one
/// window-wide layout pass each; in step, they cost one between them.
func wholeSecond(after date: Date) -> Date {
    Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.up))
}

struct StatusDot: View {
    let state: SessionState

    @Environment(\.liveTicking) private var live

    var body: some View {
        ZStack {
            if state == .working, live {
                PulseRing().frame(width: PulseRing.diameter, height: PulseRing.diameter)
            }
            Circle()
                .fill(Color.forState(state))
                .frame(width: 8, height: 8)
        }
        .frame(width: 22, height: 14)
    }
}


struct FeedLine: View {
    let event: ActivityEvent
    var dim: Bool = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.renderMarkdown) private var markdown

    private var tint: Color { eventColor(event.kind, scheme) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: event.glyph)
                .font(.system(size: 8))
                .foregroundStyle((event.isError ? Color.errorRed : tint).opacity(dim ? 0.7 : 1))
                .frame(width: 11)

            if !event.tag.isEmpty {
                Text(event.tag)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(tint.opacity(dim ? 0.7 : 1))
            }

            eventText(detailText, markdown: markdown && event.isProse)
                .font(event.isProse ? .system(size: 10) : .system(size: 9.5, design: .monospaced))
                .foregroundStyle(event.isError
                                 ? Color.errorRed.opacity(dim ? 0.8 : 1)
                                 : .secondary.opacity(dim ? 0.75 : 1))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var detailText: String {
        if case .result(let lines) = event.kind {
            let head = event.detail.isEmpty ? "done" : event.detail
            return lines > 1 ? "\(head)  (\(lines) lines)" : head
        }
        return event.detail
    }
}

/// One colour per kind of record, in two weights: the dark-mode set is light
/// and saturated, which on a white card drops to almost nothing, so light
/// mode gets the same hues pulled down far enough to read against it.
func eventColor(_ kind: ActivityEvent.Kind, _ scheme: ColorScheme) -> Color {
    let light = scheme == .light
    switch kind {
    case .prompt:   return light ? Color(red: 0.16, green: 0.42, blue: 0.86) : Color(red: 0.42, green: 0.67, blue: 1.0)
    case .thinking: return light ? Color(red: 0.47, green: 0.30, blue: 0.82) : Color(red: 0.72, green: 0.55, blue: 0.98)
    case .say:      return light ? Color(red: 0.08, green: 0.52, blue: 0.49) : Color(red: 0.38, green: 0.82, blue: 0.78)
    case .tool:     return light ? Color(red: 0.76, green: 0.46, blue: 0.02) : Color(red: 0.98, green: 0.70, blue: 0.22)
    case .result:   return light ? Color(white: 0.42) : Color(white: 0.55)
    case .subagent: return light ? Color(red: 0.80, green: 0.28, blue: 0.42) : Color(red: 0.98, green: 0.49, blue: 0.62)
    case .question: return light ? Color(red: 0.78, green: 0.50, blue: 0.02) : .waitingAmber
    }
}


private struct PermissionBanner: View {
    @EnvironmentObject var store: FleetStore

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.waitingAmber)
            Text("Accessibility access lets the reveal button jump to a session's editor window, even on another Space.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Grant Access…") { store.requestAccessibility() }
                .controlSize(.small)
            Button {
                store.refreshWindows()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .help("Re-check after approving")
            Button {
                withAnimation(.easeOut(duration: 0.2)) { store.hidePermissionBanner = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .padding(.leading, 2)
            .help("Dismiss. You can grant access later from Settings → Permissions.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.waitingAmber.opacity(0.09))
    }
}


// MARK: - Thinking indicator

let thinkingWords = [
    "Accomplishing", "Actioning", "Actualizing", "Baking", "Brewing", "Calculating",
    "Cerebrating", "Channelling", "Churning", "Clauding", "Coalescing", "Cogitating",
    "Computing", "Concocting", "Conjuring", "Considering", "Contemplating", "Cooking",
    "Crafting", "Crunching", "Deciphering", "Deliberating", "Determining", "Divining",
    "Effecting", "Elucidating", "Enchanting", "Envisioning", "Finagling", "Forging",
    "Generating", "Hatching", "Herding", "Honking", "Hustling", "Ideating", "Imagining",
    "Incubating", "Inferring", "Manifesting", "Marinating", "Moseying", "Mulling",
    "Mustering", "Musing", "Noodling", "Percolating", "Pondering", "Processing",
    "Puttering", "Puzzling", "Reticulating", "Ruminating", "Schlepping", "Shucking",
    "Simmering", "Smooshing", "Spinning", "Stewing", "Synthesizing", "Thinking",
    "Tinkering", "Transmuting", "Unfurling", "Unravelling", "Vibing", "Wibbling"
]

/// Shown while a session owes us output — right after you send a prompt, or
/// between a tool result and whatever Claude does next.
///
/// When the newest record is a tool call with no result yet, the strip names
/// the tool instead of a gerund: "Running Bash" for forty seconds is a fact,
/// where "Percolating" for forty seconds is a guess, and a long-running
/// command is the thing most worth knowing about a working session.
struct ThinkingStrip: View {
    let since: Date
    let seed: Int
    var pending: String? = nil

    @Environment(\.liveTicking) private var live

    var body: some View {
        HStack(spacing: 6) {
            if live {
                BreathingMark()
                    .frame(width: BreathingMark.size.width, height: BreathingMark.size.height)
            } else {
                Image(systemName: "asterisk")
                    .font(.system(size: BreathingMark.pointSize, weight: .black))
                    .foregroundStyle(Color.workingGreen)
            }

            // One tick a second is enough: the label only shows whole seconds,
            // and it is the only part of the strip that has to redraw.
            TimelineView(.periodic(from: wholeSecond(after: .now), by: live ? 1 : 3600)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(since))
                let word = pending.map { "Running \($0)" }
                    ?? thinkingWords[(seed &+ Int(elapsed / 3)) % thinkingWords.count]

                HStack(spacing: 6) {
                    Text(word + "…")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.78))
                        .lineLimit(1)

                    Text(shortDuration(elapsed))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
    }
}


// MARK: - Empty state

private struct EmptyState: View {
    let reason: FleetStore.EmptyReason

    @EnvironmentObject private var store: FleetStore

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: reason.symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(reason.title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
            Text(reason.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            // The fix for each is one click away, so offer it here rather
            // than sending anyone off to find the right toolbar button.
            switch reason {
            case .filtered:
                Button("Show All Sessions") { store.activeOnly = false }
                    .controlSize(.small)
                    .padding(.top, 4)
            case .cleanedUp:
                Button("Bring Them Back") { store.restoreCleanedUp() }
                    .controlSize(.small)
                    .padding(.top, 4)
            case .noSessions:
                EmptyView()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


// MARK: - Environment

private struct InspectorEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether clicking a tile may open the inspector popover. Off inside the
    /// notch's full-app panel: a popover anchored in a panel that refuses to
    /// become key opens behind it, or not at all.
    var inspectorEnabled: Bool {
        get { self[InspectorEnabledKey.self] }
        set { self[InspectorEnabledKey.self] = newValue }
    }
}
