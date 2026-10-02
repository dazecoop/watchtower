import Foundation
import Network
import os

/// Where the Mac's internet stands. Worth three states rather than two: a
/// dropped Wi-Fi link and a Wi-Fi link that reaches nothing look identical from
/// the app's point of view, but mean very different things to whoever has to
/// fix it.
enum NetStatus: Equatable {
    /// A public resolver answered.
    case online
    /// An interface is up, but nothing answered — a captive portal, a dead
    /// router, DNS blocked, a VPN half-way up.
    case degraded
    /// No usable interface at all.
    case offline
    /// Not checked yet, or checking is turned off.
    case unknown

    var label: String {
        switch self {
        case .online: return "Internet is working"
        case .degraded: return "Connected, but nothing is answering"
        case .offline: return "No network connection"
        case .unknown: return "Not checked yet"
        }
    }
}

/// Watches whether the Mac can actually reach the internet, as opposed to
/// merely holding an IP address.
///
/// This is the one part of Watchtower that touches the network, so it is off
/// until asked for, and even then it never speaks to Anthropic, to this
/// project, or to anything that could identify the machine. It opens a TCP
/// connection to port 53 on a public DNS resolver, notes whether it opened,
/// and closes it. Nothing is sent and nothing is read.
@MainActor
final class ReachabilityMonitor {
    private(set) var status: NetStatus = .unknown {
        didSet { if status != oldValue { onChange?(status) } }
    }
    private(set) var checkedAt: Date?

    /// Reported outwards rather than published: the store mirrors this into
    /// its own state, so views have one object to observe instead of two.
    var onChange: ((NetStatus) -> Void)?

    /// Rotated so no single operator sees more than one connection a minute,
    /// which keeps this comfortably inside what any of them consider normal
    /// use, and stops one resolver having a bad day from reading as an outage.
    private let resolvers = ["1.1.1.1", "8.8.8.8", "9.9.9.9", "208.67.222.222"]
    private var next = 0

    /// Long enough that a slow link isn't called dead, short enough that the
    /// dot is not lying for a quarter of the poll interval.
    private nonisolated static let timeout: TimeInterval = 4

    static let interval: TimeInterval = 15

    private nonisolated let queue = DispatchQueue(label: "watchtower.net", qos: .utility)
    private var path: NWPathMonitor?
    private var timer: Timer?
    private var probing = false

    /// The last thing `NWPathMonitor` said about the link, which decides
    /// whether a failed probe reads as offline or merely degraded.
    private var linkUp = true

    var isRunning: Bool { path != nil }

    func start() {
        guard path == nil else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor [weak self] in self?.linkChanged(to: up) }
        }
        monitor.start(queue: queue)
        path = monitor

        // Fires on the same cadence whatever happens, so a probe that hangs
        // can't stall the schedule.
        let t = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.check() }
        }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t

        check()
    }

    func stop() {
        path?.cancel()
        path = nil
        timer?.invalidate()
        timer = nil
        probing = false
        status = .unknown
        checkedAt = nil
    }

    /// A link coming back is worth checking immediately rather than waiting out
    /// the interval — that is the moment someone is staring at the dot.
    private func linkChanged(to up: Bool) {
        let was = linkUp
        linkUp = up
        if !up {
            status = .offline
            checkedAt = Date()
        } else if !was {
            check()
        }
    }

    private func check() {
        guard isRunning, !probing else { return }
        guard linkUp else {
            status = .offline
            checkedAt = Date()
            return
        }

        probing = true
        probe(take()) { [weak self] ok in
            guard let self else { return }
            if ok { return self.settle(.online) }

            // One dropped connection is not an outage. Before calling it,
            // try a different operator — two in a row failing is real.
            self.probe(self.take()) { [weak self] retry in
                guard let self else { return }
                self.settle(retry ? .online : (self.linkUp ? .degraded : .offline))
            }
        }
    }

    private func settle(_ result: NetStatus) {
        probing = false
        checkedAt = Date()
        status = result
    }

    private func take() -> String {
        defer { next = (next + 1) % resolvers.count }
        return resolvers[next]
    }

    /// Opens a connection, notes whether it opened, and drops it. `.waiting`
    /// counts as a failure: it means the system has nowhere to send this right
    /// now, which is exactly what a dead network looks like.
    private nonisolated func probe(_ host: String, then: @escaping @MainActor @Sendable (Bool) -> Void) {
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = Int(Self.timeout)
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: 53,
                                      using: NWParameters(tls: nil, tcp: tcp))

        let answered = OSAllocatedUnfairLock(initialState: false)
        let finish: @Sendable (Bool) -> Void = { ok in
            let first = answered.withLock { done -> Bool in
                defer { done = true }
                return !done
            }
            guard first else { return }
            connection.cancel()
            Task { @MainActor in then(ok) }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: finish(true)
            case .failed, .cancelled, .waiting: finish(false)
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.timeout) { finish(false) }
    }
}
