import Foundation

@MainActor
final class CallSocket {
    private struct Pending {
        let continuation: CheckedContinuation<JSONValue, Error>
        let timeout: Task<Void, Never>
    }

    private let auth: AuthService
    private var socket: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var pending: [String: Pending] = [:]
    private var generation = 0
    private var pongAt = Date.distantPast
    private(set) var isOnline = false
    var onConnection: ((Bool) -> Void)?
    var onChanged: (() -> Void)?
    var onError: ((String) -> Void)?

    init(auth: AuthService) { self.auth = auth }

    func start() {
        guard connectionTask == nil else { return }
        generation += 1
        let epoch = generation
        connectionTask = Task { [weak self] in
            var delay = 1
            while !Task.isCancelled {
                guard let self, self.generation == epoch else { return }
                do {
                    try await self.runConnection(epoch: epoch)
                } catch {
                    if self.generation != epoch || Task.isCancelled { return }
                    self.onError?(error.localizedDescription)
                }
                self.disconnect()
                guard self.auth.current != nil, self.generation == epoch else { return }
                try? await Task.sleep(for: .seconds(delay))
                delay = min(delay * 2, 15)
            }
        }
    }

    func stop() {
        generation += 1
        connectionTask?.cancel()
        connectionTask = nil
        disconnect()
    }

    func request(_ command: [String: JSONValue]) async throws -> JSONValue {
        try Task.checkCancellation()
        guard isOnline, let socket else { throw MatrixError.message("Нет соединения с сервером.") }
        guard pending.count < 32 else { throw MatrixError.message("Слишком много действий звонка.") }
        let id = UUID().uuidString
        var payload = command
        payload["commandId"] = .string(id)
        let frame = try JSONValue.object(["type": .string("call"), "payload": .object(payload)]).json()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(20)) } catch { return }
                    self?.finish(id, result: .failure(MatrixError.message("Сервер звонков не ответил.")))
                }
                pending[id] = Pending(continuation: continuation, timeout: timeout)
                Task { [weak self] in
                    do { try await socket.send(.string(frame)) } catch { self?.finish(id, result: .failure(error)) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, result: .failure(CancellationError())) }
        }
    }

    private func runConnection(epoch: Int) async throws {
        let token = try await auth.accessToken()
        guard generation == epoch, let server = auth.current?.server else { throw CancellationError() }
        let task = auth.http.session.webSocketTask(with: server.socketRequest(token: token))
        socket = task
        task.maximumMessageSize = 2 * 1024 * 1024
        task.resume()
        try await task.send(.string("{\"type\":\"ping\",\"payload\":null}"))
        guard generation == epoch else { throw CancellationError() }
        pongAt = Date()
        isOnline = true
        onConnection?(true)
        heartbeatTask = Task { [weak self, weak task] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(25)) } catch { return }
                guard let self, let task, self.generation == epoch else { return }
                do {
                    let sent = Date()
                    try await task.send(.string("{\"type\":\"ping\",\"payload\":null}"))
                    try await Task.sleep(for: .seconds(10))
                    if self.pongAt < sent {
                        task.cancel(with: .goingAway, reason: nil)
                        return
                    }
                } catch {
                    task.cancel(with: .goingAway, reason: nil)
                    return
                }
            }
        }
        do {
            while !Task.isCancelled {
                let frame = try await task.receive()
                guard generation == epoch else { return }
                let data: Data
                switch frame {
                case .string(let text): data = Data(text.utf8)
                case .data(let bytes): data = bytes
                @unknown default: continue
                }
                let message = try JSONDecoder().decode(JSONValue.self, from: data)
                handle(message)
            }
        } catch {
            if task.closeCode == .policyViolation, generation == epoch {
                _ = try await auth.accessToken(forceRefresh: true)
            }
            throw error
        }
    }

    private func handle(_ message: JSONValue) {
        switch message["type"].string {
        case "pong": pongAt = Date()
        case "calls_changed": onChanged?()
        case "call_reply":
            let payload = message["payload"]
            guard let id = payload["commandId"].string else { return }
            if payload["ok"].bool == true {
                finish(id, result: .success(payload["data"]))
            } else {
                finish(id, result: .failure(MatrixError.message(payload["message"].string ?? "Ошибка звонка.")))
            }
        default: break
        }
    }

    private func finish(_ id: String, result: Result<JSONValue, Error>) {
        guard let item = pending.removeValue(forKey: id) else { return }
        item.timeout.cancel()
        item.continuation.resume(with: result)
    }

    private func disconnect() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        for id in Array(pending.keys) { finish(id, result: .failure(MatrixError.message("Связь прервана."))) }
        if isOnline {
            isOnline = false
            onConnection?(false)
        }
    }
}
