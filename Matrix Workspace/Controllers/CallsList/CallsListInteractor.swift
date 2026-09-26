import Foundation

struct CallsListState {
    var chats: [ChatSummary] = []
    var calls: [CallSnapshot] = []
    var online = false
    var enabled: Bool?
    var error: String?
}

@MainActor
final class CallsListInteractor {
    private let auth: AuthService
    private let socket: CallSocket
    private var state = CallsListState()
    private var chatsTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    var onChange: ((CallsListState) -> Void)?

    init(auth: AuthService) {
        self.auth = auth
        socket = CallSocket(auth: auth)
    }

    func start() {
        guard timer == nil else { return }
        socket.onConnection = { [weak self] online in
            guard let self else { return }
            self.state.online = online
            self.state.enabled = nil
            self.onChange?(self.state)
            if online { self.sync() }
        }
        socket.onChanged = { [weak self] in self?.sync() }
        socket.onError = { [weak self] text in
            self?.state.error = text
            if let self { self.onChange?(self.state) }
        }
        socket.start()
        refresh()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                self?.sync()
            }
        }
    }
    func stop() {
        timer?.cancel()
        timer = nil
        chatsTask?.cancel()
        chatsTask = nil
        syncTask?.cancel()
        syncTask = nil
        socket.stop()
    }
    func refresh() {
        guard chatsTask == nil else { return }
        chatsTask = Task { [weak self, auth] in
            do {
                let response = try await auth.get("api/v1/messages/chats", as: ChatsResponse.self)
                try Task.checkCancellation()
                self?.state.chats = response.items
            } catch { if !Task.isCancelled { self?.state.error = error.localizedDescription } }
            guard !Task.isCancelled, let self else { return }
            self.chatsTask = nil
            self.onChange?(self.state)
        }
        sync()
    }
    private func sync() {
        guard syncTask == nil, socket.isOnline else { return }
        syncTask = Task { [weak self, socket] in
            do {
                let response = try await socket.request(["action": .string("sync")]).decoded(CallsSnapshot.self)
                try Task.checkCancellation()
                self?.state.calls = response.calls
                self?.state.enabled = response.enabled
                self?.state.error = nil
            } catch { if !Task.isCancelled { self?.state.error = error.localizedDescription } }
            guard !Task.isCancelled, let self else { return }
            self.syncTask = nil
            self.onChange?(self.state)
        }
    }
    func logout() async throws {
        stop()
        try await auth.logout()
    }
}
