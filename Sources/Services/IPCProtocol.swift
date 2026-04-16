import Foundation

// MARK: - Outgoing Commands (App -> Daemon)

struct IPCCommand: Codable {
  let type: String
  var contactName: String?
  var contactPhone: String?
  var message: String?
}

// MARK: - Incoming Messages (Daemon -> App)

struct IPCMessage: Codable {
  let type: String
  var success: Bool?
  var version: String?
  var pmset: Bool?
  var lockScreen: Bool?
  var powerButton: Bool?
  var accessibilityGranted: Bool?
  var motion: Bool?
  var motionSupported: Bool?
  var motionDetail: String?
  var motionSession: UInt64?
  var message: String?
}
