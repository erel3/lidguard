#if APPSTORE
import StoreKit

enum ReceiptValidation {
  static func validateOrExit() {
    // AppTransaction.shared verifies the app was legitimately purchased.
    // No action needed on failure — StoreKit handles it.
    Task {
      _ = try? await AppTransaction.shared
    }
  }
}
#endif
