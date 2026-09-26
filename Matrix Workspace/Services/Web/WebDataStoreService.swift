import OSLog
import WebKit

@MainActor
enum WebDataStoreService {
    private static let logger = Logger(subsystem: "com.andreichev.matrix", category: "WebDataStore")

    static func clearInactiveStores(auth: AuthService) {
        Task {
            let identifiers = await WKWebsiteDataStore.allDataStoreIdentifiers
            for identifier in identifiers {
                // Recheck after suspension: the user may already have signed in again.
                guard identifier != auth.current?.id else { continue }
                await WKWebsiteDataStore(forIdentifier: identifier).removeData(
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
                do {
                    try await WKWebsiteDataStore.remove(forIdentifier: identifier)
                } catch {
                    // An old WebView can still be releasing. Its data is cleared; retry removal on next launch.
                    logger.warning("Could not remove inactive web data store: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
