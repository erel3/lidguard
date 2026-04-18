import Foundation
import IOKit
import os.log

@MainActor
protocol LidMonitorDelegate: AnyObject {
  func lidMonitorDidDetectClose(_ monitor: LidMonitorService)
  func lidMonitorDidDetectOpen(_ monitor: LidMonitorService)
}

@MainActor
final class LidMonitorService {
  weak var delegate: LidMonitorDelegate?

  private var lastState: Bool?
  private var timer: DispatchSourceTimer?
  private let checkInterval: TimeInterval
  private let queue = DispatchQueue(label: "com.lidguard.lidmonitor", qos: .userInitiated)

  init(checkInterval: TimeInterval = Config.Tracking.lidCheckInterval) {
    self.checkInterval = checkInterval
  }

  func start() {
    timer = DispatchSource.makeTimerSource(queue: queue)
    timer?.schedule(deadline: .now(), repeating: checkInterval)
    timer?.setEventHandler { [weak self] in
      self?.checkState()
    }
    timer?.resume()
    Logger.lid.info("Started")
  }

  func stop() {
    timer?.cancel()
    timer = nil
    lastState = nil
    Logger.lid.info("Stopped")
  }

  var isClosed: Bool {
    getClamshellState()
  }

  private func checkState() {
    let currentState = getClamshellState()

    if let last = lastState {
      if !last && currentState {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
          guard let self = self else { return }
          self.delegate?.lidMonitorDidDetectClose(self)
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
      } else if last && !currentState {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
          guard let self = self else { return }
          self.delegate?.lidMonitorDidDetectOpen(self)
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
      }
    }

    lastState = currentState
  }

  private func getClamshellState() -> Bool {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard service != 0 else { return false }
    defer { IOObjectRelease(service) }

    if let prop = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0) {
      return prop.takeRetainedValue() as? Bool ?? false
    }
    return false
  }
}
