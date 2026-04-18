import Foundation
import IOKit.pwr_mgt
import os.log

// IOKit message constants (not exposed to Swift)
private let kIOMessageCanSystemSleep: UInt32 = 0xe0000270
private let kIOMessageSystemWillSleep: UInt32 = 0xe0000280
private let kIOMessageSystemHasPoweredOn: UInt32 = 0xe0000300

@MainActor
protocol SleepWakeDelegate: AnyObject {
  func systemWillSleep()
  func systemDidWake()
  func shouldDenySleep() -> Bool
}

@MainActor
final class SleepWakeService {
  weak var delegate: SleepWakeDelegate?

  private var notificationPort: IONotificationPortRef?
  private var runLoopSource: CFRunLoopSource?
  private var notifierObject: io_object_t = 0
  private var rootPort: io_connect_t = 0

  isolated deinit {
    stop()
  }

  func start() {
    rootPort = IORegisterForSystemPower(
      Unmanaged.passUnretained(self).toOpaque(),
      &notificationPort,
      powerCallback,
      &notifierObject
    )

    guard rootPort != 0 else {
      Logger.power.error("SleepWakeService failed to register")
      return
    }

    if let port = notificationPort {
      let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
      runLoopSource = source
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    Logger.power.info("SleepWakeService started")
  }

  func stop() {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
      runLoopSource = nil
    }
    if notifierObject != 0 {
      IODeregisterForSystemPower(&notifierObject)
      notifierObject = 0
    }
    if let port = notificationPort {
      IONotificationPortDestroy(port)
      notificationPort = nil
    }
    rootPort = 0
  }

  fileprivate func handlePower(_ type: UInt32, _ argBits: Int) {
    switch type {
    case kIOMessageSystemWillSleep:
      Logger.power.info("System will sleep")
      delegate?.systemWillSleep()
      IOAllowPowerChange(rootPort, argBits)

    case kIOMessageSystemHasPoweredOn:
      Logger.power.info("System did wake")
      delegate?.systemDidWake()

    case kIOMessageCanSystemSleep:
      if delegate?.shouldDenySleep() == true {
        IOCancelPowerChange(rootPort, argBits)
      } else {
        IOAllowPowerChange(rootPort, argBits)
      }

    default:
      break
    }
  }
}

private func powerCallback(
  refCon: UnsafeMutableRawPointer?,
  service: io_service_t,
  messageType: UInt32,
  messageArgument: UnsafeMutableRawPointer?
) {
  guard let refCon = refCon else { return }
  let svc = Unmanaged<SleepWakeService>.fromOpaque(refCon).takeUnretainedValue()
  let argBits: Int = messageArgument.map { Int(bitPattern: $0) } ?? 0
  MainActor.assumeIsolated {
    svc.handlePower(messageType, argBits)
  }
}
