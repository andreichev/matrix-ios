import Foundation

struct DirectoryOrganization: Decodable {
    let id: UUID
    let name: String
    let baseUrl: String
}

struct OrganizationSelection: Codable {
    let name: String?
    let baseUrl: String

    var title: String { name ?? "Другая организация" }
}

@MainActor
final class OrganizationDirectoryService {
    private struct Response: Decodable {
        let organizations: [DirectoryOrganization]
        let protocolVersion: Int
    }
    private let http: HTTPClient
    private let defaults: UserDefaults
    private static let selectionKey = "matrix.selectedOrganization"

    init(http: HTTPClient, defaults: UserDefaults = .standard) {
        self.http = http
        self.defaults = defaults
    }

    var lastSelection: OrganizationSelection? {
        guard let data = defaults.data(forKey: Self.selectionKey),
            let selection = try? JSONDecoder().decode(OrganizationSelection.self, from: data),
            (try? ServerAddress(selection.baseUrl)) != nil else { return nil }
        return selection
    }

    func remember(_ selection: OrganizationSelection) {
        defaults.set(try? JSONEncoder().encode(selection), forKey: Self.selectionKey)
    }

    func organizations(query: String) async throws -> [DirectoryOrganization] {
        #if targetEnvironment(simulator)
            let address = "http://localhost:8095"
        #else
            let address = "https://hub.mtx.su"
        #endif
        // This is the only direct Hub request. It carries no account or device credentials.
        let data = try await http.send(server: ServerAddress(address), path: "api/v1/directory",
            queryItems: [URLQueryItem(name: "q", value: query)])
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.protocolVersion == 1 else {
            throw MatrixError.message("Обновите приложение для загрузки списка организаций.")
        }
        return response.organizations
    }
}
