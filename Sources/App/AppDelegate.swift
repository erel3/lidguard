import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private var statusItem: NSStatusItem!
  private var menu: NSMenu!
  private var statusMenuItem: NSMenuItem!
  private var toggleMenuItem: NSMenuItem!
  private var testMenuItem: NSMenuItem!
  private var activityLogMenuItem: NSMenuItem!

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
    if theftProtection.state == .enabled && !SettingsService.shared.behaviorShutdownBlocking {
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

    menu.addItem(.separator())

    let settingsItem = NSMenuItem(title: "Settings... (Touch ID)", action: #selector(openSettings), keyEquivalent: ",")
    settingsItem.target = self
    settingsItem.image = menuSymbol("gearshape", color: .secondaryLabelColor)
    menu.addItem(settingsItem)

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

    case .enabled:
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
      drawMenuBarIcon(ctx: ctx, size: size, style: style)
    }
    image.unlockFocus()
    // Colored icons (green for enabled, red for alert) — not templates
    image.isTemplate = (style == .eyeClosed)
    return image
  }

  private enum MenuBarIconStyle {
    case eyeOpen       // enabled / monitoring
    case eyeClosed     // disabled
    case eyeAlert      // theft mode — eye + exclamation
  }

  private func drawMenuBarIcon(ctx: CGContext, size: CGFloat, style: MenuBarIconStyle) {
    let s = size
    let cx = s * 0.5
    let lw = s * 0.065

    switch style {
    case .eyeAlert:
      let red = CGColor(red: 0.9, green: 0.2, blue: 0.15, alpha: 1.0)
      ctx.setStrokeColor(red)
      ctx.setFillColor(red)
    case .eyeOpen:
      let green = CGColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1.0)
      ctx.setStrokeColor(green)
      ctx.setFillColor(green)
    case .eyeClosed:
      ctx.setStrokeColor(.black)
      ctx.setFillColor(.black)
    }
    ctx.setLineWidth(lw)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // --- Screen lid (landscape rect) ---
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

    // --- Hinge ---
    let hingeW = screenW * 0.5
    let hingeH = s * 0.035
    ctx.fill([CGRect(x: cx - hingeW / 2, y: screenY - hingeH, width: hingeW, height: hingeH)])

    // --- Base (trapezoid) ---
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

    // --- Eye inside screen ---
    let eyeCY = screenY + screenH * 0.5
    let eyeW = s * 0.36
    let eyeH = s * 0.14
    let leftX = cx - eyeW / 2
    let rightX = cx + eyeW / 2

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
      statusMenuItem.title = "Status: Disabled"
      statusMenuItem.image = menuSymbol("circle.fill", color: .systemRed)
      toggleMenuItem.title = "Enable Protection"
      toggleMenuItem.image = menuSymbol("checkmark.shield", color: .systemGreen)
      statusItem.button?.image = menuBarIcon(.eyeClosed)

    case .enabled:
      statusMenuItem.title = "Status: Monitoring"
      statusMenuItem.image = menuSymbol("checkmark.circle.fill", color: .systemGreen)
      toggleMenuItem.title = "Disable Protection"
      toggleMenuItem.image = menuSymbol("xmark.shield", color: .systemRed)
      statusItem.button?.image = menuBarIcon(.eyeOpen)

    case .theftMode:
      statusMenuItem.title = "THEFT MODE ACTIVE"
      statusMenuItem.image = menuSymbol("exclamationmark.triangle.fill", color: .systemRed)
      toggleMenuItem.title = "Deactivate Theft Mode"
      toggleMenuItem.image = menuSymbol("lock.open", color: .systemOrange)
      statusItem.button?.image = menuBarIcon(.eyeAlert)
    }
  }

  @objc private func toggleProtection() {
    switch theftProtection.state {
    case .disabled:
      theftProtection.enableProtection(lockScreen: true)

    case .enabled:
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
    case .enabled:
      authService.authenticate(reason: "Authenticate to disable protection") { [weak self] success in
        guard success else { return }
        self?.theftProtection.disableProtection()
      }
    case .theftMode:
      break
    }
  }

  func theftProtectionStateDidChange(_ service: TheftProtectionService, state: ProtectionState) {
    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
      // Force close menu if open (critical for theft mode activation)
      if state == .theftMode {
        self?.menu.cancelTracking()
      }
      self?.updateStatus()

      // Show Dock icon when protection enabled (required to block shutdown)
      // Hide Dock icon when disabled (cleaner UX)
      let policy: NSApplication.ActivationPolicy = (state == .disabled) ? .accessory : .regular
      NSApp.setActivationPolicy(policy)
    }
    CFRunLoopWakeUp(CFRunLoopGetMain())
  }
}
