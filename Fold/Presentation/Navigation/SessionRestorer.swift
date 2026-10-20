import Foundation
import SwiftUI

/// Checks a saved connection without allowing an old launch request to invalidate
/// a replacement connection or interrupt navigation to a private download.
enum SessionRestorer {
    static func restore(authState: AuthState, repository: AuthRepositoryProtocol, router: AppRouter) async {
        guard let id = authState.authorization?.id else { return }
        func isCurrent() -> Bool {
            !Task.isCancelled && authState.authorization?.id == id && router.path.isEmpty
        }
        do {
            let valid = try await repository.ping()
            guard isCurrent() else { return }
            guard valid else { router.onAutoLoginFailed(); return }
            do { try await repository.fetchUserAccount() }
            catch {
                guard isCurrent() else { return }
                if let error = error as? AppError, case .unauthorized = error {
                    router.onAutoLoginFailed(); return
                }
                // Account metadata is optional while the server is unavailable.
                // Privileges default to false until a later successful fetch.
            }
            guard isCurrent() else { return }
            router.onLoginSuccess()
        } catch {
            guard isCurrent() else { return }
            if let error = error as? AppError, case .unauthorized = error { router.onAutoLoginFailed() }
            else { router.onAutoLoginUnavailable() }
        }
    }
}
