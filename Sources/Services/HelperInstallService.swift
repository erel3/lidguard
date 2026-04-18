import Cocoa
import os.log
import SwiftUI

@MainActor
final class HelperInstallService {
  static let shared = HelperInstallService()

  enum HelperUpdateMode {
    case required   // version < minHelperVersion
    case optional   // version >= minHelperVersion but < latest GitHub release
  }

  private let installQueue = DispatchQueue(label: "com.lidguard.helper.install", qos: .utility)
  private let checkQueue = DispatchQueue(label: "com.lidguard.helper.update.check", qos: .utility)
  private let settings = SettingsService.shared
  private var isInstalling = false
  private var updateWindow: NSWindow?
  private var periodicTimer: DispatchSourceTimer?
  private var initialCheckDone = false
  var disconnectedForRequiredUpdate = false

  /// Tracks the mode of the currently displayed update window for handleInstall progress view
  private var currentUpdateMode: HelperUpdateMode = .required
  private var currentLatestVersion: String?

  private var installDir: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(Config.Daemon.helperInstallDir)
  }

  private var binaryPath: URL {
    installDir.appendingPathComponent(Config.Daemon.helperBinaryName)
  }

  private var plistDst: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/\(Config.Daemon.launchAgentLabel).plist")
  }

  private init() {}

  // MARK: - Version Comparison

  nonisolated private func isNewer(_ remote: String, than local: String) -> Bool {
    func parts(_ v: String) -> [Int] {
      let clean = v.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
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

  // MARK: - Periodic Helper Checks

  func startPeriodicHelperChecks() {
    guard settings.autoUpdateEnabled else { return }

    if !initialCheckDone {
      initialCheckDone = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
        self?.checkForHelperUpdates(silent: true)
      }
    }

    schedulePeriodicTimer()
  }

  func stopPeriodicHelperChecks() {
    periodicTimer?.cancel()
    periodicTimer = nil
  }

  private func schedulePeriodicTimer() {
    periodicTimer?.cancel()

    let interval = Config.GitHub.autoCheckInterval
    let delay: TimeInterval

    if let last = settings.lastHelperUpdateCheckDate {
      delay = max(0, interval - Date().timeIntervalSince(last))
    } else {
      delay = interval
    }

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + delay, repeating: interval)
    timer.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        guard let self = self, self.settings.autoUpdateEnabled else { return }
        self.checkForHelperUpdates(silent: true)
      }
    }
    timer.resume()
    periodicTimer = timer
  }

  // MARK: - Check for Helper Updates

  func checkForHelperUpdates(silent: Bool, completion: (@Sendable () -> Void)? = nil) {
    guard let url = URL(string: Config.Daemon.helperReleasesURL) else {
      completion?()
      return
    }

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("LidGuard/\(Config.App.version)", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 15

    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      let hadError = error != nil
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self = self else { completion?(); return }
          self.handleHelperCheckResponse(
            data: data,
            statusCode: statusCode,
            hadError: hadError,
            silent: silent
          )
          completion?()
        }
      }
    }.resume()
  }

  private func handleHelperCheckResponse(data: Data?, statusCode: Int, hadError: Bool, silent: Bool) {
    settings.lastHelperUpdateCheckDate = Date()

    guard !hadError, (200...299).contains(statusCode), let data = data,
          let release = try? JSONDecoder().decode(GitHubReleaseInfo.self, from: data) else {
      if !silent {
        Logger.daemon.error("Failed to check for helper updates")
        showHelperCheckError()
      }
      return
    }

    let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))

    guard TheftProtectionService.daemonConnected,
          let currentVersion = TheftProtectionService.daemonVersion else {
      if !silent { showHelperUpToDate() }
      return
    }

    let isRequired = TheftProtectionService.helperNeedsUpdate
    let hasNewerRelease = isNewer(latestVersion, than: currentVersion)

    guard isRequired || hasNewerRelease else {
      if !silent { showHelperUpToDate() }
      return
    }

    let mode: HelperUpdateMode = isRequired ? .required : .optional

    if mode == .optional && silent && settings.skippedHelperVersion == latestVersion {
      Logger.daemon.info("Skipping helper update to \(latestVersion) (user skipped)")
      return
    }

    if silent && UpdateService.shared.hasUpdateAvailable {
      Logger.daemon.info("Suppressing helper update notification — app update available")
      return
    }

    showUpdateWindow(currentVersion: currentVersion, latestVersion: latestVersion, mode: mode)
  }

  private func showHelperUpToDate() {
    let alert = NSAlert()
    alert.messageText = "Helper Is Up to Date"
    alert.informativeText = "Helper daemon v\(TheftProtectionService.daemonVersion ?? "?") is the latest version."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private func showHelperCheckError() {
    let alert = NSAlert()
    alert.messageText = "Helper Update Check Failed"
    alert.informativeText = "Could not check for helper updates. Please try again later."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  // MARK: - Update Window

  func showUpdateWindow(currentVersion: String?, latestVersion: String? = nil, mode: HelperUpdateMode = .required) {
    DispatchQueue.main.async { [self] in
      if let existing = updateWindow, existing.isVisible {
        existing.makeKeyAndOrderFront(nil)
        return
      }

      currentUpdateMode = mode
      currentLatestVersion = latestVersion

      let view = HelperUpdateView(
        currentVersion: currentVersion ?? "unknown",
        requiredVersion: Config.Daemon.minHelperVersion,
        latestVersion: latestVersion,
        mode: mode,
        isInstalling: false,
        onInstall: { [weak self] in self?.handleInstall() },
        onSkip: mode == .optional ? { [weak self] in
          if let v = latestVersion { self?.settings.skippedHelperVersion = v }
          self?.updateWindow?.close()
        } : nil,
        onDismiss: { [weak self] in
          if mode == .required {
            self?.handleRequiredUpdateDismissed()
          }
          self?.updateWindow?.close()
        }
      )

      let window = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: mode == .optional ? 260 : 240),
        styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
        backing: .buffered,
        defer: false
      )
      window.title = "Helper Update"
      window.contentView = NSHostingView(rootView: view)
      window.center()
      window.isReleasedWhenClosed = false
      window.level = .normal
      window.hidesOnDeactivate = false
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)

      updateWindow = window
    }
  }

  private func handleRequiredUpdateDismissed() {
    disconnectedForRequiredUpdate = true
    NotificationCenter.default.post(name: .helperUpdateDismissed, object: nil)
  }

  private func handleInstall() {
    // Show progress state
    let progressView = HelperUpdateView(
      currentVersion: TheftProtectionService.daemonVersion ?? "unknown",
      requiredVersion: Config.Daemon.minHelperVersion,
      latestVersion: currentLatestVersion,
      mode: currentUpdateMode,
      isInstalling: true,
      onInstall: {},
      onSkip: nil,
      onDismiss: {}
    )
    updateWindow?.contentView = NSHostingView(rootView: progressView)

    autoInstall { [weak self] success in
      DispatchQueue.main.async {
        self?.updateWindow?.close()
        if !success {
          let alert = NSAlert()
          alert.messageText = "Helper Update Failed"
          alert.informativeText = "Could not update the helper daemon. Check the activity log for details."
          alert.alertStyle = .warning
          alert.addButton(withTitle: "OK")
          alert.runModal()
        }
      }
    }
  }

  // MARK: - Auto-Install

  func autoInstall(completion: (@Sendable (Bool) -> Void)? = nil) {
    guard !isInstalling else { completion?(false); return }
    isInstalling = true
    installQueue.async { [weak self] in
      let success = Self.performAutoInstall()
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self?.isInstalling = false
          if success {
            self?.disconnectedForRequiredUpdate = false
            self?.settings.skippedHelperVersion = nil
            NotificationCenter.default.post(name: .helperInstallCompleted, object: nil)
          }
          completion?(success)
        }
      }
    }
  }

  nonisolated private static func performAutoInstall() -> Bool {
    Logger.daemon.info("Auto-installing helper daemon...")
    ActivityLog.logAsync(.system, "Auto-installing helper daemon...")

    guard let url = URL(string: Config.Daemon.helperReleasesURL) else { return false }

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("LidGuard/\(Config.App.version)", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 30

    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var fetchedData: Data?
    nonisolated(unsafe) var fetchError: Bool = false

    URLSession.shared.dataTask(with: request) { data, response, error in
      if error != nil {
        fetchError = true
      } else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        fetchError = true
      } else {
        fetchedData = data
      }
      semaphore.signal()
    }.resume()
    semaphore.wait()

    guard let data = fetchedData, !fetchError else {
      Logger.daemon.error("Failed to fetch helper release info")
      ActivityLog.logAsync(.system, "Helper auto-install failed: could not fetch release info")
      return false
    }

    guard let release = try? JSONDecoder().decode(GitHubReleaseInfo.self, from: data),
          let asset = release.assets.first(where: { $0.name.hasSuffix(".pkg") }),
          let downloadURL = URL(string: asset.browserDownloadURL) else {
      Logger.daemon.error("No suitable asset found in helper release")
      ActivityLog.logAsync(.system, "Helper auto-install failed: no suitable asset")
      return false
    }

    do {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lidguard-helper-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: tempDir) }

      let pkgPath = tempDir.appendingPathComponent(asset.name)
      try downloadFile(from: downloadURL, to: pkgPath)

      // Unload existing daemon and wait for cleanup
      unloadDaemon()
      Thread.sleep(forTimeInterval: 1)

      let escapedPath = pkgPath.path.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
      let script = "do shell script \"/usr/sbin/installer -pkg \\\"\(escapedPath)\\\" -target /\" with administrator privileges"
      let installer = Process()
      installer.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      installer.arguments = ["-e", script]
      installer.standardOutput = FileHandle.nullDevice
      installer.standardError = FileHandle.nullDevice
      try installer.run()
      installer.waitUntilExit()

      guard installer.terminationStatus == 0 else {
        throw NSError(domain: "HelperInstall", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "PKG installer exited with status \(installer.terminationStatus)"])
      }

      Logger.daemon.info("Helper daemon installed successfully")
      ActivityLog.logAsync(.system, "Helper daemon installed successfully")
      return true
    } catch {
      Logger.daemon.error("Helper install failed: \(error.localizedDescription)")
      ActivityLog.logAsync(.system, "Helper auto-install failed: \(error.localizedDescription)")
      return false
    }
  }

  nonisolated private static func downloadFile(from url: URL, to destination: URL) throws {
    let semaphore = DispatchSemaphore(value: 0)
    var downloadError: Error?

    URLSession.shared.downloadTask(with: url) { localURL, _, error in
      defer { semaphore.signal() }
      if let error { downloadError = error; return }
      guard let localURL else { downloadError = URLError(.badServerResponse); return }
      do {
        try FileManager.default.moveItem(at: localURL, to: destination)
      } catch {
        downloadError = error
      }
    }.resume()

    let result = semaphore.wait(timeout: .now() + 120)
    if result == .timedOut {
      throw NSError(domain: "HelperInstall", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Download timed out"])
    }
    if let error = downloadError { throw error }
  }

  private func installLaunchAgent() {
    let plist: [String: Any] = [
      "Label": Config.Daemon.launchAgentLabel,
      "ProgramArguments": [binaryPath.path],
      "Sockets": [
        "Listeners": [
          "SockServiceName": String(Config.Daemon.port),
          "SockFamily": "IPv4",
          "SockNodeName": "localhost"
        ]
      ]
    ]

    let plistData = try? PropertyListSerialization.data(
      fromPropertyList: plist, format: .xml, options: 0
    )

    let launchAgentsDir = plistDst.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

    try? plistData?.write(to: plistDst)
  }

  nonisolated private static func unloadDaemon() {
    let plistDst = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/\(Config.Daemon.launchAgentLabel).plist")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["bootout", "gui/\(getuid())", plistDst.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
  }
}

