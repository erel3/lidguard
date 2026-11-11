import Contacts
import Foundation

extension Notification.Name {
  static let bluetoothSettingsChanged = Notification.Name("com.lidguard.bluetoothSettingsChanged")
  static let telegramSettingsChanged = Notification.Name("com.lidguard.telegramSettingsChanged")
  static let motionSettingsChanged = Notification.Name("com.lidguard.motionSettingsChanged")
  /// Trigger/behavior settings were saved. Armed monitors must be reconciled
  /// against them — see `TheftProtectionService.reconcileMonitors()`.
  static let armedSettingsChanged = Notification.Name("com.lidguard.armedSettingsChanged")
  static let daemonConnectionChanged = Notification.Name("com.lidguard.daemonConnectionChanged")
  static let helperVersionChanged = Notification.Name("com.lidguard.helperVersionChanged")
  static let helperInstallCompleted = Notification.Name("com.lidguard.helperInstallCompleted")
  static let helperStatusChanged = Notification.Name("com.lidguard.helperStatusChanged")
  static let helperStatusRequested = Notification.Name("com.lidguard.helperStatusRequested")
  static let helperUpdateDismissed = Notification.Name("com.lidguard.helperUpdateDismissed")
}

@MainActor
final class SettingsService {
  static let shared = SettingsService()
  private let defaults = UserDefaults.standard
  private let contactStore = CNContactStore()

  private enum Keys: String, CaseIterable {
    case contactName = "lidguard.contactName"
    case contactPhone = "lidguard.contactPhone"
    case telegramEnabled = "lidguard.telegramEnabled"
    case alarmSound = "lidguard.alarmSound"

    // Triggers
    case triggerLidClose = "lidguard.triggerLidClose"
    case suppressLidTriggerWhenExternalDisplay = "lidguard.suppressLidTriggerWhenExternalDisplay"
    case triggerPowerDisconnect = "lidguard.triggerPowerDisconnect"
    case triggerPowerButton = "lidguard.triggerPowerButton"
    case triggerMotionDetect = "lidguard.triggerMotionDetect"

    // Global Shortcut
    case shortcutEnabled = "lidguard.shortcutEnabled"

    // Behaviors
    case behaviorSleepPrevention = "lidguard.behaviorSleepPrevention"
    case behaviorLidCloseSleep = "lidguard.behaviorLidCloseSleep"
    case behaviorShutdownBlocking = "lidguard.behaviorShutdownBlocking"
    case behaviorLockScreen = "lidguard.behaviorLockScreen"
    case lockScreenOnTheftMode = "lidguard.lockScreenOnTheftMode"
    case lockScreenOnShortcut = "lidguard.lockScreenOnShortcut"
    case lockScreenOnTelegramEnable = "lidguard.lockScreenOnTelegramEnable"
    case lockScreenOnBluetoothArm = "lidguard.lockScreenOnBluetoothArm"
    case biometricAuthEnabled = "lidguard.biometricAuthEnabled"
    case behaviorAlarm = "lidguard.behaviorAlarm"
    case behaviorAutoAlarm = "lidguard.behaviorAutoAlarm"
    case alarmVolume = "lidguard.alarmVolume"
    case offlineSirenEnabled = "lidguard.offlineSirenEnabled"
    case restoreTheftModeEnabled = "lidguard.restoreTheftModeEnabled"

    // Updates
    case autoUpdateEnabled = "lidguard.autoUpdateEnabled"
    case lastUpdateCheckDate = "lidguard.lastUpdateCheckDate"
    case skippedVersion = "lidguard.skippedVersion"
    case skippedHelperVersion = "lidguard.skippedHelperVersion"
    case lastHelperUpdateCheckDate = "lidguard.lastHelperUpdateCheckDate"

    // Setup
    case setupComplete = "lidguard.setupComplete"

    // Bluetooth Shortcut
    case btShortcutEnabled = "lidguard.btShortcutEnabled"

    // Notification toggles
    case notifyAutoArm = "lidguard.notifyAutoArm"
    case notifyProtectionToggle = "lidguard.notifyProtectionToggle"

    // Tracking data toggles
    case trackLocation = "lidguard.trackLocation"
    case trackPublicIP = "lidguard.trackPublicIP"
    case trackWiFi = "lidguard.trackWiFi"
    case trackBattery = "lidguard.trackBattery"
    case trackDeviceName = "lidguard.trackDeviceName"

