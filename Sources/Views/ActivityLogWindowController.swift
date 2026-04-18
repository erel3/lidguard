import Cocoa
import SwiftUI

@MainActor
final class ActivityLogWindowController {
  static let shared = ActivityLogWindowController()

  private var window: NSWindow?

  private init() {}

  func show() {
    if let existingWindow = window {
      existingWindow.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let logView = ActivityLogView()
    let hostingController = NSHostingController(rootView: logView)

    let newWindow = NSWindow(contentViewController: hostingController)
    newWindow.title = "Activity Log"
    newWindow.styleMask = [.titled, .closable, .resizable]
    newWindow.center()
    newWindow.isReleasedWhenClosed = false
    newWindow.setFrameAutosaveName("ActivityLogWindow")
    newWindow.delegate = ActivityLogWindowDelegate.shared

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

@MainActor
private class ActivityLogWindowDelegate: NSObject, NSWindowDelegate {
  static let shared = ActivityLogWindowDelegate()

  func windowWillClose(_ notification: Notification) {
    if notification.object is NSWindow {
      ActivityLogWindowController.shared.windowWillClose()
    }
  }
}
