import SwiftUI

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var store: FleetStore

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
                    EmptyState(filtered: !store.sessions.isEmpty)
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
        .toolbar { toolbarItems }
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

/// Ticks on its own so an otherwise unchanged tile doesn't have to re-render
/// once a second just to advance this label.
/// Sweeps a soft highlight across a block to signal it is still in progress.
struct Shimmer: ViewModifier {
    let active: Bool

    @Environment(\.liveTicking) private var live
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if active, live {
                    GeometryReader { geo in
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: Color.primary.opacity(0.07), location: 0.45),
                                .init(color: Color.primary.opacity(0.13), location: 0.50),
                                .init(color: Color.primary.opacity(0.07), location: 0.55),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width)
                        .offset(x: phase * geo.size.width * 1.8)
                    }
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                    .onDisappear { phase = -1 }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct RelativeAge: View {
    let since: Date

    @Environment(\.liveTicking) private var live

    var body: some View {
        Group {
            if live {
                TimelineView(.periodic(from: .now, by: 1)) { context in
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

struct StatusDot: View {
    let state: SessionState

    @Environment(\.liveTicking) private var live
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if state == .working, live {
                // Core Animation drives this, rather than redrawing the view
                // 20 times a second from a TimelineView.
                Circle()
                    .fill(Color.workingGreen.opacity(0.30))
                    .frame(width: 22, height: 22)
                    .scaleEffect(pulsing ? 1.0 : 0.45)
                    .opacity(pulsing ? 0 : 0.85)
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                            pulsing = true
                        }
                    }
                    .onDisappear { pulsing = false }
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
    @State private var breathing = false

    var body: some View {
        // One tick a second is enough: the label only shows whole seconds.
        TimelineView(.periodic(from: .now, by: live ? 1 : 3600)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(since))
            let word = thinkingWords[(seed &+ Int(elapsed / 3)) % thinkingWords.count]

            HStack(spacing: 6) {
                Image(systemName: "asterisk")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color.workingGreen)
                    .opacity(breathing ? 1 : 0.35)

                Text(word + "…")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.78))

                Text(shortDuration(elapsed))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .onDisappear { breathing = false }
    }
}

// MARK: - Empty state

private struct EmptyState: View {
    let filtered: Bool

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: filtered ? "bolt.slash" : "binoculars")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(filtered ? "No active sessions" : "No Claude sessions running")
                .font(.system(size: 14, weight: .medium, design: .rounded))
            Text(filtered
                 ? "Everything is idle. Turn off the bolt filter to see them all."
                 : "Start Claude Code in a project and it will appear here within a second.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
