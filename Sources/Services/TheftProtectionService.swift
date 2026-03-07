import AppKit
import Foundation
import os.log

enum ProtectionState {
  case disabled
  case enabled
  case enabledBluetooth
  case theftMode
}

enum TheftTrigger {
  case lidClosed
  case powerDisconnected

  var description: String {
    switch self {
    case .lidClosed: return "Lid closed"
    case .powerDisconnected: return "Power disconnected"
    }
  }
}

protocol TheftProtectionDelegate: AnyObject {
  func theftProtectionStateDidChange(_ service: TheftProtectionService, state: ProtectionState)
  func theftProtectionShortcutTriggered(_ service: TheftProtectionService)
  func theftProtectionBluetoothShortcutTriggered(_ service: TheftProtectionService)
}

final class TheftProtectionService {
  weak var delegate: TheftProtectionDelegate?

  private let notificationService: NotificationService
  private let deviceInfoCollector: DeviceInfoCollecting
  private let sleepPrevention: SleepPrevention
  private let lidMonitor: LidMonitorService
  private let commandService: TelegramCommandService
  private let sleepWakeService: SleepWakeService
  private let powerMonitor: PowerMonitorService
  private let globalShortcutService = GlobalShortcutService()
  private let bluetoothProximityService = BluetoothProximityService()

  private var lastManualDisarmTime: Date?
  private var trackingTimer: DispatchSourceTimer?
  private let trackingQueue = DispatchQueue(label: "com.lidguard.tracking", qos: .userInitiated)
  private var updateCount = 0
  private var currentTrigger: TheftTrigger?
  private var stateBeforeTheft: ProtectionState?

  private(set) var state: ProtectionState = .disabled

  init(notificationService: NotificationService = TelegramService(),
       deviceInfoCollector: DeviceInfoCollecting = DeviceInfoCollector(),
       sleepPrevention: SleepPrevention = SleepPreventionService(),
       lidMonitor: LidMonitorService = LidMonitorService(),
       commandService: TelegramCommandService = TelegramCommandService(),
       sleepWakeService: SleepWakeService = SleepWakeService(),
       powerMonitor: PowerMonitorService = PowerMonitorService()) {
    self.notificationService = notificationService
    self.deviceInfoCollector = deviceInfoCollector
    self.sleepPrevention = sleepPrevention
    self.lidMonitor = lidMonitor
    self.commandService = commandService
    self.sleepWakeService = sleepWakeService
    self.powerMonitor = powerMonitor

    self.lidMonitor.delegate = self
    self.commandService.delegate = self
    self.sleepWakeService.delegate = self
    self.powerMonitor.delegate = self
    self.globalShortcutService.delegate = self
    self.bluetoothProximityService.delegate = self

    NotificationCenter.default.addObserver(
      forName: .shortcutSettingsChanged, object: nil, queue: .main
    ) { [weak self] _ in
      self?.globalShortcutService.restart()
    }

    NotificationCenter.default.addObserver(
      forName: .bluetoothSettingsChanged, object: nil, queue: .main
    ) { [weak self] _ in
      if SettingsService.shared.bluetoothAutoArmEnabled {
        self?.bluetoothProximityService.restart()
      } else {
        self?.bluetoothProximityService.stop()
      }
      self?.globalShortcutService.restart()
    }
  }

  func start() {
    deviceInfoCollector.warmUp()
    commandService.start()
    sleepWakeService.start()
    globalShortcutService.start()
    if SettingsService.shared.bluetoothAutoArmEnabled {
      bluetoothProximityService.start()
    }
    Logger.theft.info("Started (protection disabled)")
  }

  func shutdown() {
    powerMonitor.stop()
    globalShortcutService.stop()
    bluetoothProximityService.stop()
  }

  private func activeTriggerNames() -> [String] {
    let settings = SettingsService.shared
    var result: [String] = []
    if settings.triggerLidClose { result.append("lid close") }
    if settings.triggerPowerDisconnect { result.append("power disconnect") }
    if settings.triggerPowerButton { result.append("power button") }
    return result
  }

