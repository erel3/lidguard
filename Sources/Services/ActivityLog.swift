import Foundation
import os.log

enum LogCategory: String, CaseIterable, Codable {
  case system
  case armed
  case disarmed
  case trigger
  case theft
  case telegram
  case power
  case location
  case bluetooth

  var icon: String {
    switch self {
    case .system: return "⚙️"
    case .armed: return "🟢"
    case .disarmed: return "🔴"
    case .trigger: return "⚠️"
    case .theft: return "🚨"
    case .telegram: return "📱"
    case .power: return "🔋"
    case .location: return "📍"
    case .bluetooth: return "📶"
    }
  }

  var displayName: String {
    switch self {
    case .system: return "System"
    case .armed: return "Armed"
    case .disarmed: return "Disarmed"
    case .trigger: return "Trigger"
    case .theft: return "Theft"
    case .telegram: return "Telegram"
    case .power: return "Power"
    case .location: return "Location"
    case .bluetooth: return "Bluetooth"
    }
  }
}

struct LogEntry: Identifiable, Codable {
  let id: UUID
  let timestamp: Date
  let category: LogCategory
  let message: String

  init(category: LogCategory, message: String) {
    self.id = UUID()
    self.timestamp = Date()
    self.category = category
    self.message = message
  }
}

@MainActor
final class ActivityLog: ObservableObject {
  static let shared = ActivityLog()

  @Published private(set) var entries: [LogEntry] = []
  private let maxEntries = 500
  private let saveQueue = DispatchQueue(label: "com.akim.lidguard.activitylog")
  private var logFileURL: URL?

  private init() {
    setupLogFile()
    loadFromDisk()
  }

  private func setupLogFile() {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    guard let supportDir = appSupport?.appendingPathComponent("LidGuard") else { return }

    try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    logFileURL = supportDir.appendingPathComponent("activity-log.json")
  }

  private func loadFromDisk() {
    guard let url = logFileURL,
          let data = try? Data(contentsOf: url),
          let saved = try? JSONDecoder().decode([LogEntry].self, from: data) else {
      return
    }
    entries = saved
  }

  private func saveToDisk() {
    guard let url = logFileURL else { return }
    let entriesToSave = entries
    saveQueue.async {
      guard let data = try? JSONEncoder().encode(entriesToSave) else { return }
      try? data.write(to: url, options: .atomic)
    }
  }

  func log(_ category: LogCategory, _ message: String) {
    let entry = LogEntry(category: category, message: message)
    entries.insert(entry, at: 0)

    // Trim if needed
    if entries.count > maxEntries {
      entries = Array(entries.prefix(maxEntries))
    }

    saveToDisk()

    // Also log to os.log
    let logger = Logger(subsystem: Config.App.bundleIdentifier, category: category.rawValue)
    logger.info("\(message)")
  }

  func clear() {
    entries = []
    saveToDisk()
  }

  func exportAsText() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

    return entries.reversed().map { entry in
      "[\(formatter.string(from: entry.timestamp))] \(entry.category.icon) \(entry.category.displayName): \(entry.message)"
    }.joined(separator: "\n")
  }
}

// Non-MainActor convenience for logging from any thread
extension ActivityLog {
  nonisolated static func logAsync(_ category: LogCategory, _ message: String) {
    Task { @MainActor in
      shared.log(category, message)
    }
  }
}
