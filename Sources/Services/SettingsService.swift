import Contacts
import Foundation

extension Notification.Name {
  static let bluetoothSettingsChanged = Notification.Name("com.lidguard.bluetoothSettingsChanged")
  static let daemonConnectionChanged = Notification.Name("com.lidguard.daemonConnectionChanged")
}

final class SettingsService {
  static let shared = SettingsService()
  private let defaults = UserDefaults.standard
  private let contactStore = CNContactStore()

  private enum Keys {
    static let contactName = "lidguard.contactName"
    static let contactPhone = "lidguard.contactPhone"
    static let telegramEnabled = "lidguard.telegramEnabled"
    static let alarmSound = "lidguard.alarmSound"

    // Triggers
    static let triggerLidClose = "lidguard.triggerLidClose"
    static let triggerPowerDisconnect = "lidguard.triggerPowerDisconnect"
    static let triggerPowerButton = "lidguard.triggerPowerButton"

    // Global Shortcut
    static let shortcutEnabled = "lidguard.shortcutEnabled"

    // Behaviors
    static let behaviorSleepPrevention = "lidguard.behaviorSleepPrevention"
    static let behaviorShutdownBlocking = "lidguard.behaviorShutdownBlocking"
    static let behaviorLockScreen = "lidguard.behaviorLockScreen"
    static let behaviorAlarm = "lidguard.behaviorAlarm"
    static let behaviorAutoAlarm = "lidguard.behaviorAutoAlarm"
    static let alarmVolume = "lidguard.alarmVolume"
    static let offlineSirenEnabled = "lidguard.offlineSirenEnabled"

    // Updates
    static let autoUpdateEnabled = "lidguard.autoUpdateEnabled"
    static let lastUpdateCheckDate = "lidguard.lastUpdateCheckDate"
    static let skippedVersion = "lidguard.skippedVersion"

    // Bluetooth Shortcut
    static let btShortcutEnabled = "lidguard.btShortcutEnabled"

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
    get { defaults.string(forKey: Keys.contactName) ?? macOSOwnerName }
    set { defaults.set(newValue, forKey: Keys.contactName) }
  }

  var contactPhone: String? {
    get { defaults.string(forKey: Keys.contactPhone) ?? myCardPhone }
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
    get { defaults.object(forKey: Keys.telegramEnabled) as? Bool ?? true }
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

  var behaviorShutdownBlocking: Bool {
    get { defaults.object(forKey: Keys.behaviorShutdownBlocking) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.behaviorShutdownBlocking) }
  }

  var behaviorLockScreen: Bool {
    get { defaults.object(forKey: Keys.behaviorLockScreen) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.behaviorLockScreen) }
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

  var skippedVersion: String? {
    get { defaults.string(forKey: Keys.skippedVersion) }
    set { defaults.set(newValue, forKey: Keys.skippedVersion) }
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

  // MARK: - Configuration Status

  func isConfigured() -> Bool {
    isTelegramConfigured
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
    defaults.removeObject(forKey: Keys.shortcutEnabled)
    defaults.removeObject(forKey: Keys.behaviorSleepPrevention)
    defaults.removeObject(forKey: Keys.behaviorShutdownBlocking)
    defaults.removeObject(forKey: Keys.behaviorLockScreen)
    defaults.removeObject(forKey: Keys.behaviorAlarm)
    defaults.removeObject(forKey: Keys.behaviorAutoAlarm)
    defaults.removeObject(forKey: Keys.alarmVolume)
    defaults.removeObject(forKey: Keys.offlineSirenEnabled)
    defaults.removeObject(forKey: Keys.autoUpdateEnabled)
    defaults.removeObject(forKey: Keys.lastUpdateCheckDate)
    defaults.removeObject(forKey: Keys.skippedVersion)
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
}
