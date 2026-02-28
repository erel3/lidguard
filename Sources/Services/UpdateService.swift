import Cocoa
import os.log
import SwiftUI

final class UpdateService {
  static let shared = UpdateService()

  private let settings = SettingsService.shared
  private let logger = Logger.update
  private let checkQueue = DispatchQueue(label: "com.lidguard.update", qos: .utility)
  private var periodicTimer: DispatchSourceTimer?
  private var updateWindow: NSWindow?
  private var initialCheckDone = false

  private init() {}

  // MARK: - Periodic Checks

  func startPeriodicChecks() {
    guard settings.autoUpdateEnabled else { return }

    if !initialCheckDone {
      initialCheckDone = true
      checkQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
        self?.checkForUpdates(silent: true)
      }
    }

    schedulePeriodicTimer()
  }

  func stopPeriodicChecks() {
    periodicTimer?.cancel()
    periodicTimer = nil
  }

  private func schedulePeriodicTimer() {
    periodicTimer?.cancel()

    let interval = Config.GitHub.autoCheckInterval
    let delay: TimeInterval

    if let last = settings.lastUpdateCheckDate {
      delay = max(0, interval - Date().timeIntervalSince(last))
    } else {
      delay = interval
    }

    let timer = DispatchSource.makeTimerSource(queue: checkQueue)
    timer.schedule(deadline: .now() + delay, repeating: interval)
    timer.setEventHandler { [weak self] in
      guard let self = self, self.settings.autoUpdateEnabled else { return }
      self.checkForUpdates(silent: true)
    }
    timer.resume()
    periodicTimer = timer
  }

  // MARK: - Check for Updates

  func checkForUpdates(silent: Bool, completion: (() -> Void)? = nil) {
    guard let url = URL(string: Config.GitHub.releasesURL) else {
      completion?()
      return
    }

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("LidGuard/\(Config.App.version)", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 15

    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      guard let self = self else { completion?(); return }

      self.settings.lastUpdateCheckDate = Date()

      if let error = error {
        self.logger.error("Update check failed: \(error.localizedDescription)")
        if !silent {
          DispatchQueue.main.async { self.showError("Could not reach GitHub: \(error.localizedDescription)") }
        }
        completion?()
        return
      }

      guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode),
            let data = data else {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        self.logger.error("Update check HTTP error: \(status)")
        if !silent {
          DispatchQueue.main.async { self.showError("GitHub returned status \(status).") }
        }
        completion?()
        return
      }

      let release: GitHubRelease
      do {
        release = try JSONDecoder().decode(GitHubRelease.self, from: data)
      } catch {
        self.logger.error("Failed to parse GitHub release: \(error)")
        if !silent {
          DispatchQueue.main.async { self.showError("Could not parse GitHub response.") }
        }
        completion?()
        return
      }

      let remoteVersion = release.version
      let localVersion = Config.App.version

      guard self.isNewer(remoteVersion, than: localVersion) else {
        self.logger.info("App is up to date (\(localVersion))")
        if !silent {
          DispatchQueue.main.async { self.showUpToDate() }
        }
        completion?()
        return
      }

      // Skip version check: silent auto-checks respect it, manual checks don't
      if silent && self.settings.skippedVersion == remoteVersion {
        self.logger.info("Skipping update to \(remoteVersion) (user skipped)")
        completion?()
        return
      }

      DispatchQueue.main.async {
        self.showUpdateWindow(release: release)
      }
      completion?()
    }.resume()
  }

  // MARK: - Version Comparison

  private func isNewer(_ remote: String, than local: String) -> Bool {
    func parts(_ v: String) -> [Int] {
      let clean = v.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        .split(separator: "-").first.map(String.init) ?? v
      return clean.split(separator: ".").compactMap { Int($0) }
    }
    let r = parts(remote), l = parts(local)
    let count = max(r.count, l.count)
    for i in 0..<count {
      let rv = i < r.count ? r[i] : 0
      let lv = i < l.count ? l[i] : 0
      if rv != lv { return rv > lv }
    }
    return false
  }

  // MARK: - Update Window

  private func showUpdateWindow(release: GitHubRelease) {
    if let existing = updateWindow, existing.isVisible {
      existing.makeKeyAndOrderFront(nil)
      return
    }

    let view = UpdateView(
      version: release.version,
      changelog: release.body ?? "No release notes.",
      onInstall: { [weak self] in
        self?.installUpdate(release: release)
      },
      onSkip: { [weak self] in
        self?.settings.skippedVersion = release.version
        self?.updateWindow?.close()
      },
      onDismiss: { [weak self] in
        self?.updateWindow?.close()
      }
    )

    let window = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
      styleMask: [.titled, .closable, .hudWindow],
      backing: .buffered,
      defer: false
    )
    window.title = "Software Update"
    window.contentView = NSHostingView(rootView: view)
    window.center()
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    updateWindow = window
  }

  // MARK: - Install

  private func installUpdate(release: GitHubRelease) {
    guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
          let downloadURL = URL(string: asset.browserDownloadURL) else {
      showError("No download found in this release.")
      return
    }

    // Update the view to show progress
    if let window = updateWindow {
      let progressView = UpdateView(
        version: release.version,
        changelog: release.body ?? "",
        isInstalling: true,
        onInstall: {},
        onSkip: {},
        onDismiss: {}
      )
      window.contentView = NSHostingView(rootView: progressView)
    }

    checkQueue.async { [weak self] in
      guard let self = self else { return }

      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lidguard-update-\(UUID().uuidString)")

      do {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let zipPath = tempDir.appendingPathComponent("LidGuard.zip")

        // Download
        let semaphore = DispatchSemaphore(value: 0)
        var downloadError: Error?

        URLSession.shared.downloadTask(with: downloadURL) { localURL, _, error in
          defer { semaphore.signal() }
          if let error = error { downloadError = error; return }
          guard let localURL = localURL else {
            downloadError = URLError(.badServerResponse)
            return
          }
          do {
            try FileManager.default.moveItem(at: localURL, to: zipPath)
          } catch {
            downloadError = error
          }
        }.resume()

        let result = semaphore.wait(timeout: .now() + 300)
        if result == .timedOut {
          throw NSError(domain: "UpdateService", code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "Download timed out"])
        }
        if let error = downloadError { throw error }

        // Unzip
        let unzipDir = tempDir.appendingPathComponent("unzipped")
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", zipPath.path, "-d", unzipDir.path]
        try unzip.run()
        unzip.waitUntilExit()

        guard unzip.terminationStatus == 0 else {
          throw NSError(domain: "UpdateService", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to unzip update"])
        }

        // Find LidGuard.app
        let contents = try FileManager.default.contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil)
        guard let newAppURL = contents.first(where: { $0.lastPathComponent == "LidGuard.app" }) else {
          throw NSError(domain: "UpdateService", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "LidGuard.app not found in zip"])
        }

        // Verify code signature
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--verify", "--deep", "--strict", newAppURL.path]
        try codesign.run()
        codesign.waitUntilExit()
        guard codesign.terminationStatus == 0 else {
          throw NSError(domain: "UpdateService", code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Code signature verification failed"])
        }

        // Replace current bundle atomically
        let currentAppURL = Bundle.main.bundleURL
        let staging = tempDir.appendingPathComponent("LidGuard-staged.app")
        try FileManager.default.moveItem(at: newAppURL, to: staging)

        try FileManager.default.replaceItem(
          at: currentAppURL,
          withItemAt: staging,
          backupItemName: "LidGuard-backup.app",
          options: .usingNewMetadataOnly,
          resultingItemURL: nil
        )

        // Clear skipped version on successful install
        self.settings.skippedVersion = nil
        try? FileManager.default.removeItem(at: tempDir)
        ActivityLog.logAsync(.system, "Update to v\(release.version) installed")

        // Restart
        DispatchQueue.main.async {
          self.restartApp(at: currentAppURL)
        }
      } catch {
        self.logger.error("Update failed: \(error.localizedDescription)")
        try? FileManager.default.removeItem(at: tempDir)
        DispatchQueue.main.async {
          self.updateWindow?.close()
          self.showError("Update failed: \(error.localizedDescription)")
        }
      }
    }
  }

  private func restartApp(at appURL: URL) {
    let pid = ProcessInfo.processInfo.processIdentifier
    let escapedPath = appURL.path.replacingOccurrences(of: "'", with: "'\\''")
    let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open '\(escapedPath)'"

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", script]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      logger.error("Failed to launch restart: \(error.localizedDescription)")
      showError("Update installed. Please relaunch LidGuard manually.")
      return
    }

    ActivityLog.logAsync(.system, "Restarting for update")

    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.allowQuitForUpdate()
    } else {
      exit(0)
    }
    NSApp.terminate(nil)
  }

  // MARK: - Alerts

  private func showUpToDate() {
    let alert = NSAlert()
    alert.messageText = "You're Up to Date"
    alert.informativeText = "LidGuard \(Config.App.version) is the latest version."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private func showError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "Update Error"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}

// MARK: - GitHub API Model

private struct GitHubRelease: Decodable {
  let tagName: String
  let body: String?
  let assets: [Asset]

  var version: String {
    tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
  }

  struct Asset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
      case name
      case browserDownloadURL = "browser_download_url"
    }
  }

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case body
    case assets
  }
}
