import Foundation

/// Follows one session's .jsonl transcript, reading only the bytes appended
/// since the last poll. On first open it starts from the tail of the file so a
/// 50 MB history never has to be parsed.
final class TranscriptTail {
    let url: URL

    private var offset: UInt64 = 0
    private var carry = Data()
    private var opened = false
    private var startedMidFile = false
    private var counter = 0
    private var inode: UInt64 = 0

    private(set) var state = ParsedTranscript()

    private static let maxEvents = 400
    /// Records vary wildly in size, so the initial read is sized by line count
    /// rather than bytes — a byte window can hold only one huge record.
    private static let initialLines = 160
    private static let maxInitialScan: UInt64 = 6 * 1024 * 1024
    private static let scanBlock: UInt64 = 256 * 1024

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoPlain = ISO8601DateFormatter()

    init(url: URL) {
        self.url = url
    }

    func poll() {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0

        // Detect replacement of the file underneath us (compaction, rotation).
        // Uses stat() rather than FileManager, which also fetches extended
        // attributes and dominated this thread's time in the profiler.
        var info = Darwin.stat()
        let currentInode: UInt64 = stat(url.path, &info) == 0 ? UInt64(info.st_ino) : 0
        if opened, currentInode != 0, currentInode != inode {
            opened = false
            carry = Data()
            state = ParsedTranscript()
        }
        inode = currentInode

        if !opened {
            opened = true
            offset = initialOffset(handle, size: size)
            startedMidFile = offset > 0
        }

        if size < offset {            // truncated
            offset = 0
            carry = Data()
        }
        guard size > offset else { return }

        try? handle.seek(toOffset: offset)
        let chunk = (try? handle.read(upToCount: Int(size - offset))) ?? Data()
        offset = size
        guard !chunk.isEmpty else { return }

        var buffer = carry + chunk

        // The very first read may land mid-line; discard that fragment.
        if startedMidFile {
            startedMidFile = false
            if let nl = buffer.firstIndex(of: 0x0A) {
                buffer = buffer[buffer.index(after: nl)...]
            } else {
                carry = buffer
                return
            }
        }

        var lines: [Data] = []
        var cursor = buffer.startIndex
        while let nl = buffer[cursor...].firstIndex(of: 0x0A) {
            lines.append(buffer[cursor..<nl])
            cursor = buffer.index(after: nl)
        }
        carry = Data(buffer[cursor...])

        for line in lines where !line.isEmpty {
            ingest(line)
        }

        if state.events.count > Self.maxEvents {
            state.events.removeFirst(state.events.count - Self.maxEvents)
        }
    }

    /// Walk backwards from EOF until we have enough complete lines to fill the
    /// feed, so startup never parses the whole history of a long session.
    private func initialOffset(_ handle: FileHandle, size: UInt64) -> UInt64 {
        var pos = size
        var newlines = 0

        while pos > 0, size - pos < Self.maxInitialScan {
            let span = min(Self.scanBlock, pos)
            pos -= span
            try? handle.seek(toOffset: pos)
            guard let block = try? handle.read(upToCount: Int(span)), !block.isEmpty else { break }
            for byte in block where byte == 0x0A { newlines += 1 }
            if newlines >= Self.initialLines { break }
        }
        return pos
    }

    // MARK: - Record handling

