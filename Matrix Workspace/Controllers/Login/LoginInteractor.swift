import Foundation

@MainActor
final class LoginInteractor {
    private let auth: AuthService
    init(auth: AuthService) { self.auth = auth }

    func login(username: String, password: String) async throws {
        guard !username.isEmpty, !password.isEmpty else { throw MatrixError.message("Укажите логин и пароль.") }
        try await auth.login(server: .configured, username: username, password: password)
    }
}
