import Cocoa
import os.log
import SwiftUI

@MainActor
final class UpdateService {
  static let shared = UpdateService()

  private let settings = SettingsService.shared
  private let logger = Logger.update
  private let checkQueue = DispatchQueue(label: "com.lidguard.update", qos: .utility)
  private var periodicTimer: DispatchSourceTimer?
  private var updateWindow: NSWindow?
  private var initialCheckDone = false
  private(set) var hasUpdateAvailable = false

  private init() {}

  // MARK: - Periodic Checks

  func startPeriodicChecks() {
    guard settings.autoUpdateEnabled else { return }

    if !initialCheckDone {
      initialCheckDone = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
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

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + delay, repeating: interval)
    timer.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        guard let self = self, self.settings.autoUpdateEnabled else { return }
        self.checkForUpdates(silent: true)
      }
    }
    timer.resume()
    periodicTimer = timer
  }

  // MARK: - Check for Updates

  private func logAndShowError(_ message: String, silent: Bool) {
    logger.error("\(message)")
    if !silent {
      showError(message)
    }
  }

  func checkForUpdates(silent: Bool, completion: (@Sendable () -> Void)? = nil) {
    guard let url = URL(string: Config.GitHub.releasesURL) else {
      completion?()
      return
    }

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("LidGuard/\(Config.App.version)", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 15

    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      let errorMessage = error?.localizedDescription
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self = self else { completion?(); return }
          self.handleCheckResponse(
            data: data,
            statusCode: statusCode,
            errorMessage: errorMessage,
            silent: silent
          )
          completion?()
        }
      }
    }.resume()
  }

  private func handleCheckResponse(data: Data?, statusCode: Int, errorMessage: String?, silent: Bool) {
    settings.lastUpdateCheckDate = Date()

    if let errorMessage {
      logAndShowError("Could not reach GitHub: \(errorMessage)", silent: silent)
      return
    }

    guard (200...299).contains(statusCode), let data = data else {
      logAndShowError("Update check HTTP error: \(statusCode)", silent: silent)
      return
    }

    let releases: [GitHubRelease]
    do {
      releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
    } catch {
      logAndShowError("Could not parse GitHub response: \(error)", silent: silent)
      return
    }

    let localVersion = Config.App.version
    let newerReleases = releases.filter { isNewer($0.version, than: localVersion) }
      .sorted { isNewer($0.version, than: $1.version) }  // newest first

    guard let latest = newerReleases.first else {
      logger.info("App is up to date (\(localVersion))")
      if !silent { showUpToDate() }
      return
    }

    if silent && settings.skippedVersion == latest.version {
      logger.info("Skipping update to \(latest.version) (user skipped)")
      return
    }

    let combinedChangelog = newerReleases.map { release in
      let header = "## v\(release.version)"
      let body = release.body ?? "No release notes."
      return "\(header)\n\(body)"
    }.joined(separator: "\n\n")

    hasUpdateAvailable = true
    showUpdateWindow(release: latest, changelog: combinedChangelog)
  }

  private func showUpdateWindow(release: GitHubRelease, changelog: String) {
    if let existing = updateWindow, existing.isVisible {
      existing.makeKeyAndOrderFront(nil)
      return
    }

    let view = UpdateView(
      version: release.version,
      changelog: changelog,
      onInstall: { [weak self] in
        self?.installUpdate(release: release)
      },
      onSkip: { [weak self] in
        self?.hasUpdateAvailable = false
        self?.settings.skippedVersion = release.version
        self?.updateWindow?.close()
      },
      onDismiss: { [weak self] in
        self?.hasUpdateAvailable = false
        self?.updateWindow?.close()
      }
    )

    let window = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
      styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
      backing: .buffered,
      defer: false
    )
    window.title = "Software Update"
    window.contentView = NSHostingView(rootView: view)
    window.center()
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.hidesOnDeactivate = false
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

    let version = release.version
    let downloadDest = downloadURL
    checkQueue.async { [weak self] in
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lidguard-update-\(UUID().uuidString)")

      do {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let zipPath = tempDir.appendingPathComponent("LidGuard.zip")

        try Self.downloadFile(from: downloadDest, to: zipPath)
        let newAppURL = try Self.unzipAndVerify(zipPath: zipPath, in: tempDir)

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

        try? FileManager.default.removeItem(at: tempDir)
        ActivityLog.logAsync(.system, "Update to v\(version) installed")

        DispatchQueue.main.async {
          MainActor.assumeIsolated {
            guard let self = self else { return }
            self.hasUpdateAvailable = false
            self.settings.skippedVersion = nil
            self.restartApp(at: currentAppURL)
          }
        }
      } catch {
        try? FileManager.default.removeItem(at: tempDir)
        DispatchQueue.main.async {
          MainActor.assumeIsolated {
            guard let self = self else { return }
            self.logger.error("Update failed: \(error.localizedDescription)")
            self.updateWindow?.close()
            self.showError("Update failed: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  nonisolated private static func downloadFile(from url: URL, to destination: URL) throws {
    let semaphore = DispatchSemaphore(value: 0)
    var downloadError: Error?

    URLSession.shared.downloadTask(with: url) { localURL, _, error in
      defer { semaphore.signal() }
      if let error = error { downloadError = error; return }
      guard let localURL = localURL else {
        downloadError = URLError(.badServerResponse)
        return
      }
      do {
        try FileManager.default.moveItem(at: localURL, to: destination)
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
  }

  nonisolated private static func unzipAndVerify(zipPath: URL, in tempDir: URL) throws -> URL {
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

    let contents = try FileManager.default.contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil)
    guard let newAppURL = contents.first(where: { $0.lastPathComponent == "LidGuard.app" }) else {
      throw NSError(domain: "UpdateService", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "LidGuard.app not found in zip"])
    }

    let codesign = Process()
    codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    codesign.arguments = ["--verify", "--deep", "--strict", newAppURL.path]
    try codesign.run()
    codesign.waitUntilExit()
    guard codesign.terminationStatus == 0 else {
      throw NSError(domain: "UpdateService", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Code signature verification failed"])
    }

    return newAppURL
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

  // MARK: - Version Comparison

  nonisolated private func isNewer(_ remote: String, than local: String) -> Bool {
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

// MARK: - API Models

private struct GitHubReleaseAsset: Decodable, Sendable {
  let name: String
  let browserDownloadURL: String

  enum CodingKeys: String, CodingKey {
    case name
    case browserDownloadURL = "browser_download_url"
  }
}

private struct GitHubRelease: Decodable, Sendable {
  let tagName: String
  let body: String?
  let assets: [GitHubReleaseAsset]

  var version: String {
    tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
  }

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case body
    case assets
  }
}
