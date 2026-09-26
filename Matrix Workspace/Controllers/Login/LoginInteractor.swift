import Foundation

@MainActor
final class LoginInteractor {
    private let auth: AuthService
    init(auth: AuthService) { self.auth = auth }

    func login(server: String, username: String, password: String) async throws {
        guard !username.isEmpty, !password.isEmpty else { throw MatrixError.message("Укажите логин и пароль.") }
        try await auth.login(server: ServerAddress(server), username: username, password: password)
    }
}
