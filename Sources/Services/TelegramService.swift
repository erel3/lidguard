import Foundation
import os.log

enum TelegramKeyboard: Sendable {
  case none
  case theftMode           // "Safe" + "Alarm"
  case theftModeAlarmOn    // "Safe" + "Stop Alarm"
  case enabled             // "Status" + "Disable"
  case disabled            // "Status" + "Enable"
}

@MainActor
protocol NotificationService {
  func send(message: String, keyboard: TelegramKeyboard, completion: (@Sendable (Bool) -> Void)?)
}

extension NotificationService {
  func send(message: String, completion: (@Sendable (Bool) -> Void)?) {
    send(message: message, keyboard: .none, completion: completion)
  }
}

@MainActor
final class TelegramService: NotificationService {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func send(message: String, keyboard: TelegramKeyboard = .none, completion: (@Sendable (Bool) -> Void)? = nil) {
    guard Config.Telegram.isConfigured && Config.Telegram.isEnabled,
          let botToken = Config.Telegram.botToken,
          let chatId = Config.Telegram.chatId else {
      Logger.telegram.debug("Telegram not configured or disabled, skipping")
      completion?(false)
      return
    }

    let urlString = "https://api.telegram.org/bot\(botToken)/sendMessage"
    guard let url = URL(string: urlString) else {
      completion?(false)
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var body: [String: Any] = [
      "chat_id": chatId,
      "text": message,
      "parse_mode": "HTML"
    ]

    if let replyMarkup = buildKeyboard(keyboard) {
      body["reply_markup"] = replyMarkup
    }

    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    NetworkRetry.send(
      request: request,
      session: session,
      logger: Logger.telegram,
      logCategory: .telegram,
      completion: completion
    )
  }

  private func buildKeyboard(_ keyboard: TelegramKeyboard) -> [String: Any]? {
    switch keyboard {
    case .none:
      return nil
    case .theftMode:
      var buttons: [[String: String]] = [["text": "✅ Safe"]]
      if SettingsService.shared.behaviorAlarm {
        buttons.append(["text": "🔊 Alarm"])
      }
      return [
        "keyboard": [buttons],
        "resize_keyboard": true
      ]
    case .theftModeAlarmOn:
      return [
        "keyboard": [[["text": "✅ Safe"], ["text": "🔇 Stop Alarm"]]],
        "resize_keyboard": true
      ]
    case .enabled:
      return [
        "keyboard": [[["text": "📊 Status"], ["text": "🔴 Disable"]]],
        "resize_keyboard": true
      ]
    case .disabled:
      return [
        "keyboard": [[["text": "📊 Status"], ["text": "🟢 Enable"]]],
        "resize_keyboard": true
      ]
    }
  }
}
