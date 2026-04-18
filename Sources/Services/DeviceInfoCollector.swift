import Foundation
import CoreLocation

protocol DeviceInfoCollecting {
  func warmUp()
  func collect(completion: @escaping (DeviceInfo) -> Void)
}

final class DeviceInfoCollector: DeviceInfoCollecting {
  private let locationService: LocationProvider
  private let systemInfoService: SystemInfoProvider

  init(locationService: LocationProvider = LocationService(),
       systemInfoService: SystemInfoProvider = SystemInfoService()) {
    self.locationService = locationService
    self.systemInfoService = systemInfoService
  }

  func warmUp() {
    locationService.requestAuthorization()
  }

  func collect(completion: @escaping (DeviceInfo) -> Void) {
    let settings = SettingsService.shared

    let locationBlock: (@escaping (CLLocation?) -> Void) -> Void = { callback in
      if settings.trackLocation {
        self.locationService.requestLocation { location in callback(location) }
      } else {
        callback(nil)
      }
    }

    locationBlock { [weak self] location in
      guard let self = self else { return }

      let ipBlock: (@escaping (String?) -> Void) -> Void = { callback in
        if settings.trackPublicIP {
          self.systemInfoService.getPublicIP { ip in callback(ip) }
        } else {
          callback(nil)
        }
      }

      ipBlock { publicIP in
        let info = DeviceInfo(
          timestamp: Date(),
          location: location,
          publicIP: publicIP,
          wifiName: settings.trackWiFi ? self.systemInfoService.getWiFiName() : nil,
          batteryLevel: settings.trackBattery ? self.systemInfoService.getBatteryLevel() : nil,
          isCharging: settings.trackBattery ? self.systemInfoService.isCharging() : nil,
          deviceName: settings.trackDeviceName ? self.systemInfoService.getDeviceName() : ""
        )

        completion(info)
      }
    }
  }
}
