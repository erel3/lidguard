import SwiftUI

struct NotificationsTabView: View {
  @Binding var telegramEnabled: Bool
  @Binding var telegramBotToken: String
  @Binding var telegramChatId: String
  @Binding var lockScreenOnTelegramEnable: Bool
  @Binding var notifyAutoArm: Bool
  @Binding var notifyProtectionToggle: Bool
  @Binding var trackLocation: Bool
  @Binding var trackPublicIP: Bool
  @Binding var trackWiFi: Bool
  @Binding var trackBattery: Bool
  @Binding var trackDeviceName: Bool
  var isDaemonConnected: Bool
  var onConnect: () -> Void

  var body: some View {
    Form {
      Section {
        Toggle("Enable Telegram notifications", isOn: $telegramEnabled)
        if telegramEnabled {
          LabeledContent("Bot Token") {
            SecureField("", text: $telegramBotToken)
              .textFieldStyle(.plain)
          }
          LabeledContent("Chat ID") {
            if telegramChatId.isEmpty {
              Button("Connect") {
                onConnect()
              }
              .disabled(telegramBotToken.isEmpty)
            } else {
              HStack {
                Text(telegramChatId)
                  .foregroundStyle(.secondary)
                Button("Disconnect") {
                  telegramChatId = ""
                }
              }
            }
          }
          helperToggle("Lock screen on /enable command", isOn: $lockScreenOnTelegramEnable)
        }
      } header: {
        Text("Telegram")
      } footer: {
        if telegramEnabled {
          Text("To create a bot: open Telegram → search @BotFather → send /newbot → copy the token. Then paste it above and click Connect to link your chat.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
          Text("Telegram notifications are disabled. The app will still protect your device locally (alarm, lock screen).")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      Section {
        Toggle("Bluetooth auto-arm / disarm", isOn: $notifyAutoArm)
        Toggle("Protection enabled / disabled", isOn: $notifyProtectionToggle)
      } header: {
        Text("Telegram Alerts")
      } footer: {
        Text("Choose which status changes are sent to Telegram. Theft alerts and tracking are always sent.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .disabled(!telegramEnabled)

      Section {
        Toggle("Location", isOn: $trackLocation)
        Toggle("Public IP", isOn: $trackPublicIP)
        Toggle("WiFi name", isOn: $trackWiFi)
        Toggle("Battery level", isOn: $trackBattery)
        Toggle("Device name", isOn: $trackDeviceName)
      } header: {
        Text("Tracking Data")
      } footer: {
        Text("Choose which information is collected and sent in tracking messages.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .disabled(!telegramEnabled)
    }
    .formStyle(.grouped)
  }

  private func helperToggle(_ title: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
      HStack(spacing: 6) {
        Text(title)
        if !isDaemonConnected {
          Text("(requires Helper)")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
    }
    .disabled(!isDaemonConnected)
  }
}