// MARK: - GitHub Release Model

private struct GitHubReleaseInfo: Decodable, Sendable {
  let tagName: String
  let assets: [GitHubAsset]

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case assets
  }
}

private struct GitHubAsset: Decodable, Sendable {
  let name: String
  let browserDownloadURL: String

  enum CodingKeys: String, CodingKey {
    case name
    case browserDownloadURL = "browser_download_url"
  }
}

// MARK: - Helper Update View

private struct HelperUpdateView: View {
  let currentVersion: String
  let requiredVersion: String
  var latestVersion: String?
  var mode: HelperInstallService.HelperUpdateMode = .required
  var isInstalling: Bool = false
  let onInstall: () -> Void
  var onSkip: (() -> Void)?
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      VStack(spacing: 8) {
        Image(systemName: mode == .required ? "arrow.triangle.2.circlepath" : "arrow.up.circle")
          .font(.system(size: 40))
          .foregroundStyle(mode == .required ? .orange : .blue)

        Text(mode == .required ? "Helper Update Required" : "Helper Update Available")
          .font(.headline)

        if mode == .required {
          Text("Installed: v\(currentVersion) — Required: v\(requiredVersion)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else if let latest = latestVersion {
          Text("Installed: v\(currentVersion) — Latest: v\(latest)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      Text(mode == .required
        ? "LidGuard requires a newer version of the helper daemon for full functionality. Some features may not work until the helper is updated."
        : "A newer version of the helper daemon is available.")
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .padding(.horizontal)

      Spacer()

      if isInstalling {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Updating helper...")
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
      } else {
        HStack(spacing: 12) {
          Button("Not Now") { onDismiss() }
            .keyboardShortcut(.cancelAction)

          if mode == .optional, let onSkip {
            Button("Skip This Version") { onSkip() }
          }

          if #available(macOS 26.0, *) {
            Button("Update Helper") { onInstall() }
              .keyboardShortcut(.defaultAction)
              .buttonStyle(.glassProminent)
          } else {
            Button("Update Helper") { onInstall() }
              .keyboardShortcut(.defaultAction)
          }
        }
        .padding(.bottom, 4)
      }
    }
    .padding(20)
    .frame(width: 400, height: mode == .optional ? 260 : 240)
  }
}
