import KeyboardShortcuts
import SwiftUI

struct TriggersTabView: View {
  @Binding var triggerLidClose: Bool
  @Binding var suppressLidTriggerWhenExternalDisplay: Bool
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
        Toggle("Ignore lid close when external display is attached",
               isOn: $suppressLidTriggerWhenExternalDisplay)
          .disabled(!triggerLidClose)
        Toggle("Power disconnect detection", isOn: $triggerPowerDisconnect)
        HelperToggle("Power button detection", isOn: $triggerPowerButton, isDaemonConnected: isDaemonConnected)
          .onChange(of: triggerPowerButton) { _, newValue in
            if newValue && !helperAccessibilityGranted {
              triggerPowerButton = false
              onOpenAccessibility()
            }
          }
        if motionSupported {
          HelperToggle("Motion detection", isOn: $triggerMotionDetect, isDaemonConnected: isDaemonConnected)
        }
      } header: {
        Text("Theft Mode Triggers")
      } footer: {
        triggersFooter
      }

      Section {
        KeyboardShortcuts.Recorder("Shortcut", name: .toggleProtection)
        HelperToggle("Lock screen when arming", isOn: $lockScreenOnShortcut, isDaemonConnected: isDaemonConnected)
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

  // macOS 27 renamed the Privacy & Security pane; the TCC permission is unchanged.
  private var accessibilityPaneName: String {
    if #available(macOS 27, *) { return "Device Control and Data Access" }
    return "Accessibility"
  }

  @ViewBuilder
  private var triggersFooter: some View {
    VStack(alignment: .leading, spacing: 6) {
      if isDaemonConnected && !helperAccessibilityGranted {
        HStack(spacing: 4) {
          Text("Grant \(accessibilityPaneName) permission to enable power button detection.")
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
}
