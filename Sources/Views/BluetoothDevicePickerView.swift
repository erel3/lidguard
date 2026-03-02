import SwiftUI

struct BluetoothDevicePickerView: View {
  @Binding var trustedDevices: [TrustedBLEDevice]
  @State private var discoveredDevices: [UUID: (name: String, rssi: Int)] = [:]
  @State private var isScanning = false
  private let service = BluetoothProximityService()

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Trusted devices
      if !trustedDevices.isEmpty {
        Section {
          ForEach($trustedDevices) { $device in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                  .font(.body)
                Text("Threshold: \(device.rssiThreshold) dBm (~\(approxDistance(rssi: device.rssiThreshold)))")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Slider(
                value: Binding(
                  get: { Double(device.rssiThreshold) },
                  set: { device.rssiThreshold = Int($0) }
                ),
                in: -90...(-40),
                step: 5
              )
              .frame(width: 120)
              Button(role: .destructive) {
                trustedDevices.removeAll { $0.id == device.id }
              } label: {
                Image(systemName: "trash")
                  .foregroundStyle(.red)
              }
              .buttonStyle(.borderless)
            }
            .padding(.vertical, 2)
          }
        } header: {
          Text("Trusted Devices")
            .font(.headline)
        }
      }

      Divider()

      // Discovery
      HStack {
        Text("Nearby Devices")
          .font(.headline)
        Spacer()
        if #available(macOS 26.0, *) {
          Button(isScanning ? "Stop Scanning" : "Scan") {
            toggleScanning()
          }
          .buttonStyle(.glass)
        } else {
          Button(isScanning ? "Stop Scanning" : "Scan") {
            toggleScanning()
          }
          .buttonStyle(.borderless)
        }
      }

      if isScanning && discoveredDevices.isEmpty {
        HStack {
          ProgressView()
            .scaleEffect(0.7)
          Text("Scanning for Bluetooth devices...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      let sortedDevices = discoveredDevices.sorted { $0.value.rssi > $1.value.rssi }
      let trustedIDs = Set(trustedDevices.map(\.id))

      ForEach(sortedDevices.filter { !trustedIDs.contains($0.key) }, id: \.key) { id, info in
        HStack {
          VStack(alignment: .leading) {
            Text(info.name)
              .font(.body)
            Text("\(info.rssi) dBm · ~\(approxDistance(rssi: info.rssi))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          rssiIndicator(rssi: info.rssi)
          Button("Add") {
            let device = TrustedBLEDevice(id: id, name: info.name)
            trustedDevices.append(device)
          }
          .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
      }
    }
    .onDisappear {
      if isScanning {
        service.stopDiscovery()
        isScanning = false
      }
    }
  }

  private func toggleScanning() {
    if isScanning {
      service.stopDiscovery()
      isScanning = false
    } else {
      discoveredDevices.removeAll()
      service.onDiscoveryUpdate = { devices in
        discoveredDevices = devices
      }
      service.startDiscovery()
      isScanning = true
    }
  }

  private func approxDistance(rssi: Int) -> String {
    // Log-distance path loss model: d = 10^((txPower - rssi) / (10 * n))
    // txPower ≈ -59 dBm (typical BLE at 1m), n ≈ 2.0 (free space)
    let txPower: Double = -59
    let n: Double = 2.0
    let distance = pow(10.0, (txPower - Double(rssi)) / (10.0 * n))
    if distance < 1.0 {
      return String(format: "%.1f m", distance)
    } else if distance < 10.0 {
      return String(format: "%.0f m", distance)
    } else {
      return ">10 m"
    }
  }

  private func rssiIndicator(rssi: Int) -> some View {
    let bars: Int
    if rssi >= -50 { bars = 3 }
    else if rssi >= -70 { bars = 2 }
    else { bars = 1 }

    return HStack(spacing: 1) {
      ForEach(0..<3) { i in
        RoundedRectangle(cornerRadius: 1)
          .fill(i < bars ? Color.green : Color.gray.opacity(0.3))
          .frame(width: 3, height: CGFloat(4 + i * 3))
      }
    }
  }
}
