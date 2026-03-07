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

protocol GlobalShortcutDelegate: AnyObject {
  func globalShortcutTriggered()
  func bluetoothShortcutTriggered()
}

/// Monitors for user-configured global keyboard shortcuts.
/// Uses CGEventTap via KeyboardShortcuts library — requires Input Monitoring permission.
final class GlobalShortcutService {
  weak var delegate: GlobalShortcutDelegate?

  private var lastTriggerTime: Date = .distantPast
  private var lastBtTriggerTime: Date = .distantPast

  func start() {
    let settings = SettingsService.shared

    if settings.shortcutEnabled {
      KeyboardShortcuts.onKeyUp(for: .toggleProtection) { [weak self] in
        guard let self, Date().timeIntervalSince(self.lastTriggerTime) > 1.0 else { return }
        self.lastTriggerTime = Date()
        ActivityLog.logAsync(.trigger, "Global shortcut pressed")
        self.delegate?.globalShortcutTriggered()
      }
      Logger.theft.info("Global shortcut monitor started")
      ActivityLog.logAsync(.system, "Global shortcut monitor started")
    }

    if settings.btShortcutEnabled {
      KeyboardShortcuts.onKeyUp(for: .toggleBluetooth) { [weak self] in
        guard let self, Date().timeIntervalSince(self.lastBtTriggerTime) > 1.0 else { return }
        self.lastBtTriggerTime = Date()
        ActivityLog.logAsync(.bluetooth, "Bluetooth shortcut pressed")
        self.delegate?.bluetoothShortcutTriggered()
      }
      Logger.bluetooth.info("Bluetooth shortcut monitor started")
      ActivityLog.logAsync(.bluetooth, "Bluetooth shortcut monitor started")
    }
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
