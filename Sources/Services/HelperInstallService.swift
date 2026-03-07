import Cocoa
import os.log
import SwiftUI

final class HelperInstallService {
  static let shared = HelperInstallService()

  private let installQueue = DispatchQueue(label: "com.lidguard.helper.install", qos: .utility)
  private var isInstalling = false

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
            let asset = release.assets.first(where: { $0.name == Config.Daemon.helperBinaryName
                                                      || $0.name.hasSuffix(".zip") }),
            let downloadURL = URL(string: asset.browserDownloadURL) else {
        Logger.daemon.error("No suitable asset found in helper release")
        ActivityLog.logAsync(.system, "Helper auto-install failed: no suitable asset")
        return
      }

      let isZip = asset.name.hasSuffix(".zip")

      do {
        let tempDir = FileManager.default.temporaryDirectory
          .appendingPathComponent("lidguard-helper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let downloadDst = tempDir.appendingPathComponent(asset.name)
        try downloadFile(from: downloadURL, to: downloadDst)

        let binarySource: URL
        if isZip {
          binarySource = try unzipAndFindBinary(zipPath: downloadDst, in: tempDir)
        } else {
          binarySource = downloadDst
        }

        // Ensure install directory exists
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        // Unload existing daemon and wait for cleanup
        unloadDaemon()
        Thread.sleep(forTimeInterval: 1)

        // Copy binary
        if FileManager.default.fileExists(atPath: binaryPath.path) {
          try FileManager.default.removeItem(at: binaryPath)
        }
        try FileManager.default.copyItem(at: binarySource, to: binaryPath)

        // Make executable
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o755],
          ofItemAtPath: binaryPath.path
        )

        // Install LaunchAgent plist
        installLaunchAgent()

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

  private func unzipAndFindBinary(zipPath: URL, in tempDir: URL) throws -> URL {
    let unzipDir = tempDir.appendingPathComponent("unzipped")
    try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)

    let unzip = Process()
    unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    unzip.arguments = ["-q", zipPath.path, "-d", unzipDir.path]
    try unzip.run()
    unzip.waitUntilExit()

    guard unzip.terminationStatus == 0 else {
      throw NSError(domain: "HelperInstall", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to unzip helper"])
    }

    let contents = try FileManager.default.contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil)
    guard let binary = contents.first(where: { $0.lastPathComponent == Config.Daemon.helperBinaryName }) else {
      throw NSError(domain: "HelperInstall", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Helper binary not found in zip"])
    }
    return binary
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