  private func activeBehaviorNames() -> [String] {
    let settings = SettingsService.shared
    var result: [String] = []
    if settings.behaviorSleepPrevention { result.append("sleep prevention") }
    if settings.behaviorShutdownBlocking { result.append("shutdown blocking") }
    if settings.behaviorLockScreen { result.append("lock screen") }
    if settings.behaviorAlarm {
      result.append(settings.behaviorAutoAlarm ? "alarm (auto)" : "alarm")
    }
    return result
  }

  private func startMonitors() {
    let settings = SettingsService.shared
    if settings.behaviorSleepPrevention {
      sleepPrevention.enable()
    }
    if settings.triggerLidClose { lidMonitor.start() }
    if settings.triggerPowerDisconnect { powerMonitor.start() }
  }

  func enableProtection(notify: Bool = true, lockScreen: Bool = false) {
    guard state == .disabled else { return }

    state = .enabled

    if lockScreen {
      if Thread.isMainThread {
        self.lockScreen()
      } else {
        DispatchQueue.main.async { self.lockScreen() }
      }
    }
    startMonitors()
    Logger.theft.info("Protection enabled")
    ActivityLog.logAsync(.armed, "Protection enabled")

    if notify {
      let triggers = activeTriggerNames()
      let behaviors = activeBehaviorNames()
      var message = "🟢 <b>PROTECTION ENABLED</b>\n\n"
      message += "⚡️ <b>Triggers:</b> \(triggers.isEmpty ? "none" : triggers.joined(separator: ", "))\n"
      message += "🛡 <b>Behaviors:</b> \(behaviors.isEmpty ? "none" : behaviors.joined(separator: ", "))"

      notificationService.send(
        message: message,
        keyboard: .enabled,
        completion: nil
      )
    }

    delegate?.theftProtectionStateDidChange(self, state: .enabled)
  }

  func enableProtectionBluetooth() {
    guard state == .disabled else { return }

    state = .enabledBluetooth

    if Thread.isMainThread {
      self.lockScreen()
    } else {
      DispatchQueue.main.async { self.lockScreen() }
    }
    startMonitors()
    Logger.theft.info("Protection enabled via Bluetooth auto-arm")
    ActivityLog.logAsync(.bluetooth, "Protection auto-armed (all devices out of range)")

    notificationService.send(
      message: "📶 <b>PROTECTION AUTO-ARMED</b>\n\nAll trusted Bluetooth devices left range.",
      keyboard: .enabled,
      completion: nil
    )

    delegate?.theftProtectionStateDidChange(self, state: .enabledBluetooth)
  }

  func disableProtection(remote: Bool = false) {
    guard state == .enabled || state == .enabledBluetooth else { return }

    let wasBluetooth = state == .enabledBluetooth
    state = .disabled
    // Only set cooldown for genuine manual disarms (not bluetooth auto-disarm)
    if !wasBluetooth {
      lastManualDisarmTime = Date()
    }
    lidMonitor.stop()
    powerMonitor.stop()
    sleepPrevention.disable()
    Logger.theft.info("Protection disabled")

    let method = remote ? "Telegram" : "Touch ID"
    if wasBluetooth && !remote {
      ActivityLog.logAsync(.bluetooth, "Protection auto-disarmed (trusted device returned)")
      notificationService.send(
        message: "📶 <b>PROTECTION AUTO-DISARMED</b>\n\nTrusted Bluetooth device returned.",
        keyboard: .disabled,
        completion: nil
      )
    } else {
      ActivityLog.logAsync(.disarmed, "Protection disabled via \(method)")
      notificationService.send(
        message: "🔴 <b>PROTECTION DISABLED</b>\n\nDisabled via \(method).",
        keyboard: .disabled,
        completion: nil
      )
    }

    delegate?.theftProtectionStateDidChange(self, state: .disabled)
  }

