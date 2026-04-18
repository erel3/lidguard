import AppKit
import Foundation
import os.log

enum ProtectionState: Sendable {
  case disabled
  case enabled
  case enabledBluetooth
  case theftMode
}

enum TheftTrigger: Sendable {
  case lidClosed
  case powerDisconnected
  case motionDetected(String)

  var description: String {
    switch self {
    case .lidClosed: return "Lid closed"
    case .powerDisconnected: return "Power disconnected"
    case .motionDetected(let detail):
      return detail.isEmpty ? "Motion detected" : "Motion detected (\(detail))"
    }
  }
}

@MainActor
protocol TheftProtectionDelegate: AnyObject {
  func theftProtectionStateDidChange(_ service: TheftProtectionService, state: ProtectionState)
  func theftProtectionShortcutTriggered(_ service: TheftProtectionService)
  func theftProtectionBluetoothShortcutTriggered(_ service: TheftProtectionService)
}

@MainActor
final class TheftProtectionService {
  // Daemon connection state — mutated only by TheftProtectionService
  // and its +Daemon extension (same module). Readable elsewhere.
  @MainActor static var daemonConnected = false
  @MainActor static var daemonVersion: String?
  @MainActor static var helperNeedsUpdate = false
  @MainActor static var helperDisconnectedForUpdate = false
  @MainActor static var helperAccessibilityGranted = false
  @MainActor static var daemonMotionSupported = true

  weak var delegate: TheftProtectionDelegate?

  private let notificationService: NotificationService
  private let deviceInfoCollector: DeviceInfoCollecting
  private let sleepPrevention: SleepPrevention
  private let lidMonitor: LidMonitorService
  private let commandService: TelegramCommandService
  private let sleepWakeService: SleepWakeService
  private let powerMonitor: PowerMonitorService
  private let daemonClient: DaemonIPC
  private let globalShortcutService = GlobalShortcutService()
  private let bluetoothProximityService = BluetoothProximityService()

  private var lastManualDisarmTime: Date?
  var lastArmTime: Date?
  private var trackingTimer: DispatchSourceTimer?
  private var updateCount = 0
  private(set) var currentTrigger: TheftTrigger?
  private var stateBeforeTheft: ProtectionState?
  private var offlineSirenTimer: DispatchSourceTimer?
  private var telegramSucceededInTheftMode = false

  /// Grace period after arming (or re-arming from theft mode) during which
  /// motion triggers are suppressed, so the baseline has a chance to
  /// calibrate without capturing the owner's hands-on-laptop gesture.
  /// ~500ms covers the TCP round-trip, SPU wake, and calibration; the
  /// rest is slack for the user to let go of the lid.
  static let motionArmGrace: TimeInterval = 3

  private(set) var state: ProtectionState = .disabled

  init(notificationService: NotificationService? = nil,
       deviceInfoCollector: DeviceInfoCollecting? = nil,
       sleepPrevention: SleepPrevention? = nil,
       lidMonitor: LidMonitorService? = nil,
       commandService: TelegramCommandService? = nil,
       sleepWakeService: SleepWakeService? = nil,
       powerMonitor: PowerMonitorService? = nil,
       daemonClient: DaemonIPC? = nil) {
    self.notificationService = notificationService ?? TelegramService()
    self.deviceInfoCollector = deviceInfoCollector ?? DeviceInfoCollector()
    self.sleepPrevention = sleepPrevention ?? SleepPreventionService()
    self.lidMonitor = lidMonitor ?? LidMonitorService()
    self.commandService = commandService ?? TelegramCommandService()
    self.sleepWakeService = sleepWakeService ?? SleepWakeService()
    self.powerMonitor = powerMonitor ?? PowerMonitorService()
    self.daemonClient = daemonClient ?? DaemonIPCClient()

    self.lidMonitor.delegate = self
    self.commandService.delegate = self
    self.sleepWakeService.delegate = self
    self.powerMonitor.delegate = self
    self.globalShortcutService.delegate = self
    self.bluetoothProximityService.delegate = self
    if let client = self.daemonClient as? DaemonIPCClient {
      client.delegate = self
    }

    installNotificationObservers()
  }

