#if APPSTORE
import Foundation

enum ReceiptValidation {
  static func validateOrExit() {
    guard let receiptURL = Bundle.main.appStoreReceiptURL,
          FileManager.default.fileExists(atPath: receiptURL.path) else {
      exit(173)
    }
  }
}
#endif
