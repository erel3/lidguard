import Foundation
import CoreLocation
import os.log

protocol LocationProvider {
  func requestAuthorization()
  func requestLocation(completion: @escaping (CLLocation?) -> Void)
}

final class LocationService: NSObject, LocationProvider {
  private let locationManager = CLLocationManager()
  private var completion: ((CLLocation?) -> Void)?
  private let timeout: TimeInterval
  private var cachedLocation: CLLocation?

  init(timeout: TimeInterval = 5.0) {
    self.timeout = timeout
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
  }

  func requestAuthorization() {
    let status = locationManager.authorizationStatus
    if status == .notDetermined {
      locationManager.requestWhenInUseAuthorization()
    }
    // Warm up - request location to cache it
    if status == .authorized || status == .authorizedAlways {
      locationManager.requestLocation()
    }
  }

  func requestLocation(completion: @escaping (CLLocation?) -> Void) {
    // If already have pending request, complete it first
    if self.completion != nil {
      complete(with: nil)
    }
    self.completion = completion

    let status = locationManager.authorizationStatus
    switch status {
    case .notDetermined:
      // Request auth - delegate will handle location request when granted
      locationManager.requestWhenInUseAuthorization()
      startTimeout()
    case .authorized, .authorizedAlways:
      locationManager.requestLocation()
      startTimeout()
    default:
      Logger.location.warning("Location not authorized: \(status.rawValue)")
      complete(with: nil)
    }
  }

  private func startTimeout() {
    // Use background queue for timeout - main run loop may be blocked by menu
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
      guard let self = self else { return }
      // Complete with cached location if still waiting
      // Use cachedLocation (not locationManager.location) to avoid CLLocationManager
      // internal @synchronized deadlock when accessed from background thread
      if self.completion != nil {
        self.complete(with: self.cachedLocation)
      }
    }
  }

  private func complete(with location: CLLocation?) {
    completion?(location)
    completion = nil
  }
}

// MARK: - CLLocationManagerDelegate
extension LocationService: CLLocationManagerDelegate {
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    if let location = locations.last {
      cachedLocation = location
      let lat = String(format: "%.4f", location.coordinate.latitude)
      let lon = String(format: "%.4f", location.coordinate.longitude)
      ActivityLog.logAsync(.location, "Location updated: \(lat), \(lon)")
    }
    complete(with: locations.last)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Logger.location.error("Error: \(error.localizedDescription)")
    ActivityLog.logAsync(.location, "Location error: \(error.localizedDescription)")
    complete(with: nil)
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    // Only act if we have a pending request
    guard completion != nil else { return }

    switch manager.authorizationStatus {
    case .authorized, .authorizedAlways:
      manager.requestLocation()
    case .denied, .restricted:
      Logger.location.warning("Location authorization denied")
      complete(with: nil)
    default:
      break
    }
  }
}
