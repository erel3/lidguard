import os.log
import ServiceManagement

@MainActor
final class LoginItemService {
  static let shared = LoginItemService()

  private init() {}

  var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  func enable() -> Bool {
    do {
      try SMAppService.mainApp.register()
      return true
    } catch {
      Logger.system.error("Failed to enable login item: \(error.localizedDescription)")
      return false
    }
  }

  func disable() -> Bool {
    do {
      try SMAppService.mainApp.unregister()
      return true
    } catch {
      Logger.system.error("Failed to disable login item: \(error.localizedDescription)")
      return false
    }
  }

  func toggle() -> Bool {
    if isEnabled {
      return disable()
    } else {
      return enable()
    }
  }
}
