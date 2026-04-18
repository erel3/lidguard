import Foundation
import KeyboardShortcuts
import os.log

extension Notification.Name {
  static let shortcutSettingsChanged = Notification.Name("com.lidguard.shortcutSettingsChanged")
}

extension KeyboardShortcuts.Name {
  static let toggleProtection = Self("toggleProtection")
  static let toggleBluetooth = Self("toggleBluetooth")
}

@MainActor
protocol GlobalShortcutDelegate: AnyObject {
  func globalShortcutTriggered()
  func bluetoothShortcutTriggered()
}

/// Monitors for user-configured global keyboard shortcuts.
/// Uses CGEventTap via KeyboardShortcuts library — requires Input Monitoring permission.
@MainActor
final class GlobalShortcutService {
  weak var delegate: GlobalShortcutDelegate?

  private var lastTriggerTime: Date = .distantPast
  private var lastBtTriggerTime: Date = .distantPast

  func start() {
    KeyboardShortcuts.onKeyUp(for: .toggleProtection) { [weak self] in
      guard let self, Date().timeIntervalSince(self.lastTriggerTime) > 1.0 else { return }
      self.lastTriggerTime = Date()
      ActivityLog.logAsync(.trigger, "Global shortcut pressed")
      self.delegate?.globalShortcutTriggered()
    }

    KeyboardShortcuts.onKeyUp(for: .toggleBluetooth) { [weak self] in
      guard let self, Date().timeIntervalSince(self.lastBtTriggerTime) > 1.0 else { return }
      self.lastBtTriggerTime = Date()
      ActivityLog.logAsync(.bluetooth, "Bluetooth shortcut pressed")
      self.delegate?.bluetoothShortcutTriggered()
    }

    Logger.theft.info("Global shortcut monitor started")
  }

  func stop() {
    KeyboardShortcuts.disable(.toggleProtection)
    KeyboardShortcuts.disable(.toggleBluetooth)
  }

  func restart() {
    stop()
    start()
  }
}
