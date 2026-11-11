import CoreWLAN

/// A trusted Wi-Fi network counts as a trusted device for Bluetooth auto-arm:
/// while the Mac is joined to one, auto-arm does not fire. It never disarms —
/// presence only blocks arming.
///
/// Matching is by SSID, gated on a password-protected security mode. Joining a
/// WPA network proves the handshake with its passphrase succeeded, so a rogue
/// access point that merely copies the SSID cannot complete it. BSSID is not
/// matched because mesh and dual-band routers rotate it within one network.
enum TrustedWiFi {
  /// Allowlist, not denylist: a security mode added in a future SDK lands in
  /// `default` and is refused until reviewed.
  static func isSecure(_ security: CWSecurity) -> Bool {
    switch security {
    case .wpaPersonal, .wpaPersonalMixed, .wpa2Personal, .personal,
         .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .enterprise,
         .wpa3Personal, .wpa3Enterprise, .wpa3Transition:
      return true
    default:
      return false
    }
  }

  static func isTrusted(ssid: String?, security: CWSecurity, trusted: Set<String>) -> Bool {
    guard let ssid, !ssid.isEmpty else { return false }
    return isSecure(security) && trusted.contains(ssid)
  }

  /// The joined network, or nil when Wi-Fi is off, not associated, or the SSID
  /// is unreadable (macOS 14+ hides it without Location permission).
  static func currentNetwork() -> (ssid: String, security: CWSecurity)? {
    guard let interface = CWWiFiClient.shared().interface(),
          let ssid = interface.ssid(), !ssid.isEmpty else { return nil }
    return (ssid, interface.security())
  }

  static func isConnectedToTrusted(_ trusted: Set<String>) -> Bool {
    guard !trusted.isEmpty, let network = currentNetwork() else { return false }
    return isTrusted(ssid: network.ssid, security: network.security, trusted: trusted)
  }
}
