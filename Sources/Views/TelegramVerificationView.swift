import SwiftUI

struct TelegramVerificationView: View {
  let code: String
  let onCancel: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Text("Send this code to your bot in Telegram")
        .font(.headline)

      Text(code)
        .font(.system(size: 40, weight: .bold, design: .monospaced))
        .textSelection(.enabled)
        .padding(.vertical, 8)

      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Text("Waiting for code...")
          .foregroundStyle(.secondary)
      }

      Button("Cancel") {
        onCancel()
      }
      .keyboardShortcut(.cancelAction)
    }
    .padding(32)
    .frame(width: 360)
  }
}
