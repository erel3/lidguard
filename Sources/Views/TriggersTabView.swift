import KeyboardShortcuts
import SwiftUI

struct TriggersTabView: View {
  @Binding var triggerLidClose: Bool
  @Binding var triggerPowerDisconnect: Bool
  @Binding var triggerPowerButton: Bool
  @Binding var triggerMotionDetect: Bool
  @Binding var lockScreenOnShortcut: Bool
  var isDaemonConnected: Bool
  var helperAccessibilityGranted: Bool
  var motionSupported: Bool
  var onOpenAccessibility: () -> Void

  var body: some View {
    Form {
      Section {
        Toggle("Lid close detection", isOn: $triggerLidClose)
        Toggle("Power disconnect detection", isOn: $triggerPowerDisconnect)
        helperToggle("Power button detection", isOn: $triggerPowerButton)
          .onChange(of: triggerPowerButton) { _, newValue in
            if newValue && !helperAccessibilityGranted {
              triggerPowerButton = false
              onOpenAccessibility()
            }
          }
        if motionSupported {
          helperToggle("Motion detection", isOn: $triggerMotionDetect)
        }
      } header: {
        Text("Theft Mode Triggers")
      } footer: {
        triggersFooter
      }

      Section {
        KeyboardShortcuts.Recorder("Shortcut", name: .toggleProtection)
        helperToggle("Lock screen when arming", isOn: $lockScreenOnShortcut)
      } header: {
        Text("Global Keyboard Shortcut")
      } footer: {
        Text("Press the shortcut anywhere to toggle protection. Requires Input Monitoring permission.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section {
        Text("💡 Right-click the menu bar icon to quickly toggle protection.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  @ViewBuilder
  private var triggersFooter: some View {
    VStack(alignment: .leading, spacing: 6) {
      if isDaemonConnected && !helperAccessibilityGranted {
        HStack(spacing: 4) {
          Text("Grant Accessibility permission to enable power button detection.")
          Button("Open Settings") { onOpenAccessibility() }
            .buttonStyle(.link)
        }
      }
      if motionSupported && triggerMotionDetect {
        Text(
          "Motion detection triggers theft mode when the Mac is picked up, "
          + "tilted, or carried. Brief grace period after arming while the "
          + "baseline calibrates."
        )
      }
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
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
