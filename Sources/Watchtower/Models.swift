import Foundation

/// How a session presents in the grid. Derived from the registry status plus
/// how long it has been since anything happened.
enum SessionState: Int, Comparable {
    case working   // Claude is actively running a turn
    case waiting   // turn finished recently; it's your move
    case dormant   // alive, but nothing has happened in a long while

    static func < (a: SessionState, b: SessionState) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .working: return "Working"
        case .waiting: return "Your turn"
        case .dormant: return "Idle"
        }
    }
}

struct ActivityEvent: Identifiable, Equatable {
    enum Kind: Equatable {
        case prompt      // you said something
        case thinking
        case say         // Claude wrote prose
        case tool(String)
        case result(Int) // line count of tool output
        case subagent(String)
        /// Claude has stopped to ask you something — a question, or a plan
        /// waiting for approval. The turn is technically still running, but
        /// nothing moves until you answer.
        case question
    }

    let id: Int
    let at: Date
    let kind: Kind
    let detail: String

    var glyph: String {
        switch kind {
        case .prompt: return "person.fill"
        case .thinking: return "sparkles"
        case .say: return "text.alignleft"
        case .tool: return "wrench.and.screwdriver.fill"
        case .result: return isError ? "exclamationmark.triangle.fill" : "arrow.turn.down.right"
        case .subagent: return "person.2.fill"
        case .question: return "questionmark.circle.fill"
        }
    }

    var tag: String {
        switch kind {
        case .prompt: return "you"
        case .thinking: return "think"
        case .say: return "says"
        case .tool(let n): return n
        case .result: return ""
        case .subagent(let n): return n
        case .question: return "asks"
        }
    }

    /// A tool result Claude Code flagged as an error. Worth a different colour:
    /// a red line in the feed is often the first sign a session has gone off
    /// the rails, long before Claude says so.
    var isError: Bool {
        if case .result = kind { return detail.hasPrefix("error:") }
        return false
    }

    /// Prose reads in the system face; commands, paths and output stay
    /// monospaced. Claude's own sentences set in a terminal font looked like
    /// log lines, and the two deserve to be told apart at a glance.
    var isProse: Bool {
        switch kind {
        case .prompt, .say, .thinking, .subagent, .question: return true
        case .tool, .result: return false
        }
    }

    /// A tool call that has not yet produced a result — the tool is running.
    var isToolCall: Bool {
        switch kind {
        case .tool, .subagent: return true
        default: return false
        }
    }
}

/// Everything parsed out of a session's transcript tail.
struct ParsedTranscript: Equatable {
    var title = ""
    var lastPrompt = ""
    var model = ""
    var gitBranch = ""
    var events: [ActivityEvent] = []
    var contextTokens = 0
    var outputTokens = 0
    var toolCalls = 0
    var promptCount = 0
    var lastEventAt: Date?

    /// The newest record is a question Claude is waiting on you to answer.
    /// Claude Code reports the session as busy throughout, but it is your
    /// move, and the tile should say so.
    var awaitingAnswer: Bool {
        if case .question = events.last?.kind { return true }
        return false
    }

    /// The tool that is running right now, if the newest record is a call
    /// that has not produced a result yet.
    var pendingTool: String? {
        guard let last = events.last else { return nil }
        switch last.kind {
        case .tool(let name): return name
        case .subagent(let name): return name == "agent" ? "an agent" : "\(name) agent"
        default: return nil
        }
    }

    /// How many tokens the model can hold. Claude Code marks the long-context
    /// variants with a `[1m]` suffix on the model id; everything else is the
    /// standard window.
    var contextLimit: Int {
        model.contains("[1m]") || model.contains("-1m") ? 1_000_000 : 200_000
    }

    /// 0…1 of the context window in use. Claude Code compacts automatically
    /// at around 80%, so a figure approaching that is the one worth noticing:
    /// the session is about to lose detail.
    var contextFraction: Double {
        guard contextTokens > 0 else { return 0 }
        return min(1, Double(contextTokens) / Double(contextLimit))
    }
}

