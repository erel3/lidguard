import Cocoa
import SwiftUI

final class SettingsWindowController {
  static let shared = SettingsWindowController()

  private var window: NSWindow?

  private init() {}

  func show() {
    if let existingWindow = window {
      existingWindow.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let settingsView = SettingsView()
    let hostingController = NSHostingController(rootView: settingsView)

    let newWindow = NSWindow(contentViewController: hostingController)
    newWindow.title = "Settings"
    newWindow.titlebarAppearsTransparent = true
    newWindow.toolbarStyle = .unified
    newWindow.styleMask = [.titled, .closable]
    newWindow.isReleasedWhenClosed = false
    newWindow.delegate = WindowDelegate.shared

    // Set size and center on screen
    newWindow.setContentSize(NSSize(width: 620, height: 500))
    if let screen = NSScreen.main {
      let screenFrame = screen.visibleFrame
      let x = screenFrame.midX - 310
      let y = screenFrame.midY - 250
      newWindow.setFrameOrigin(NSPoint(x: x, y: y))
    }

    window = newWindow
    newWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func close() {
    window?.close()
    window = nil
  }

  fileprivate func windowWillClose() {
    window = nil
  }
}

private class WindowDelegate: NSObject, NSWindowDelegate {
  static let shared = WindowDelegate()

  func windowWillClose(_ notification: Notification) {
    if notification.object is NSWindow {
      SettingsWindowController.shared.windowWillClose()
    }
  }
}