    // Photo capture
    case photoCaptureEnabled = "lidguard.photoCaptureEnabled"
    case photoCaptureEveryN = "lidguard.photoCaptureEveryN"

    // Bluetooth
    case bluetoothAutoArmEnabled = "lidguard.bluetoothAutoArmEnabled"
    case trustedBLEDevices = "lidguard.trustedBLEDevices"
    case bluetoothArmGracePeriod = "lidguard.bluetoothArmGracePeriod"
    case trustedWiFiNetworks = "lidguard.trustedWiFiNetworks"
  }

  private enum KeychainKeys {
    static let telegramBotToken = "telegram.botToken"
    static let telegramChatId = "telegram.chatId"
  }

  private init() {}

  // MARK: - Contact Info (UserDefaults)

  var contactName: String? {
    get { defaults.string(forKey: Keys.contactName.rawValue) }
    set { defaults.set(newValue, forKey: Keys.contactName.rawValue) }
  }

  var contactPhone: String? {
    get { defaults.string(forKey: Keys.contactPhone.rawValue) }
    set { defaults.set(newValue, forKey: Keys.contactPhone.rawValue) }
  }

  var contactDisplay: String {
    var parts: [String] = []
    if let name = contactName { parts.append(name) }
    if let phone = contactPhone { parts.append(phone) }
    return parts.isEmpty ? "Contact owner" : parts.joined(separator: " • ")
  }

  // MARK: - Telegram (Keychain)

  var telegramBotToken: String? {
    get { KeychainService.load(key: KeychainKeys.telegramBotToken) }
    set {
      if let value = newValue {
        KeychainService.save(key: KeychainKeys.telegramBotToken, value: value)
      } else {
        KeychainService.delete(key: KeychainKeys.telegramBotToken)
      }
    }
  }

  var telegramChatId: String? {
    get { KeychainService.load(key: KeychainKeys.telegramChatId) }
    set {
      if let value = newValue {
        KeychainService.save(key: KeychainKeys.telegramChatId, value: value)
      } else {
        KeychainService.delete(key: KeychainKeys.telegramChatId)
      }
    }
  }

