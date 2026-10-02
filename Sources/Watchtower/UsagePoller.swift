import Foundation

/// Asks Anthropic for the account's limits directly, instead of waiting for
/// Claude Code to do it.
///
/// Claude Code refreshes its own cache only when something inside it asks —
/// rendering `/usage`, mostly — behind a five-minute floor. Nothing asks on a
/// timer, so with a session running but nobody looking, the figures on disk can
/// sit an hour behind. This closes that gap by making the same request Claude
/// Code makes.
///
/// It is off by default, and these are the rules it keeps to:
///
/// - **Read-only.** It reads the credential Claude Code already stores and
///   never writes one back. In particular it does not refresh an expired token:
///   both apps rotating the same refresh token is a race, and losing it signs
///   you out of Claude Code. An expired token simply means no poll.
/// - **One destination.** The host is fixed in `endpoint` and redirects are
///   refused, so the token cannot be carried anywhere else.
/// - **Never recorded.** The token is held for the length of one request. It is
///   not logged, not written to disk, and not kept between polls.
@MainActor
final class UsagePoller {
    /// The same endpoint Claude Code reads, on a host that cannot be redirected
    /// away from.
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Matches the timeout Claude Code gives its own call.
    private static let timeout: TimeInterval = 5

    static let intervals: [Int] = [1, 5, 15, 30]

    private(set) var lastResult: UsageSnapshot?
    private(set) var lastAttempt: Date?

    /// Why the last poll produced nothing, for the settings page to own up to.
    private(set) var lastProblem: String?

    private var polling = false
    private var timer: Timer?
    private var onResult: ((UsageSnapshot) -> Void)?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = UsagePoller.timeout
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config,
                          delegate: NoRedirects.shared,
                          delegateQueue: nil)
    }()

    var isRunning: Bool { timer != nil }

    func start(everyMinutes minutes: Int, onResult: @escaping (UsageSnapshot) -> Void) {
        stop()
        self.onResult = onResult

        let t = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        t.tolerance = 15
        RunLoop.main.add(t, forMode: .common)
        timer = t

        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onResult = nil
        polling = false
    }

    func poll() {
        guard !polling else { return }
        polling = true
        lastAttempt = Date()

        Task { @MainActor in
            defer { polling = false }

            guard let token = await Credentials.accessToken() else {
                lastProblem = "No usable Claude Code login found"
                return
            }

            var request = URLRequest(url: Self.endpoint)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("Watchtower", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = Self.timeout

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastProblem = "Unexpected response"
                    return
                }
                guard http.statusCode == 200 else {
                    lastProblem = http.statusCode == 401
                        ? "Login has expired — run anything in Claude Code to renew it"
                        : "Anthropic returned \(http.statusCode)"
                    return
                }

                guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let rows = root["limits"] as? [[String: Any]]
                else {
                    lastProblem = "Could not read the response"
                    return
                }

                var snapshot = UsageSnapshot()
                snapshot.fetchedAt = Date()
                snapshot.limits = UsageLimit.parse(rows, now: Date())
                snapshot.stale = false

                lastProblem = nil
                lastResult = snapshot
                onResult?(snapshot)
            } catch {
                lastProblem = "Could not reach Anthropic"
            }
        }
    }
}

/// Refuses every redirect, so a bearer token cannot be handed to a host other
/// than the one compiled in.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    static let shared = NoRedirects()

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Finds the OAuth access token Claude Code has already stored, in the two
/// places it keeps one. Nothing here writes, and the token is returned to a
/// single caller that uses it once.
enum Credentials {
    /// What Claude Code names the item: `Claude Code` + an OAuth suffix that is
    /// empty in released builds + `-credentials`, with a hash of the config
    /// directory appended only when `CLAUDE_CONFIG_DIR` is set. A GUI app
    /// inherits no shell environment, so the plain name is the one to ask for,
    /// and the file below covers the rest.
    private static let service = "Claude Code-credentials"

    private static var file: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude")
            .appendingPathComponent(".credentials.json")
    }

    static func accessToken() async -> String? {
        let blob = await keychain() ?? (try? String(contentsOf: file, encoding: .utf8))
        guard let blob else { return nil }
        return token(in: blob)
    }

    /// Read through `/usr/bin/security`, which is what put the item there. The
    /// item's access list names that tool, so this is the one route that does
    /// not provoke a keychain prompt on every poll.
    private static func keychain() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
                task.arguments = ["find-generic-password", "-a", account, "-w", "-s", service]

                let out = Pipe()
                task.standardOutput = out
                task.standardError = FileHandle.nullDevice

                do { try task.run() } catch {
                    return continuation.resume(returning: nil)
                }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()

                guard task.terminationStatus == 0 else {
                    return continuation.resume(returning: nil)
                }
                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }

    /// The account Claude Code files it under: the login name, or a fixed
    /// stand-in when that holds anything unexpected.
    private static var account: String {
        let name = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !name.isEmpty, name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return "claude-code-user"
        }
        return name
    }

    /// `{ "claudeAiOauth": { "accessToken": …, "expiresAt": … } }`. An expired
    /// token is treated as no token: renewing it is Claude Code's business.
    private static func token(in blob: String) -> String? {
        guard let data = blob.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }

        if let expiresAt = oauth["expiresAt"] as? Double,
           Date(timeIntervalSince1970: expiresAt / 1000) <= Date() {
            return nil
        }
        return token
    }
}
