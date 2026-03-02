import Foundation
import AppKit

final class PmsetService {
  static let shared = PmsetService()
  private let sudoersPath = "/etc/sudoers.d/lidguard"
  private let queue = DispatchQueue(label: "com.lidguard.pmset")

  private init() {}

  func isInstalled() -> Bool {
    FileManager.default.fileExists(atPath: sudoersPath)
  }

  func install() -> Bool {
    let user = NSUserName()
    let script = """
      do shell script "echo '\(user) ALL = NOPASSWD: /usr/bin/pmset -a disablesleep 1
      \(user) ALL = NOPASSWD: /usr/bin/pmset -a disablesleep 0' > /etc/sudoers.d/lidguard && chmod 440 /etc/sudoers.d/lidguard" with administrator privileges
      """
    return runAppleScript(script)
  }

  func uninstall() -> Bool {
    disable()  // Clean up before removing sudoers access
    let script = "do shell script \"rm /etc/sudoers.d/lidguard\" with administrator privileges"
    return runAppleScript(script)
  }

  func enable() {
    queue.async { [self] in
      guard isInstalled() else { return }
      let success = runProcess("/usr/bin/sudo", arguments: ["pmset", "-a", "disablesleep", "1"])
      print("[PmsetService] Enable disablesleep: \(success ? "OK" : "FAILED")")
    }
  }

  func disable() {
    queue.async { [self] in
      guard isInstalled() else { return }
      let success = runProcess("/usr/bin/sudo", arguments: ["pmset", "-a", "disablesleep", "0"])
      print("[PmsetService] Disable disablesleep: \(success ? "OK" : "FAILED")")
    }
  }

  private func runAppleScript(_ source: String) -> Bool {
    if let script = NSAppleScript(source: source) {
      var error: NSDictionary?
      script.executeAndReturnError(&error)
      if let error = error {
        print("[PmsetService] AppleScript error: \(error)")
        return false
      }
      return true
    }
    return false
  }

  private func runProcess(_ path: String, arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus == 0
    } catch {
      print("[PmsetService] Process error: \(error)")
      return false
    }
  }
}
