import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac from falling asleep mid-turn.
///
/// Takes the same power assertions `caffeinate -i`/`-d` do, rather than
/// shelling out to it: no subprocess to supervise, and the assertions are
/// released by the kernel if Watchtower dies, so a crash cannot leave a
/// machine that will never sleep again.
///
/// By default only idle *system* sleep is prevented; the display still sleeps
/// on its usual schedule, and closing the lid still suspends — neither of
/// those is something an app should be overriding because a session happens
/// to be running. Display sleep is additionally held off only when a caller
/// opts in via `apply(_:preventDisplaySleep:)`.
@MainActor
final class SleepGuard {
    private var systemAssertion: IOPMAssertionID = IOPMAssertionID(0)
    private var displayAssertion: IOPMAssertionID = IOPMAssertionID(0)

    private(set) var held = false
    private(set) var heldDisplay = false

    /// Idempotent, so callers can hand it the current answer every refresh
    /// without tracking edges themselves.
    func apply(_ wanted: Bool, preventDisplaySleep: Bool = false) {
        if wanted != held {
            wanted ? acquireSystem() : releaseSystem()
        }
        let wantedDisplay = wanted && preventDisplaySleep
        if wantedDisplay != heldDisplay {
            wantedDisplay ? acquireDisplay() : releaseDisplay()
        }
    }

    private func acquireSystem() {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Watchtower: a Claude session is working" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return }
        systemAssertion = id
        held = true
    }

    private func releaseSystem() {
        guard held else { return }
        IOPMAssertionRelease(systemAssertion)
        systemAssertion = IOPMAssertionID(0)
        held = false
    }

    private func acquireDisplay() {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Watchtower: a Claude session is working" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return }
        displayAssertion = id
        heldDisplay = true
    }

    private func releaseDisplay() {
        guard heldDisplay else { return }
        IOPMAssertionRelease(displayAssertion)
        displayAssertion = IOPMAssertionID(0)
        heldDisplay = false
    }

    deinit {
        if held { IOPMAssertionRelease(systemAssertion) }
        if heldDisplay { IOPMAssertionRelease(displayAssertion) }
    }
}