  func activateTheftMode(trigger: TheftTrigger) {
    guard state == .enabled || state == .enabledBluetooth else { return }

    stateBeforeTheft = state
    state = .theftMode
    currentTrigger = trigger
    updateCount = 0
    Logger.theft.warning("THEFT MODE ACTIVATED - \(trigger.description)")
    ActivityLog.logAsync(.theft, "THEFT MODE ACTIVATED - \(trigger.description)")

    // Lock screen
    if SettingsService.shared.behaviorLockScreen {
      lockScreen()
    }

    // Auto-play alarm if enabled
    if SettingsService.shared.behaviorAlarm && SettingsService.shared.behaviorAutoAlarm {
      AlarmAudioManager.shared.play()
    }

    sendUpdate(type: .initial)
    startTracking()

    delegate?.theftProtectionStateDidChange(self, state: .theftMode)
  }

  func deactivateTheftMode(remote: Bool = false) {
    guard state == .theftMode else { return }

    let restoredState = stateBeforeTheft ?? .enabled
    state = restoredState
    stateBeforeTheft = nil
    stopTracking()
    updateCount = 0
    currentTrigger = nil
    AlarmAudioManager.shared.stop()
    Logger.theft.info("Theft mode deactivated")

    let method = remote ? "Telegram" : "Touch ID"
    ActivityLog.logAsync(.theft, "Theft mode deactivated via \(method)")

    notificationService.send(
      message: "✅ <b>THEFT MODE DEACTIVATED</b>\n\nOwner authenticated via \(method).",
      keyboard: .enabled,
      completion: nil
    )

    delegate?.theftProtectionStateDidChange(self, state: restoredState)
  }

  func sendStatus() {
    deviceInfoCollector.collect { [weak self] info in
      guard let self = self else { return }
      let status: String
      let keyboard: TelegramKeyboard

      switch self.state {
      case .disabled:
        status = "🔴 PROTECTION DISABLED"
        keyboard = .disabled
      case .enabled:
        status = "✅ Monitoring"
        keyboard = .enabled
      case .enabledBluetooth:
        status = "📶 Auto-Armed (Bluetooth)"
        keyboard = .enabled
      case .theftMode:
        status = "🚨 THEFT MODE ACTIVE"
        keyboard = AlarmAudioManager.shared.isPlaying ? .theftModeAlarmOn : .theftMode
      }

      let lidState = self.lidMonitor.isClosed ? "closed" : "open"
      let chargerState = self.powerMonitor.isCharging() ? "connected" : "disconnected"
      let triggers = self.activeTriggerNames()
      let behaviors = self.activeBehaviorNames()

      var hardwareInfo = ""
      hardwareInfo += "🖥 <b>Lid:</b> \(lidState)\n"
      hardwareInfo += "🔌 <b>Charger:</b> \(chargerState)\n"
      hardwareInfo += "⚡️ <b>Triggers:</b> \(triggers.isEmpty ? "none" : triggers.joined(separator: ", "))\n"
      hardwareInfo += "🛡 <b>Behaviors:</b> \(behaviors.isEmpty ? "none" : behaviors.joined(separator: ", "))\n"

      let sendMessage = { (btInfo: String) in
        self.notificationService.send(
          message: "<b>STATUS: \(status)</b>\n\n\(hardwareInfo)\(btInfo)\n\(info.formattedMessage)",
          keyboard: keyboard,
          completion: nil
        )
      }

      let settings = SettingsService.shared
      if settings.bluetoothAutoArmEnabled && settings.hasTrustedBLEDevices {
        self.bluetoothProximityService.getDeviceStatus { devices in
          var bt = "📶 <b>Bluetooth:</b> auto-arm on\n"
          for d in devices {
            if let rssi = d.rssi {
              bt += "  • \(d.name): nearby (\(rssi) dBm)\n"
            } else {
              bt += "  • \(d.name): not seen\n"
            }
          }
          sendMessage(bt)
        }
      } else {
        sendMessage("📶 <b>Bluetooth:</b> auto-arm off\n")
      }
    }
  }

