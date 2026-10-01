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

extension Color {
    static let workingGreen = Color(red: 0.26, green: 0.80, blue: 0.47)
    static let waitingAmber = Color(red: 0.98, green: 0.70, blue: 0.22)
    static let dormantGray = Color(white: 0.52)

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
