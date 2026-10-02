import SwiftUI
import AppKit

/// Things you can do *about* a session, none of which touch the session
/// itself: find its folder, find its transcript, copy its particulars. Shared
/// by the tile's context menu and the inspector's footer so the two agree.
enum SessionActions {
    static func revealFolder(_ session: SessionSnapshot) {
        let url = URL(fileURLWithPath: session.cwd)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func revealTranscript(_ session: SessionSnapshot) {
        guard let url = session.transcript else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openInTerminal(_ session: SessionSnapshot) {
        let url = URL(fileURLWithPath: session.cwd)
        // The default terminal for folders is whatever the user has set;
        // asking the workspace rather than naming Terminal.app honours it.
        if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }
}

/// The detail view a tile opens into: the whole feed Watchtower has, with
/// timestamps and full lines, plus the figures the tile's footer only hints
/// at. A popover rather than a window — it is something you glance into and
/// dismiss, not somewhere you work.
///
/// Looks the session up by id on every render so it stays live while open;
/// a copy taken when the popover appeared would freeze mid-turn.
struct SessionInspector: View {
    let sessionID: String

    @EnvironmentObject private var store: FleetStore
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.renderMarkdown) private var markdown

    private var session: SessionSnapshot? {
        store.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        Group {
            if let session {
                content(session)
            } else {
                // The session exited while the popover was open.
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("This session has ended")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 500, height: 560)
    }

    private func content(_ session: SessionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(session)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()

            facts(session)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            feed(session)

            Divider()

            footer(session)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
    }

    // MARK: Header

    private func header(_ session: SessionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusDot(state: session.state)
                Text(session.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                StatePill(state: session.state)
                Spacer(minLength: 6)
                FocusButton(session: session)
            }

            Text(session.headline)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(session.prettyPath)
                    .lineLimit(1)
                    .truncationMode(.head)
                if !session.parsed.gitBranch.isEmpty {
                    Text("·")
                    Image(systemName: "arrow.triangle.branch")
                    Text(session.parsed.gitBranch).lineLimit(1)
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Facts

    private func facts(_ session: SessionSnapshot) -> some View {
        let columns = [GridItem(.flexible(), alignment: .leading),
                       GridItem(.flexible(), alignment: .leading),
                       GridItem(.flexible(), alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            Fact(label: "Model", value: session.parsed.model.isEmpty ? "—" : prettyModel(session.parsed.model))

            Fact(label: "Context") {
                HStack(spacing: 5) {
                    ContextRing(fraction: session.parsed.contextFraction, level: session.contextLevel, size: 11)
                    Text(session.parsed.contextTokens > 0 ? session.contextSummary : "—")
                }
            }

            Fact(label: "Open for", value: session.uptime > 0 ? shortDuration(session.uptime) : "—")
            Fact(label: "Prompts", value: "\(session.parsed.promptCount)")
            Fact(label: "Tool calls", value: "\(session.parsed.toolCalls)")
            Fact(label: "Output", value: session.parsed.outputTokens > 0 ? compactCount(session.parsed.outputTokens) + " tokens" : "—")
            Fact(label: "Surface", value: session.surface)
            Fact(label: "Claude Code", value: session.version.isEmpty ? "—" : session.version)
            Fact(label: "Process", value: "\(session.pid)")
        }
    }

    private struct Fact<Content: View>: View {
        let label: String
        let content: Content

        init(label: String, value: String) where Content == Text {
            self.label = label
            self.content = Text(value)
        }

        init(label: String, @ViewBuilder content: () -> Content) {
            self.label = label
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                content
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
    }

    // MARK: Feed

    private func feed(_ session: SessionSnapshot) -> some View {
        let events = session.parsed.events
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if events.isEmpty {
                        Text("Nothing recorded yet")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    }
                    ForEach(events) { event in
                        InspectorLine(event: event)
                            .id(event.id)
                    }
                    if session.state == .working {
                        ThinkingStrip(since: events.last?.at ?? session.statusUpdatedAt,
                                      seed: seed(session),
                                      pending: session.parsed.pendingTool)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .id("tail")
                    }
                }
                .padding(.vertical, 6)
            }
            .onAppear { scrollToEnd(proxy, events: events, working: session.state == .working, animated: false) }
            .onChange(of: events.last?.id) { _, _ in
                scrollToEnd(proxy, events: events, working: session.state == .working, animated: true)
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, events: [ActivityEvent], working: Bool, animated: Bool) {
        func go() {
            if working || events.isEmpty {
                proxy.scrollTo("tail", anchor: .bottom)
            } else if let last = events.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { go() }
        } else {
            go()
        }
    }

    private func seed(_ session: SessionSnapshot) -> Int {
        abs(session.sessionID.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff })
    }

    // MARK: Footer

    private func footer(_ session: SessionSnapshot) -> some View {
        HStack(spacing: 8) {
            Button {
                SessionActions.revealFolder(session)
            } label: {
                Label("Reveal Folder", systemImage: "folder")
            }
            .help("Show the project folder in Finder")

            Button {
                SessionActions.revealTranscript(session)
            } label: {
                Label("Transcript", systemImage: "doc.text")
            }
            .disabled(session.transcript == nil)
            .help("Show the session's transcript in Finder")

            Spacer()

            Menu {
                Button("Copy Project Path") { SessionActions.copy(session.cwd) }
                Button("Copy Session ID") { SessionActions.copy(session.sessionID) }
                if let transcript = session.transcript {
                    Button("Copy Transcript Path") { SessionActions.copy(transcript.path) }
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .fixedSize()
        }
        .controlSize(.small)
    }
}

/// One line of the inspector's feed. Fuller than the tile's `FeedLine`: the
/// time, the whole clipped detail rather than the first line of it, and room
/// for a result's line count to sit on its own.
private struct InspectorLine: View {
    let event: ActivityEvent

    @Environment(\.colorScheme) private var scheme
    @Environment(\.renderMarkdown) private var markdown

    @State private var hovering = false

    private var tint: Color { eventColor(event.kind, scheme) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(event.at, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.quaternary)
                .frame(width: 52, alignment: .trailing)

            Image(systemName: event.glyph)
                .font(.system(size: 8.5))
                .foregroundStyle(event.isError ? Color.errorRed : tint)
                .frame(width: 12)

            // A fixed tag column, so the text starts on the same line edge
            // all the way down and the feed reads as a table rather than a
            // ragged list.
            Text(event.tag.isEmpty ? (lineCount ?? "") : event.tag)
                .font(.system(size: 9.5, weight: event.tag.isEmpty ? .regular : .semibold, design: .monospaced))
                .foregroundStyle(event.tag.isEmpty ? AnyShapeStyle(.quaternary) : AnyShapeStyle(tint))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 64, alignment: .leading)

            eventText(text, markdown: markdown && event.isProse)
                .font(event.isProse ? .system(size: 11.5) : .system(size: 11, design: .monospaced))
                .foregroundStyle(event.isError ? Color.errorRed.opacity(0.9) : .primary.opacity(0.85))
                .lineLimit(hovering ? nil : 6)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { hovering = $0 }
    }

    private var text: String {
        if case .result = event.kind, event.detail.isEmpty { return "done" }
        return event.detail
    }

    /// "12 lines", in the tag column a result would otherwise leave empty.
    private var lineCount: String? {
        if case .result(let lines) = event.kind, lines > 1 { return "\(lines) lines" }
        return nil
    }
}

/// A small ring showing how much of the context window is in use, tinted by
/// how close the session is to compaction.
struct ContextRing: View {
    let fraction: Double
    let level: Int
    var size: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.14), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(Color.forSeverity(level) ?? Color.primary.opacity(0.55),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

/// The small "Working / Your turn / Idle" capsule, shared by the tile header
/// and the inspector so the two never drift.
struct StatePill: View {
    let state: SessionState

    var body: some View {
        Text(state.label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.forState(state))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.forState(state).opacity(0.13), in: Capsule())
    }
}