/// One row of ~/.claude/sessions/<pid>.json
struct RegistryEntry {
    let pid: Int32
    let sessionID: String
    let name: String
    let cwd: String
    let startedAt: Date
    let status: String
    let statusUpdatedAt: Date
    let version: String
    let entrypoint: String
}

struct SessionSnapshot: Identifiable, Equatable {
    var id: String { sessionID }

    let pid: Int32
    let sessionID: String
    let name: String
    let cwd: String
    let startedAt: Date
    let rawStatus: String
    let statusUpdatedAt: Date
    let version: String
    let entrypoint: String
    let transcript: URL?
    let parsed: ParsedTranscript
    let lastActivity: Date
    let state: SessionState

    init(reg: RegistryEntry, parsed: ParsedTranscript, transcript: URL?) {
        self.pid = reg.pid
        self.sessionID = reg.sessionID
        self.name = reg.name
        self.cwd = reg.cwd
        self.startedAt = reg.startedAt
        self.rawStatus = reg.status
        self.statusUpdatedAt = reg.statusUpdatedAt
        self.version = reg.version
        self.entrypoint = reg.entrypoint
        self.parsed = parsed
        self.transcript = transcript

        // Last sign of life from either the registry heartbeat or the transcript.
        let activity = max(reg.statusUpdatedAt, parsed.lastEventAt ?? .distantPast)
        self.lastActivity = activity

        if reg.status == "busy" && !parsed.awaitingAnswer {
            self.state = .working
        } else {
            self.state = Date().timeIntervalSince(activity) > Self.dormantAfter ? .dormant : .waiting
        }
    }

    /// How long the session has been open.
    var uptime: TimeInterval {
        startedAt == .distantPast ? 0 : Date().timeIntervalSince(startedAt)
    }

    /// "94k of 200k", for tooltips and the inspector.
    var contextSummary: String {
        "\(compactCount(parsed.contextTokens)) of \(compactCount(parsed.contextLimit))"
    }

    /// 0 fine, 1 close to compaction, 2 about to compact — on the same scale
    /// `Color.forSeverity` reads.
    var contextLevel: Int {
        let f = parsed.contextFraction
        return f >= 0.85 ? 2 : (f >= 0.70 ? 1 : 0)
    }

    /// How long a quiet session waits before it reads as dormant rather than
    /// as your turn to answer.
    static let dormantAfter: TimeInterval = 30 * 60

    /// A dormant tile keeps fading over this span, so the grid shows age at a
    /// glance instead of one flat wall of idle.
    static let fadeSpan: TimeInterval = 6 * 60 * 60
    private static let fadeStart = 0.85
    private static let fadeFloor = 0.40

    /// Tile opacity: 1 while there is anything to say, stepping back to
    /// `fadeStart` on going dormant and easing down to `fadeFloor` from there.
    /// Eased so the first stretch of silence is the most visible change —
    /// an hour quiet and a day quiet should not look alike.
    func fade(at now: Date) -> Double {
        guard state == .dormant else { return 1 }
        let quiet = now.timeIntervalSince(lastActivity) - Self.dormantAfter
        let progress = min(max(quiet / Self.fadeSpan, 0), 1)
        return Self.fadeStart - (Self.fadeStart - Self.fadeFloor) * pow(progress, 0.6)
    }

    var projectName: String {
        let base = (cwd as NSString).lastPathComponent
        return base.isEmpty ? cwd : base
    }

    /// Short, friendly path: ~/Work/Stacked-Studios/network
    var prettyPath: String {
        let home = NSHomeDirectory()
        return cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
    }

    var headline: String {
        if !parsed.title.isEmpty { return parsed.title }
        if !parsed.lastPrompt.isEmpty { return parsed.lastPrompt.firstLine(max: 90) }
        return "No activity yet"
    }

    /// The single most useful "what is it doing right now" line.
    var currentActivity: ActivityEvent? {
        // Prefer the newest tool call or prose while working; otherwise newest anything.
        parsed.events.last
    }

    var surface: String {
        switch entrypoint {
        case "claude-vscode": return "VS Code"
        case "claude-desktop": return "Desktop"
        case let e where e.hasPrefix("claude-"): return String(e.dropFirst(7)).capitalized
        default: return entrypoint.isEmpty ? "CLI" : entrypoint
        }
    }
}
