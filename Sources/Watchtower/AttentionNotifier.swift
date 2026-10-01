import Foundation
import UserNotifications

/// Posts a notification when a session stops working and starts waiting on you —
/// the moment that actually needs your attention when several are running.
final class AttentionNotifier {
    static let shared = AttentionNotifier()

    private var lastStates: [String: SessionState] = [:]
    private var primed = false

    /// `UNUserNotificationCenter` throws rather than fails when the process
    /// isn't inside an app bundle, taking the whole app down with it. That is
    /// the case when the binary is run straight out of `.build` during
    /// development, so notifications are skipped there instead.
    private static let available = Bundle.main.bundleIdentifier != nil

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Records states without alerting. Used while alerts are off so that
    /// turning them on doesn't fire a burst for transitions already missed.
    func prime(_ snapshots: [SessionSnapshot]) {
        lastStates = Dictionary(snapshots.map { ($0.sessionID, $0.state) },
                                uniquingKeysWith: { first, _ in first })
        primed = true
    }

    func evaluate(_ snapshots: [SessionSnapshot]) {
        defer { prime(snapshots) }
        guard primed else { return }   // first pass only establishes a baseline

        for snapshot in snapshots {
            guard let previous = lastStates[snapshot.sessionID] else { continue }
            if previous == .working, snapshot.state == .waiting {
                post(snapshot)
            }
        }
    }

    private func post(_ snapshot: SessionSnapshot) {
        guard Self.available else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(snapshot.name) needs you"
        content.body = snapshot.headline
        content.subtitle = snapshot.projectName
        content.sound = .default

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
