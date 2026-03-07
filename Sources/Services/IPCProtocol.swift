import Foundation

// MARK: - Outgoing Commands (App -> Daemon)

struct IPCCommand: Codable {
  let type: String
  var secret: String?
  var contactName: String?
  var contactPhone: String?
  var message: String?
}

// MARK: - Incoming Messages (Daemon -> App)

struct IPCMessage: Codable {
  let type: String
  var success: Bool?
  var pmset: Bool?
  var lockScreen: Bool?
  var powerButton: Bool?
  var message: String?
}
