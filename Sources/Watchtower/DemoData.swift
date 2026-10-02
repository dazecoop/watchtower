import Foundation

/// Fabricated sessions used only when `WT_DEMO=1` is set, so the README
/// screenshot can show a full dashboard without exposing real project names
/// or conversation content. Never reachable in normal use.
enum DemoData {
    static let isEnabled = ProcessInfo.processInfo.environment["WT_DEMO"] != nil

    /// Built once, so the age and thinking timers count up naturally from launch.
    static let sessions: [SessionSnapshot] = make()

    static let usage = UsageSnapshot(
        limits: [
            UsageLimit(id: "session", label: "Session", percent: 23,
                       resetsAt: Date().addingTimeInterval(3600 * 1.4), severity: "normal"),
            UsageLimit(id: "weekly_all", label: "Weekly", percent: 61,
                       resetsAt: Date().addingTimeInterval(3600 * 52), severity: "normal"),
            UsageLimit(id: "weekly_scopedFable", label: "Weekly Fable", percent: 88,
                       resetsAt: Date().addingTimeInterval(3600 * 52), severity: "warning")
        ],
        fetchedAt: Date().addingTimeInterval(-40)
    )

    private static var counter = 0

    private static func event(_ ago: TimeInterval, _ kind: ActivityEvent.Kind, _ detail: String) -> ActivityEvent {
        counter += 1
        return ActivityEvent(id: counter, at: Date().addingTimeInterval(-ago), kind: kind, detail: detail)
    }

    private static func session(
        name: String,
        folder: String,
        branch: String,
        title: String,
        model: String,
        context: Int,
        tools: Int,
        busy: Bool,
        idleFor: TimeInterval,
        events: [ActivityEvent]
    ) -> SessionSnapshot {
        let entry = RegistryEntry(
            pid: Int32.random(in: 10000...99999),
            sessionID: name,
            name: name,
            cwd: NSHomeDirectory() + "/Code/" + folder,
            startedAt: Date().addingTimeInterval(-3600 * 2),
            status: busy ? "busy" : "idle",
            statusUpdatedAt: Date().addingTimeInterval(-idleFor),
            version: "2.1.285",
            entrypoint: "claude-vscode"
        )

        var parsed = ParsedTranscript()
        parsed.title = title
        parsed.model = model
        parsed.gitBranch = branch
        parsed.contextTokens = context
        parsed.toolCalls = tools
        parsed.events = events
        parsed.lastEventAt = events.last?.at
        parsed.promptCount = max(1, tools / 6)
        parsed.outputTokens = tools * 1_900

        return SessionSnapshot(reg: entry, parsed: parsed, transcript: nil)
    }

    private static func make() -> [SessionSnapshot] {
        [
            session(
                name: "api-gateway-a4", folder: "api-gateway", branch: "main",
                title: "Rate limiting for the auth endpoints",
                model: "claude-opus-5", context: 128_000, tools: 31,
                busy: true, idleFor: 4,
                events: [
                    event(66, .prompt, "Add a per-IP rate limit to the auth routes, 20 requests a minute."),
                    event(51, .say, "I'll put the limiter in the middleware chain so every auth route picks it up."),
                    event(40, .tool("Read"), "src/middleware/rateLimit.ts"),
                    event(28, .tool("Bash"), "npm test -- rateLimit"),
                    event(19, .result(12), "12 passing"),
                    event(8, .say, "All twelve pass. Now wiring it into the router and checking the 429 body matches the error shape used elsewhere.")
                ]
            ),
            session(
                name: "storefront-b1", folder: "web-storefront", branch: "fix/cart-totals",
                title: "Cart total rounds wrong with stacked discounts",
                model: "claude-opus-5", context: 94_000, tools: 18,
                busy: true, idleFor: 2,
                events: [
                    event(45, .say, "Reproduced it — two percentage discounts round separately before summing."),
                    event(33, .tool("Grep"), "roundCurrency"),
                    event(24, .result(6), "src/cart/totals.ts:41"),
                    event(11, .thinking, "The fix is to defer rounding until the final total rather than per line."),
                    event(3, .tool("Edit"), "src/cart/totals.ts")
                ]
            ),
            session(
                name: "docs-site-c7", folder: "docs-site", branch: "main",
                title: "Rewrite the getting-started guide",
                model: "claude-sonnet-5-5", context: 47_000, tools: 9,
                busy: false, idleFor: 180,
                events: [
                    event(400, .tool("Write"), "content/getting-started.mdx"),
                    event(320, .tool("Bash"), "npm run build"),
                    event(300, .result(3), "built in 4.2s"),
                    event(190, .say, "Draft is in and the site builds. I've split install and first-run into separate pages — want me to add a troubleshooting section, or leave that for the FAQ?")
                ]
            ),
            session(
                name: "mobile-app-d2", folder: "mobile-app", branch: "feat/typed-routes",
                title: "Migrate navigation to typed routes",
                model: "claude-opus-5", context: 171_000, tools: 54,
                busy: true, idleFor: 520,
                events: [
                    event(900, .tool("Bash"), "npx tsc --noEmit"),
                    event(780, .result(31), "31 errors"),
                    event(640, .subagent("explore"), "Find every navigation.navigate call"),
                    event(530, .say, "Down to three errors, all in the onboarding stack where routes take optional params."),
                    event(500, .question, "Should the onboarding routes' optional params become required? It changes behaviour for deep links.")
                ]
            ),
            session(
                name: "data-pipeline-e9", folder: "data-pipeline", branch: "main",
                title: "Backfill the events table",
                model: "claude-sonnet-5-5", context: 62_000, tools: 23,
                busy: false, idleFor: 3600 * 2.4,
                events: [
                    event(9400, .tool("Bash"), "python backfill.py --dry-run --since 2026-01"),
                    event(9200, .result(4), "error: psycopg2.OperationalError: connection timed out"),
                    event(9000, .tool("Bash"), "python backfill.py --dry-run"),
                    event(8800, .result(18), "would write 1,284,003 rows"),
                    event(8600, .say, "Dry run looks right. Holding before the real run — it's a couple of hours of writes.")
                ]
            ),
            session(
                name: "infra-f3", folder: "infra", branch: "main",
                title: "Pin Terraform provider versions",
                model: "claude-sonnet-5-5", context: 38_000, tools: 12,
                busy: false, idleFor: 3600 * 5.1,
                events: [
                    event(19000, .tool("Edit"), "terraform/versions.tf"),
                    event(18800, .tool("Bash"), "terraform validate"),
                    event(18700, .result(2), "Success! The configuration is valid."),
                    event(18600, .say, "Pinned to the current minors and validated.")
                ]
            )
        ]
    }
}
