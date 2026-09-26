import Foundation

@MainActor
final class LoginInteractor {
    private let auth: AuthService
    let directory: OrganizationDirectoryService
    init(auth: AuthService) {
        self.auth = auth
        directory = OrganizationDirectoryService(http: auth.http)
    }

    func login(organization: OrganizationSelection, username: String, password: String) async throws {
        guard !username.isEmpty, !password.isEmpty else { throw MatrixError.message("Укажите логин и пароль.") }
        let server = try ServerAddress(organization.baseUrl)
        try await auth.login(server: server, username: username, password: password)
        directory.remember(OrganizationSelection(name: organization.name, baseUrl: server.url.absoluteString))
    }
}
