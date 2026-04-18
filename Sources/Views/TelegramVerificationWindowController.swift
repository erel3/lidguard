import Cocoa
import SwiftUI

@MainActor
final class TelegramVerificationWindowController: NSObject {
  private var window: NSWindow?
  private let verificationService = TelegramVerificationService()
  private var completion: ((String?) -> Void)?

  isolated deinit {
    verificationService.stop()
    window?.delegate = nil
    window?.close()
  }

  func show(botToken: String, completion: @escaping (String?) -> Void) {
    dismiss()
    self.completion = completion

    let code = String(format: "%06d", Int.random(in: 0...999999))

    let view = TelegramVerificationView(code: code) { [weak self] in
      self?.dismiss()
    }
    let hostingController = NSHostingController(rootView: view)

    let newWindow = NSWindow(contentViewController: hostingController)
    newWindow.title = "Connect Telegram"
    newWindow.titlebarAppearsTransparent = true
    newWindow.toolbarStyle = .unified
    newWindow.styleMask = [.titled, .closable]
    newWindow.isReleasedWhenClosed = false
    newWindow.delegate = self

    newWindow.setContentSize(NSSize(width: 360, height: 220))
    if let screen = NSScreen.main {
      let screenFrame = screen.visibleFrame
      let x = screenFrame.midX - 180
      let y = screenFrame.midY - 110
      newWindow.setFrameOrigin(NSPoint(x: x, y: y))
    }

    window = newWindow
    newWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    verificationService.start(botToken: botToken, code: code) { [weak self] chatId in
      MainActor.assumeIsolated {
        self?.dismiss(chatId: chatId)
      }
    }
  }

  func close() {
    dismiss()
  }

  private func dismiss(chatId: String? = nil) {
    verificationService.stop()
    window?.delegate = nil
    window?.close()
    window = nil
    if let completion = completion {
      self.completion = nil
      completion(chatId)
    }
  }
}

extension TelegramVerificationWindowController: NSWindowDelegate {
  func windowWillClose(_ notification: Notification) {
    verificationService.stop()
    window = nil
    if let completion = completion {
      self.completion = nil
      completion(nil)
    }
  }
}