    private func ingest(_ line: Data) {
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "ai-title":
            if let t = obj["aiTitle"] as? String, !t.isEmpty { state.title = t }

        case "last-prompt":
            if let p = obj["lastPrompt"] as? String, !p.isEmpty { state.lastPrompt = p }

        case "assistant":
            handleAssistant(obj)

        case "user":
            handleUser(obj)

        default:
            break
        }
    }

    private func handleAssistant(_ obj: [String: Any]) {
        if let branch = obj["gitBranch"] as? String, !branch.isEmpty { state.gitBranch = branch }
        let at = date(obj["timestamp"])
        let sidechain = obj["isSidechain"] as? Bool ?? false

        guard let msg = obj["message"] as? [String: Any] else { return }
        if let model = msg["model"] as? String, !model.isEmpty { state.model = model }

        if let usage = msg["usage"] as? [String: Any] {
            let input = usage["input_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            let cacheNew = usage["cache_creation_input_tokens"] as? Int ?? 0
            // Context in flight for this turn — it shrinks after a compaction,
            // so take the latest value rather than a running max.
            state.contextTokens = input + cacheRead + cacheNew
            state.outputTokens += usage["output_tokens"] as? Int ?? 0
        }

        guard let blocks = msg["content"] as? [[String: Any]] else { return }
        for block in blocks {
            switch block["type"] as? String {
            case "text":
                let text = (block["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                append(at: at, kind: sidechain ? .subagent("subagent") : .say, detail: text.clipped(300))

            case "thinking":
                let text = (block["thinking"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                append(at: at, kind: .thinking, detail: text.clipped(220))

            case "tool_use":
                let raw = block["name"] as? String ?? "tool"
                let name = prettyToolName(raw)
                let input = block["input"] as? [String: Any] ?? [:]
                state.toolCalls += 1
                if raw == "Task" || raw == "Agent" {
                    let sub = input["subagent_type"] as? String ?? "agent"
                    append(at: at, kind: .subagent(sub), detail: summarize(tool: raw, input: input))
                } else if raw == "AskUserQuestion" {
                    // Claude stops here until you answer, so this is your
                    // turn in all but the registry's bookkeeping.
                    append(at: at, kind: .question, detail: questionText(input))
                } else if raw == "ExitPlanMode" {
                    append(at: at, kind: .question, detail: "Plan is ready for your review")
                } else {
                    append(at: at, kind: .tool(name), detail: summarize(tool: raw, input: input))
                }

            default:
                continue
            }
        }
    }

    private func handleUser(_ obj: [String: Any]) {
        let at = date(obj["timestamp"])
        guard let msg = obj["message"] as? [String: Any] else { return }

        if let text = msg["content"] as? String {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, !clean.hasPrefix("<") else { return }
            state.promptCount += 1
            append(at: at, kind: .prompt, detail: clean.clipped(300))
            return
        }

        guard let blocks = msg["content"] as? [[String: Any]] else { return }
        for block in blocks {
            switch block["type"] as? String {
            case "text":
                let clean = (block["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty, !clean.hasPrefix("<") else { continue }
                state.promptCount += 1
                append(at: at, kind: .prompt, detail: clean.clipped(300))

            case "tool_result":
                let body = resultText(block["content"])
                let lines = body.isEmpty ? 0 : body.split(whereSeparator: \.isNewline).count
                let isError = block["is_error"] as? Bool ?? false
                let detail = isError ? "error: " + body.firstLine(max: 120) : body.firstLine(max: 120)
                append(at: at, kind: .result(lines), detail: detail)

            default:
                continue
            }
        }
    }

    private func resultText(_ content: Any?) -> String {
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            return arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    /// The first question Claude is asking, which is what the tile should show
    /// while it waits. Several questions are summarised as a count.
    private func questionText(_ input: [String: Any]) -> String {
        let questions = input["questions"] as? [[String: Any]] ?? []
        let texts = questions.compactMap { ($0["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = texts.first else { return "Waiting for your answer" }
        return texts.count > 1 ? "\(first.clipped(220))  (+\(texts.count - 1) more)" : first.clipped(300)
    }

    /// Pull the one field from a tool's input that says what it is acting on.
    private func summarize(tool: String, input: [String: Any]) -> String {
        let preferred: [String]
        switch tool {
        case "Bash", "BashOutput":
            preferred = ["description", "command"]
        case "Read", "Write", "Edit", "NotebookEdit":
            preferred = ["file_path", "notebook_path"]
        case "Grep":
            preferred = ["pattern"]
        case "Glob":
            preferred = ["pattern", "path"]
        case "Task", "Agent":
            preferred = ["description", "prompt"]
        case "WebFetch", "WebSearch":
            preferred = ["url", "query"]
        case "TodoWrite":
            preferred = []
        default:
            preferred = ["description", "query", "prompt", "path", "file_path", "url", "pattern", "command"]
        }

        for key in preferred {
            if let v = input[key] as? String, !v.isEmpty { return v.clipped(160) }
        }
        // Fall back to the first string-ish value present.
        for (_, v) in input {
            if let s = v as? String, !s.isEmpty { return s.clipped(160) }
        }
        return ""
    }

    private func append(at: Date, kind: ActivityEvent.Kind, detail: String) {
        counter += 1
        state.events.append(ActivityEvent(id: counter, at: at, kind: kind, detail: detail))
        state.lastEventAt = at
    }

    private func date(_ value: Any?) -> Date {
        guard let s = value as? String else { return Date() }
        return iso.date(from: s) ?? isoPlain.date(from: s) ?? Date()
    }
}
