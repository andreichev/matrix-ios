import Foundation

@MainActor
final class NativeCallCoordinator {
    private let auth: AuthService
    private let systemCalls: SystemCallService
    private var seen: [UUID: Date] = [:]
    private(set) var active: CallInteractor?
    var onOpen: ((CallInteractor) -> Void)?

    init(auth: AuthService, systemCalls: SystemCallService) {
        self.auth = auth
        self.systemCalls = systemCalls
    }

    func open(_ target: CallTarget) {
        let call = active ?? make(target: target)
        onOpen?(call)
    }

    func receive(_ invitation: IncomingCall?, completion: @escaping () -> Void) {
        seen = seen.filter { $0.value > Date() }
        if let invitation, invitation.sessionId == auth.current?.id, invitation.expiresAt > Date(),
            seen[invitation.id] == nil, active?.state.phase == .ready {
            active?.stop()
        }
        guard let invitation, invitation.sessionId == auth.current?.id, invitation.expiresAt > Date(),
            active == nil, seen[invitation.id] == nil else {
            systemCalls.reportIncoming(invitation, delegate: nil) { _ in completion() }
            return
        }
        seen[invitation.id] = Date().addingTimeInterval(300)
        let call = make(target: .call(invitation.id.uuidString.lowercased()), incoming: invitation)
        // Report to CallKit before starting network/auth work, even for stale invitations.
        systemCalls.reportIncoming(invitation, delegate: call) { [weak call] accepted in
            completion()
            if !accepted { call?.stop() }
        }
        call.start()
    }

    func stop() { active?.stop() }

    private func make(target: CallTarget, incoming: IncomingCall? = nil) -> CallInteractor {
        let call = CallInteractor(target: target, auth: auth, systemCalls: systemCalls, incoming: incoming)
        active = call
        call.onStopped = { [weak self, weak call] in
            if self?.active === call { self?.active = nil }
        }
        call.onAnswered = { [weak self, weak call] in
            guard let call else { return }
            self?.onOpen?(call)
        }
        return call
    }
}
