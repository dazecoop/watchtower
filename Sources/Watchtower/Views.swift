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
                if !store.axTrusted {
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
                }
                if store.waitingCount > 0 {
                    CountPill(count: store.waitingCount, label: "your turn", color: .waitingAmber)
                }
                if store.workingCount == 0 && store.waitingCount == 0 {
                    Text("\(store.sessions.count) session\(store.sessions.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Sort", selection: $store.sortMode) {
                ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 104)

            Toggle(isOn: $store.activeOnly) {
                Image(systemName: "bolt.fill")
            }
            .toggleStyle(.button)
            .help("Hide idle sessions")

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
            .help("Theme")

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
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
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
    @Environment(\.renderMarkdown) private var markdown

    private var events: [ActivityEvent] { session.parsed.events }

    /// The highlighted box shows Claude's own words rather than whatever record
    /// happens to be newest. Without this it often lands on a raw tool result —
    /// the first line of a `gh pr checks` dump, say — which reads as a mismatch
    /// against what the editor's chat panel is showing.
    private var newest: ActivityEvent? {
        events.last(where: isProse) ?? events.last
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

    private func isProse(_ event: ActivityEvent) -> Bool {
        switch event.kind {
        case .say, .prompt: return true
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            headline

            if isThinking {
                ThinkingStrip(since: thinkingSince, seed: seed)
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
                .strokeBorder(
                    session.state == .working
                        ? Color.workingGreen.opacity(0.50)
                        : (theme.style?.border ?? Color.primary.opacity(0.13)),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.12), radius: 7, y: 2)
        .shadow(color: session.state == .working ? Color.workingGreen.opacity(0.18) : .clear,
                radius: 12, y: 0)
        .modifier(AgeFade(session: session))
    }

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(state: session.state)

            Text(session.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Text(session.state.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.forState(session.state))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.forState(session.state).opacity(0.13), in: Capsule())

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
                    Text(session.parsed.gitBranch).lineLimit(1)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var nowBox: some View {
        if let newest {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: newest.glyph)
                    .font(.system(size: 10))
                    .foregroundStyle(eventColor(newest.kind))
                    .frame(width: 13)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    if !spotlightTag(newest).isEmpty {
                        Text(spotlightTag(newest))
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(eventColor(newest.kind))
                    }
                    eventText(newest.detail.isEmpty ? "—" : newest.detail, markdown: markdown)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(eventColor(newest.kind).opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .modifier(Shimmer(active: session.state == .working))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !session.parsed.model.isEmpty {
                Label(prettyModel(session.parsed.model), systemImage: "cpu")
            }
            if session.parsed.contextTokens > 0 {
                Label(compactCount(session.parsed.contextTokens), systemImage: "square.stack.3d.up")
            }
            if session.parsed.toolCalls > 0 {
                Label("\(session.parsed.toolCalls)", systemImage: "wrench.and.screwdriver")
            }
            Spacer(minLength: 0)
            Text(session.surface)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .font(.system(size: 9.5))
        .foregroundStyle(.tertiary)
        .labelStyle(.titleAndIcon)
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

    @Environment(\.renderMarkdown) private var markdown

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: event.glyph)
                .font(.system(size: 8))
                .foregroundStyle(eventColor(event.kind).opacity(dim ? 0.6 : 1))
                .frame(width: 11)

            if !event.tag.isEmpty {
                Text(event.tag)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(eventColor(event.kind).opacity(dim ? 0.7 : 1))
            }

            eventText(detailText, markdown: markdown)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary.opacity(dim ? 0.75 : 1))
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

func eventColor(_ kind: ActivityEvent.Kind) -> Color {
    switch kind {
    case .prompt: return Color(red: 0.42, green: 0.67, blue: 1.0)
    case .thinking: return Color(red: 0.72, green: 0.55, blue: 0.98)
    case .say: return Color(red: 0.38, green: 0.82, blue: 0.78)
    case .tool: return Color(red: 0.98, green: 0.70, blue: 0.22)
    case .result: return Color(white: 0.55)
    case .subagent: return Color(red: 0.98, green: 0.49, blue: 0.62)
    }
}


private struct PermissionBanner: View {
    @EnvironmentObject var store: FleetStore

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.waitingAmber)
            Text("Needs Accessibility access to focus editor windows across Spaces. If “Watchtower” is already in the list, remove it with “–” and add it again.")
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
struct ThinkingStrip: View {
    let since: Date
    let seed: Int

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
                let word = thinkingWords[(seed &+ Int(elapsed / 3)) % thinkingWords.count]

                HStack(spacing: 6) {
                    Text(word + "…")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.78))

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
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
