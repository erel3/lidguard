import Cocoa
import os.log
import SwiftUI

final class HelperInstallService {
  static let shared = HelperInstallService()

  private let installQueue = DispatchQueue(label: "com.lidguard.helper.install", qos: .utility)
  private var isInstalling = false
  private var updateWindow: NSWindow?

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

  // MARK: - Update Window

  func showUpdateWindow(currentVersion: String?) {
    DispatchQueue.main.async { [self] in
      if let existing = updateWindow, existing.isVisible {
        existing.makeKeyAndOrderFront(nil)
        return
      }

      let view = HelperUpdateView(
        currentVersion: currentVersion ?? "unknown",
        requiredVersion: Config.Daemon.minHelperVersion,
        isInstalling: false,
        onInstall: { [weak self] in self?.handleInstall() },
        onDismiss: { [weak self] in self?.updateWindow?.close() }
      )

      let window = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
        styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
        backing: .buffered,
        defer: false
      )
      window.title = "Helper Update"
      window.contentView = NSHostingView(rootView: view)
      window.center()
      window.isReleasedWhenClosed = false
      window.level = .floating
      window.hidesOnDeactivate = false
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)

      updateWindow = window
    }
  }

  private func handleInstall() {
    #if APPSTORE
    if let url = URL(string: Config.Daemon.helperBrowserURL) {
      NSWorkspace.shared.open(url)
    }
    updateWindow?.close()
    #else
    // Show progress state
    let progressView = HelperUpdateView(
      currentVersion: TheftProtectionService.daemonVersion ?? "unknown",
      requiredVersion: Config.Daemon.minHelperVersion,
      isInstalling: true,
      onInstall: {},
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
    #endif
  }

  // MARK: - Direct Edition (Auto-Install)

  #if !APPSTORE

  func autoInstall(completion: ((Bool) -> Void)? = nil) {
    installQueue.async { [self] in
      guard !isInstalling else { completion?(false); return }
      isInstalling = true
      defer { isInstalling = false }

      Logger.daemon.info("Auto-installing helper daemon...")
      ActivityLog.logAsync(.system, "Auto-installing helper daemon...")

      guard let url = URL(string: Config.Daemon.helperReleasesURL) else { return }

      var request = URLRequest(url: url)
      request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
      request.setValue("LidGuard/\(Config.App.version)", forHTTPHeaderField: "User-Agent")
      request.timeoutInterval = 30

      let semaphore = DispatchSemaphore(value: 0)
      var fetchedData: Data?
      var fetchError: Bool = false

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
        return
      }

      guard let release = try? JSONDecoder().decode(GitHubReleaseInfo.self, from: data),
            let asset = release.assets.first(where: { $0.name.hasSuffix(".pkg") }),
            let downloadURL = URL(string: asset.browserDownloadURL) else {
        Logger.daemon.error("No suitable asset found in helper release")
        ActivityLog.logAsync(.system, "Helper auto-install failed: no suitable asset")
        return
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

        // Install PKG to user domain
        let installer = Process()
        installer.executableURL = URL(fileURLWithPath: "/usr/sbin/installer")
        installer.arguments = ["-pkg", pkgPath.path, "-target", "CurrentUserHomeDirectory"]
        installer.standardOutput = FileHandle.nullDevice
        installer.standardError = FileHandle.nullDevice
        try installer.run()
        installer.waitUntilExit()

        guard installer.terminationStatus == 0 else {
          throw NSError(domain: "HelperInstall", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "PKG installer exited with status \(installer.terminationStatus)"])
        }

        // Install LaunchAgent plist
        installLaunchAgent()

        // Install sudoers for passwordless pmset
        if SettingsService.shared.behaviorLidCloseSleep {
          installSudoers()
        }

        // Load daemon
        loadDaemon()

        Logger.daemon.info("Helper daemon installed successfully")
        ActivityLog.logAsync(.system, "Helper daemon installed successfully")
        NotificationCenter.default.post(name: .helperInstallCompleted, object: nil)
        completion?(true)
      } catch {
        Logger.daemon.error("Helper install failed: \(error.localizedDescription)")
        ActivityLog.logAsync(.system, "Helper auto-install failed: \(error.localizedDescription)")
        completion?(false)
      }
    }
  }

  private func downloadFile(from url: URL, to destination: URL) throws {
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

  func removeSudoers() {
    installQueue.async {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
      process.arguments = ["rm", "-f", "/etc/sudoers.d/lidguard"]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try? process.run()
      process.waitUntilExit()
      if process.terminationStatus == 0 {
        Logger.daemon.info("Sudoers file removed")
        ActivityLog.logAsync(.system, "Sudoers file removed")
      }
    }
  }

  private func installSudoers() {
    let username = NSUserName()
    let rules = """
    \(username) ALL = NOPASSWD: /usr/bin/pmset -a disablesleep 1
    \(username) ALL = NOPASSWD: /usr/bin/pmset -a disablesleep 0
    """

    let tempFile = FileManager.default.temporaryDirectory
      .appendingPathComponent("lidguard-sudoers-\(UUID().uuidString)")
    do {
      try rules.write(to: tempFile, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o440], ofItemAtPath: tempFile.path)
    } catch {
      Logger.daemon.error("Failed to write sudoers temp file: \(error.localizedDescription)")
      return
    }
    defer { try? FileManager.default.removeItem(at: tempFile) }

    // visudo --check validates the file, then sudo cp installs it
    let check = Process()
    check.executableURL = URL(fileURLWithPath: "/usr/sbin/visudo")
    check.arguments = ["--check", "--file", tempFile.path]
    check.standardOutput = FileHandle.nullDevice
    check.standardError = FileHandle.nullDevice
    try? check.run()
    check.waitUntilExit()

    guard check.terminationStatus == 0 else {
      Logger.daemon.error("Sudoers validation failed")
      return
    }

    let install = Process()
    install.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    install.arguments = ["cp", tempFile.path, "/etc/sudoers.d/lidguard"]
    install.standardOutput = FileHandle.nullDevice
    install.standardError = FileHandle.nullDevice
    try? install.run()
    install.waitUntilExit()

    if install.terminationStatus == 0 {
      Logger.daemon.info("Sudoers file installed")
      ActivityLog.logAsync(.system, "Sudoers file installed for pmset")
    } else {
      Logger.daemon.error("Failed to install sudoers file")
      ActivityLog.logAsync(.system, "Failed to install sudoers file (sudo required)")
    }
  }

  private func unloadDaemon() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["bootout", "gui/\(getuid())", plistDst.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
  }

  private func loadDaemon() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["bootstrap", "gui/\(getuid())", plistDst.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
  }

  #endif

  // MARK: - App Store Edition (Manual Install)

  #if APPSTORE

  private var instructionsWindow: NSWindow?

  func showInstallInstructions() {
    if let existing = instructionsWindow, existing.isVisible {
      existing.makeKeyAndOrderFront(nil)
      return
    }

    let view = HelperInstallView(
      onDownload: {
        if let url = URL(string: Config.Daemon.helperBrowserURL) {
          NSWorkspace.shared.open(url)
        }
      },
      onDismiss: { [weak self] in
        self?.instructionsWindow?.close()
      }
    )

    let window = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
      styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
      backing: .buffered,
      defer: false
    )
    window.title = "Install LidGuard Helper"
    window.contentView = NSHostingView(rootView: view)
    window.center()
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.hidesOnDeactivate = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    instructionsWindow = window
  }

  #endif
}

