import Foundation
import IOKit.ps
import os.log

@MainActor
protocol PowerMonitorDelegate: AnyObject {
  func powerMonitorDidDetectDisconnect(_ monitor: PowerMonitorService)
}

@MainActor
final class PowerMonitorService {
  weak var delegate: PowerMonitorDelegate?

  private var runLoopSource: CFRunLoopSource?
  private var wasCharging: Bool?

  func start() {
    let context = Unmanaged.passUnretained(self).toOpaque()
    runLoopSource = IOPSNotificationCreateRunLoopSource({ ctx in
      guard let ctx = ctx else { return }
      Unmanaged<PowerMonitorService>.fromOpaque(ctx)
        .takeUnretainedValue()
        .checkPowerState()
    }, context)?.takeRetainedValue()

    guard let source = runLoopSource else {
      Logger.power.error("Failed to create power notification source")
      return
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

    // Initialize state
    wasCharging = isCharging()
    Logger.power.info("Started (charging: \(self.wasCharging == true))")
  }

  func stop() {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
      runLoopSource = nil
    }
    wasCharging = nil
    Logger.power.info("Stopped")
  }

  private func checkPowerState() {
    let charging = isCharging()
    defer { wasCharging = charging }

    // Detect disconnect: was charging → not charging
    if wasCharging == true && charging == false {
      Logger.power.warning("Power disconnected")
      delegate?.powerMonitorDidDetectDisconnect(self)
    }
  }

  func isCharging() -> Bool {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
          let source = sources.first,
          let info = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?
            .takeUnretainedValue() as? [String: Any]
    else { return false }

    return info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
  }
}
