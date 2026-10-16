import Foundation

protocol AuthRepositoryProtocol {
    func login(serverURL: String, username: String, password: String) async throws
    func connectSession(serverURL: URL, cookies: [HTTPCookie]) async throws
    func connectToken(serverURL: URL, token: String) async throws
    func ping() async throws -> Bool
    func fetchUserAccount() async throws
    func logout()
}

// Default implementations keep older preview/mock repositories source compatible.
extension AuthRepositoryProtocol {
    func connectSession(serverURL: URL, cookies: [HTTPCookie]) async throws { throw AppError.unauthorized }
    func connectToken(serverURL: URL, token: String) async throws { throw AppError.unauthorized }
}
