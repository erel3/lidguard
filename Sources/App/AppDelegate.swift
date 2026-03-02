import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private var statusItem: NSStatusItem!
  private var menu: NSMenu!
  private var statusMenuItem: NSMenuItem!
  private var toggleMenuItem: NSMenuItem!
  private var testMenuItem: NSMenuItem!
  private var activityLogMenuItem: NSMenuItem!
  private var bluetoothAutoArmMenuItem: NSMenuItem!
  private var eyeOverlayView: NSImageView?

  private let theftProtection = TheftProtectionService()
  private let authService = BiometricAuthService()
  private let pmsetService = PmsetService.shared
  private var allowQuit = false

  func allowQuitForUpdate() {
    allowQuit = true
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    setupMainMenu()
    setupMenuBar()
    theftProtection.delegate = self
    theftProtection.start()

    ActivityLog.logAsync(.system, "LidGuard v\(Config.App.version) started")
    UpdateService.shared.startPeriodicChecks()

    // Start with no Dock icon (protection disabled)
    NSApp.setActivationPolicy(.accessory)

    // Show settings on first launch if not configured
    if !SettingsService.shared.isConfigured() {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        self.showSettings()
      }
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // Allow quit if user authenticated with Touch ID
    if allowQuit {
      return .terminateNow
    }

    // Allow quit if protection disabled
    if theftProtection.state == .disabled {
      return .terminateNow
    }

    // In theft mode, always block termination
    // In enabled state, check shutdownBlocking setting
    if (theftProtection.state == .enabled || theftProtection.state == .enabledBluetooth)
       && !SettingsService.shared.behaviorShutdownBlocking {
      return .terminateNow
    }

    ActivityLog.logAsync(.trigger, "Shutdown/quit BLOCKED")
    theftProtection.sendShutdownAlert(blocked: true)

    // This will show system dialog: "LidGuard is preventing shutdown"
    // User must click Cancel or we get force-killed after timeout
    return .terminateCancel
  }

  private func setupMainMenu() {
    let mainMenu = NSMenu()

    // App menu
    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(NSMenuItem(title: "About \(Config.App.name)", action: #selector(showAbout), keyEquivalent: ""))
    appMenu.addItem(.separator())
    appMenu.addItem(NSMenuItem(title: "Quit \(Config.App.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    // Edit menu (enables Cmd+C, Cmd+V, Cmd+X, Cmd+A)
    let editMenuItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
    editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
    editMenu.addItem(.separator())
    editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)

    // Help menu
    let helpMenuItem = NSMenuItem()
    let helpMenu = NSMenu(title: "Help")
    helpMenu.addItem(NSMenuItem(title: "\(Config.App.name) on GitHub", action: #selector(openGitHub), keyEquivalent: ""))
    helpMenu.addItem(NSMenuItem(title: "Report an Issue", action: #selector(openIssues), keyEquivalent: ""))
    helpMenuItem.submenu = helpMenu
    mainMenu.addItem(helpMenuItem)

    NSApp.mainMenu = mainMenu
  }

  private func setupMenuBar() {
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

    let settingsItem = NSMenuItem(title: "Settings... (Touch ID)", action: #selector(openSettings), keyEquivalent: ",")
    settingsItem.target = self
    settingsItem.image = menuSymbol("gearshape", color: .secondaryLabelColor)
    menu.addItem(settingsItem)

    let moreItem = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
    moreItem.image = menuSymbol("ellipsis.circle", color: .secondaryLabelColor)
    let moreMenu = NSMenu()
    moreMenu.addItem(NSMenuItem(title: "About \(Config.App.name)", action: #selector(showAbout), keyEquivalent: ""))
    moreMenu.addItem(NSMenuItem(title: "\(Config.App.name) on GitHub", action: #selector(openGitHub), keyEquivalent: ""))
    moreMenu.addItem(NSMenuItem(title: "Report an Issue", action: #selector(openIssues), keyEquivalent: ""))
    moreItem.submenu = moreMenu
    menu.addItem(moreItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(title: "Quit (Touch ID)", action: #selector(quitApp), keyEquivalent: "q")
    quitItem.target = self
    quitItem.image = menuSymbol("power", color: .secondaryLabelColor)
    menu.addItem(quitItem)

    updateStatus()
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }

    // Pre-fetch location before menu blocks run loop
    theftProtection.refreshLocation()

    if event.type == .rightMouseUp {
      handleRightClick()
    } else {
      // Left click: show menu (Option key shows hidden items via menuWillOpen)
      if let button = statusItem.button {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
      }
    }
  }

  private func handleRightClick() {
    switch theftProtection.state {
    case .disabled:
      theftProtection.enableProtection()

    case .enabled, .enabledBluetooth:
      authService.authenticate(reason: "Authenticate to disable protection") { [weak self] success in
        if success {
          self?.theftProtection.disableProtection()
        }
      }

    case .theftMode:
      authService.authenticate(reason: "Authenticate to deactivate theft mode") { [weak self] success in
        if success {
          self?.theftProtection.deactivateTheftMode()
        }
      }
    }
  }

  // MARK: - NSMenuDelegate
  func menuWillOpen(_ menu: NSMenu) {
    let optionPressed = NSEvent.modifierFlags.contains(.option)
    testMenuItem.isHidden = !optionPressed
    activityLogMenuItem.isHidden = !optionPressed
  }

  private func menuSymbol(_ name: String, color: NSColor) -> NSImage? {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
      .applying(.init(paletteColors: [color]))
    return image.withSymbolConfiguration(config)
  }

  // MARK: - Custom Menu Bar Icons

  private func menuBarIcon(_ style: MenuBarIconStyle) -> NSImage {
    let size: CGFloat = 18
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    if let ctx = NSGraphicsContext.current?.cgContext {
      ctx.setStrokeColor(.black)
      ctx.setFillColor(.black)
      ctx.setLineWidth(size * 0.065)
      ctx.setLineCap(.round)
      ctx.setLineJoin(.round)
      drawLaptopBody(ctx: ctx, s: size, cx: size * 0.5)
      // For eyeClosed, draw the eye in template too (same black, macOS colors it)
      if style == .eyeClosed {
        let screenH = size * 0.42
        let screenY = size * 0.38
        let eyeCY = screenY + screenH * 0.5
        let eyeW = size * 0.36
        let eyeH = size * 0.14
        let cx = size * 0.5
        drawEyeShape(ctx: ctx, s: size, style: style, eyeCY: eyeCY, eyeW: eyeW, eyeH: eyeH,
                     leftX: cx - eyeW / 2, rightX: cx + eyeW / 2, cx: cx)
      }
    }
    image.unlockFocus()
    image.isTemplate = true
    return image
  }

  private enum MenuBarIconStyle {
    case eyeOpen                 // enabled / monitoring
    case eyeOpenBluetooth        // auto-armed via bluetooth (yellow)
    case eyeHalfClosedBluetooth  // disabled but BT monitoring active (yellow half-closed)
    case eyeClosed               // disabled
    case eyeAlert                // theft mode — eye + exclamation
  }

  private func menuBarEyeImage(_ style: MenuBarIconStyle) -> NSImage {
    let size: CGFloat = 18
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    if let ctx = NSGraphicsContext.current?.cgContext {
      let color: CGColor
      switch style {
      case .eyeOpen, .eyeOpenBluetooth:
        color = CGColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1.0)
      case .eyeHalfClosedBluetooth:
        color = CGColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 1.0)
      case .eyeAlert:
        color = CGColor(red: 0.9, green: 0.2, blue: 0.15, alpha: 1.0)
      case .eyeClosed:
        color = .black
      }
      ctx.setStrokeColor(color)
      ctx.setFillColor(color)
      ctx.setLineWidth(size * 0.065)
      ctx.setLineCap(.round)
      ctx.setLineJoin(.round)
      let screenH = size * 0.42
      let screenY = size * 0.38
      let eyeCY = screenY + screenH * 0.5
      let eyeW = size * 0.36
      let eyeH = size * 0.14
      let cx = size * 0.5
      drawEyeShape(ctx: ctx, s: size, style: style, eyeCY: eyeCY, eyeW: eyeW, eyeH: eyeH,
                   leftX: cx - eyeW / 2, rightX: cx + eyeW / 2, cx: cx)
    }
    image.unlockFocus()
    image.isTemplate = false
    return image
  }

  private func showEyeOverlay(style: MenuBarIconStyle) {
    guard let button = statusItem.button else { return }
    removeEyeOverlay()
    let imageView = NSImageView(image: menuBarEyeImage(style))
    imageView.frame = button.bounds
    imageView.imageScaling = .scaleNone
    button.addSubview(imageView)
    eyeOverlayView = imageView
  }

  private func removeEyeOverlay() {
    eyeOverlayView?.removeFromSuperview()
    eyeOverlayView = nil
  }

  private func drawLaptopBody(ctx: CGContext, s: CGFloat, cx: CGFloat) {
    let screenW = s * 0.72
    let screenH = s * 0.42
    let screenY = s * 0.38
    let screenCorner = s * 0.04
    let screenPath = CGPath(roundedRect: CGRect(x: cx - screenW / 2, y: screenY,
                                                 width: screenW, height: screenH),
                             cornerWidth: screenCorner, cornerHeight: screenCorner,
                             transform: nil)
    ctx.addPath(screenPath)
    ctx.strokePath()

    let hingeW = screenW * 0.5
    let hingeH = s * 0.035
    ctx.fill([CGRect(x: cx - hingeW / 2, y: screenY - hingeH, width: hingeW, height: hingeH)])

    let baseTopW = screenW + s * 0.06
    let baseBotW = screenW + s * 0.18
    let baseH = s * 0.09
    let baseTopY = screenY - hingeH - s * 0.01
    let baseBotY = baseTopY - baseH
    let cr = s * 0.02

    let base = CGMutablePath()
    base.move(to: CGPoint(x: cx - baseTopW / 2, y: baseTopY))
    base.addLine(to: CGPoint(x: cx + baseTopW / 2, y: baseTopY))
    base.addLine(to: CGPoint(x: cx + baseBotW / 2 - cr, y: baseBotY + cr))
    base.addQuadCurve(to: CGPoint(x: cx + baseBotW / 2, y: baseBotY),
                      control: CGPoint(x: cx + baseBotW / 2, y: baseBotY + cr))
    base.addLine(to: CGPoint(x: cx - baseBotW / 2, y: baseBotY))
    base.addQuadCurve(to: CGPoint(x: cx - baseBotW / 2 + cr, y: baseBotY + cr),
                      control: CGPoint(x: cx - baseBotW / 2, y: baseBotY + cr))
    base.closeSubpath()
    ctx.addPath(base)
    ctx.fillPath()
  }

  private func drawEyeShape(ctx: CGContext, s: CGFloat, style: MenuBarIconStyle,
                             eyeCY: CGFloat, eyeW: CGFloat, eyeH: CGFloat,
                             leftX: CGFloat, rightX: CGFloat, cx: CGFloat) {
    switch style {
    case .eyeOpen, .eyeAlert:
      let path = CGMutablePath()
      path.move(to: CGPoint(x: leftX, y: eyeCY))
      path.addCurve(to: CGPoint(x: rightX, y: eyeCY),
                    control1: CGPoint(x: leftX + eyeW * 0.25, y: eyeCY + eyeH),
                    control2: CGPoint(x: rightX - eyeW * 0.25, y: eyeCY + eyeH))
      path.addCurve(to: CGPoint(x: leftX, y: eyeCY),
                    control1: CGPoint(x: rightX - eyeW * 0.25, y: eyeCY - eyeH),
                    control2: CGPoint(x: leftX + eyeW * 0.25, y: eyeCY - eyeH))
      path.closeSubpath()

      ctx.addPath(path)
      ctx.strokePath()

      let irisR = s * 0.08
      ctx.fillEllipse(in: CGRect(x: cx - irisR, y: eyeCY - irisR,
                                  width: irisR * 2, height: irisR * 2))

    case .eyeOpenBluetooth, .eyeHalfClosedBluetooth:
      // Bottom curve (full open eye bottom)
      let halfPath = CGMutablePath()
      halfPath.move(to: CGPoint(x: leftX, y: eyeCY))
      halfPath.addCurve(to: CGPoint(x: rightX, y: eyeCY),
                        control1: CGPoint(x: leftX + eyeW * 0.25, y: eyeCY - eyeH),
                        control2: CGPoint(x: rightX - eyeW * 0.25, y: eyeCY - eyeH))
      // Top curve (drooping — half the normal height)
      let halfH = eyeH * 0.4
      halfPath.addCurve(to: CGPoint(x: leftX, y: eyeCY),
                        control1: CGPoint(x: rightX - eyeW * 0.25, y: eyeCY + halfH),
                        control2: CGPoint(x: leftX + eyeW * 0.25, y: eyeCY + halfH))
      halfPath.closeSubpath()

      ctx.addPath(halfPath)
      ctx.strokePath()

      // Small iris peeking below the lid
      let irisR = s * 0.05
      ctx.fillEllipse(in: CGRect(x: cx - irisR, y: eyeCY - irisR * 1.5,
                                  width: irisR * 2, height: irisR * 2))

    case .eyeClosed:
      // Shift up so the downward curve + lashes don't hit screen bottom
      let closedCY = eyeCY + s * 0.06
      let closedLeftX = cx - eyeW / 2
      let closedRightX = cx + eyeW / 2

      let path = CGMutablePath()
      path.move(to: CGPoint(x: closedLeftX, y: closedCY))
      path.addCurve(to: CGPoint(x: closedRightX, y: closedCY),
                    control1: CGPoint(x: closedLeftX + eyeW * 0.25, y: closedCY - eyeH),
                    control2: CGPoint(x: closedRightX - eyeW * 0.25, y: closedCY - eyeH))

      ctx.addPath(path)
      ctx.strokePath()

      let lashLen = s * 0.06
      for t: CGFloat in [0.25, 0.5, 0.75] {
        let x = closedLeftX + eyeW * t
        let yOff = eyeH * (1.0 - 4.0 * (t - 0.5) * (t - 0.5))
        let y = closedCY - yOff
        ctx.move(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x, y: y - lashLen))
      }
      ctx.strokePath()
    }
  }

  private func updateStatus() {
    switch theftProtection.state {
    case .disabled:
      let btWatching = SettingsService.shared.bluetoothAutoArmEnabled && SettingsService.shared.hasTrustedBLEDevices
      statusMenuItem.title = btWatching ? "Status: Watching Bluetooth" : "Status: Disabled"
      statusMenuItem.image = menuSymbol("circle.fill", color: btWatching ? .systemYellow : .systemRed)
      toggleMenuItem.title = "Enable Protection"
      toggleMenuItem.image = menuSymbol("checkmark.shield", color: .systemGreen)
      statusItem.button?.image = menuBarIcon(btWatching ? .eyeHalfClosedBluetooth : .eyeClosed)
      if btWatching { showEyeOverlay(style: .eyeHalfClosedBluetooth) } else { removeEyeOverlay() }

    case .enabled:
      statusMenuItem.title = "Status: Monitoring"
      statusMenuItem.image = menuSymbol("checkmark.circle.fill", color: .systemGreen)
      toggleMenuItem.title = "Disable Protection"
      toggleMenuItem.image = menuSymbol("xmark.shield", color: .systemRed)
      statusItem.button?.image = menuBarIcon(.eyeOpen)
      showEyeOverlay(style: .eyeOpen)

    case .enabledBluetooth:
      statusMenuItem.title = "Status: Auto-Armed (Bluetooth)"
      statusMenuItem.image = menuSymbol("antenna.radiowaves.left.and.right", color: .systemYellow)
      toggleMenuItem.title = "Disable Protection"
      toggleMenuItem.image = menuSymbol("xmark.shield", color: .systemRed)
      statusItem.button?.image = menuBarIcon(.eyeOpenBluetooth)
      showEyeOverlay(style: .eyeOpenBluetooth)

    case .theftMode:
      statusMenuItem.title = "THEFT MODE ACTIVE"
      statusMenuItem.image = menuSymbol("exclamationmark.triangle.fill", color: .systemRed)
      toggleMenuItem.title = "Deactivate Theft Mode"
      toggleMenuItem.image = menuSymbol("lock.open", color: .systemOrange)
      statusItem.button?.image = menuBarIcon(.eyeAlert)
      showEyeOverlay(style: .eyeAlert)
    }

    updateBluetoothMenuItem()
  }

  private func updateBluetoothMenuItem() {
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

  @objc private func toggleProtection() {
    switch theftProtection.state {
    case .disabled:
      theftProtection.enableProtection(lockScreen: true)

    case .enabled, .enabledBluetooth:
      authService.authenticate(reason: "Authenticate to disable protection") { [weak self] success in
        if success {
          self?.theftProtection.disableProtection()
        }
      }

    case .theftMode:
      authService.authenticate(reason: "Authenticate to deactivate theft mode") { [weak self] success in
        if success {
          self?.theftProtection.deactivateTheftMode()
        }
      }
    }
  }

  @objc private func toggleBluetoothAutoArm() {
    let settings = SettingsService.shared
    let turningOff = settings.bluetoothAutoArmEnabled

    let perform = { [weak self] in
      settings.bluetoothAutoArmEnabled = !settings.bluetoothAutoArmEnabled
      NotificationCenter.default.post(name: .bluetoothSettingsChanged, object: nil)
      if turningOff && self?.theftProtection.state == .enabledBluetooth {
        self?.theftProtection.disableProtection()
      }
      self?.updateStatus()
      ActivityLog.logAsync(.bluetooth, "Bluetooth auto-arm \(settings.bluetoothAutoArmEnabled ? "enabled" : "disabled")")
    }

    if turningOff {
      authService.authenticate(reason: "Authenticate to disable Bluetooth auto-arm") { success in
        guard success else { return }
        perform()
      }
    } else {
      perform()
    }
  }

  @objc private func quitApp() {
    authService.authenticate(reason: "Authenticate to quit \(Config.App.name)") { [weak self] success in
      if success {
        self?.allowQuit = true
        NSApplication.shared.terminate(nil)
      }
    }
  }

  @objc private func sendTestAlert() {
    theftProtection.sendTestAlert()
  }

  @objc private func openSettings() {
    authService.authenticate(reason: "Authenticate to open Settings") { [weak self] success in
      if success {
        self?.showSettings()
      }
    }
  }

  private func showSettings() {
    SettingsWindowController.shared.show()
  }

  @objc private func showActivityLog() {
    ActivityLogWindowController.shared.show()
  }

  @objc private func showAbout() {
    let credits = NSAttributedString(
      string: "Laptop theft protection for macOS",
      attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
    )
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationName: Config.App.name,
      .applicationVersion: Config.App.version,
      .version: "",
      .credits: credits
    ])
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func openGitHub() {
    NSWorkspace.shared.open(URL(string: "https://github.com/Erel3/lidguard")!)
  }

  @objc private func openIssues() {
    NSWorkspace.shared.open(URL(string: "https://github.com/Erel3/lidguard/issues")!)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    return false
  }

  func applicationWillTerminate(_ notification: Notification) {
    ActivityLog.logAsync(.system, "LidGuard shutting down")
    theftProtection.shutdown()
  }
}

// MARK: - TheftProtectionDelegate
extension AppDelegate: TheftProtectionDelegate {
  func theftProtectionShortcutTriggered(_ service: TheftProtectionService) {
    switch service.state {
    case .disabled:
      service.enableProtection(lockScreen: true)
    case .enabled, .enabledBluetooth:
      authService.authenticate(reason: "Authenticate to disable protection") { [weak self] success in
        guard success else { return }
        self?.theftProtection.disableProtection()
      }
    case .theftMode:
      break
    }
  }

  func theftProtectionBluetoothShortcutTriggered(_ service: TheftProtectionService) {
    let settings = SettingsService.shared
    guard settings.hasTrustedBLEDevices else { return }

    if settings.bluetoothAutoArmEnabled {
      // Turning off — require Touch ID
      authService.authenticate(reason: "Authenticate to disable Bluetooth auto-arm") { [weak self] success in
        guard success else { return }
        settings.bluetoothAutoArmEnabled = false
        NotificationCenter.default.post(name: .bluetoothSettingsChanged, object: nil)
        if self?.theftProtection.state == .enabledBluetooth {
          self?.theftProtection.disableProtection()
        }
        self?.updateStatus()
        ActivityLog.logAsync(.bluetooth, "Bluetooth auto-arm disabled via shortcut")
      }
    } else {
      // Turning on — no auth needed
      settings.bluetoothAutoArmEnabled = true
      NotificationCenter.default.post(name: .bluetoothSettingsChanged, object: nil)
      updateStatus()
      ActivityLog.logAsync(.bluetooth, "Bluetooth auto-arm enabled via shortcut")
    }
  }

  func theftProtectionStateDidChange(_ service: TheftProtectionService, state: ProtectionState) {
    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
      // Force close menu if open (critical for theft mode activation)
      if state == .theftMode {
        self?.menu.cancelTracking()
      }
      self?.updateStatus()
      self?.updateBluetoothMenuItem()

      // Show Dock icon when protection enabled (required to block shutdown)
      // Hide Dock icon when disabled (cleaner UX)
      let policy: NSApplication.ActivationPolicy = (state == .disabled) ? .accessory : .regular
      NSApp.setActivationPolicy(policy)
    }
    CFRunLoopWakeUp(CFRunLoopGetMain())
  }
}
