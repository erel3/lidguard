import Foundation
import CoreLocation

@MainActor
protocol DeviceInfoCollecting {
  func warmUp()
  func collect(completion: @escaping @Sendable (DeviceInfo) -> Void)
}

@MainActor
final class DeviceInfoCollector: DeviceInfoCollecting {
  private let locationService: LocationProvider
  private let systemInfoService: SystemInfoProvider

  init(locationService: LocationProvider? = nil,
       systemInfoService: SystemInfoProvider? = nil) {
    self.locationService = locationService ?? LocationService()
    self.systemInfoService = systemInfoService ?? SystemInfoService()
  }

  func warmUp() {
    locationService.requestAuthorization()
  }

  func collect(completion: @escaping @Sendable (DeviceInfo) -> Void) {
    let settings = SettingsService.shared
    let trackLocation = settings.trackLocation
    let trackPublicIP = settings.trackPublicIP

    fetchLocation(enabled: trackLocation) { [weak self] location in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.fetchIP(enabled: trackPublicIP) { [weak self] publicIP in
          MainActor.assumeIsolated {
            guard let self else { return }
            let s = SettingsService.shared
            let info = DeviceInfo(
              timestamp: Date(),
              location: location,
              publicIP: publicIP,
              wifiName: s.trackWiFi ? self.systemInfoService.getWiFiName() : nil,
              batteryLevel: s.trackBattery ? self.systemInfoService.getBatteryLevel() : nil,
              isCharging: s.trackBattery ? self.systemInfoService.isCharging() : nil,
              deviceName: s.trackDeviceName ? self.systemInfoService.getDeviceName() : ""
            )
            completion(info)
          }
        }
      }
    }
  }

  private func fetchLocation(enabled: Bool, callback: @escaping @Sendable (CLLocation?) -> Void) {
    if enabled {
      locationService.requestLocation(completion: callback)
    } else {
      callback(nil)
    }
  }

  private func fetchIP(enabled: Bool, callback: @escaping @Sendable (String?) -> Void) {
    if enabled {
      systemInfoService.getPublicIP(completion: callback)
    } else {
      callback(nil)
    }
  }
}
