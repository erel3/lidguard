import Foundation
import IOKit.pwr_mgt

@MainActor
protocol SleepPrevention {
  func enable()
  func disable()
  var isEnabled: Bool { get }
}

@MainActor
final class SleepPreventionService: SleepPrevention {
  private var idleSleepAssertionID: IOPMAssertionID = 0
  private var systemSleepAssertionID: IOPMAssertionID = 0
  private(set) var isEnabled = false

  func enable() {
    guard !isEnabled else { return }

    let reason = "LidGuard theft protection active" as CFString

    // Prevent idle sleep
    IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      reason,
      &idleSleepAssertionID
    )

    // Prevent system sleep (more aggressive, includes lid close)
    let result = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventSystemSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      reason,
      &systemSleepAssertionID
    )

    isEnabled = (result == kIOReturnSuccess)
    print("[SleepPreventionService] \(isEnabled ? "Enabled" : "Failed to enable")")
  }

  func disable() {
    guard isEnabled else { return }

    IOPMAssertionRelease(idleSleepAssertionID)
    IOPMAssertionRelease(systemSleepAssertionID)
    isEnabled = false
    print("[SleepPreventionService] Disabled")
  }
}
