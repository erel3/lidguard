import Foundation
import CoreLocation

struct DeviceInfo {
  let timestamp: Date
  let location: CLLocation?
  let publicIP: String?
  let wifiName: String?
  let batteryLevel: Int?
  let isCharging: Bool?
  let deviceName: String

  var formattedMessage: String {
    var lines: [String] = []

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    lines.append("🕐 <b>Time:</b> \(formatter.string(from: timestamp))")

    if let loc = location {
      lines.append("📍 <b>Location:</b> \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
      lines.append("🗺 <b>Maps:</b> https://maps.google.com/?q=\(loc.coordinate.latitude),\(loc.coordinate.longitude)")
      if loc.horizontalAccuracy > 0 {
        lines.append("🎯 <b>Accuracy:</b> \(Int(loc.horizontalAccuracy))m")
      }
    } else {
      lines.append("📍 <b>Location:</b> unavailable")
    }

    if let ip = publicIP {
      lines.append("🌐 <b>Public IP:</b> \(ip)")
    }

    if let wifi = wifiName {
      lines.append("📶 <b>WiFi:</b> \(wifi)")
    }

    if let level = batteryLevel {
      let status = isCharging == true ? "charging" : "discharging"
      lines.append("🔋 <b>Battery:</b> \(level)% (\(status))")
    }

    if !deviceName.isEmpty {
      lines.append("💻 <b>Device:</b> \(deviceName)")
    }

    return lines.joined(separator: "\n")
  }
}
