import OSLog
import WebKit

@MainActor
enum WebDataStoreService {
    private static let logger = Logger(subsystem: "com.andreichev.matrix", category: "WebDataStore")
    private static let identifiersKey = "matrix.webDataStoreIdentifiers"
    private static var clearing: Set<UUID> = []

    private static var identifiers: Set<UUID> {
        get {
            Set((UserDefaults.standard.stringArray(forKey: identifiersKey) ?? []).compactMap(UUID.init(uuidString:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.uuidString).sorted(), forKey: identifiersKey)
        }
    }

    static func remember(_ identifier: UUID) {
        var known = identifiers
        if known.insert(identifier).inserted { identifiers = known }
    }

    static func dataStore(for identifier: UUID) -> WKWebsiteDataStore {
        // Record ownership before WebKit creates files, including when launch is interrupted.
        remember(identifier)
        return WKWebsiteDataStore(forIdentifier: identifier)
    }

    static func clearInactiveStores(auth: AuthService) {
        for identifier in identifiers {
            guard identifier != auth.current?.id, clearing.insert(identifier).inserted else { continue }
            Task {
                defer { clearing.remove(identifier) }
                // Recheck after suspension: the user may already have signed in again.
                guard identifier != auth.current?.id else { return }
                await WKWebsiteDataStore(forIdentifier: identifier).removeData(
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
                do {
                    try await WKWebsiteDataStore.remove(forIdentifier: identifier)
                    identifiers.remove(identifier)
                } catch {
                    // An old WebView can still be releasing. Its data is cleared; retry removal on next launch.
                    logger.warning("Could not remove inactive web data store: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
