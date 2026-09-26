import AVFoundation
import Foundation
import Mediasoup
import WebRTC

enum MediaConnectionState: Sendable {
    case connecting, connected, disconnected, failed, closed

    init(_ state: TransportConnectionState) {
        switch state {
        case .new, .checking: self = .connecting
        case .connected, .completed: self = .connected
        case .disconnected: self = .disconnected
        case .failed: self = .failed
        case .closed: self = .closed
        @unknown default: self = .failed
        }
    }
}

// libmediasoupclient can block while waiting for signaling callbacks. Keep all native
// operations on one queue, never MainActor; callbacks return through the socket asynchronously.
final class MediaWorker: SendTransportDelegate, ReceiveTransportDelegate, @unchecked Sendable {
    private static let queue = DispatchQueue(label: "matrix.calls.media", qos: .userInitiated)
    private static let initializeSSL: Void = { RTCInitializeSSL() }()
    private let factory: RTCPeerConnectionFactory
    let track: RTCAudioTrack
    private var device: Device?
    private var send: SendTransport?
    private var receive: ReceiveTransport?
    private var producer: Producer?
    private var consumers: [String: Consumer] = [:]
    private var closed = false
    private var audioActive = false

    let connect: @Sendable (String, String) -> Void
    let produce: @Sendable (String, String, @escaping (String?) -> Void) -> Void
    let stateChanged: @Sendable (String, MediaConnectionState) -> Void

    init(
        connect: @escaping @Sendable (String, String) -> Void,
        produce: @escaping @Sendable (String, String, @escaping (String?) -> Void) -> Void,
        stateChanged: @escaping @Sendable (String, MediaConnectionState) -> Void
    ) {
        _ = Self.initializeSSL
        factory = RTCPeerConnectionFactory()
        track = factory.audioTrack(withTrackId: UUID().uuidString)
        track.isEnabled = false
        self.connect = connect
        self.produce = produce
        self.stateChanged = stateChanged
    }

    private func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    func load(capabilities: JSONValue, systemManagedAudio: Bool = false) async throws -> JSONValue {
        try await perform {
            guard !self.closed else { throw CancellationError() }
            if !systemManagedAudio {
                let audio = RTCAudioSession.sharedInstance()
                audio.lockForConfiguration()
                defer { audio.unlockForConfiguration() }
                audio.useManualAudio = false
                let config = RTCAudioSessionConfiguration.webRTC()
                config.category = AVAudioSession.Category.playAndRecord.rawValue
                config.mode = AVAudioSession.Mode.voiceChat.rawValue
                config.categoryOptions = [.allowBluetoothHFP]
                try audio.setConfiguration(config, active: true)
                self.audioActive = true
            }
            let device = Device(pcFactory: self.factory)
            self.device = device
            try device.load(with: capabilities.json())
            guard try device.canProduce(.audio) else {
                throw MatrixError.message("Устройство не поддерживает аудиозвонки.")
            }
            return try JSONValue.parse(device.rtpCapabilities())
        }
    }

    func start(send options: MediaTransportOptions, receive receiving: MediaTransportOptions, iceServers: JSONValue)
        async throws -> String
    {
        try await perform {
            guard !self.closed, let device = self.device else { throw CancellationError() }
            let send = try device.createSendTransport(
                id: options.id, iceParameters: options.iceParameters.json(),
                iceCandidates: options.iceCandidates.json(), dtlsParameters: options.dtlsParameters.json(),
                sctpParameters: nil, iceServers: iceServers.json(), appData: nil)
            self.send = send
            send.delegate = self
            let receive = try device.createReceiveTransport(
                id: receiving.id, iceParameters: receiving.iceParameters.json(),
                iceCandidates: receiving.iceCandidates.json(), dtlsParameters: receiving.dtlsParameters.json(),
                iceServers: iceServers.json())
            self.receive = receive
            receive.delegate = self
            let producer = try send.createProducer(
                for: self.track, encodings: nil,
                codecOptions: "{\"opusStereo\":false,\"opusDtx\":true,\"opusFec\":true}", codec: nil, appData: nil)
            self.producer = producer
            return producer.id
        }
    }

    func consume(_ options: MediaConsumerOptions) async throws {
        try await perform {
            guard !self.closed, let receive = self.receive else { throw CancellationError() }
            let consumer = try receive.consume(
                consumerId: options.id, producerId: options.producerId,
                kind: .audio, rtpParameters: options.rtpParameters.json(), appData: nil)
            self.consumers[options.producerId] = consumer
        }
    }

    func removeConsumer(_ id: String) async throws {
        try await perform { self.consumers.removeValue(forKey: id)?.close() }
    }

    func restart(_ id: String, ice: JSONValue, servers: JSONValue) async throws {
        try await perform {
            guard !self.closed else { throw CancellationError() }
            let transport: Transport? = self.send?.id == id ? self.send : self.receive
            guard let transport, transport.id == id else { return }
            try transport.updateICEServers(servers.json())
            try transport.restartICE(with: ice.json())
        }
    }

    func close() {
        // Disable capture immediately, even when the worker is waiting for a producer reply.
        track.isEnabled = false
        Self.queue.async {
            guard !self.closed else { return }
            self.closed = true
            self.producer?.close()
            self.consumers.values.forEach { $0.close() }
            self.consumers.removeAll()
            self.send?.close()
            self.receive?.close()
            self.producer = nil
            self.send = nil
            self.receive = nil
            self.device = nil
            if self.audioActive {
                let audio = RTCAudioSession.sharedInstance()
                audio.lockForConfiguration()
                try? audio.setActive(false)
                audio.unlockForConfiguration()
                self.audioActive = false
            }
        }
    }

    #if DEBUG
        func receiveStatistics() async throws -> JSONValue {
            try await perform { try JSONValue.parse(self.receive?.stats ?? "[]") }
        }
    #endif

    func onConnect(transport: Transport, dtlsParameters: String) { connect(transport.id, dtlsParameters) }
    func onConnectionStateChange(transport: Transport, connectionState: TransportConnectionState) {
        stateChanged(transport.id, MediaConnectionState(connectionState))
    }
    func onProduce(
        transport: Transport, kind: MediaKind, rtpParameters: String, appData: String,
        callback: @escaping (String?) -> Void
    ) {
        produce(transport.id, rtpParameters, callback)
    }
    func onProduceData(
        transport: Transport, sctpParameters: String, label: String, protocol dataProtocol: String,
        appData: String, callback: @escaping (String?) -> Void
    ) { callback(nil) }
}