  private func installNotificationObservers() {
    let center = NotificationCenter.default
    center.addObserver(forName: .shortcutSettingsChanged, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.globalShortcutService.restart() }
    }
    center.addObserver(forName: .motionSettingsChanged, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.handleMotionSettingsChange() }
    }
    center.addObserver(forName: .bluetoothSettingsChanged, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        if SettingsService.shared.bluetoothAutoArmEnabled {
          self?.bluetoothProximityService.restart()
        } else {
          self?.bluetoothProximityService.stop()
        }
      }
    }
    center.addObserver(forName: .telegramSettingsChanged, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.commandService.stop()
        self?.commandService.start()
        if SettingsService.shared.telegramEnabled {
          self?.deviceInfoCollector.warmUp()
        }
      }
    }
    center.addObserver(forName: .helperStatusRequested, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.daemonClient.isConnected else { return }
        self.daemonClient.getStatus()
      }
    }
    center.addObserver(forName: .helperUpdateDismissed, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.handleHelperUpdateDismissed() }
    }
    center.addObserver(forName: .helperInstallCompleted, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.handleHelperInstallCompleted() }
    }
  }

  private func handleHelperUpdateDismissed() {
    daemonClient.disconnect()
    TheftProtectionService.helperDisconnectedForUpdate = true
    TheftProtectionService.daemonConnected = false
    TheftProtectionService.daemonVersion = nil
    NotificationCenter.default.post(name: .daemonConnectionChanged, object: nil)
    Logger.daemon.warning("Disconnected from helper — required update was dismissed")
    ActivityLog.logAsync(.system, "Helper disconnected — update required but dismissed")
  }

  private func handleHelperInstallCompleted() {
    // Retry a few times — helper may not be running yet after manual install
    for delay in [0.0, 2.0, 5.0, 10.0] {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        MainActor.assumeIsolated {
          guard let self, !self.daemonClient.isConnected else { return }
          self.daemonClient.reconnectNow()
        }
      }
    }
  }

  func start() {
    if SettingsService.shared.telegramEnabled {
      deviceInfoCollector.warmUp()
    }
    commandService.start()
    sleepWakeService.start()
    globalShortcutService.start()
    daemonClient.connect()
    if SettingsService.shared.bluetoothAutoArmEnabled {
      bluetoothProximityService.start()
    }

    DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name("com.apple.screenIsUnlocked"),
      object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.state == .theftMode else { return }
        Logger.theft.info("Screen unlocked — deactivating theft mode")
        ActivityLog.logAsync(.theft, "Screen unlocked — owner authenticated")
        self.deactivateTheftMode()
      }
    }

    Logger.theft.info("Started (protection disabled)")
  }

  func shutdown() {
    commandService.stop()
    sleepWakeService.stop()
    lidMonitor.stop()
    powerMonitor.stop()
    globalShortcutService.stop()
    bluetoothProximityService.stop()
    daemonClient.disablePmset()
    daemonClient.disablePowerButton()
    daemonClient.disableMotionMonitoring()
    daemonClient.hideLockScreen()
    daemonClient.disconnect()
  }

  private func activeTriggerNames() -> [String] {
    let settings = SettingsService.shared
    var result: [String] = []
    if settings.triggerLidClose { result.append("lid close") }
    if settings.triggerPowerDisconnect { result.append("power disconnect") }
    if settings.triggerPowerButton { result.append("power button") }
    if settings.triggerMotionDetect { result.append("motion") }
    return result
  }

  private func activeBehaviorNames() -> [String] {
    let settings = SettingsService.shared
    var result: [String] = []
    if settings.behaviorSleepPrevention { result.append("sleep prevention") }
    if settings.behaviorLidCloseSleep { result.append("lid-close sleep prevention") }
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

    // Daemon features
    if settings.behaviorLidCloseSleep { daemonClient.enablePmset() }
    if settings.triggerPowerButton { daemonClient.enablePowerButton() }
    if settings.triggerMotionDetect && daemonClient.motionSupported {
      daemonClient.enableMotionMonitoring()
    }
    lastArmTime = Date()
  }

  /// Re-arm motion monitoring with a fresh baseline. Called after returning
  /// from theft mode — the laptop may have been repositioned while in theft
  /// mode, so the old baseline would cause an immediate re-trigger.
  private func recalibrateMotion() {
    guard SettingsService.shared.triggerMotionDetect && daemonClient.motionSupported else { return }
    daemonClient.disableMotionMonitoring()
    daemonClient.enableMotionMonitoring()
    lastArmTime = Date()
  }

  /// Apply a mid-arm toggle of the motion setting. Only meaningful when
  /// protection is actively armed — otherwise startMonitors/disableProtection
  /// handle lifecycle on their own.
  private func handleMotionSettingsChange() {
    guard state == .enabled || state == .enabledBluetooth else { return }
    if SettingsService.shared.triggerMotionDetect && daemonClient.motionSupported {
      daemonClient.enableMotionMonitoring()
      lastArmTime = Date()
    } else {
      daemonClient.disableMotionMonitoring()
    }
  }

  func enableProtection(notify: Bool = true, lockScreen: Bool = false) {
    guard state == .disabled else { return }

    state = .enabled

    if lockScreen {
      self.lockScreen()
    }
    startMonitors()
    Logger.theft.info("Protection enabled")
    ActivityLog.logAsync(.armed, "Protection enabled")

    if notify && SettingsService.shared.notifyProtectionToggle {
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

    if SettingsService.shared.lockScreenOnBluetoothArm {
      self.lockScreen()
    }
    startMonitors()
    Logger.theft.info("Protection enabled via Bluetooth auto-arm")
    ActivityLog.logAsync(.bluetooth, "Protection auto-armed (all devices out of range)")

    if SettingsService.shared.notifyAutoArm {
      notificationService.send(
        message: "📶 <b>PROTECTION AUTO-ARMED</b>\n\nAll trusted Bluetooth devices left range.",
        keyboard: .enabled,
        completion: nil
      )
    }

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
    daemonClient.disablePmset()
    daemonClient.disablePowerButton()
    daemonClient.disableMotionMonitoring()
    daemonClient.hideLockScreen()
    lastArmTime = nil
    Logger.theft.info("Protection disabled")

    let method = remote ? "Telegram" : "Touch ID"
    if wasBluetooth && !remote {
      ActivityLog.logAsync(.bluetooth, "Protection auto-disarmed (trusted device returned)")
      if SettingsService.shared.notifyAutoArm {
        notificationService.send(
          message: "📶 <b>PROTECTION AUTO-DISARMED</b>\n\nTrusted Bluetooth device returned.",
          keyboard: .disabled,
          completion: nil
        )
      }
    } else {
      ActivityLog.logAsync(.disarmed, "Protection disabled via \(method)")
      if SettingsService.shared.notifyProtectionToggle {
        notificationService.send(
          message: "🔴 <b>PROTECTION DISABLED</b>\n\nDisabled via \(method).",
          keyboard: .disabled,
          completion: nil
        )
      }
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
    // Stop motion monitoring while in theft mode (the main-app gate would
    // drop events anyway, but this saves helper CPU and log spam).
    // On deactivate, recalibrateMotion() restarts it with a fresh baseline.
    daemonClient.disableMotionMonitoring()

    // System lock screen + overlay message
    let settings = SettingsService.shared
    if settings.lockScreenOnTheftMode {
      lockScreen()
    }
    if settings.lockScreenOnTheftMode && settings.behaviorLockScreen {
      let name = settings.contactName ?? ""
      let phone = settings.contactPhone ?? ""
      daemonClient.showLockScreen(contactName: name, contactPhone: phone, message: "STOLEN DEVICE")
    }

    // Auto-play alarm if enabled
    if settings.behaviorAlarm && settings.behaviorAutoAlarm {
      AlarmAudioManager.shared.play()
    }

    // Offline siren: if Telegram not available, play siren immediately
    telegramSucceededInTheftMode = false
    if settings.offlineSirenEnabled && settings.behaviorAlarm
       && (!Config.Telegram.isConfigured || !Config.Telegram.isEnabled) {
      AlarmAudioManager.shared.play()
      ActivityLog.logAsync(.theft, "Offline siren triggered (Telegram not configured/disabled)")
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
    cancelOfflineSirenTimer()
    telegramSucceededInTheftMode = false
    daemonClient.hideLockScreen()
    recalibrateMotion()  // laptop may have been repositioned during theft
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
      MainActor.assumeIsolated {
        guard let self else { return }
        self.sendStatusWithInfo(info)
      }
    }
  }

  private func sendStatusWithInfo(_ info: DeviceInfo) {
    let status: String
    let keyboard: TelegramKeyboard

    switch state {
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

    let lidState = lidMonitor.isClosed ? "closed" : "open"
    let chargerState = powerMonitor.isCharging() ? "connected" : "disconnected"
    let triggers = activeTriggerNames()
    let behaviors = activeBehaviorNames()

    var hardwareInfo = ""
    hardwareInfo += "🖥 <b>Lid:</b> \(lidState)\n"
    hardwareInfo += "🔌 <b>Charger:</b> \(chargerState)\n"
    hardwareInfo += "⚡️ <b>Triggers:</b> \(triggers.isEmpty ? "none" : triggers.joined(separator: ", "))\n"
    hardwareInfo += "🛡 <b>Behaviors:</b> \(behaviors.isEmpty ? "none" : behaviors.joined(separator: ", "))\n"

    let settings = SettingsService.shared
    if settings.bluetoothAutoArmEnabled && settings.hasTrustedBLEDevices {
      bluetoothProximityService.getDeviceStatus { [weak self] devices in
        MainActor.assumeIsolated {
          guard let self else { return }
          var bt = "📶 <b>Bluetooth:</b> auto-arm on\n"
          for d in devices {
            if let rssi = d.rssi {
              bt += "  • \(d.name): nearby (\(rssi) dBm)\n"
            } else {
              bt += "  • \(d.name): not seen\n"
            }
          }
          self.notificationService.send(
            message: "<b>STATUS: \(status)</b>\n\n\(hardwareInfo)\(bt)\n\(info.formattedMessage)",
            keyboard: keyboard,
            completion: nil
          )
        }
      }
    } else {
      notificationService.send(
        message: "<b>STATUS: \(status)</b>\n\n\(hardwareInfo)📶 <b>Bluetooth:</b> auto-arm off\n\n\(info.formattedMessage)",
        keyboard: keyboard,
        completion: nil
      )
    }
  }

  func refreshLocation() {
    deviceInfoCollector.warmUp()
  }

  func sendTestAlert() {
    let keyboard: TelegramKeyboard = (state == .disabled) ? .disabled : .enabled
    deviceInfoCollector.collect { [weak self] info in
      MainActor.assumeIsolated {
        self?.notificationService.send(
          message: "🧪 <b>TEST ALERT</b>\n\n\(info.formattedMessage)",
          keyboard: keyboard,
          completion: nil
        )
      }
    }
    ActivityLog.logAsync(.system, "Test alert sent")
  }

  func sendShutdownAlert(blocked: Bool) {
    let title = blocked ? "SHUTDOWN BLOCKED" : "POWER BUTTON PRESSED"
    let subtitle = blocked ? "Someone tried to shut down!" : "Device may be force-powered off!"

    deviceInfoCollector.collect { [weak self] info in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.notificationService.send(
          message: "🚨 <b>\(title)</b>\n\n⚠️ \(subtitle)\n\n\(info.formattedMessage)",
          keyboard: self.state == .theftMode
            ? (AlarmAudioManager.shared.isPlaying ? .theftModeAlarmOn : .theftMode)
            : .enabled,
          completion: nil
        )
      }
    }
  }

  private func startTracking() {
    trackingTimer = DispatchSource.makeTimerSource(queue: .main)
    trackingTimer?.schedule(deadline: .now() + Config.Tracking.interval, repeating: Config.Tracking.interval)
    trackingTimer?.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        self?.sendUpdate(type: .tracking)
      }
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
      MainActor.assumeIsolated {
        guard let self else { return }
        self.deliverUpdate(type: type, info: info)
      }
    }
  }

  private func deliverUpdate(type: UpdateType, info: DeviceInfo) {
    let prefix: String
    switch type {
    case .initial:
      let reason = currentTrigger?.description ?? "Unknown"
      prefix = "🚨 <b>THEFT MODE ACTIVATED</b>\n⚠️ <b>Trigger:</b> \(reason)\n\n"
    case .tracking:
      prefix = "📡 <b>TRACKING UPDATE #\(updateCount)</b>\n\n"
      ActivityLog.logAsync(.theft, "Tracking update #\(updateCount) sent")
    }

    let keyboard: TelegramKeyboard = AlarmAudioManager.shared.isPlaying ? .theftModeAlarmOn : .theftMode
    notificationService.send(
      message: prefix + info.formattedMessage,
      keyboard: keyboard
    ) { [weak self] success in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self, self.state == .theftMode else { return }
          if success {
            self.telegramSucceededInTheftMode = true
            self.cancelOfflineSirenTimer()
          } else {
            self.scheduleOfflineSiren()
          }
        }
      }
    }
  }

  private enum UpdateType {
    case initial
    case tracking
  }

  private func scheduleOfflineSiren() {
    let settings = SettingsService.shared
    guard settings.offlineSirenEnabled, settings.behaviorAlarm,
          !telegramSucceededInTheftMode else { return }
    guard offlineSirenTimer == nil else { return }
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 10)
    timer.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.state == .theftMode else { return }
        AlarmAudioManager.shared.play()
        ActivityLog.logAsync(.theft, "Offline siren triggered (Telegram unreachable)")
      }
    }
    offlineSirenTimer = timer
    timer.resume()
  }

  private func cancelOfflineSirenTimer() {
    offlineSirenTimer?.cancel()
    offlineSirenTimer = nil
  }

  private func lockScreen() {
    daemonClient.lockScreen()
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
  // Telegram commands arrive on `com.lidguard.telegram.commands` (utility
  // queue, intentional). State mutations must happen on main so
  // `currentTrigger` and other state are read/written on a single thread.
  func telegramCommandReceived(_ command: TelegramCommand) {
    DispatchQueue.main.async { [weak self] in
      self?.handleTelegramCommand(command)
    }
  }

  private func handleTelegramCommand(_ command: TelegramCommand) {
    switch command {
    case .stop, .safe:
      deactivateTheftMode(remote: true)
    case .status:
      sendStatus()
    case .enable:
      enableProtection(lockScreen: SettingsService.shared.lockScreenOnTelegramEnable)
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
    // Check lid FIRST — if entering theft mode, services should stay active
    if (state == .enabled || state == .enabledBluetooth) && SettingsService.shared.triggerLidClose && lidMonitor.isClosed {
      activateTheftMode(trigger: .lidClosed)
    }
    // Only pause services if NOT in theft mode
    if state != .theftMode {
      bluetoothProximityService.pause()
      commandService.pause()
    }
  }

  func systemDidWake() {
    ActivityLog.logAsync(.power, "System did wake")
    // On any wake (including DarkWake), check lid for theft trigger
    if state == .enabled || state == .enabledBluetooth {
      if SettingsService.shared.triggerLidClose && lidMonitor.isClosed {
        activateTheftMode(trigger: .lidClosed)
        // Resume command polling even in DarkWake so user can remotely /stop
        commandService.resume()
      }
    }
    // Only resume services and re-enable assertions on full (user) wake, not DarkWake
    guard CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return }
    if state == .enabled || state == .enabledBluetooth {
      if SettingsService.shared.behaviorSleepPrevention {
        sleepPrevention.enable()
      }
    }
    bluetoothProximityService.resume()
    commandService.resume()
    // Laptop may have been moved during sleep — rebaseline motion.
    recalibrateMotion()
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
