import Foundation

enum HelperVersionCheck {
  /// Returns true if `version` is older than `Config.Daemon.minHelperVersion`
  /// or nil. Uses lexicographic comparison of dotted integer parts.
  static func isOutdated(_ version: String?) -> Bool {
    guard let version else { return true }
    func parts(_ str: String) -> [Int] {
      str.split(separator: ".").compactMap { Int($0) }
    }
    let remote = parts(version)
    let required = parts(Config.Daemon.minHelperVersion)
    for idx in 0..<max(remote.count, required.count) {
      let remotePart = idx < remote.count ? remote[idx] : 0
      let reqPart = idx < required.count ? required[idx] : 0
      if remotePart != reqPart { return remotePart < reqPart }
    }
    return false
  }
}
