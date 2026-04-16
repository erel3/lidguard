import Foundation
import os.log

// MARK: - DaemonIPCDelegate

extension TheftProtectionService: DaemonIPCDelegate {
  func daemonDidConnect(_ client: DaemonIPCClient, version: String?) {
    TheftProtectionService.daemonConnected = true
    TheftProtectionService.daemonVersion = version
    TheftProtectionService.helperNeedsUpdate = HelperVersionCheck.isOutdated(version)
    TheftProtectionService.helperDisconnectedForUpdate = false
    HelperInstallService.shared.disconnectedForRequiredUpdate = false
    NotificationCenter.default.post(name: .daemonConnectionChanged, object: nil)
    NotificationCenter.default.post(name: .helperVersionChanged, object: nil)
    Logger.daemon.info("Connected to helper daemon (v\(version ?? "unknown"))")
    ActivityLog.logAsync(.system, "Helper daemon connected (v\(version ?? "unknown"))")
    if TheftProtectionService.helperNeedsUpdate {
      Logger.daemon.warning("Helper daemon outdated (v\(version ?? "?"), requires v\(Config.Daemon.minHelperVersion))")
      ActivityLog.logAsync(.system, "Helper daemon needs update (v\(version ?? "?") < v\(Config.Daemon.minHelperVersion))")
      HelperInstallService.shared.showUpdateWindow(currentVersion: version, mode: .required)
    }
    client.getStatus()
    resyncDaemonState(client: client)
  }

  func daemonDidDisconnect(_ client: DaemonIPCClient) {
    TheftProtectionService.daemonConnected = false
    TheftProtectionService.daemonVersion = nil
    TheftProtectionService.helperAccessibilityGranted = false
    NotificationCenter.default.post(name: .daemonConnectionChanged, object: nil)
    Logger.daemon.info("Disconnected from helper daemon")
    ActivityLog.logAsync(.system, "Helper daemon disconnected")
  }

  func daemonDidReceiveStatus(_ client: DaemonIPCClient, accessibilityGranted: Bool) {
    TheftProtectionService.helperAccessibilityGranted = accessibilityGranted
    TheftProtectionService.daemonMotionSupported = client.motionSupported
    NotificationCenter.default.post(name: .helperStatusChanged, object: nil)
  }

  func daemonDidReceivePowerButtonPress(_ client: DaemonIPCClient) {
    guard state != .disabled else { return }
    guard SettingsService.shared.triggerPowerButton else { return }
    ActivityLog.logAsync(.trigger, "Power button pressed detected")
    sendShutdownAlert(blocked: false)
  }

  func daemonDidDetectMotion(_ client: DaemonIPCClient, detail: String, session: UInt64) {
    #if APPSTORE
    return
    #else
    guard state == .enabled || state == .enabledBluetooth else { return }
    guard SettingsService.shared.triggerMotionDetect else { return }
    if let armed = lastArmTime,
       Date().timeIntervalSince(armed) < TheftProtectionService.motionArmGrace { return }
    ActivityLog.logAsync(.trigger, "Motion detected (\(detail))")
    activateTheftMode(trigger: .motionDetected(detail))
    #endif
  }

  func daemonDidUpdateMotionSupport(_ client: DaemonIPCClient, supported: Bool) {
    NotificationCenter.default.post(name: .helperStatusChanged, object: nil)
  }

  private func resyncDaemonState(client: DaemonIPCClient) {
    guard state == .enabled || state == .enabledBluetooth || state == .theftMode else { return }
    let settings = SettingsService.shared
    if settings.behaviorLidCloseSleep { client.enablePmset() }
    if settings.triggerPowerButton { client.enablePowerButton() }
    #if !APPSTORE
    if settings.triggerMotionDetect && client.motionSupported
      && (state == .enabled || state == .enabledBluetooth) {
      client.enableMotionMonitoring()
    }
    #endif
    if state == .theftMode && settings.lockScreenOnTheftMode && settings.behaviorLockScreen {
      let name = settings.contactName ?? ""
      let phone = settings.contactPhone ?? ""
      client.showLockScreen(contactName: name, contactPhone: phone, message: "STOLEN DEVICE")
    }
  }
}
