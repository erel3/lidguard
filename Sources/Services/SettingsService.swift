#if !APPSTORE
import Contacts
#endif
import Foundation

extension Notification.Name {
  static let bluetoothSettingsChanged = Notification.Name("com.lidguard.bluetoothSettingsChanged")
  static let telegramSettingsChanged = Notification.Name("com.lidguard.telegramSettingsChanged")
  static let motionSettingsChanged = Notification.Name("com.lidguard.motionSettingsChanged")
  static let daemonConnectionChanged = Notification.Name("com.lidguard.daemonConnectionChanged")
  static let helperVersionChanged = Notification.Name("com.lidguard.helperVersionChanged")
  static let helperInstallCompleted = Notification.Name("com.lidguard.helperInstallCompleted")
  static let helperStatusChanged = Notification.Name("com.lidguard.helperStatusChanged")
  static let helperStatusRequested = Notification.Name("com.lidguard.helperStatusRequested")
  static let helperUpdateDismissed = Notification.Name("com.lidguard.helperUpdateDismissed")
}

final class SettingsService {
  static let shared = SettingsService()
  private let defaults = UserDefaults.standard
  #if !APPSTORE
  private let contactStore = CNContactStore()
  #endif

  private enum Keys {
    static let contactName = "lidguard.contactName"
    static let contactPhone = "lidguard.contactPhone"
    static let telegramEnabled = "lidguard.telegramEnabled"
    static let alarmSound = "lidguard.alarmSound"

    // Triggers
    static let triggerLidClose = "lidguard.triggerLidClose"
    static let triggerPowerDisconnect = "lidguard.triggerPowerDisconnect"
    static let triggerPowerButton = "lidguard.triggerPowerButton"
    static let triggerMotionDetect = "lidguard.triggerMotionDetect"

    // Global Shortcut
    static let shortcutEnabled = "lidguard.shortcutEnabled"

    // Behaviors
    static let behaviorSleepPrevention = "lidguard.behaviorSleepPrevention"
    static let behaviorLidCloseSleep = "lidguard.behaviorLidCloseSleep"
    static let behaviorShutdownBlocking = "lidguard.behaviorShutdownBlocking"
    static let behaviorLockScreen = "lidguard.behaviorLockScreen"
    static let lockScreenOnTheftMode = "lidguard.lockScreenOnTheftMode"
    static let lockScreenOnShortcut = "lidguard.lockScreenOnShortcut"
    static let lockScreenOnTelegramEnable = "lidguard.lockScreenOnTelegramEnable"
    static let lockScreenOnBluetoothArm = "lidguard.lockScreenOnBluetoothArm"
    static let biometricAuthEnabled = "lidguard.biometricAuthEnabled"
    static let behaviorAlarm = "lidguard.behaviorAlarm"
    static let behaviorAutoAlarm = "lidguard.behaviorAutoAlarm"
    static let alarmVolume = "lidguard.alarmVolume"
    static let offlineSirenEnabled = "lidguard.offlineSirenEnabled"

    // Updates
    static let autoUpdateEnabled = "lidguard.autoUpdateEnabled"
    static let lastUpdateCheckDate = "lidguard.lastUpdateCheckDate"
    #if !APPSTORE
    static let skippedVersion = "lidguard.skippedVersion"
    static let skippedHelperVersion = "lidguard.skippedHelperVersion"
    #endif
    static let lastHelperUpdateCheckDate = "lidguard.lastHelperUpdateCheckDate"

    // Setup
    static let setupComplete = "lidguard.setupComplete"

    // Bluetooth Shortcut
    static let btShortcutEnabled = "lidguard.btShortcutEnabled"

    // Notification toggles
    static let notifyAutoArm = "lidguard.notifyAutoArm"
    static let notifyProtectionToggle = "lidguard.notifyProtectionToggle"

    // Tracking data toggles
    static let trackLocation = "lidguard.trackLocation"
    static let trackPublicIP = "lidguard.trackPublicIP"
    static let trackWiFi = "lidguard.trackWiFi"
    static let trackBattery = "lidguard.trackBattery"
    static let trackDeviceName = "lidguard.trackDeviceName"

