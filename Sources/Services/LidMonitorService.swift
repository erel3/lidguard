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

  init(checkInterval: TimeInterval = Config.Tracking.lidCheckInterval) {
    self.checkInterval = checkInterval
  }

  func start() {
    let newTimer = DispatchSource.makeTimerSource(queue: .main)
    newTimer.schedule(deadline: .now(), repeating: checkInterval)
    newTimer.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        self?.checkState()
      }
    }
    newTimer.resume()
    timer = newTimer
    Logger.lid.info("Started")
  }

  func stop() {
    timer?.cancel()
    timer = nil
    lastState = nil
    Logger.lid.info("Stopped")
  }

  var isClosed: Bool {
    Self.getClamshellState()
  }

  private func checkState() {
    let currentState = Self.getClamshellState()

    if let last = lastState {
      if !last && currentState {
        delegate?.lidMonitorDidDetectClose(self)
      } else if last && !currentState {
        delegate?.lidMonitorDidDetectOpen(self)
      }
    }

    lastState = currentState
  }

  nonisolated private static func getClamshellState() -> Bool {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard service != 0 else { return false }
    defer { IOObjectRelease(service) }

    if let prop = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0) {
      return prop.takeRetainedValue() as? Bool ?? false
    }
    return false
  }
}
