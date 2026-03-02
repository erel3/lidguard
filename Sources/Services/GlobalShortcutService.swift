import ApplicationServices
import Cocoa
import os.log

extension Notification.Name {
  static let shortcutSettingsChanged = Notification.Name("com.lidguard.shortcutSettingsChanged")
}

protocol GlobalShortcutDelegate: AnyObject {
  func globalShortcutTriggered()
  func bluetoothShortcutTriggered()
}

/// Monitors for a user-configured global keyboard shortcut.
/// Requires Accessibility permission for global event monitoring.
final class GlobalShortcutService {
  weak var delegate: GlobalShortcutDelegate?

  private var globalMonitor: Any?
  private var keyCode: Int = -1
  private var modifiers: NSEvent.ModifierFlags = []
  private var btKeyCode: Int = -1
  private var btModifiers: NSEvent.ModifierFlags = []
  private var lastTriggerTime: Date = .distantPast
  private var lastBtTriggerTime: Date = .distantPast

  func start() {
    let settings = SettingsService.shared
    let hasProtectionShortcut = settings.shortcutEnabled && settings.isShortcutConfigured
    let hasBtShortcut = settings.btShortcutEnabled && settings.isBtShortcutConfigured

    guard hasProtectionShortcut || hasBtShortcut else { return }
    guard globalMonitor == nil else { return }

    if hasProtectionShortcut {
      keyCode = settings.shortcutKeyCode
      modifiers = NSEvent.ModifierFlags(rawValue: UInt(settings.shortcutModifiers))
        .intersection([.command, .control, .option, .shift])
    }

    if hasBtShortcut {
      btKeyCode = settings.btShortcutKeyCode
      btModifiers = NSEvent.ModifierFlags(rawValue: UInt(settings.btShortcutModifiers))
        .intersection([.command, .control, .option, .shift])
    }

    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(options) {
      Logger.power.warning("Accessibility permission not granted - global shortcut may not work")
    }

    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.handleKeyEvent(event)
    }

    if hasProtectionShortcut {
      let displayStr = shortcutDisplayString(keyCode: keyCode, modifiers: modifiers)
      Logger.theft.info("Global shortcut monitor started: \(displayStr)")
      ActivityLog.logAsync(.system, "Global shortcut monitor started: \(displayStr)")
    }
    if hasBtShortcut {
      let displayStr = shortcutDisplayString(keyCode: btKeyCode, modifiers: btModifiers)
      Logger.bluetooth.info("Bluetooth shortcut monitor started: \(displayStr)")
      ActivityLog.logAsync(.bluetooth, "Bluetooth shortcut monitor started: \(displayStr)")
    }
  }

  func stop() {
    if let monitor = globalMonitor {
      NSEvent.removeMonitor(monitor)
      globalMonitor = nil
    }
    keyCode = -1
    btKeyCode = -1
  }

  func restart() {
    stop()
    start()
  }

  private func handleKeyEvent(_ event: NSEvent) {
    let eventMods = event.modifierFlags.intersection([.command, .control, .option, .shift])
    let code = Int(event.keyCode)

    if keyCode >= 0 && code == keyCode && eventMods == modifiers {
      guard Date().timeIntervalSince(lastTriggerTime) > 1.0 else { return }
      lastTriggerTime = Date()
      ActivityLog.logAsync(.trigger, "Global shortcut pressed")
      delegate?.globalShortcutTriggered()
    } else if btKeyCode >= 0 && code == btKeyCode && eventMods == btModifiers {
      guard Date().timeIntervalSince(lastBtTriggerTime) > 1.0 else { return }
      lastBtTriggerTime = Date()
      ActivityLog.logAsync(.bluetooth, "Bluetooth shortcut pressed")
      delegate?.bluetoothShortcutTriggered()
    }
  }
}
