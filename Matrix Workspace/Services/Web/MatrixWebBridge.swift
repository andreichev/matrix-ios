import WebKit

@MainActor
final class MatrixWebBridge: NSObject, @preconcurrency WKScriptMessageHandlerWithReply {
    let server: ServerAddress
    private let auth: AuthService
    private let calls: NativeCallCoordinator
    private let sessionId: UUID?

    init(server: ServerAddress, auth: AuthService, calls: NativeCallCoordinator) {
        self.server = server; self.auth = auth; self.calls = calls; self.sessionId = auth.current?.id
    }

    func isApplication(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == server.url.scheme && url.host == server.url.host && url.port == server.url.port
            && url.user == nil && url.password == nil && url.path.hasPrefix("/matrix-mobile/")
    }

    func applicationURL(route: String = "/") -> URL {
        var route = route
        for prefix in ["/matrix-mobile", "/matrix-crm"] where route == prefix || route.hasPrefix(prefix + "/") {
            route = String(route.dropFirst(prefix.count))
        }
        guard route.hasPrefix("/"), !route.hasPrefix("//"), !route.contains("\\"),
            let url = URL(string: "/matrix-mobile" + route, relativeTo: server.url)?.absoluteURL,
            isApplication(url.standardized) else { return server.endpoint("matrix-mobile/") }
        return url
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, isApplication(message.frameInfo.request.url),
            isApplication(message.webView?.url), auth.current?.id == sessionId,
            let body = message.body as? [String: Any], let action = body["action"] as? String else {
            replyHandler(nil, "Недопустимый источник запроса")
            return
        }
        Task { [auth, calls] in
            do {
                switch action {
                case "token":
                    let token = try await auth.accessToken(forceRefresh: body["forceRefresh"] as? Bool == true)
                    guard auth.current?.id == self.sessionId, self.isApplication(message.webView?.url) else { throw CancellationError() }
                    replyHandler(["accessToken": token, "expiresAt": auth.current?.tokens.expiresAt ?? ""], nil)
                case "logout":
                    try await auth.logout()
                    replyHandler(true, nil)
                case "openCall":
                    if let value = body["chatId"] as? String, let id = UUID(uuidString: value) {
                        calls.open(.chat(id.uuidString.lowercased()))
                    } else if let value = body["callId"] as? String, let id = UUID(uuidString: value) {
                        calls.open(.call(id.uuidString.lowercased()))
                    } else { throw MatrixError.message("Некорректный звонок") }
                    replyHandler(true, nil)
                default: replyHandler(nil, "Неизвестная команда")
                }
            } catch { replyHandler(nil, error.localizedDescription) }
        }
    }
}
