import Foundation
import os.log

extension Logger {
  static let app = Logger(subsystem: Config.App.bundleIdentifier, category: "app")
  static let theft = Logger(subsystem: Config.App.bundleIdentifier, category: "theft")
  static let lid = Logger(subsystem: Config.App.bundleIdentifier, category: "lid")
  static let telegram = Logger(subsystem: Config.App.bundleIdentifier, category: "telegram")
  static let pushover = Logger(subsystem: Config.App.bundleIdentifier, category: "pushover")
  static let location = Logger(subsystem: Config.App.bundleIdentifier, category: "location")
  static let system = Logger(subsystem: Config.App.bundleIdentifier, category: "system")
  static let power = Logger(subsystem: Config.App.bundleIdentifier, category: "power")
  static let update = Logger(subsystem: Config.App.bundleIdentifier, category: "update")
}

enum Config {
  enum Telegram {
    static var botToken: String? { SettingsService.shared.telegramBotToken }
    static var chatId: String? { SettingsService.shared.telegramChatId }
    static var isEnabled: Bool { SettingsService.shared.telegramEnabled }
    static var isConfigured: Bool { SettingsService.shared.isTelegramConfigured }
  }

  enum Pushover {
    static var userKey: String? { SettingsService.shared.pushoverUserKey }
    static var apiToken: String? { SettingsService.shared.pushoverApiToken }
    static var isEnabled: Bool { SettingsService.shared.pushoverEnabled }
    static var isConfigured: Bool { SettingsService.shared.isPushoverConfigured }
  }

  enum Tracking {
    static let interval: TimeInterval = 20
    static let lidCheckInterval: TimeInterval = 0.5
  }

  enum GitHub {
    static let releasesURL = "https://api.github.com/repos/Erel3/lidguard/releases"
    static let autoCheckInterval: TimeInterval = 2 * 24 * 60 * 60  // 2 days
  }

  enum App {
    static let bundleIdentifier = "com.akim.lidguard"
    static let name = "LidGuard"
    static let version: String = {
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }()
  }
}
