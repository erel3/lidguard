import CoreWLAN
import KeyboardShortcuts
import SwiftUI

struct BluetoothTabView: View {
  @Binding var bluetoothAutoArmEnabled: Bool
  @Binding var bluetoothArmGracePeriod: Double
  @Binding var lockScreenOnBluetoothArm: Bool
  @Binding var trustedBLEDevices: [TrustedBLEDevice]
  @Binding var trustedWiFiNetworks: [String]
  var isDaemonConnected: Bool

  var body: some View {
    Form {
      Section {
        Toggle("Enable Bluetooth auto-arm", isOn: $bluetoothAutoArmEnabled)
        if bluetoothAutoArmEnabled {
          HelperToggle("Lock screen when auto-arming", isOn: $lockScreenOnBluetoothArm, isDaemonConnected: isDaemonConnected)
        }
      } header: {
        Text("Auto-Arm")
      } footer: {
        Text(
          "Automatically arms protection when all trusted Bluetooth devices leave range and the Mac is off trusted Wi-Fi. "
            + "Disarms when a Bluetooth device returns."
        )
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section {
        KeyboardShortcuts.Recorder("Shortcut", name: .toggleBluetooth)
      } header: {
        Text("Global Keyboard Shortcut")
      } footer: {
        Text("Press the shortcut anywhere to toggle Bluetooth auto-arm. Requires Input Monitoring permission.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if bluetoothAutoArmEnabled {
        Section {
          LabeledContent("Arm delay") {
            HStack {
              Slider(value: $bluetoothArmGracePeriod, in: 60...300, step: 10)
              Text("\(Int(bluetoothArmGracePeriod))s")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            }
          }
        } header: {
          Text("Arm Delay")
        }

        Section {
          BluetoothDevicePickerView(trustedDevices: $trustedBLEDevices)
        } header: {
          Text("Bluetooth Devices")
        }

        Section {
          ForEach(trustedWiFiNetworks, id: \.self) { ssid in
            HStack {
              Label(ssid, systemImage: "wifi")
              Spacer()
              Button(role: .destructive) {
                trustedWiFiNetworks.removeAll { $0 == ssid }
              } label: {
                Image(systemName: "minus.circle")
              }
              .buttonStyle(.borderless)
            }
          }
          addCurrentNetworkRow
        } header: {
          Text("Wi-Fi Networks")
        } footer: {
          Text("While the Mac is connected to a trusted network, auto-arm won't fire. Wi-Fi never disarms. Only password-protected networks can be added.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
  }

  /// Nothing notifies SwiftUI when the Mac changes networks, so the row
  /// re-reads the current network on a short timer instead of once per render.
  private var addCurrentNetworkRow: some View {
    TimelineView(.periodic(from: .now, by: 2)) { _ in
      let blocker = addNetworkBlocker(TrustedWiFi.currentNetwork())
      HStack {
        Button("Add Current Network") {
          // Re-read at click time: the network may have changed since the last tick.
          let network = TrustedWiFi.currentNetwork()
          if addNetworkBlocker(network) == nil, let network {
            trustedWiFiNetworks.append(network.ssid)
          }
        }
        .disabled(blocker != nil)
        if let blocker {
          Text(blocker)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func addNetworkBlocker(_ network: (ssid: String, security: CWSecurity)?) -> String? {
    guard let network else { return "Not connected, or Location permission missing" }
    if !TrustedWiFi.isSecure(network.security) { return "Current network has no password" }
    if trustedWiFiNetworks.contains(network.ssid) { return "\(network.ssid) already added" }
    return nil
  }
}