    // Bluetooth
    static let bluetoothAutoArmEnabled = "lidguard.bluetoothAutoArmEnabled"
    static let trustedBLEDevices = "lidguard.trustedBLEDevices"
    static let bluetoothArmGracePeriod = "lidguard.bluetoothArmGracePeriod"
  }

  private enum KeychainKeys {
    static let telegramBotToken = "telegram.botToken"
    static let telegramChatId = "telegram.chatId"
  }

  private init() {}

  // MARK: - Contact Info (UserDefaults)

  var contactName: String? {
    get { defaults.string(forKey: Keys.contactName) }
    set { defaults.set(newValue, forKey: Keys.contactName) }
  }

  var contactPhone: String? {
    get { defaults.string(forKey: Keys.contactPhone) }
    set { defaults.set(newValue, forKey: Keys.contactPhone) }
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
    get { defaults.object(forKey: Keys.telegramEnabled) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.telegramEnabled) }
  }

  var isTelegramConfigured: Bool {
    telegramBotToken != nil && telegramChatId != nil
  }

  // MARK: - Alarm Sound

  var alarmSound: String {
    get { defaults.string(forKey: Keys.alarmSound) ?? "Siren" }
    set { defaults.set(newValue, forKey: Keys.alarmSound) }
  }

  // MARK: - Triggers

  var triggerLidClose: Bool {
    get { defaults.object(forKey: Keys.triggerLidClose) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.triggerLidClose) }
  }

  var triggerPowerDisconnect: Bool {
    get { defaults.object(forKey: Keys.triggerPowerDisconnect) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.triggerPowerDisconnect) }
  }

  var triggerPowerButton: Bool {
    get { defaults.object(forKey: Keys.triggerPowerButton) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.triggerPowerButton) }
  }

  var triggerMotionDetect: Bool {
    get {
      #if APPSTORE
      return false
      #else
      return defaults.object(forKey: Keys.triggerMotionDetect) as? Bool ?? false
      #endif
    }
    set {
      #if !APPSTORE
      defaults.set(newValue, forKey: Keys.triggerMotionDetect)
      NotificationCenter.default.post(name: .motionSettingsChanged, object: nil)
      #endif
    }
  }

  // MARK: - Global Shortcut

  var shortcutEnabled: Bool {
    get { defaults.object(forKey: Keys.shortcutEnabled) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.shortcutEnabled) }
  }

  // MARK: - Behaviors

  var behaviorSleepPrevention: Bool {
    get { defaults.object(forKey: Keys.behaviorSleepPrevention) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.behaviorSleepPrevention) }
  }

  var behaviorLidCloseSleep: Bool {
    get { defaults.object(forKey: Keys.behaviorLidCloseSleep) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.behaviorLidCloseSleep) }
  }

  var behaviorShutdownBlocking: Bool {
    get { defaults.object(forKey: Keys.behaviorShutdownBlocking) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.behaviorShutdownBlocking) }
  }

  var behaviorLockScreen: Bool {
    get { defaults.object(forKey: Keys.behaviorLockScreen) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.behaviorLockScreen) }
  }

  var lockScreenOnTheftMode: Bool {
    get { defaults.object(forKey: Keys.lockScreenOnTheftMode) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.lockScreenOnTheftMode) }
  }

  var lockScreenOnShortcut: Bool {
    get { defaults.object(forKey: Keys.lockScreenOnShortcut) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.lockScreenOnShortcut) }
  }

  var lockScreenOnBluetoothArm: Bool {
    get { defaults.object(forKey: Keys.lockScreenOnBluetoothArm) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.lockScreenOnBluetoothArm) }
  }

  var lockScreenOnTelegramEnable: Bool {
    get { defaults.object(forKey: Keys.lockScreenOnTelegramEnable) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.lockScreenOnTelegramEnable) }
  }

  var biometricAuthEnabled: Bool {
    get { defaults.object(forKey: Keys.biometricAuthEnabled) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.biometricAuthEnabled) }
  }

  var behaviorAlarm: Bool {
    get { defaults.object(forKey: Keys.behaviorAlarm) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.behaviorAlarm) }
  }

  var behaviorAutoAlarm: Bool {
    get { defaults.object(forKey: Keys.behaviorAutoAlarm) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.behaviorAutoAlarm) }
  }

  var alarmVolume: Int {
    get { defaults.object(forKey: Keys.alarmVolume) as? Int ?? 100 }
    set { defaults.set(newValue, forKey: Keys.alarmVolume) }
  }

  var offlineSirenEnabled: Bool {
    get { defaults.object(forKey: Keys.offlineSirenEnabled) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.offlineSirenEnabled) }
  }

  // MARK: - Updates

  var autoUpdateEnabled: Bool {
    get { defaults.object(forKey: Keys.autoUpdateEnabled) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.autoUpdateEnabled) }
  }

  var lastUpdateCheckDate: Date? {
    get { defaults.object(forKey: Keys.lastUpdateCheckDate) as? Date }
    set { defaults.set(newValue, forKey: Keys.lastUpdateCheckDate) }
  }

  #if !APPSTORE
  var skippedVersion: String? {
    get { defaults.string(forKey: Keys.skippedVersion) }
    set { defaults.set(newValue, forKey: Keys.skippedVersion) }
  }

  var skippedHelperVersion: String? {
    get { defaults.string(forKey: Keys.skippedHelperVersion) }
    set { defaults.set(newValue, forKey: Keys.skippedHelperVersion) }
  }
  #endif

  var lastHelperUpdateCheckDate: Date? {
    get { defaults.object(forKey: Keys.lastHelperUpdateCheckDate) as? Date }
    set { defaults.set(newValue, forKey: Keys.lastHelperUpdateCheckDate) }
  }

  // MARK: - Notification Toggles

  var notifyAutoArm: Bool {
    get { defaults.object(forKey: Keys.notifyAutoArm) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.notifyAutoArm) }
  }

  var notifyProtectionToggle: Bool {
    get { defaults.object(forKey: Keys.notifyProtectionToggle) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.notifyProtectionToggle) }
  }

  // MARK: - Tracking Data Toggles

  var trackLocation: Bool {
    get { defaults.object(forKey: Keys.trackLocation) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.trackLocation) }
  }

  var trackPublicIP: Bool {
    get { defaults.object(forKey: Keys.trackPublicIP) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.trackPublicIP) }
  }

  var trackWiFi: Bool {
    get { defaults.object(forKey: Keys.trackWiFi) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.trackWiFi) }
  }

  var trackBattery: Bool {
    get { defaults.object(forKey: Keys.trackBattery) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.trackBattery) }
  }

  var trackDeviceName: Bool {
    get { defaults.object(forKey: Keys.trackDeviceName) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.trackDeviceName) }
  }

  // MARK: - Bluetooth Shortcut

  var btShortcutEnabled: Bool {
    get { defaults.object(forKey: Keys.btShortcutEnabled) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.btShortcutEnabled) }
  }

  // MARK: - Bluetooth

  var bluetoothAutoArmEnabled: Bool {
    get { defaults.object(forKey: Keys.bluetoothAutoArmEnabled) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.bluetoothAutoArmEnabled) }
  }

  var trustedBLEDevices: [TrustedBLEDevice] {
    get {
      guard let data = defaults.data(forKey: Keys.trustedBLEDevices),
            let devices = try? JSONDecoder().decode([TrustedBLEDevice].self, from: data) else {
        return []
      }
      return devices
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        defaults.set(data, forKey: Keys.trustedBLEDevices)
      }
    }
  }

  var bluetoothArmGracePeriod: TimeInterval {
    get { defaults.object(forKey: Keys.bluetoothArmGracePeriod) as? TimeInterval ?? Config.Bluetooth.defaultArmGracePeriod }
    set { defaults.set(newValue, forKey: Keys.bluetoothArmGracePeriod) }
  }

  var hasTrustedBLEDevices: Bool {
    !trustedBLEDevices.isEmpty
  }

  // MARK: - Setup

  var setupComplete: Bool {
    get { defaults.bool(forKey: Keys.setupComplete) }
    set { defaults.set(newValue, forKey: Keys.setupComplete) }
  }

  func isConfigured() -> Bool {
    setupComplete
  }

  // MARK: - Reset

  func resetAll() {
    // Clear UserDefaults
    defaults.removeObject(forKey: Keys.contactName)
    defaults.removeObject(forKey: Keys.contactPhone)
    defaults.removeObject(forKey: Keys.telegramEnabled)
    defaults.removeObject(forKey: Keys.alarmSound)
    defaults.removeObject(forKey: Keys.triggerLidClose)
    defaults.removeObject(forKey: Keys.triggerPowerDisconnect)
    defaults.removeObject(forKey: Keys.triggerPowerButton)
    defaults.removeObject(forKey: Keys.triggerMotionDetect)
    defaults.removeObject(forKey: Keys.shortcutEnabled)
    defaults.removeObject(forKey: Keys.behaviorSleepPrevention)
    defaults.removeObject(forKey: Keys.behaviorLidCloseSleep)
    defaults.removeObject(forKey: Keys.behaviorShutdownBlocking)
    defaults.removeObject(forKey: Keys.behaviorLockScreen)
    defaults.removeObject(forKey: Keys.lockScreenOnTheftMode)
    defaults.removeObject(forKey: Keys.lockScreenOnShortcut)
    defaults.removeObject(forKey: Keys.lockScreenOnBluetoothArm)
    defaults.removeObject(forKey: Keys.lockScreenOnTelegramEnable)
    defaults.removeObject(forKey: Keys.biometricAuthEnabled)
    defaults.removeObject(forKey: Keys.behaviorAlarm)
    defaults.removeObject(forKey: Keys.behaviorAutoAlarm)
    defaults.removeObject(forKey: Keys.alarmVolume)
    defaults.removeObject(forKey: Keys.offlineSirenEnabled)
    defaults.removeObject(forKey: Keys.notifyAutoArm)
    defaults.removeObject(forKey: Keys.notifyProtectionToggle)
    defaults.removeObject(forKey: Keys.trackLocation)
    defaults.removeObject(forKey: Keys.trackPublicIP)
    defaults.removeObject(forKey: Keys.trackWiFi)
    defaults.removeObject(forKey: Keys.trackBattery)
    defaults.removeObject(forKey: Keys.trackDeviceName)
    defaults.removeObject(forKey: Keys.setupComplete)
    defaults.removeObject(forKey: Keys.autoUpdateEnabled)
    defaults.removeObject(forKey: Keys.lastUpdateCheckDate)
    #if !APPSTORE
    defaults.removeObject(forKey: Keys.skippedVersion)
    defaults.removeObject(forKey: Keys.skippedHelperVersion)
    #endif
    defaults.removeObject(forKey: Keys.lastHelperUpdateCheckDate)
    defaults.removeObject(forKey: Keys.btShortcutEnabled)
    defaults.removeObject(forKey: Keys.bluetoothAutoArmEnabled)
    defaults.removeObject(forKey: Keys.trustedBLEDevices)
    defaults.removeObject(forKey: Keys.bluetoothArmGracePeriod)

    // Clear Keychain
    KeychainService.deleteAll()
  }

  // MARK: - macOS Owner

  private var macOSOwnerName: String? {
    let name = NSFullUserName()
    return name.isEmpty ? nil : name
  }

  // MARK: - My Card Phone

  #if !APPSTORE
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

  func requestContactsAccess(completion: @escaping (Bool) -> Void) {
    contactStore.requestAccess(for: .contacts) { granted, _ in
      DispatchQueue.main.async {
        completion(granted)
      }
    }
  }

  func requestContactsAccessIfNeeded(completion: @escaping () -> Void) {
    let status = CNContactStore.authorizationStatus(for: .contacts)
    if status == .notDetermined {
      requestContactsAccess { _ in
        completion()
      }
    } else {
      completion()
    }
  }
  #endif
}