  func refreshLocation() {
    deviceInfoCollector.warmUp()
  }

  func sendTestAlert() {
    let keyboard: TelegramKeyboard = (state == .disabled) ? .disabled : .enabled
    deviceInfoCollector.collect { [weak self] info in
      self?.notificationService.send(
        message: "🧪 <b>TEST ALERT</b>\n\n\(info.formattedMessage)",
        keyboard: keyboard,
        completion: nil
      )
    }
    ActivityLog.logAsync(.system, "Test alert sent")
  }

  func sendShutdownAlert(blocked: Bool) {
    let title = blocked ? "SHUTDOWN BLOCKED" : "POWER BUTTON PRESSED"
    let subtitle = blocked ? "Someone tried to shut down!" : "Device may be force-powered off!"

    deviceInfoCollector.collect { [weak self] info in
      guard let self = self else { return }
      self.notificationService.send(
        message: "🚨 <b>\(title)</b>\n\n⚠️ \(subtitle)\n\n\(info.formattedMessage)",
        keyboard: self.state == .theftMode
          ? (AlarmAudioManager.shared.isPlaying ? .theftModeAlarmOn : .theftMode)
          : .enabled,
        completion: nil
      )
    }

  }

  private func startTracking() {
    trackingTimer = DispatchSource.makeTimerSource(queue: trackingQueue)
    trackingTimer?.schedule(deadline: .now() + Config.Tracking.interval, repeating: Config.Tracking.interval)
    trackingTimer?.setEventHandler { [weak self] in
      self?.sendUpdate(type: .tracking)
    }
    trackingTimer?.resume()
  }

  private func stopTracking() {
    trackingTimer?.cancel()
    trackingTimer = nil
  }

  private func sendUpdate(type: UpdateType) {
    updateCount += 1

    deviceInfoCollector.collect { [weak self] info in
      guard let self = self else { return }

      let prefix: String
      switch type {
      case .initial:
        let reason = self.currentTrigger?.description ?? "Unknown"
        prefix = "🚨 <b>THEFT MODE ACTIVATED</b>\n⚠️ <b>Trigger:</b> \(reason)\n\n"
      case .tracking:
        prefix = "📡 <b>TRACKING UPDATE #\(self.updateCount)</b>\n\n"
        ActivityLog.logAsync(.theft, "Tracking update #\(self.updateCount) sent")
      }

      let keyboard: TelegramKeyboard = AlarmAudioManager.shared.isPlaying ? .theftModeAlarmOn : .theftMode
      self.notificationService.send(
        message: prefix + info.formattedMessage,
        keyboard: keyboard,
        completion: nil
      )
    }
  }

  private enum UpdateType {
    case initial
    case tracking
  }

  private func lockScreen() {
    // Use private Login framework API
    let libHandle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY)
    guard libHandle != nil else { return }
    guard let sym = dlsym(libHandle, "SACLockScreenImmediate") else { return }
    typealias LockFunction = @convention(c) () -> Void
    let lock = unsafeBitCast(sym, to: LockFunction.self)
    lock()
  }
}

// MARK: - LidMonitorDelegate
extension TheftProtectionService: LidMonitorDelegate {
  func lidMonitorDidDetectClose(_ monitor: LidMonitorService) {
    guard SettingsService.shared.triggerLidClose else { return }
    ActivityLog.logAsync(.trigger, "Lid closed detected")
    activateTheftMode(trigger: .lidClosed)
  }

  func lidMonitorDidDetectOpen(_ monitor: LidMonitorService) {
    Logger.theft.info("Lid opened - theft mode still active")
    ActivityLog.logAsync(.trigger, "Lid opened - theft mode still active")
  }
}

