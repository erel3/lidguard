import Foundation
import LocalAuthentication

@MainActor
protocol AuthenticationService {
  func authenticate(reason: String, completion: @escaping @Sendable (Bool) -> Void)
}

@MainActor
final class BiometricAuthService: AuthenticationService {
  func authenticate(reason: String, completion: @escaping @Sendable (Bool) -> Void) {
    guard SettingsService.shared.biometricAuthEnabled else {
      completion(true)
      return
    }

    let context = LAContext()

    // Use deviceOwnerAuthentication to allow both Touch ID and password fallback
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
      DispatchQueue.main.async {
        completion(success)
      }
    }
  }
}
