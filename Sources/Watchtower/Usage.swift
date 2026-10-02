import Foundation

struct UsageLimit: Identifiable, Equatable {
    let id: String
    let label: String
    let percent: Int
    let resetsAt: Date?
    let severity: String

    /// `resets_at` has passed, so this percentage describes a window that has
    /// already rolled over. Whatever has been used in the new window is
    /// unknown until Claude Code polls again, so the figure must not be shown
    /// as if it were current.
    var expired: Bool = false

    /// The percentage as shown, or a dash once the window it describes has
    /// rolled over and the live figure is unknown.
    var figure: String { expired ? "—" : "\(percent)%" }

    /// Used when the window is too narrow for the full label.
    var shortLabel: String {
        if label == "Session" { return "5h" }
        if label == "Weekly" { return "7d" }
        return label.replacingOccurrences(of: "Weekly ", with: "")
    }

    /// Falls back to the percentage when the API doesn't classify it. An
    /// expired window carries no severity: the old one no longer applies.
    var level: Int {
        if expired { return 0 }
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

    /// Nothing has refreshed these figures in a while. Claude Code only writes
    /// them while it is running, so with no session open they freeze at
    /// whatever was last seen.
    var stale: Bool = false

    /// How old the cache may get before it stops counting as current.
    static let staleAfter: TimeInterval = 30 * 60
}

extension UsageLimit {
    /// The `limits` array, which Anthropic returns in the same shape whether it
    /// arrives through Claude Code's cache or straight off the endpoint — so
    /// both readers share this and cannot drift apart.
    static func parse(_ rows: [[String: Any]], now: Date) -> [UsageLimit] {
        rows.compactMap { row in
            guard let percent = row["percent"] as? Int else { return nil }
            let kind = row["kind"] as? String ?? ""
            let scopeName = ((row["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String

            let label: String
            switch kind {
            case "session": label = "Session"
            case "weekly_all": label = "Weekly"
            case "weekly_scoped": label = scopeName.map { "Weekly \($0)" } ?? "Weekly"
            default: label = kind.replacingOccurrences(of: "_", with: " ").capitalized
            }

            let resets = resetDate(row["resets_at"])
            return UsageLimit(
                id: kind + (scopeName ?? ""),
                label: label,
                percent: percent,
                resetsAt: resets,
                severity: row["severity"] as? String ?? "normal",
                expired: resets.map { $0 <= now } ?? false
            )
        }
    }

    /// Fractional seconds here run to six digits, which ISO8601DateFormatter
    /// won't take, so drop the fraction before parsing.
    private static func resetDate(_ value: Any?) -> Date? {
        guard var text = value as? String else { return nil }
        if let dot = text.firstIndex(of: "."),
           let zoneStart = text[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            text.removeSubrange(dot..<zoneStart)
        }
        return ISO8601DateFormatter().date(from: text)
    }
}

/// Reads the usage figures Claude Code caches in ~/.claude.json after it polls
/// the account's limits. Watchtower never fetches them itself, so a figure is
/// only as fresh as the last time Claude Code wrote one: the JSON is re-parsed
/// when its mtime changes, but the snapshot is rebuilt on every poll so that
/// windows expiring and the cache going stale are noticed without a write.
final class UsageReader {
    private let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")
    private var lastModified: Date?

    /// The last successfully parsed payload, kept raw so the derived snapshot
    /// can be re-evaluated against the current time.
    private var rows: [[String: Any]] = []
    private var fetchedAt: Date?
    private var loaded = false

    func poll() -> UsageSnapshot? {
        reload()
        guard loaded else { return nil }
        return snapshot(now: Date())
    }

    /// Re-reads the file only when it has changed on disk. A parse failure
    /// leaves the previous payload in place rather than blanking the readout.
    private func reload() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date else { return }

        if let last = lastModified, last == modified { return }
        lastModified = modified

        guard let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let blob = root["cachedUsageUtilization"] as? [String: Any],
              let util = blob["utilization"] as? [String: Any]
        else { return }

        // `limits` is the same list Claude's own usage panel renders, so new
        // limit kinds appear here without needing a code change.
        rows = util["limits"] as? [[String: Any]] ?? []
        fetchedAt = (blob["fetchedAtMs"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        loaded = true
    }

    private func snapshot(now: Date) -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        snapshot.fetchedAt = fetchedAt
        snapshot.stale = fetchedAt.map { now.timeIntervalSince($0) > UsageSnapshot.staleAfter } ?? true

        snapshot.limits = UsageLimit.parse(rows, now: now)

        return snapshot
    }
}
