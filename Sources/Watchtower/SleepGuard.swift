import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac from falling asleep mid-turn.
///
/// Takes the same power assertion `caffeinate -i` does, rather than shelling
/// out to it: no subprocess to supervise, and the assertion is released by the
/// kernel if Watchtower dies, so a crash cannot leave a machine that will never
/// sleep again.
///
/// Only idle *system* sleep is prevented. The display still sleeps on its usual
/// schedule, and closing the lid still suspends — neither of those is something
/// an app should be overriding because a session happens to be running.
@MainActor
final class SleepGuard {
    private var assertion: IOPMAssertionID = IOPMAssertionID(0)

    private(set) var held = false

    /// Idempotent, so callers can hand it the current answer every refresh
    /// without tracking edges themselves.
    func apply(_ wanted: Bool) {
        guard wanted != held else { return }
        wanted ? acquire() : release()
    }

    private func acquire() {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Watchtower: a Claude session is working" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return }
        assertion = id
        held = true
    }

    private func release() {
        guard held else { return }
        IOPMAssertionRelease(assertion)
        assertion = IOPMAssertionID(0)
        held = false
    }

    deinit {
        if held { IOPMAssertionRelease(assertion) }
    }
}
