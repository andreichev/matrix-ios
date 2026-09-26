import AVFoundation
import CallKit
import OSLog
import WebRTC

@MainActor
protocol SystemCallDelegate: AnyObject {
    func systemCallDidEnd()
    func systemCallSetMuted(_ muted: Bool) async throws
    func systemCallAudioRouteChanged(speakerEnabled: Bool)
    func systemCallAnswer()
}

// One provider for the application; signaling and media belong to the active CallInteractor.
@MainActor
final class SystemCallService: NSObject, @preconcurrency CXProviderDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Matrix", category: "CallKit")
    private let provider: CXProvider
    private let controller = CXCallController()
    private weak var delegate: SystemCallDelegate?
    private var callID: UUID?
    private var ending = false
    private var connected = false
    private var incoming = false
    private var answerAction: CXAnswerCallAction?
    private var pendingStart: CheckedContinuation<Void, Error>?
    private var muteTask: Task<Void, Never>?
    private var muteAction: CXSetMutedCallAction?
    private var pendingMute: (id: UUID, continuation: CheckedContinuation<Void, Error>)?
    private var routeObserver: NSObjectProtocol?

    var isSpeakerEnabled: Bool {
        RTCAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
    }

    var usesSystemAudio: Bool {
        #if targetEnvironment(simulator)
            return false
        #else
            return true
        #endif
    }

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportedHandleTypes = [.generic]
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportsVideo = false
        // Recents redial needs separate routing, which is not implemented yet.
        configuration.includesCallsInRecents = false
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: .main)
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.notifyAudioRoute() }
        }
    }

    deinit {
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    }

    func setSpeaker(id: UUID, enabled: Bool) throws {
        guard callID == id, !ending else { throw CancellationError() }
        let audio = RTCAudioSession.sharedInstance()
        audio.lockForConfiguration()
        defer { audio.unlockForConfiguration() }
        try audio.overrideOutputAudioPort(enabled ? .speaker : .none)
        notifyAudioRoute()
    }

    private func notifyAudioRoute() {
        guard callID != nil, !ending else { return }
        delegate?.systemCallAudioRouteChanged(speakerEnabled: isSpeakerEnabled)
    }

    func start(id: UUID, title: String, delegate: SystemCallDelegate) async throws {
        try Task.checkCancellation()
        if callID == id, !ending { return }
        guard callID == nil else { throw MatrixError.message("Сначала завершите текущий звонок.") }
        if usesSystemAudio { try configureAudio() }
        callID = id
        self.delegate = delegate
        guard usesSystemAudio else { return }
        let action = CXStartCallAction(call: id, handle: CXHandle(type: .generic, value: title))
        action.isVideo = false
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingStart = continuation
                controller.request(CXTransaction(action: action)) { [weak self] error in
                    Task { @MainActor in
                        guard let self, self.callID == id, let error else { return }
                        self.clear(error: self.transactionError(error, operation: "start"))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.end(id: id) }
        }
    }

    func reportIncoming(_ invitation: IncomingCall?, delegate: SystemCallDelegate?, completion: @escaping (Bool) -> Void) {
        let id = invitation?.id ?? UUID()
        let update = CXCallUpdate()
        update.localizedCallerName = delegate == nil ? "Матрица" : invitation?.title ?? "Матрица"
        update.remoteHandle = CXHandle(type: .generic, value: update.localizedCallerName ?? "Матрица")
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        let accepted = callID == nil && delegate != nil
        let duplicate = callID == id
        if accepted {
            callID = id
            self.delegate = delegate
            incoming = true
        }
        // Every VoIP push is reported, before validation/network work. A duplicate UUID
        // is rejected by CallKit without replacing the existing call or its delegate.
        provider.reportNewIncomingCall(with: id, update: update) { [weak self] error in
            Task { @MainActor in
                guard let self else { completion(false); return }
                if let error {
                    self.logger.error("Incoming CallKit report failed: \((error as NSError).code)")
                    if accepted, self.callID == id { self.clear(error: error) }
                    completion(false)
                } else if !accepted || self.callID != id {
                    if !duplicate { self.provider.reportCall(with: id, endedAt: Date(), reason: .failed) }
                    completion(false)
                } else {
                    completion(true)
                }
            }
        }
    }

    func answer(id: UUID) async throws {
        guard callID == id, incoming, !ending else { throw CancellationError() }
        try await controller.request(CXTransaction(action: CXAnswerCallAction(call: id)))
    }

    func reportConnected(id: UUID) {
        guard callID == id, !ending, !connected else { return }
        connected = true
        if incoming {
            answerAction?.fulfill(withDateConnected: Date())
            answerAction = nil
        } else if usesSystemAudio {
            provider.reportOutgoingCall(with: id, connectedAt: Date())
        }
    }

    func updateTitle(id: UUID, title: String) {
        guard callID == id, !ending, usesSystemAudio else { return }
        let update = CXCallUpdate()
        update.localizedCallerName = title
        provider.reportCall(with: id, updated: update)
    }

    func setMuted(id: UUID, muted: Bool) async throws {
        guard callID == id, !ending else { throw CancellationError() }
        if !usesSystemAudio {
            guard let delegate else { throw CancellationError() }
            try await delegate.systemCallSetMuted(muted)
            return
        }
        guard pendingMute == nil, muteTask == nil else {
            throw MatrixError.message("Дождитесь изменения микрофона.")
        }
        let action = CXSetMutedCallAction(call: id, muted: muted)
        try await withCheckedThrowingContinuation { continuation in
            pendingMute = (action.uuid, continuation)
            controller.request(CXTransaction(action: action)) { [weak self] error in
                Task { @MainActor in
                    guard let self, let error else { return }
                    self.finishMute(id: action.uuid, result: .failure(self.transactionError(error, operation: "mute")))
                }
            }
        }
    }

    func end(id: UUID, reason: CXCallEndedReason? = nil) {
        guard callID == id else { return }
        guard usesSystemAudio else {
            clear()
            return
        }
        if let reason {
            provider.reportCall(with: id, endedAt: Date(), reason: reason)
            clear()
            return
        }
        guard !ending else { return }
        ending = true
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        pendingStart?.resume(throwing: CancellationError())
        pendingStart = nil
        controller.request(CXTransaction(action: CXEndCallAction(call: id))) { [weak self] error in
            Task { @MainActor in
                guard let self, self.callID == id, let error else { return }
                _ = self.transactionError(error, operation: "end")
                self.provider.reportCall(with: id, endedAt: Date(), reason: .failed)
                let delegate = self.delegate
                self.clear()
                delegate?.systemCallDidEnd()
            }
        }
    }

    private func transactionError(_ error: Error, operation: String) -> Error {
        let error = error as NSError
        logger.error("Transaction \(operation, privacy: .public) failed: \(error.domain, privacy: .public), code \(error.code)")
        if error.domain == CXErrorDomainRequestTransaction,
            error.code == CXErrorCodeRequestTransactionError.Code.unentitled.rawValue {
            return MatrixError.message("iOS не разрешила звонок. Проверьте Background Modes → Voice over IP и подпись приложения в Xcode.")
        }
        return error
    }

    private func configureAudio() throws {
        let audio = RTCAudioSession.sharedInstance()
        audio.useManualAudio = true
        audio.isAudioEnabled = false
        audio.lockForConfiguration()
        defer { audio.unlockForConfiguration() }
        let configuration = RTCAudioSessionConfiguration.webRTC()
        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.mode = AVAudioSession.Mode.voiceChat.rawValue
        configuration.categoryOptions = [.allowBluetoothHFP]
        // CallKit activates the session; do not call setActive here or in MediaWorker.
        try audio.setConfiguration(configuration)
    }

    private func clear(error: Error = CancellationError()) {
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        callID = nil
        delegate = nil
        ending = false
        connected = false
        incoming = false
        if let answerAction, !answerAction.isComplete { answerAction.fail() }
        answerAction = nil
        pendingStart?.resume(throwing: error)
        pendingStart = nil
        muteTask?.cancel()
        muteTask = nil
        if let muteAction, !muteAction.isComplete { muteAction.fail() }
        muteAction = nil
        if let pendingMute { finishMute(id: pendingMute.id, result: .failure(error)) }
    }

    private func finishMute(id: UUID, result: Result<Void, Error>) {
        guard let pendingMute, pendingMute.id == id else { return }
        self.pendingMute = nil
        pendingMute.continuation.resume(with: result)
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        guard action.callUUID == callID, !ending, pendingStart != nil else {
            action.fail()
            return
        }
        let update = CXCallUpdate()
        update.localizedCallerName = action.handle.value
        update.remoteHandle = action.handle
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        provider.reportCall(with: action.callUUID, updated: update)
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        action.fulfill()
        pendingStart?.resume()
        pendingStart = nil
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard action.callUUID == callID else {
            action.fail()
            return
        }
        let delegate = delegate
        clear()
        delegate?.systemCallDidEnd()
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard action.callUUID == callID, incoming, !ending, answerAction == nil, let delegate else {
            action.fail()
            return
        }
        do {
            try configureAudio()
            answerAction = action
            delegate.systemCallAnswer()
        } catch {
            action.fail()
            end(id: action.callUUID, reason: .failed)
            delegate.systemCallDidEnd()
        }
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard action.callUUID == callID, !ending, muteTask == nil, let delegate else {
            action.fail()
            finishMute(id: action.uuid, result: .failure(MatrixError.message("Микрофон сейчас недоступен.")))
            return
        }
        muteAction = action
        muteTask = Task { [weak self] in
            do {
                try await delegate.systemCallSetMuted(action.isMuted)
                guard !Task.isCancelled, !action.isComplete else { return }
                action.fulfill()
                self?.finishMute(id: action.uuid, result: .success(()))
            } catch {
                if !Task.isCancelled, !action.isComplete {
                    action.fail()
                    self?.finishMute(id: action.uuid, result: .failure(error))
                }
            }
            guard !Task.isCancelled else { return }
            self?.muteAction = nil
            self?.muteTask = nil
        }
    }

    func providerDidReset(_ provider: CXProvider) {
        let delegate = delegate
        clear()
        delegate?.systemCallDidEnd()
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        guard let action = action as? CXCallAction, action.callUUID == callID else { return }
        // A timed-out action must not be fulfilled or failed again.
        if action.uuid == muteAction?.uuid { muteAction = nil }
        if action.uuid == answerAction?.uuid { answerAction = nil }
        let delegate = delegate
        end(id: action.callUUID, reason: .failed)
        delegate?.systemCallDidEnd()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        let audio = RTCAudioSession.sharedInstance()
        audio.audioSessionDidActivate(audioSession)
        audio.isAudioEnabled = callID != nil && !ending
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        let audio = RTCAudioSession.sharedInstance()
        audio.isAudioEnabled = false
        audio.audioSessionDidDeactivate(audioSession)
    }
}
