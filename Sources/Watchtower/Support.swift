import SwiftUI
import AppKit

extension String {
    func firstLine(max limit: Int) -> String {
        let line = split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
    }

    func clipped(_ limit: Int) -> String {
        let flat = replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}

/// "4s", "12m", "3h 20m" — compact and glanceable.
func shortDuration(_ interval: TimeInterval) -> String {
    let s = Int(max(0, interval))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m" }
    let h = s / 3600, m = (s % 3600) / 60
    return m == 0 ? "\(h)h" : "\(h)h \(m)m"
}

func compactCount(_ n: Int) -> String {
    if n < 1000 { return "\(n)" }
    if n < 1_000_000 {
        let k = Double(n) / 1000
        return k < 10 ? String(format: "%.1fk", k) : "\(Int(k))k"
    }
    return String(format: "%.1fM", Double(n) / 1_000_000)
}

func prettyModel(_ id: String) -> String {
    guard !id.isEmpty else { return "" }
    var s = id
    for prefix in ["us.anthropic.", "anthropic."] where s.hasPrefix(prefix) {
        s = String(s.dropFirst(prefix.count))
    }
    s = s.replacingOccurrences(of: "claude-", with: "")
    // Drop trailing date / version stamps: opus-5-5-20260101 -> Opus 5.5
    let parts = s.split(separator: "-").filter { !($0.count == 8 && Int($0) != nil) }
    guard let family = parts.first else { return s }
    let nums = parts.dropFirst().compactMap { Int($0) }
    let version = nums.map(String.init).joined(separator: ".")
    return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
}

/// Strip the mcp__server__tool noise down to something readable.
func prettyToolName(_ name: String) -> String {
    guard name.hasPrefix("mcp__") else { return name }
    let parts = name.dropFirst(5).components(separatedBy: "__")
    return parts.last ?? name
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Melds the title bar into the content: `toolbarBackground(.hidden)` drops the
/// toolbar's own material and separator, but the strip behind it is still
/// painted by the window, not the view. Making the title bar transparent and
/// handing the window the theme's own colour — or clearing it so the content's
/// vibrancy reaches up through `fullSizeContentView` — leaves one unbroken
/// surface from the traffic lights down.
struct WindowSurface: NSViewRepresentable {
    let theme: Theme

    func makeNSView(context: Context) -> SurfaceView { SurfaceView() }

    func updateNSView(_ view: SurfaceView, context: Context) {
        view.theme = theme
    }

    /// Applies the window settings once per theme, rather than on every render.
    ///
    /// This used to re-apply them from an async hop on every `updateNSView`.
    /// Setting `styleMask` and `backgroundColor` invalidates the window, which
    /// brings on another render, which schedules another hop — a loop that
    /// kept the window laying out when nothing had changed. The attachment
    /// problem the hop was there to solve is what `viewDidMoveToWindow` is for.
    final class SurfaceView: NSView {
        var theme: Theme = .system {
            didSet { applyIfNeeded() }
        }

        private var applied: Theme?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applied = nil
            applyIfNeeded()
        }

        private func applyIfNeeded() {
            guard let window, applied != theme else { return }
            applied = theme

            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)

            if let style = theme.style {
                window.backgroundColor = NSColor(style.window)
                window.isOpaque = true
            } else {
                // Vibrancy themes draw their own `.behindWindow` effect view.
                window.backgroundColor = .clear
                window.isOpaque = false
            }
        }
    }
}

extension Color {
    static let workingGreen = Color(red: 0.26, green: 0.80, blue: 0.47)
    static let waitingAmber = Color(red: 0.98, green: 0.70, blue: 0.22)
    static let dormantGray = Color(white: 0.52)

    /// One fixed colour per plan limit, shared by the usage bar and the notch
    /// rings so a given limit reads the same wherever you see it. Severity is
    /// carried by the percentage text instead, which leaves these stable.
    static func forLimit(_ index: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.26, green: 0.56, blue: 0.95),   // blue
            Color(red: 0.58, green: 0.46, blue: 0.93),   // violet
            Color(red: 0.90, green: 0.40, blue: 0.58),   // pink
            Color(red: 0.13, green: 0.70, blue: 0.66)    // teal

            // Nothing green: the notch's spinner is green, and a ring beside
            // it in the same hue reads as part of the same indicator.
        ]
        return palette[((index % palette.count) + palette.count) % palette.count]
    }

    /// Red when a limit is critical, amber when it is close, otherwise nil —
    /// callers fall back to their own resting colour.
    static func forSeverity(_ level: Int) -> Color? {
        switch level {
        case 2: return Color(red: 0.95, green: 0.35, blue: 0.35)
        case 1: return .waitingAmber
        default: return nil
        }
    }

    /// Green working, amber reaching nothing, red nothing to reach. Deliberately
    /// the same green and amber as session state: one vocabulary of colour for
    /// "fine" and "needs you" across the whole app.
    static func forNet(_ s: NetStatus) -> Color {
        switch s {
        case .online: return .workingGreen
        case .degraded: return .waitingAmber
        case .offline: return Color(red: 0.95, green: 0.35, blue: 0.35)
        case .unknown: return .dormantGray
        }
    }

    static func forState(_ s: SessionState) -> Color {
        switch s {
        case .working: return .workingGreen
        case .waiting: return .waitingAmber
        case .dormant: return .dormantGray
        }
    }
}


// MARK: - Markdown

/// Claude's prose is markdown, so raw `**bold**` and backticks end up on the
/// tiles. Inline-only parsing keeps it to one line while losing the syntax.
enum Markdown {
    private static var cache: [String: AttributedString] = [:]

    static func attributed(_ text: String) -> AttributedString {
        if let hit = cache[text] { return hit }

        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        let parsed = (try? AttributedString(markdown: text, options: options))
            ?? AttributedString(text)

        if cache.count > 800 { cache.removeAll() }
        cache[text] = parsed
        return parsed
    }
}

func eventText(_ text: String, markdown: Bool) -> Text {
    markdown ? Text(Markdown.attributed(text)) : Text(text)
}

private struct MarkdownKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var renderMarkdown: Bool {
        get { self[MarkdownKey.self] }
        set { self[MarkdownKey.self] = newValue }
    }
}


private struct LiveTickingKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False when the window is hidden or fully covered, so animations and
    /// per-second timers can stop instead of burning CPU off-screen.
    var liveTicking: Bool {
        get { self[LiveTickingKey.self] }
        set { self[LiveTickingKey.self] = newValue }
    }
}


// MARK: - Status dot

/// The connectivity dot. Small enough to sit in a toolbar or the notch's
/// header without taking a line of its own, and the only thing on screen that
/// says anything about the network.
struct NetDot: View {
    let status: NetStatus
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(Color.forNet(status))
            .frame(width: size, height: size)
            // Unknown is a state to notice, not to read as fine.
            .opacity(status == .unknown ? 0.5 : 1)
            .help(status.label)
            .accessibilityLabel(status.label)
    }
}
