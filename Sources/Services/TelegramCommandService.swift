import Foundation
import os.log

@MainActor
protocol TelegramCommandDelegate: AnyObject {
  func telegramCommandReceived(_ command: TelegramCommand)
}

enum TelegramCommand: String {
  case stop = "/stop"
  case safe = "/safe"
  case status = "/status"
  case enable = "/enable"
  case disable = "/disable"
  case alarm = "/alarm"
  case stopalarm = "/stopalarm"
}

@MainActor
final class TelegramCommandService {
  weak var delegate: TelegramCommandDelegate?

  private let session: URLSession

  private var timer: DispatchSourceTimer?
  private var lastUpdateId: Int?
  private let pollInterval: TimeInterval
  private var isPolling = false

  init(session: URLSession = .shared,
       pollInterval: TimeInterval = 3.0) {
    self.session = session
    self.pollInterval = pollInterval
  }

  func start() {
    guard Config.Telegram.isConfigured && Config.Telegram.isEnabled else {
      Logger.telegram.debug("Telegram not configured, command polling disabled")
      return
    }

    schedulePolling(initialDeadline: .now())
    Logger.telegram.info("Command polling started")
    ActivityLog.logAsync(.telegram, "Command polling started")
  }

  func stop() {
    timer?.cancel()
    timer = nil
    Logger.telegram.info("Command polling stopped")
  }

  func pause() {
    timer?.cancel()
    timer = nil
    Logger.telegram.info("Command polling paused for sleep")
  }

  func resume() {
    guard Config.Telegram.isConfigured && Config.Telegram.isEnabled else { return }
    guard timer == nil else { return }
    schedulePolling(initialDeadline: .now() + pollInterval)
    Logger.telegram.info("Command polling resumed after wake")
  }

  private func schedulePolling(initialDeadline: DispatchTime) {
    let newTimer = DispatchSource.makeTimerSource(queue: .main)
    newTimer.schedule(deadline: initialDeadline, repeating: pollInterval)
    newTimer.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        self?.pollUpdates()
      }
    }
    newTimer.resume()
    timer = newTimer
  }

  private func pollUpdates() {
    guard !isPolling else { return }
    guard let botToken = Config.Telegram.botToken,
          let chatId = Config.Telegram.chatId else { return }

    isPolling = true

    var urlString = "https://api.telegram.org/bot\(botToken)/getUpdates?timeout=1"
    if let lastId = lastUpdateId {
      urlString += "&offset=\(lastId + 1)"
    }

    guard let url = URL(string: urlString) else {
      isPolling = false
      return
    }

    let task = session.dataTask(with: url) { [weak self] data, _, error in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self else { return }
          defer { self.isPolling = false }
          guard let data, error == nil else { return }
          self.parseUpdates(data, chatId: chatId)
        }
      }
    }
    task.resume()
  }

  private func parseUpdates(_ data: Data, chatId: String) {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let ok = json["ok"] as? Bool, ok,
          let results = json["result"] as? [[String: Any]] else { return }

    for update in results {
      if let updateId = update["update_id"] as? Int {
        lastUpdateId = updateId
      }

      // Handle text messages
      guard let message = update["message"] as? [String: Any],
            let chat = message["chat"] as? [String: Any],
            let messageChatId = chat["id"] as? Int,
            String(messageChatId) == chatId,
            let text = message["text"] as? String else { continue }

      if let command = parseCommand(text) {
        Logger.telegram.info("Received command: \(text)")
        ActivityLog.logAsync(.telegram, "Received command: \(text)")
        delegate?.telegramCommandReceived(command)
      }
    }
  }

  private func parseCommand(_ text: String) -> TelegramCommand? {
    let trimmed = text.lowercased().trimmingCharacters(in: .whitespaces)

    // Exact slash commands
    if let command = TelegramCommand(rawValue: trimmed) {
      return command
    }

    // Exact button text matching
    switch trimmed {
    case "✅ safe": return .safe
    case "📊 status": return .status
    case "🟢 enable": return .enable
    case "🔴 disable": return .disable
    case "🔊 alarm": return .alarm
    case "🔇 stop alarm": return .stopalarm
    default: return nil
    }
  }
}
