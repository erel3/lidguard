import Foundation
import os.log

extension Logger {
  static let app = Logger(subsystem: Config.App.bundleIdentifier, category: "app")
  static let theft = Logger(subsystem: Config.App.bundleIdentifier, category: "theft")
  static let lid = Logger(subsystem: Config.App.bundleIdentifier, category: "lid")
  static let telegram = Logger(subsystem: Config.App.bundleIdentifier, category: "telegram")
  static let location = Logger(subsystem: Config.App.bundleIdentifier, category: "location")
  static let system = Logger(subsystem: Config.App.bundleIdentifier, category: "system")
  static let power = Logger(subsystem: Config.App.bundleIdentifier, category: "power")
  static let update = Logger(subsystem: Config.App.bundleIdentifier, category: "update")
  static let bluetooth = Logger(subsystem: Config.App.bundleIdentifier, category: "bluetooth")
}

enum Config {
  enum Telegram {
    static var botToken: String? { SettingsService.shared.telegramBotToken }
    static var chatId: String? { SettingsService.shared.telegramChatId }
    static var isEnabled: Bool { SettingsService.shared.telegramEnabled }
    static var isConfigured: Bool { SettingsService.shared.isTelegramConfigured }
  }

  enum Tracking {
    static let interval: TimeInterval = 20
    static let lidCheckInterval: TimeInterval = 0.5
  }

  enum GitHub {
    static let releasesURL = "https://api.github.com/repos/Erel3/lidguard/releases"
    static let autoCheckInterval: TimeInterval = 12 * 60 * 60  // 12 hours
  }

  enum Bluetooth {
    static let scanDuration: TimeInterval = 15
    static let defaultRssiThreshold: Int = -70
    static let defaultArmGracePeriod: TimeInterval = 120
    static let rssiHysteresis: Int = 5
    static let btRecoveryCooldown: TimeInterval = 15
  }

  enum App {
    static let bundleIdentifier = "com.akim.lidguard"
    static let name = "LidGuard"
    static let version: String = {
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }()
  }
}
