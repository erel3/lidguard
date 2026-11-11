import CoreWLAN
import XCTest
@testable import LidGuard

final class TrustedWiFiTests: XCTestCase {
  private let trusted: Set<String> = ["Home"]

  func testSecuredTrustedNetworkIsTrusted() {
    XCTAssertTrue(TrustedWiFi.isTrusted(ssid: "Home", security: .wpa2Personal, trusted: trusted))
    XCTAssertTrue(TrustedWiFi.isTrusted(ssid: "Home", security: .wpa3Personal, trusted: trusted))
    XCTAssertTrue(TrustedWiFi.isTrusted(ssid: "Home", security: .wpa2Enterprise, trusted: trusted))
  }

  func testInsecureNetworkWithTrustedSSIDIsRejected() {
    for security: CWSecurity in [.none, .WEP, .dynamicWEP, .OWE, .oweTransition, .unknown] {
      XCTAssertFalse(TrustedWiFi.isTrusted(ssid: "Home", security: security, trusted: trusted),
                     "security \(security.rawValue) must not count as trusted")
    }
  }

  func testUnknownOrMissingSSIDIsRejected() {
    XCTAssertFalse(TrustedWiFi.isTrusted(ssid: nil, security: .wpa2Personal, trusted: trusted))
    XCTAssertFalse(TrustedWiFi.isTrusted(ssid: "", security: .wpa2Personal, trusted: trusted))
    XCTAssertFalse(TrustedWiFi.isTrusted(ssid: "Cafe", security: .wpa2Personal, trusted: trusted))
  }

  func testAllTrustedGone() {
    let now = Date()
    let delay: TimeInterval = 120
    let recent = now.addingTimeInterval(-30)
    let stale = now.addingTimeInterval(-200)

    XCTAssertTrue(BluetoothProximityService.allTrustedGone(lastSeen: [nil, nil], now: now, armDelay: delay))
    XCTAssertTrue(BluetoothProximityService.allTrustedGone(lastSeen: [stale, nil], now: now, armDelay: delay))
    // One recent presence (e.g. trusted Wi-Fi) holds the arm.
    XCTAssertFalse(BluetoothProximityService.allTrustedGone(lastSeen: [stale, recent], now: now, armDelay: delay))
    // Exactly at the delay counts as gone.
    XCTAssertTrue(BluetoothProximityService.allTrustedGone(
      lastSeen: [now.addingTimeInterval(-delay)], now: now, armDelay: delay))
  }
}
