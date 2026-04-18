import Foundation
import CoreWLAN
import IOKit.ps
import os.log

@MainActor
protocol SystemInfoProvider {
  func getPublicIP(completion: @escaping @Sendable (String?) -> Void)
  func getWiFiName() -> String?
  func getBatteryLevel() -> Int?
  func isCharging() -> Bool?
  func getDeviceName() -> String
}

@MainActor
final class SystemInfoService: SystemInfoProvider {
  private let session: URLSession
  private let ipServiceURL = "https://api.ipify.org"
  private let timeout: TimeInterval

  init(session: URLSession = .shared, timeout: TimeInterval = 3.0) {
    self.session = session
    self.timeout = timeout
  }

  func getPublicIP(completion: @escaping @Sendable (String?) -> Void) {
    guard let url = URL(string: ipServiceURL) else {
      completion(nil)
      return
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = timeout

    session.dataTask(with: request) { data, _, error in
      let result: String?
      if let error {
        Logger.system.error("Failed to get public IP: \(error.localizedDescription)")
        result = nil
      } else if let data, let ip = String(data: data, encoding: .utf8) {
        result = ip.trimmingCharacters(in: .whitespacesAndNewlines)
      } else {
        result = nil
      }
      DispatchQueue.main.async {
        completion(result)
      }
    }.resume()
  }

  func getWiFiName() -> String? {
    CWWiFiClient.shared().interface()?.ssid()
  }

  func getBatteryLevel() -> Int? {
    getBatteryInfo()?.level
  }

  func isCharging() -> Bool? {
    getBatteryInfo()?.isCharging
  }

  func getDeviceName() -> String {
    Host.current().localizedName ?? "Unknown"
  }

  private func getBatteryInfo() -> (level: Int, isCharging: Bool)? {
    let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array

    for source in sources {
      guard let desc = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any],
            let capacity = desc[kIOPSCurrentCapacityKey] as? Int,
            let isCharging = desc[kIOPSIsChargingKey] as? Bool else { continue }
      return (capacity, isCharging)
    }
    return nil
  }
}
