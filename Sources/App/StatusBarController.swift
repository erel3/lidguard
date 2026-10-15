import Cocoa

@MainActor
protocol StatusBarControllerDelegate: AnyObject {
  func statusBarLeftClickPreOpen()
  func statusBarRightClick()
  func statusBarToggleProtection()
  func statusBarSendTestAlert()
  func statusBarShowActivityLog()
  func statusBarToggleBluetoothAutoArm()
  func statusBarOpenSettings()
  func statusBarShowAbout()
  func statusBarOpenGitHub()
  func statusBarOpenIssues()
  func statusBarQuit()
}

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
  weak var delegate: StatusBarControllerDelegate?

  private var statusItem: NSStatusItem!
  private var menu: NSMenu!
  private var statusMenuItem: NSMenuItem!
  private var toggleMenuItem: NSMenuItem!
  private var testMenuItem: NSMenuItem!
  private var activityLogMenuItem: NSMenuItem!
  private var bluetoothAutoArmMenuItem: NSMenuItem!
  private var eyeOverlayView: NSImageView?

  func setup() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem.button {
      button.target = self
      button.action = #selector(statusItemClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    menu = NSMenu()
    menu.delegate = self

    statusMenuItem = NSMenuItem(title: "Status: Monitoring", action: nil, keyEquivalent: "")
    menu.addItem(statusMenuItem)

    menu.addItem(.separator())

    toggleMenuItem = NSMenuItem(title: "Disable Protection", action: #selector(toggleProtection), keyEquivalent: "d")
    toggleMenuItem.target = self
    menu.addItem(toggleMenuItem)

    testMenuItem = NSMenuItem(title: "Send Test Alert", action: #selector(sendTestAlert), keyEquivalent: "")
    testMenuItem.target = self
    testMenuItem.image = menuSymbol("paperplane", color: .systemBlue)
    testMenuItem.isHidden = true
    menu.addItem(testMenuItem)

    activityLogMenuItem = NSMenuItem(title: "Activity Log", action: #selector(showActivityLog), keyEquivalent: "")
    activityLogMenuItem.target = self
    activityLogMenuItem.image = menuSymbol("list.bullet.rectangle", color: .secondaryLabelColor)
    activityLogMenuItem.isHidden = true
    menu.addItem(activityLogMenuItem)

    bluetoothAutoArmMenuItem = NSMenuItem(title: "Bluetooth Auto-Arm: Off", action: #selector(toggleBluetoothAutoArm), keyEquivalent: "b")
    bluetoothAutoArmMenuItem.target = self
    bluetoothAutoArmMenuItem.image = menuSymbol("antenna.radiowaves.left.and.right", color: .secondaryLabelColor)
    menu.addItem(bluetoothAutoArmMenuItem)

    menu.addItem(.separator())

    let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
    settingsItem.target = self
    settingsItem.image = menuSymbol("gearshape", color: .secondaryLabelColor)
    menu.addItem(settingsItem)

    let moreItem = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
    moreItem.image = menuSymbol("ellipsis.circle", color: .secondaryLabelColor)
    let moreMenu = NSMenu()
    let aboutItem = NSMenuItem(title: "About \(Config.App.name)", action: #selector(showAbout), keyEquivalent: "")
    aboutItem.target = self
    moreMenu.addItem(aboutItem)
    let githubItem = NSMenuItem(title: "\(Config.App.name) on GitHub", action: #selector(openGitHub), keyEquivalent: "")
    githubItem.target = self
    moreMenu.addItem(githubItem)
    let issuesItem = NSMenuItem(title: "Report an Issue", action: #selector(openIssues), keyEquivalent: "")
    issuesItem.target = self
    moreMenu.addItem(issuesItem)
    moreItem.submenu = moreMenu
    menu.addItem(moreItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
    quitItem.target = self
    quitItem.image = menuSymbol("power", color: .secondaryLabelColor)
    menu.addItem(quitItem)

    // macOS 27 hides menu item images by default; the colored icons carry protection state.
    if #available(macOS 27, *) {
      menu.items.forEach { $0.preferredImageVisibility = .visible }
    }
  }

  func update(state: ProtectionState, trigger: TheftTrigger?) {
    switch state {
    case .disabled:
      let btWatching = SettingsService.shared.bluetoothAutoArmEnabled && SettingsService.shared.hasTrustedBLEDevices
      statusMenuItem.title = btWatching ? "Status: Watching Bluetooth" : "Status: Disabled"
      statusMenuItem.image = menuSymbol("circle.fill", color: btWatching ? .systemYellow : .systemRed)
      toggleMenuItem.title = "Enable Protection"
      toggleMenuItem.image = menuSymbol("checkmark.shield", color: .systemGreen)
      statusItem.button?.image = MenuBarIconRenderer.laptopIcon(btWatching ? .eyeHalfClosedBluetooth : .eyeClosed)
      if btWatching { showEyeOverlay(style: .eyeHalfClosedBluetooth) } else { removeEyeOverlay() }

    case .enabled:
      statusMenuItem.title = "Status: Monitoring"
      statusMenuItem.image = menuSymbol("checkmark.circle.fill", color: .systemGreen)
      toggleMenuItem.title = "Disable Protection"
      toggleMenuItem.image = menuSymbol("xmark.shield", color: .systemRed)
      statusItem.button?.image = MenuBarIconRenderer.laptopIcon(.eyeOpen)
      showEyeOverlay(style: .eyeOpen)

    case .enabledBluetooth:
      statusMenuItem.title = "Status: Auto-Armed (Bluetooth)"
      statusMenuItem.image = menuSymbol("antenna.radiowaves.left.and.right", color: .systemYellow)
      toggleMenuItem.title = "Disable Protection"
      toggleMenuItem.image = menuSymbol("xmark.shield", color: .systemRed)
      statusItem.button?.image = MenuBarIconRenderer.laptopIcon(.eyeOpenBluetooth)
      showEyeOverlay(style: .eyeOpenBluetooth)

    case .theftMode:
      let cause = trigger?.description
      statusMenuItem.title = cause.map { "THEFT MODE — \($0)" } ?? "THEFT MODE ACTIVE"
      statusMenuItem.image = menuSymbol("exclamationmark.triangle.fill", color: .systemRed)
      toggleMenuItem.title = "Deactivate Theft Mode"
      toggleMenuItem.image = menuSymbol("lock.open", color: .systemOrange)
      statusItem.button?.image = MenuBarIconRenderer.laptopIcon(.eyeAlert)
      showEyeOverlay(style: .eyeAlert)
    }

    updateBluetoothMenuItem()
  }

  func updateBluetoothMenuItem() {
    let settings = SettingsService.shared
    let hasTrusted = settings.hasTrustedBLEDevices
    let enabled = hasTrusted && settings.bluetoothAutoArmEnabled

    bluetoothAutoArmMenuItem.title = "Bluetooth Auto-Arm: \(enabled ? "On" : "Off")"
    bluetoothAutoArmMenuItem.isEnabled = hasTrusted
    bluetoothAutoArmMenuItem.image = menuSymbol(
      "antenna.radiowaves.left.and.right",
      color: enabled ? .systemYellow : .secondaryLabelColor
    )
  }

  func cancelMenuTracking() {
    menu.cancelTracking()
  }

  // MARK: - NSMenuDelegate

  func menuWillOpen(_ menu: NSMenu) {
    let optionPressed = NSEvent.modifierFlags.contains(.option)
    testMenuItem.isHidden = !optionPressed
    activityLogMenuItem.isHidden = !optionPressed
  }

  // MARK: - Private

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }

    delegate?.statusBarLeftClickPreOpen()

    if event.type == .rightMouseUp {
      delegate?.statusBarRightClick()
    } else {
      if let button = statusItem.button {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
      }
    }
  }

  @objc private func toggleProtection() { delegate?.statusBarToggleProtection() }
  @objc private func sendTestAlert() { delegate?.statusBarSendTestAlert() }
  @objc private func showActivityLog() { delegate?.statusBarShowActivityLog() }
  @objc private func toggleBluetoothAutoArm() { delegate?.statusBarToggleBluetoothAutoArm() }
  @objc private func openSettings() { delegate?.statusBarOpenSettings() }
  @objc private func showAbout() { delegate?.statusBarShowAbout() }
  @objc private func openGitHub() { delegate?.statusBarOpenGitHub() }
  @objc private func openIssues() { delegate?.statusBarOpenIssues() }
  @objc private func quitApp() { delegate?.statusBarQuit() }

  private func menuSymbol(_ name: String, color: NSColor) -> NSImage? {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
      .applying(.init(paletteColors: [color]))
    return image.withSymbolConfiguration(config)
  }

  private func showEyeOverlay(style: MenuBarIconStyle) {
    guard let button = statusItem.button else { return }
    removeEyeOverlay()
    let imageView = NSImageView(image: MenuBarIconRenderer.eyeImage(style))
    imageView.frame = button.bounds
    imageView.imageScaling = .scaleNone
    button.addSubview(imageView)
    eyeOverlayView = imageView
  }

  private func removeEyeOverlay() {
    eyeOverlayView?.removeFromSuperview()
    eyeOverlayView = nil
  }
}
