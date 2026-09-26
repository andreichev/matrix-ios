import AVFoundation
import Foundation

struct CallScreenState {
    enum Phase { case ready, joining, active, reconnecting, ended }
    var phase: Phase = .ready
    var online = false
    var connected = false
    var muted = false
    var changingMute = false
    var call: CallSnapshot?
    var error: String?
}

@MainActor
final class CallInteractor {
    private let target: CallTarget
    private let socket: CallSocket
    private var sessionId = UUID().uuidString
    private var callId: String?
    private var media: SfuAudioSession?
    private var state = CallScreenState()
    private var wanted = false
    private var stopped = false
    private var generation = 0
    private var joinTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var muteTask: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    var onChange: ((CallScreenState) -> Void)?

    init(target: CallTarget, auth: AuthService) {
        self.target = target
        socket = CallSocket(auth: auth)
    }

    func start() {
        guard timer == nil, !stopped else { return }
        socket.onConnection = { [weak self] online in
            guard let self, !self.stopped else { return }
            self.state.online = online
            if !online {
                self.invalidateMedia()
                if self.wanted { self.state.phase = .reconnecting }
            }
            self.publish()
            if online {
                if self.wanted { self.join() } else { self.sync() }
            }
        }
        socket.onChanged = { [weak self] in self?.sync() }
        socket.onError = { [weak self] text in
            self?.state.error = text
            self?.publish()
        }
        socket.start()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                self?.sync()
            }
        }
    }

    func join() {
        guard !stopped, socket.isOnline, joinTask == nil, state.phase != .active else { return }
        wanted = true
        invalidateMedia()
        let epoch = generation
        let attemptID = sessionId
        state.phase = .joining
        state.error = nil
        publish()
        joinTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == epoch {
                    self.joinTask = nil
                    if self.state.phase == .active { self.sync() }
                }
            }
            do {
                guard await AVAudioApplication.requestRecordPermission() else {
                    throw MatrixError.message("Разрешите доступ к микрофону в настройках iPhone.")
                }
                try self.check(epoch)
                let discovery = try await self.request(["action": .string("sync")], sessionId: attemptID).decoded(
                    CallsSnapshot.self)
                guard discovery.enabled else {
                    throw MatrixError.message("Звонки недоступны. Обратитесь к администратору.")
                }
                try self.check(epoch)
                let target = self.callId.map(CallTarget.call) ?? self.target
                let call = try await self.request(target.command, sessionId: attemptID).decoded(CallSnapshot.self)
                try self.check(epoch)
                self.callId = call.id
                self.state.call = call
                let media = SfuAudioSession(
                    callId: call.id, iceServers: discovery.iceServers,
                    command: { [socket = self.socket] command in
                        var command = command
                        command["sessionId"] = .string(attemptID)
                        return try await socket.request(command)
                    },
                    onError: { [weak self] text in
                        guard let self, self.generation == epoch, !self.stopped else { return }
                        self.state.error = text
                        self.publish()
                    },
                    onConnection: { [weak self] connected in
                        guard let self, self.generation == epoch, !self.stopped else { return }
                        self.state.connected = connected
                        self.publish()
                    })
                self.media = media
                try await media.start(call, muted: self.state.muted)
                try self.check(epoch)
                self.state.phase = .active
                self.publish()
            } catch {
                guard !self.stopped, self.generation == epoch else { return }
                self.media?.close()
                self.media = nil
                self.wanted = false
                self.state.phase = .ready
                self.state.connected = false
                self.state.error = error.localizedDescription
                self.publish()
                self.sessionId = UUID().uuidString
                Task { [socket = self.socket] in
                    _ = try? await socket.request(["action": .string("cancel"), "sessionId": .string(attemptID)])
                }
            }
        }
    }

    func retry() {
        guard !stopped else { return }
        state.phase = .ready
        join()
    }

    func toggleMute() {
        guard !stopped, !state.changingMute, state.phase == .active, let media else { return }
        let muted = !state.muted
        if muted { state.muted = true }
        state.changingMute = true
        let epoch = generation
        publish()
        muteTask = Task { [weak self] in
            do {
                try await media.setMuted(muted)
                guard let self, self.generation == epoch else { return }
                self.state.muted = muted
            } catch { if self?.generation == epoch { self?.state.error = error.localizedDescription } }
            guard let self, self.generation == epoch else { return }
            self.state.changingMute = false
            self.publish()
        }
    }

    func sync() {
        guard !stopped, socket.isOnline, syncTask == nil, joinTask == nil else { return }
        let epoch = generation
        syncTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == epoch { self.syncTask = nil } }
            do {
                let result = try await self.request(["action": .string("sync")]).decoded(CallsSnapshot.self)
                try self.check(epoch)
                guard result.enabled else {
                    self.stop(message: "Звонки недоступны. Обратитесь к администратору.")
                    return
                }
                let call = result.calls.first { call in
                    if let id = self.callId { return call.id == id }
                    switch self.target {
                    case .call(let id): return call.id == id
                    case .chat(let id): return call.chatId == id
                    }
                }
                if (call == nil && self.callId != nil) || (self.media != nil && call?.joinedHere != true) {
                    self.stop(message: "Звонок завершён или доступ отозван.")
                    return
                }
                if case .call = self.target, call == nil {
                    self.stop(message: "Звонок завершён.")
                    return
                }
                self.state.call = call
                self.publish()
                if let call { await self.media?.sync(call, servers: result.iceServers) }
            } catch {
                if !self.stopped, self.generation == epoch {
                    self.state.error = error.localizedDescription
                    self.publish()
                }
            }
        }
    }

    func stop(message: String? = nil) {
        guard !stopped else { return }
        stopped = true
        wanted = false
        invalidateMedia()
        timer?.cancel()
        timer = nil
        socket.onConnection = nil
        socket.onChanged = nil
        socket.onError = nil
        state.phase = .ended
        state.error = message
        publish()
        let id = sessionId
        Task { [socket] in
            _ = try? await socket.request(["action": .string("cancel"), "sessionId": .string(id)])
            socket.stop()
        }
    }

    private func request(_ command: [String: JSONValue], sessionId: String? = nil) async throws -> JSONValue {
        var command = command
        command["sessionId"] = .string(sessionId ?? self.sessionId)
        return try await socket.request(command)
    }
    private func invalidateMedia() {
        generation += 1
        joinTask?.cancel()
        joinTask = nil
        syncTask?.cancel()
        syncTask = nil
        muteTask?.cancel()
        muteTask = nil
        media?.close()
        media = nil
        state.connected = false
        state.changingMute = false
    }
    private func check(_ epoch: Int) throws {
        if stopped || epoch != generation { throw CancellationError() }
        try Task.checkCancellation()
    }
    private func publish() { onChange?(state) }
}