// MARK: - GitHub Release Model

#if !APPSTORE
private struct GitHubReleaseInfo: Decodable {
  let tagName: String
  let assets: [GitHubAsset]

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case assets
  }
}

private struct GitHubAsset: Decodable {
  let name: String
  let browserDownloadURL: String

  enum CodingKeys: String, CodingKey {
    case name
    case browserDownloadURL = "browser_download_url"
  }
}
#endif

// MARK: - Helper Update View

private struct HelperUpdateView: View {
  let currentVersion: String
  let requiredVersion: String
  var isInstalling: Bool = false
  let onInstall: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      VStack(spacing: 8) {
        Image(systemName: "arrow.triangle.2.circlepath")
          .font(.system(size: 40))
          .foregroundStyle(.orange)

        Text("Helper Update Required")
          .font(.headline)

        Text("Installed: v\(currentVersion) — Required: v\(requiredVersion)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Text("LidGuard requires a newer version of the helper daemon for full functionality. Some features may not work until the helper is updated.")
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

          #if APPSTORE
          if #available(macOS 26.0, *) {
            Button("Download Helper") { onInstall() }
              .keyboardShortcut(.defaultAction)
              .buttonStyle(.glassProminent)
          } else {
            Button("Download Helper") { onInstall() }
              .keyboardShortcut(.defaultAction)
          }
          #else
          if #available(macOS 26.0, *) {
            Button("Update Helper") { onInstall() }
              .keyboardShortcut(.defaultAction)
              .buttonStyle(.glassProminent)
          } else {
            Button("Update Helper") { onInstall() }
              .keyboardShortcut(.defaultAction)
          }
          #endif
        }
        .padding(.bottom, 4)
      }
    }
    .padding(20)
    .frame(width: 400, height: 240)
  }
}

// MARK: - App Store Install Instructions View

#if APPSTORE
private struct HelperInstallView: View {
  let onDownload: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "arrow.down.circle")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)

      Text("Install LidGuard Helper")
        .font(.headline)

      VStack(alignment: .leading, spacing: 12) {
        instructionRow(number: 1, text: "Download the helper installer from GitHub")
        instructionRow(number: 2, text: "Open the downloaded installer and follow the steps")
        instructionRow(number: 3, text: "If prompted, allow LidGuard Helper in System Settings → Privacy & Security")
      }
      .padding(.horizontal)

      Spacer()

      HStack(spacing: 12) {
        Button("Done") { onDismiss() }
          .keyboardShortcut(.cancelAction)

        if #available(macOS 26.0, *) {
          Button("Download Helper") { onDownload() }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.glassProminent)
        } else {
          Button("Download Helper") { onDownload() }
            .keyboardShortcut(.defaultAction)
        }
      }
      .padding(.bottom, 4)
    }
    .padding(20)
    .frame(width: 420, height: 300)
  }

  private func instructionRow(number: Int, text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text("\(number).")
        .fontWeight(.bold)
        .frame(width: 20, alignment: .trailing)
      Text(text)
    }
  }
}
#endif
