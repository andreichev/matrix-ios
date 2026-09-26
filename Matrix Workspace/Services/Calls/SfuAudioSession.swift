import Foundation
import WebRTC

@MainActor
final class SfuAudioSession {
    typealias Command = ([String: JSONValue]) async throws -> JSONValue
    private let command: Command
    private let onError: (String) -> Void
    private let onConnection: (Bool) -> Void
    private let callId: String
    private let systemManagedAudio: Bool
    private var worker: MediaWorker?
    private var capabilities: JSONValue = .null
    private var connected: [String: Task<Void, Error>] = [:]
    private var recovery: [String: Task<Void, Never>] = [:]
    private var consumers = Set<String>()
    private var producerId: String?
    private var sendId: String?
    private var closed = false
    private var syncing = false
    private var latest: CallSnapshot?
    private var iceServers: JSONValue

    init(
        callId: String, iceServers: JSONValue, systemManagedAudio: Bool = false, command: @escaping Command,
        onError: @escaping (String) -> Void, onConnection: @escaping (Bool) -> Void
    ) {
        self.callId = callId
        self.iceServers = iceServers
        self.systemManagedAudio = systemManagedAudio
        self.command = command
        self.onError = onError
        self.onConnection = onConnection
    }

    private func media(_ operation: String, _ data: [String: JSONValue] = [:]) async throws -> JSONValue {
        guard !closed else { throw CancellationError() }
        return try await command([
            "action": .string("media"), "callId": .string(callId),
            "operation": .string(operation), "data": .object(data),
        ])
    }

    func start(_ call: CallSnapshot, muted: Bool) async throws {
        let worker = MediaWorker(
            connect: { [weak self] id, parameters in
                Task { @MainActor [weak self] in self?.connect(id, parameters: parameters) }
            },
            produce: { [weak self] id, parameters, callback in
                Task { @MainActor [weak self] in
                    guard let self, !self.closed else {
                        callback(nil)
                        return
                    }
                    do {
                        try await self.connected[id]?.value
                        let reply = try await self.media(
                            "produce", ["transportId": .string(id), "rtpParameters": JSONValue.parse(parameters)])
                        callback(reply["id"].string)
                    } catch {
                        callback(nil)
                        if !self.closed { self.onError(error.localizedDescription) }
                    }
                }
            },
            stateChanged: { [weak self] id, state in
                Task { @MainActor [weak self] in self?.transportChanged(id, state: state) }
            })
        self.worker = worker
        capabilities = try await worker.load(capabilities: call.rtpCapabilities, systemManagedAudio: systemManagedAudio)
        try checkOpen()
        let sending = try await media("createTransport", ["direction": .string("send")]).decoded(
            MediaTransportOptions.self)
        let receiving = try await media("createTransport", ["direction": .string("recv")]).decoded(
            MediaTransportOptions.self)
        try checkOpen()
        sendId = sending.id
        producerId = try await worker.start(send: sending, receive: receiving, iceServers: iceServers)
        try checkOpen()
        try await setMuted(muted)
        await sync(call, servers: iceServers)
    }

    private func connect(_ id: String, parameters: String) {
        guard !closed else { return }
        connected[id] = Task {
            do {
                _ = try await media(
                    "connectTransport", ["transportId": .string(id), "dtlsParameters": JSONValue.parse(parameters)])
            } catch {
                if !closed { onError(error.localizedDescription) }
                throw error
            }
        }
    }

    func setMuted(_ muted: Bool) async throws {
        if muted { worker?.track.isEnabled = false }
        guard let producerId else { return }
        _ = try await media("setProducerPaused", ["producerId": .string(producerId), "paused": .bool(muted)])
        try checkOpen()
        worker?.track.isEnabled = !muted
    }

    func sync(_ snapshot: CallSnapshot, servers: JSONValue) async {
        iceServers = servers
        latest = snapshot
        guard !syncing, producerId != nil, !closed else { return }
        syncing = true
        defer { syncing = false }
        while let call = latest, !closed, let worker {
            latest = nil
            let wanted = Set(call.connections.compactMap(\.producer?.id).filter { $0 != producerId })
            for id in consumers.subtracting(wanted) {
                try? await worker.removeConsumer(id)
                consumers.remove(id)
            }
            for id in wanted.subtracting(consumers) {
                do {
                    let options = try await media(
                        "consume", ["producerId": .string(id), "rtpCapabilities": capabilities]
                    ).decoded(MediaConsumerOptions.self)
                    try checkOpen()
                    try await worker.consume(options)
                    _ = try await media("resumeConsumer", ["consumerId": .string(options.id)])
                    try checkOpen()
                    consumers.insert(id)
                } catch {
                    try? await worker.removeConsumer(id)
                    // A peer may leave during negotiation. A later snapshot retries existing peers.
                }
            }
        }
    }

    private func transportChanged(_ id: String, state: MediaConnectionState) {
        guard !closed else { return }
        if id == sendId { onConnection(state == .connected) }
        if state == .connected {
            recovery.removeValue(forKey: id)?.cancel()
        } else if state == .disconnected || state == .failed, recovery[id] == nil {
            recovery[id] = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(5))
                    guard let self else { return }
                    let reply = try await self.media("restartIce", ["transportId": .string(id)])
                    try await self.worker?.restart(id, ice: reply["iceParameters"], servers: self.iceServers)
                    try await Task.sleep(for: .seconds(15))
                    if !self.closed { self.onError("Не удалось восстановить звук. Переподключитесь к звонку.") }
                } catch is CancellationError {} catch {
                    if let self, !self.closed { self.onError(error.localizedDescription) }
                }
                self?.recovery[id] = nil
            }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        worker?.close()
        worker = nil
        connected.values.forEach { $0.cancel() }
        connected.removeAll()
        recovery.values.forEach { $0.cancel() }
        recovery.removeAll()
        latest = nil
    }

    private func checkOpen() throws {
        if closed { throw CancellationError() }
        try Task.checkCancellation()
    }

    #if DEBUG
        func receiveStatistics() async throws -> JSONValue {
            try await worker?.receiveStatistics() ?? .array([])
        }
    #endif
}
