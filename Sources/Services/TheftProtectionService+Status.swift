import Foundation

extension TheftProtectionService {
  func sendStatus() {
    deviceInfoCollector.collect { [weak self] info in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.sendStatusWithInfo(info)
      }
    }
  }

  fileprivate func sendStatusWithInfo(_ info: DeviceInfo) {
    let status: String
    let keyboard: TelegramKeyboard

    switch state {
    case .disabled:
      status = "🔴 PROTECTION DISABLED"
      keyboard = .disabled
    case .enabled:
      status = "✅ Monitoring"
      keyboard = .enabled
    case .enabledBluetooth:
      status = "📶 Auto-Armed (Bluetooth)"
      keyboard = .enabled
    case .theftMode:
      status = "🚨 THEFT MODE ACTIVE"
      keyboard = AlarmAudioManager.shared.isPlaying ? .theftModeAlarmOn : .theftMode
    }

    let lidState = lidMonitor.isClosed ? "closed" : "open"
    let chargerState = powerMonitor.isCharging() ? "connected" : "disconnected"
    let triggers = activeTriggerNames()
    let behaviors = activeBehaviorNames()

    var hardwareInfo = ""
    hardwareInfo += "🖥 <b>Lid:</b> \(lidState)\n"
    hardwareInfo += "🔌 <b>Charger:</b> \(chargerState)\n"
    hardwareInfo += "⚡️ <b>Triggers:</b> \(triggers.isEmpty ? "none" : triggers.joined(separator: ", "))\n"
    hardwareInfo += "🛡 <b>Behaviors:</b> \(behaviors.isEmpty ? "none" : behaviors.joined(separator: ", "))\n"

    let settings = SettingsService.shared
    if settings.bluetoothAutoArmEnabled && settings.hasTrustedBLEDevices {
      bluetoothProximityService.getDeviceStatus { [weak self] devices in
        MainActor.assumeIsolated {
          guard let self else { return }
          var bt = "📶 <b>Bluetooth:</b> auto-arm on\n"
          for d in devices {
            if let rssi = d.rssi {
              bt += "  • \(d.name): nearby (\(rssi) dBm)\n"
            } else {
              bt += "  • \(d.name): not seen\n"
            }
          }
          let trustedNetworks = Set(settings.trustedWiFiNetworks)
          if !trustedNetworks.isEmpty {
            let onTrusted = TrustedWiFi.isConnectedToTrusted(trustedNetworks)
            bt += "  • Trusted Wi-Fi: \(onTrusted ? "connected (auto-arm held)" : "not connected")\n"
          }
          self.notificationService.send(
            message: "<b>STATUS: \(status)</b>\n\n\(hardwareInfo)\(bt)\n\(info.formattedMessage)",
            keyboard: keyboard,
            completion: nil
          )
        }
      }
    } else {
      notificationService.send(
        message: "<b>STATUS: \(status)</b>\n\n\(hardwareInfo)📶 <b>Bluetooth:</b> auto-arm off\n\n\(info.formattedMessage)",
        keyboard: keyboard,
        completion: nil
      )
    }
  }

  func sendTestAlert() {
    let keyboard: TelegramKeyboard = (state == .disabled) ? .disabled : .enabled
    deviceInfoCollector.collect { [weak self] info in
      MainActor.assumeIsolated {
        self?.notificationService.send(
          message: "🧪 <b>TEST ALERT</b>\n\n\(info.formattedMessage)",
          keyboard: keyboard,
          completion: nil
        )
      }
    }
    ActivityLog.logAsync(.system, "Test alert sent")
  }

  func sendShutdownAlert(blocked: Bool) {
    let title = blocked ? "SHUTDOWN BLOCKED" : "POWER BUTTON PRESSED"
    let subtitle = blocked ? "Someone tried to shut down!" : "Device may be force-powered off!"

    deviceInfoCollector.collect { [weak self] info in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.notificationService.send(
          message: "🚨 <b>\(title)</b>\n\n⚠️ \(subtitle)\n\n\(info.formattedMessage)",
          keyboard: self.state == .theftMode
            ? (AlarmAudioManager.shared.isPlaying ? .theftModeAlarmOn : .theftMode)
            : .enabled,
          completion: nil
        )
      }
    }
  }
}
