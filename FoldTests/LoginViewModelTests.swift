import Foundation
import Testing
@testable import Fold

struct LoginViewModelTests {

    private func makeSUT(
        authRepo: MockAuthRepository = MockAuthRepository()
    ) -> (LoginViewModel, AppRouter, MockAuthRepository) {
        let keychain = KeychainService()
        keychain.clearAll()
        let authState = AuthState(keychainService: keychain)
        let router = AppRouter(authState: authState)
        let vm = LoginViewModel(authRepository: authRepo, router: router)
        return (vm, router, authRepo)
    }

    @Test func serverVerificationAndCredentialPersistenceHaveDistinctErrors() async {
        let repo = MockAuthRepository()
        let (vm, router, _) = makeSUT(authRepo: repo)
        let url = URL(string: "https://fixture.example")!
        repo.connectSessionHandler = { _, _ in throw KeychainService.WriteFailure(status: -34018) }
        #expect(await vm.completeServerSignIn(url: url, cookies: []) == false)
        #expect(vm.errorMessage == String(localized: "connection_credential_save_failed"))
        #expect(router.appState != .authenticated)
        repo.connectSessionHandler = { _, _ in throw AppError.unauthorized }
        #expect(await vm.completeServerSignIn(url: url, cookies: []) == false)
        #expect(vm.errorMessage == String(localized: "login_server_incomplete"))
    }

    @Test func emptyFields_setsErrorMessage_doesNotCallRepo() async {
        var repoCalled = false
        let repo = MockAuthRepository()
        repo.loginHandler = { _, _, _ in repoCalled = true }
        let (vm, _, _) = makeSUT(authRepo: repo)

        vm.serverURL = ""
        vm.username = ""
        vm.password = ""
        await vm.login()

        #expect(vm.errorMessage != nil)
        #expect(repoCalled == false)
    }

    @Test func successfulLogin_setsRouterAuthenticated() async {
        let repo = MockAuthRepository()
        let (vm, router, _) = makeSUT(authRepo: repo)

        vm.serverURL = "https://ta.example.com"
        vm.username = "admin"
        vm.password = "pass"
        await vm.login()

        #expect(router.appState == .authenticated)
        #expect(vm.errorMessage == nil)
        #expect(vm.isLoading == false)
    }

    @Test func appError_setsErrorDescription() async {
        let repo = MockAuthRepository()
        repo.loginHandler = { _, _, _ in throw AppError.invalidURL }
        let (vm, _, _) = makeSUT(authRepo: repo)

        vm.serverURL = "https://ta.example.com"
        vm.username = "admin"
        vm.password = "pass"
        await vm.login()

        #expect(vm.errorMessage != nil)
        #expect(vm.isLoading == false)
    }

    @Test func genericError_setsFallbackMessage() async {
        let repo = MockAuthRepository()
        repo.loginHandler = { _, _, _ in throw URLError(.badURL) }
        let (vm, _, _) = makeSUT(authRepo: repo)

        vm.serverURL = "https://ta.example.com"
        vm.username = "admin"
        vm.password = "pass"
        await vm.login()

        #expect(vm.errorMessage != nil)
        #expect(vm.isLoading == false)
    }

    @Test func isLoading_falseAfterCompletion() async {
        let repo = MockAuthRepository()
        let (vm, _, _) = makeSUT(authRepo: repo)

        vm.serverURL = "https://ta.example.com"
        vm.username = "admin"
        vm.password = "pass"

        #expect(vm.isLoading == false)
        await vm.login()
        #expect(vm.isLoading == false)
    }
}
