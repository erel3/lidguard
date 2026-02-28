import Contacts
import Foundation

final class SettingsService {
  static let shared = SettingsService()
  private let defaults = UserDefaults.standard
  private let contactStore = CNContactStore()

  private enum Keys {
    static let contactName = "lidguard.contactName"
    static let contactPhone = "lidguard.contactPhone"
    static let telegramEnabled = "lidguard.telegramEnabled"
    static let pushoverEnabled = "lidguard.pushoverEnabled"
    static let alarmSound = "lidguard.alarmSound"

    // Triggers
    static let triggerLidClose = "lidguard.triggerLidClose"
    static let triggerPowerDisconnect = "lidguard.triggerPowerDisconnect"
    static let triggerPowerButton = "lidguard.triggerPowerButton"

    // Global Shortcut
    static let shortcutKeyCode = "lidguard.shortcutKeyCode"
    static let shortcutModifiers = "lidguard.shortcutModifiers"
    static let shortcutEnabled = "lidguard.shortcutEnabled"

    // Behaviors
    static let behaviorSleepPrevention = "lidguard.behaviorSleepPrevention"
    static let behaviorShutdownBlocking = "lidguard.behaviorShutdownBlocking"
    static let behaviorLockScreen = "lidguard.behaviorLockScreen"
    static let behaviorAlarm = "lidguard.behaviorAlarm"
    static let behaviorAutoAlarm = "lidguard.behaviorAutoAlarm"
    static let alarmVolume = "lidguard.alarmVolume"

    // Updates
    static let autoUpdateEnabled = "lidguard.autoUpdateEnabled"
    static let lastUpdateCheckDate = "lidguard.lastUpdateCheckDate"
    static let skippedVersion = "lidguard.skippedVersion"
  }

  private enum KeychainKeys {
    static let telegramBotToken = "telegram.botToken"
    static let telegramChatId = "telegram.chatId"
    static let pushoverUserKey = "pushover.userKey"
    static let pushoverApiToken = "pushover.apiToken"
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

  // MARK: - Pushover (Keychain)

  var pushoverUserKey: String? {
    get { KeychainService.load(key: KeychainKeys.pushoverUserKey) }
    set {
      if let value = newValue {
        KeychainService.save(key: KeychainKeys.pushoverUserKey, value: value)
      } else {
        KeychainService.delete(key: KeychainKeys.pushoverUserKey)
      }
    }
  }

  var pushoverApiToken: String? {
    get { KeychainService.load(key: KeychainKeys.pushoverApiToken) }
    set {
      if let value = newValue {
        KeychainService.save(key: KeychainKeys.pushoverApiToken, value: value)
      } else {
        KeychainService.delete(key: KeychainKeys.pushoverApiToken)
      }
    }
  }

  var pushoverEnabled: Bool {
    get { defaults.object(forKey: Keys.pushoverEnabled) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.pushoverEnabled) }
  }

  var isPushoverConfigured: Bool {
    pushoverUserKey != nil && pushoverApiToken != nil
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

  var shortcutKeyCode: Int {
    get { defaults.object(forKey: Keys.shortcutKeyCode) as? Int ?? -1 }
    set { defaults.set(newValue, forKey: Keys.shortcutKeyCode) }
  }

  var shortcutModifiers: UInt {
    get { defaults.object(forKey: Keys.shortcutModifiers) as? UInt ?? 0 }
    set { defaults.set(newValue, forKey: Keys.shortcutModifiers) }
  }

  var shortcutEnabled: Bool {
    get { defaults.object(forKey: Keys.shortcutEnabled) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.shortcutEnabled) }
  }

  var isShortcutConfigured: Bool {
    shortcutKeyCode >= 0 && shortcutModifiers != 0
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

  // MARK: - Configuration Status

  func isConfigured() -> Bool {
    isTelegramConfigured || isPushoverConfigured
  }

  // MARK: - Reset

  func resetAll() {
    // Clear UserDefaults
    defaults.removeObject(forKey: Keys.contactName)
    defaults.removeObject(forKey: Keys.contactPhone)
    defaults.removeObject(forKey: Keys.telegramEnabled)
    defaults.removeObject(forKey: Keys.pushoverEnabled)
    defaults.removeObject(forKey: Keys.alarmSound)
    defaults.removeObject(forKey: Keys.triggerLidClose)
    defaults.removeObject(forKey: Keys.triggerPowerDisconnect)
    defaults.removeObject(forKey: Keys.triggerPowerButton)
    defaults.removeObject(forKey: Keys.shortcutKeyCode)
    defaults.removeObject(forKey: Keys.shortcutModifiers)
    defaults.removeObject(forKey: Keys.shortcutEnabled)
    defaults.removeObject(forKey: Keys.behaviorSleepPrevention)
    defaults.removeObject(forKey: Keys.behaviorShutdownBlocking)
    defaults.removeObject(forKey: Keys.behaviorLockScreen)
    defaults.removeObject(forKey: Keys.behaviorAlarm)
    defaults.removeObject(forKey: Keys.behaviorAutoAlarm)
    defaults.removeObject(forKey: Keys.alarmVolume)
    defaults.removeObject(forKey: Keys.autoUpdateEnabled)
    defaults.removeObject(forKey: Keys.lastUpdateCheckDate)
    defaults.removeObject(forKey: Keys.skippedVersion)

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
