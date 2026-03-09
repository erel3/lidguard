import Foundation
import os.log

final class TelegramVerificationService {
  private let session: URLSession
  private let queue = DispatchQueue(label: "com.lidguard.telegram.verification", qos: .utility)

  private var timer: DispatchSourceTimer?
  private var lastUpdateId: Int?
  private var isPolling = false

  init(session: URLSession = .shared) {
    self.session = session
  }

  deinit {
    timer?.cancel()
  }

  func start(botToken: String, code: String, onVerified: @escaping (String) -> Void) {
    queue.sync { stopInternal() }

    let newTimer = DispatchSource.makeTimerSource(queue: queue)
    newTimer.schedule(deadline: .now(), repeating: 2.0)
    newTimer.setEventHandler { [weak self] in
      self?.pollUpdates(botToken: botToken, code: code, onVerified: onVerified)
    }
    queue.sync { timer = newTimer }
    newTimer.resume()
  }

  func stop() {
    queue.sync { stopInternal() }
  }

  /// Must be called on `queue`
  private func stopInternal() {
    timer?.cancel()
    timer = nil
    lastUpdateId = nil
    isPolling = false
  }

  /// Called on `queue` by the timer
  private func pollUpdates(botToken: String, code: String, onVerified: @escaping (String) -> Void) {
    guard !isPolling else { return }
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
      guard let self = self, let data = data, error == nil else {
        self?.queue.async { self?.isPolling = false }
        return
      }
      self.queue.async {
        self.parseUpdates(data, code: code, onVerified: onVerified)
        self.isPolling = false
      }
    }
    task.resume()
  }

  /// Must be called on `queue`
  private func parseUpdates(_ data: Data, code: String, onVerified: @escaping (String) -> Void) {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let ok = json["ok"] as? Bool, ok,
          let results = json["result"] as? [[String: Any]] else { return }

    for update in results {
      if let updateId = update["update_id"] as? Int {
        lastUpdateId = updateId
      }

      guard let message = update["message"] as? [String: Any],
            let chat = message["chat"] as? [String: Any],
            let chatId = (chat["id"] as? NSNumber)?.int64Value,
            let text = message["text"] as? String else { continue }

      if text.trimmingCharacters(in: .whitespaces) == code {
        let chatIdString = String(chatId)
        Logger.telegram.info("Verification successful, chat ID: \(chatIdString)")
        stopInternal()
        DispatchQueue.main.async {
          onVerified(chatIdString)
        }
        return
      }
    }
  }
}