// MARK: - TelegramCommandDelegate
extension TheftProtectionService: TelegramCommandDelegate {
  func telegramCommandReceived(_ command: TelegramCommand) {
    switch command {
    case .stop, .safe:
      deactivateTheftMode(remote: true)
    case .status:
      sendStatus()
    case .enable:
      enableProtection(lockScreen: true)
    case .disable:
      disableProtection(remote: true)
    case .alarm:
      guard state == .theftMode else { return }
      guard SettingsService.shared.behaviorAlarm else { return }
      AlarmAudioManager.shared.play()
      notificationService.send(
        message: "🔊 <b>ALARM ACTIVATED</b>",
        keyboard: .theftModeAlarmOn,
        completion: nil
      )
    case .stopalarm:
      AlarmAudioManager.shared.stop()
      let keyboard: TelegramKeyboard = state == .theftMode ? .theftMode : .enabled
      notificationService.send(
        message: "🔇 <b>ALARM STOPPED</b>",
        keyboard: keyboard,
        completion: nil
      )
    }
  }
}

// MARK: - SleepWakeDelegate
extension TheftProtectionService: SleepWakeDelegate {
  func systemWillSleep() {
    ActivityLog.logAsync(.power, "System will sleep")
    // Check lid right before sleep (only if enabled)
    if (state == .enabled || state == .enabledBluetooth) && SettingsService.shared.triggerLidClose && lidMonitor.isClosed {
      activateTheftMode(trigger: .lidClosed)
    }
  }

  func systemDidWake() {
    ActivityLog.logAsync(.power, "System did wake")
    // On any wake (including DarkWake), check lid and re-enable sleep prevention
    if state == .enabled || state == .enabledBluetooth {
      if SettingsService.shared.behaviorSleepPrevention {
        sleepPrevention.enable()
      }
      if SettingsService.shared.triggerLidClose && lidMonitor.isClosed {
        activateTheftMode(trigger: .lidClosed)
      }
    }
  }

  func shouldDenySleep() -> Bool {
    return state == .theftMode
  }
}

// MARK: - PowerMonitorDelegate
extension TheftProtectionService: PowerMonitorDelegate {
  func powerMonitorDidDetectDisconnect(_ monitor: PowerMonitorService) {
    guard state == .enabled || state == .enabledBluetooth else { return }
    guard SettingsService.shared.triggerPowerDisconnect else { return }
    ActivityLog.logAsync(.trigger, "Power disconnected detected")
    activateTheftMode(trigger: .powerDisconnected)
  }
}

// MARK: - GlobalShortcutDelegate
extension TheftProtectionService: GlobalShortcutDelegate {
  func globalShortcutTriggered() {
    delegate?.theftProtectionShortcutTriggered(self)
  }

  func bluetoothShortcutTriggered() {
    delegate?.theftProtectionBluetoothShortcutTriggered(self)
  }
}

// MARK: - BluetoothProximityDelegate
extension TheftProtectionService: BluetoothProximityDelegate {
  func bluetoothProximityAllDevicesLost(_ service: BluetoothProximityService) {
    guard SettingsService.shared.bluetoothAutoArmEnabled else { return }
    guard state == .disabled else { return }

    // Suppress auto-arm for 5 min after manual disarm
    if let lastDisarm = lastManualDisarmTime,
       Date().timeIntervalSince(lastDisarm) < 300 {
      Logger.bluetooth.info("Skipping auto-arm — manual disarm cooldown active")
      ActivityLog.logAsync(.bluetooth, "Auto-arm suppressed (manual disarm cooldown)")
      return
    }

    enableProtectionBluetooth()
  }

  func bluetoothProximityDeviceReturned(_ service: BluetoothProximityService, device: TrustedBLEDevice) {
    guard SettingsService.shared.bluetoothAutoArmEnabled else { return }
    guard state == .enabledBluetooth else { return }

    Logger.bluetooth.info("Auto-disarming — device returned: \(device.name)")
    ActivityLog.logAsync(.bluetooth, "Auto-disarming — \(device.name) returned")
    disableProtection()
  }
}
