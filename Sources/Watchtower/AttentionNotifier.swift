import Foundation
import UserNotifications

/// Posts a notification when a session stops working and starts waiting on you —
/// the moment that actually needs your attention when several are running.
///
/// Clicking the notification hands the session id back through `onActivate`,
/// so the store can jump to that session's editor window: the notification is
/// the interruption, and the click is the way back to what caused it.
final class AttentionNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AttentionNotifier()

    private var lastStates: [String: SessionState] = [:]
    private var primed = false

    /// Set by the store. Called on the main thread with the session id a
    /// clicked notification was posted for.
    var onActivate: ((String) -> Void)?

    /// `UNUserNotificationCenter` throws rather than fails when the process
    /// isn't inside an app bundle, taking the whole app down with it. That is
    /// the case when the binary is run straight out of `.build` during
    /// development, so notifications are skipped there instead.
    private static let available = Bundle.main.bundleIdentifier != nil

    private static let sessionKey = "sessionID"

    private override init() {
        super.init()
        guard Self.available else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Whether the user has switched notifications off for Watchtower in
    /// System Settings, in which case the in-app toggle can do nothing.
    static func authorizationDenied(_ then: @escaping (Bool) -> Void) {
        guard available else { return then(false) }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            then(settings.authorizationStatus == .denied)
        }
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
        content.body = snapshot.parsed.awaitingAnswer
            ? (snapshot.parsed.events.last?.detail ?? snapshot.headline)
            : snapshot.headline
        content.subtitle = snapshot.projectName
        content.sound = .default
        content.userInfo = [Self.sessionKey: snapshot.sessionID]
        // One notification per session: a session that flips back and forth
        // replaces its own alert rather than stacking a column of them.
        content.threadIdentifier = snapshot.sessionID

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: snapshot.sessionID, content: content, trigger: nil)
        )
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let id = response.notification.request.content.userInfo[Self.sessionKey] as? String
        else { return }
        DispatchQueue.main.async { [weak self] in self?.onActivate?(id) }
    }
}
