#if APPSTORE

import SwiftUI

struct UpdateView: View {
  let version: String
  let changelog: String
  let storeURL: String
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      VStack(spacing: 8) {
        if let icon = NSApp.applicationIconImage {
          Image(nsImage: icon)
            .resizable()
            .frame(width: 64, height: 64)
        }
        Text("LidGuard \(version) Available")
          .font(.headline)
        Text("You're currently on \(Config.App.version)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      ScrollView {
        Text(changelog)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
      }
      .frame(maxHeight: .infinity)
      .background(Color(nsColor: .textBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 6))

      HStack(spacing: 12) {
        Button("Not Now") { onDismiss() }
          .keyboardShortcut(.cancelAction)

        if #available(macOS 26.0, *) {
          Button("Open App Store") { openAppStore() }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.glassProminent)
        } else {
          Button("Open App Store") { openAppStore() }
            .keyboardShortcut(.defaultAction)
        }
      }
      .padding(.bottom, 4)
    }
    .padding(20)
    .frame(width: 480, height: 360)
  }

  private func openAppStore() {
    if let url = URL(string: storeURL) {
      NSWorkspace.shared.open(url)
    }
    onDismiss()
  }
}

#else

import MarkdownUI
import SwiftUI

struct UpdateView: View {
  let version: String
  let changelog: String
  var isInstalling: Bool = false
  let onInstall: () -> Void
  let onSkip: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      // Header
      VStack(spacing: 8) {
        if let icon = NSApp.applicationIconImage {
          Image(nsImage: icon)
            .resizable()
            .frame(width: 64, height: 64)
        }
        Text("LidGuard \(version) Available")
          .font(.headline)
        Text("You're currently on \(Config.App.version)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      // Changelog
      ScrollView {
        Markdown(changelog)
          .markdownTheme(.basic)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
      }
      .frame(maxHeight: .infinity)
      .background(Color(nsColor: .textBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 6))

      // Buttons
      if isInstalling {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Downloading and installing...")
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
      } else {
        HStack(spacing: 12) {
          Button("Not Now") { onDismiss() }
            .keyboardShortcut(.cancelAction)

          Button("Skip This Version") { onSkip() }

          if #available(macOS 26.0, *) {
            Button("Install Update") { onInstall() }
              .keyboardShortcut(.defaultAction)
              .buttonStyle(.glassProminent)
          } else {
            Button("Install Update") { onInstall() }
              .keyboardShortcut(.defaultAction)
          }
        }
        .padding(.bottom, 4)
      }
    }
    .padding(20)
    .frame(width: 480, height: 360)
  }
}

#endif
