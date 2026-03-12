import SwiftUI

struct ProtectionTabView: View {
  @Binding var behaviorSleepPrevention: Bool
  @Binding var behaviorLidCloseSleep: Bool
  @Binding var behaviorShutdownBlocking: Bool
  @Binding var lockScreenOnTheftMode: Bool
  @Binding var behaviorLockScreen: Bool
  @Binding var contactName: String
  @Binding var contactPhone: String
  @Binding var behaviorAutoAlarm: Bool
  @Binding var selectedAlarmSound: String
  @Binding var alarmVolume: Double
  @Binding var offlineSirenEnabled: Bool
  var isDaemonConnected: Bool
  var alarmSounds: [String]
  var onLockScreenEnabled: (() -> Void)?
  var onRetrieveContacts: (() -> Void)?

  var body: some View {
    Form {
      Section {
        Toggle("Idle sleep prevention", isOn: $behaviorSleepPrevention)
        helperToggle("Lid-close sleep prevention", isOn: $behaviorLidCloseSleep)
      } header: {
        Text("Sleep")
      } footer: {
        Text("Idle prevents system sleep via IOPMAssertion. Lid-close uses pmset disablesleep via Helper to keep the Mac running with lid closed.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section {
        Toggle("Shutdown blocking", isOn: $behaviorShutdownBlocking)
        helperToggle("Lock screen on theft mode", isOn: $lockScreenOnTheftMode)
        if lockScreenOnTheftMode {
          helperToggle("Lock screen message", isOn: $behaviorLockScreen)
            .onChange(of: behaviorLockScreen) { _, newValue in
              if newValue && isDaemonConnected {
                onLockScreenEnabled?()
              }
            }
          if behaviorLockScreen {
            LabeledContent("Name") {
              TextField("", text: $contactName)
                .textFieldStyle(.plain)
            }
            LabeledContent("Phone") {
              TextField("", text: $contactPhone)
                .textFieldStyle(.plain)
            }
            if onRetrieveContacts != nil {
              LabeledContent {
                Button("Retrieve from Contacts") {
                  onRetrieveContacts?()
                }
                .buttonStyle(.borderless)
              } label: {
                EmptyView()
              }
            }
          }
        }
      } header: {
        Text("Defense")
      }

      Section {
        Toggle("Auto-play on theft mode", isOn: $behaviorAutoAlarm)
        Picker("Sound", selection: $selectedAlarmSound) {
          ForEach(alarmSounds, id: \.self) { sound in
            Text(sound).tag(sound)
          }
        }
        .onChange(of: selectedAlarmSound) { _, newValue in
          if newValue == "Siren" {
            AlarmAudioManager.shared.previewSiren()
          } else {
            NSSound(named: newValue)?.play()
          }
        }
        LabeledContent("Volume") {
          HStack {
            Slider(value: $alarmVolume, in: 10...100, step: 10)
            Text("\(Int(alarmVolume))%")
              .monospacedDigit()
              .frame(width: 40, alignment: .trailing)
          }
        }
        Toggle("Siren when offline", isOn: $offlineSirenEnabled)
      } header: {
        Text("Alarm")
      } footer: {
        Text("Alarm can be triggered via Telegram or keyboard shortcut. Offline siren plays automatically when Telegram is unavailable.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
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
