import Foundation

struct UsageLimit: Identifiable, Equatable {
    let id: String
    let label: String
    let percent: Int
    let resetsAt: Date?
    let severity: String

    /// Used when the window is too narrow for the full label.
    var shortLabel: String {
        if label == "Session" { return "5h" }
        if label == "Weekly" { return "7d" }
        return label.replacingOccurrences(of: "Weekly ", with: "")
    }

    /// Falls back to the percentage when the API doesn't classify it.
    var level: Int {
        switch severity {
        case "critical", "exceeded": return 2
        case "warning": return 1
        default: return percent >= 90 ? 2 : (percent >= 75 ? 1 : 0)
        }
    }
}

struct UsageSnapshot: Equatable {
    var limits: [UsageLimit] = []
    var fetchedAt: Date?
}

/// Reads the usage figures Claude Code caches in ~/.claude.json after it polls
/// the account's limits. Re-parsed only when the file's mtime changes.
final class UsageReader {
    private let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")
    private var lastModified: Date?
    private var cached: UsageSnapshot?

    private let iso = ISO8601DateFormatter()

    func poll() -> UsageSnapshot? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date else { return cached }

        if let last = lastModified, last == modified { return cached }
        lastModified = modified

        guard let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let blob = root["cachedUsageUtilization"] as? [String: Any],
              let util = blob["utilization"] as? [String: Any]
        else { return cached }

        var snapshot = UsageSnapshot()
        if let ms = blob["fetchedAtMs"] as? Double {
            snapshot.fetchedAt = Date(timeIntervalSince1970: ms / 1000)
        }

        // `limits` is the same list Claude's own usage panel renders, so new
        // limit kinds appear here without needing a code change.
        for row in (util["limits"] as? [[String: Any]] ?? []) {
            guard let percent = row["percent"] as? Int else { continue }
            let kind = row["kind"] as? String ?? ""
            let scopeName = ((row["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String

            let label: String
            switch kind {
            case "session": label = "Session"
            case "weekly_all": label = "Weekly"
            case "weekly_scoped": label = scopeName.map { "Weekly \($0)" } ?? "Weekly"
            default: label = kind.replacingOccurrences(of: "_", with: " ").capitalized
            }

            snapshot.limits.append(UsageLimit(
                id: kind + (scopeName ?? ""),
                label: label,
                percent: percent,
                resetsAt: date(row["resets_at"]),
                severity: row["severity"] as? String ?? "normal"
            ))
        }

        cached = snapshot
        return snapshot
    }

    /// Fractional seconds here run to six digits, which ISO8601DateFormatter
    /// won't take, so drop the fraction before parsing.
    private func date(_ value: Any?) -> Date? {
        guard var text = value as? String else { return nil }
        if let dot = text.firstIndex(of: "."),
           let zoneStart = text[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            text.removeSubrange(dot..<zoneStart)
        }
        return iso.date(from: text)
    }
}