  var telegramEnabled: Bool {
    get { defaults.object(forKey: Keys.telegramEnabled.rawValue) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.telegramEnabled.rawValue) }
  }

  var isTelegramConfigured: Bool {
    telegramBotToken != nil && telegramChatId != nil
  }

  // MARK: - Alarm Sound

  var alarmSound: String {
    get { defaults.string(forKey: Keys.alarmSound.rawValue) ?? "Siren" }
    set { defaults.set(newValue, forKey: Keys.alarmSound.rawValue) }
  }

  // MARK: - Triggers

  var triggerLidClose: Bool {
    get { defaults.object(forKey: Keys.triggerLidClose.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.triggerLidClose.rawValue) }
  }

  /// When an external display is attached, suppress the lid-close trigger —
  /// clamshell mode at a dock is normal use, not theft.
  var suppressLidTriggerWhenExternalDisplay: Bool {
    get { defaults.object(forKey: Keys.suppressLidTriggerWhenExternalDisplay.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.suppressLidTriggerWhenExternalDisplay.rawValue) }
  }

  var triggerPowerDisconnect: Bool {
    get { defaults.object(forKey: Keys.triggerPowerDisconnect.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.triggerPowerDisconnect.rawValue) }
  }

  var triggerPowerButton: Bool {
    get { defaults.object(forKey: Keys.triggerPowerButton.rawValue) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.triggerPowerButton.rawValue) }
  }

  var triggerMotionDetect: Bool {
    get { defaults.object(forKey: Keys.triggerMotionDetect.rawValue) as? Bool ?? false }
    set {
      defaults.set(newValue, forKey: Keys.triggerMotionDetect.rawValue)
      NotificationCenter.default.post(name: .motionSettingsChanged, object: nil)
    }
  }

  // MARK: - Global Shortcut

  var shortcutEnabled: Bool {
    get { defaults.object(forKey: Keys.shortcutEnabled.rawValue) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.shortcutEnabled.rawValue) }
  }

  // MARK: - Behaviors

  var behaviorSleepPrevention: Bool {
    get { defaults.object(forKey: Keys.behaviorSleepPrevention.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.behaviorSleepPrevention.rawValue) }
  }

  var behaviorLidCloseSleep: Bool {
    get { defaults.object(forKey: Keys.behaviorLidCloseSleep.rawValue) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.behaviorLidCloseSleep.rawValue) }
  }

  var behaviorShutdownBlocking: Bool {
    get { defaults.object(forKey: Keys.behaviorShutdownBlocking.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.behaviorShutdownBlocking.rawValue) }
  }

  var behaviorLockScreen: Bool {
    get { defaults.object(forKey: Keys.behaviorLockScreen.rawValue) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.behaviorLockScreen.rawValue) }
  }

  var lockScreenOnTheftMode: Bool {
    get { defaults.object(forKey: Keys.lockScreenOnTheftMode.rawValue) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.lockScreenOnTheftMode.rawValue) }
  }

  var lockScreenOnShortcut: Bool {
    get { defaults.object(forKey: Keys.lockScreenOnShortcut.rawValue) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.lockScreenOnShortcut.rawValue) }
  }

  var lockScreenOnBluetoothArm: Bool {
    get { defaults.object(forKey: Keys.lockScreenOnBluetoothArm.rawValue) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.lockScreenOnBluetoothArm.rawValue) }
  }

  var lockScreenOnTelegramEnable: Bool {
    get { defaults.object(forKey: Keys.lockScreenOnTelegramEnable.rawValue) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.lockScreenOnTelegramEnable.rawValue) }
  }

  var biometricAuthEnabled: Bool {
    get { defaults.object(forKey: Keys.biometricAuthEnabled.rawValue) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.biometricAuthEnabled.rawValue) }
  }

  var behaviorAlarm: Bool {
    get { defaults.object(forKey: Keys.behaviorAlarm.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.behaviorAlarm.rawValue) }
  }

  var behaviorAutoAlarm: Bool {
    get { defaults.object(forKey: Keys.behaviorAutoAlarm.rawValue) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.behaviorAutoAlarm.rawValue) }
  }

  var alarmVolume: Int {
    get { defaults.object(forKey: Keys.alarmVolume.rawValue) as? Int ?? 100 }
    set { defaults.set(newValue, forKey: Keys.alarmVolume.rawValue) }
  }

  var offlineSirenEnabled: Bool {
    get { defaults.object(forKey: Keys.offlineSirenEnabled.rawValue) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.offlineSirenEnabled.rawValue) }
  }

  var restoreTheftModeEnabled: Bool {
    get { defaults.object(forKey: Keys.restoreTheftModeEnabled.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.restoreTheftModeEnabled.rawValue) }
  }

  // MARK: - Updates

  var autoUpdateEnabled: Bool {
    get { defaults.object(forKey: Keys.autoUpdateEnabled.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.autoUpdateEnabled.rawValue) }
  }

  var lastUpdateCheckDate: Date? {
    get { defaults.object(forKey: Keys.lastUpdateCheckDate.rawValue) as? Date }
    set { defaults.set(newValue, forKey: Keys.lastUpdateCheckDate.rawValue) }
  }

  var skippedVersion: String? {
    get { defaults.string(forKey: Keys.skippedVersion.rawValue) }
    set { defaults.set(newValue, forKey: Keys.skippedVersion.rawValue) }
  }

  var skippedHelperVersion: String? {
    get { defaults.string(forKey: Keys.skippedHelperVersion.rawValue) }
    set { defaults.set(newValue, forKey: Keys.skippedHelperVersion.rawValue) }
  }

  var lastHelperUpdateCheckDate: Date? {
    get { defaults.object(forKey: Keys.lastHelperUpdateCheckDate.rawValue) as? Date }
    set { defaults.set(newValue, forKey: Keys.lastHelperUpdateCheckDate.rawValue) }
  }

  // MARK: - Notification Toggles

  var notifyAutoArm: Bool {
    get { defaults.object(forKey: Keys.notifyAutoArm.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.notifyAutoArm.rawValue) }
  }

  var notifyProtectionToggle: Bool {
    get { defaults.object(forKey: Keys.notifyProtectionToggle.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.notifyProtectionToggle.rawValue) }
  }

  // MARK: - Tracking Data Toggles

  var trackLocation: Bool {
    get { defaults.object(forKey: Keys.trackLocation.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.trackLocation.rawValue) }
  }

  var trackPublicIP: Bool {
    get { defaults.object(forKey: Keys.trackPublicIP.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.trackPublicIP.rawValue) }
  }

  var trackWiFi: Bool {
    get { defaults.object(forKey: Keys.trackWiFi.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.trackWiFi.rawValue) }
  }

  var trackBattery: Bool {
    get { defaults.object(forKey: Keys.trackBattery.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.trackBattery.rawValue) }
  }

  var trackDeviceName: Bool {
    get { defaults.object(forKey: Keys.trackDeviceName.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.trackDeviceName.rawValue) }
  }

  var photoCaptureEnabled: Bool {
    get { defaults.object(forKey: Keys.photoCaptureEnabled.rawValue) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.photoCaptureEnabled.rawValue) }
  }

  var photoCaptureEveryN: Int {
    get { defaults.object(forKey: Keys.photoCaptureEveryN.rawValue) as? Int ?? 3 }
    set { defaults.set(newValue, forKey: Keys.photoCaptureEveryN.rawValue) }
  }

  // MARK: - Bluetooth Shortcut

  var btShortcutEnabled: Bool {
    get { defaults.object(forKey: Keys.btShortcutEnabled.rawValue) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.btShortcutEnabled.rawValue) }
  }

  // MARK: - Bluetooth

  var bluetoothAutoArmEnabled: Bool {
    get { defaults.object(forKey: Keys.bluetoothAutoArmEnabled.rawValue) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.bluetoothAutoArmEnabled.rawValue) }
  }

  var trustedBLEDevices: [TrustedBLEDevice] {
    get {
      guard let data = defaults.data(forKey: Keys.trustedBLEDevices.rawValue),
            let devices = try? JSONDecoder().decode([TrustedBLEDevice].self, from: data) else {
        return []
      }
      return devices
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        defaults.set(data, forKey: Keys.trustedBLEDevices.rawValue)
      }
    }
  }

  var bluetoothArmGracePeriod: TimeInterval {
    get { defaults.object(forKey: Keys.bluetoothArmGracePeriod.rawValue) as? TimeInterval ?? Config.Bluetooth.defaultArmGracePeriod }
    set { defaults.set(newValue, forKey: Keys.bluetoothArmGracePeriod.rawValue) }
  }

  /// SSIDs that block Bluetooth auto-arm while joined. See `TrustedWiFi`.
  var trustedWiFiNetworks: [String] {
    get { defaults.stringArray(forKey: Keys.trustedWiFiNetworks.rawValue) ?? [] }
    set { defaults.set(newValue, forKey: Keys.trustedWiFiNetworks.rawValue) }
  }

  var hasTrustedBLEDevices: Bool {
    !trustedBLEDevices.isEmpty
  }

  // MARK: - Setup

  var setupComplete: Bool {
    get { defaults.bool(forKey: Keys.setupComplete.rawValue) }
    set { defaults.set(newValue, forKey: Keys.setupComplete.rawValue) }
  }

  func isConfigured() -> Bool {
    setupComplete
  }

  // MARK: - Reset

  func resetAll() {
    // Clear UserDefaults — iterate every case so a newly added key can never
    // be forgotten here (the omission that previously stranded one setting).
    for key in Keys.allCases {
      defaults.removeObject(forKey: key.rawValue)
    }

    // Clear Keychain
    KeychainService.deleteAll()
  }

  // MARK: - macOS Owner

  private var macOSOwnerName: String? {
    let name = NSFullUserName()
    return name.isEmpty ? nil : name
  }

  // MARK: - My Card Phone

  private var myCardPhone: String? {
    guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
      return nil
    }

    let keys: [CNKeyDescriptor] = [CNContactPhoneNumbersKey as CNKeyDescriptor]
    guard let me = try? contactStore.unifiedMeContactWithKeys(toFetch: keys) else {
      return nil
    }

    let mobile = me.phoneNumbers.first { $0.label == CNLabelPhoneNumberMobile }
    return mobile?.value.stringValue ?? me.phoneNumbers.first?.value.stringValue
  }

  func requestContactsAccess(completion: @escaping @Sendable (Bool) -> Void) {
    contactStore.requestAccess(for: .contacts) { granted, _ in
      DispatchQueue.main.async {
        completion(granted)
      }
    }
  }

  func requestContactsAccessIfNeeded(completion: @escaping @Sendable () -> Void) {
    let status = CNContactStore.authorizationStatus(for: .contacts)
    if status == .notDetermined {
      requestContactsAccess { _ in
        completion()
      }
    } else {
      completion()
    }
  }
}
