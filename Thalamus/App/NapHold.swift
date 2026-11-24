import Foundation
import Observation

@MainActor
final class NapHold {
    static let shared = NapHold()

    private let begin: () -> NSObjectProtocol
    private let end: (NSObjectProtocol) -> Void
    private var thinkingSessions: Set<UUID> = []
    private var activity: NSObjectProtocol?

    init(begin: @escaping () -> NSObjectProtocol = {
             ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                   reason: "Sessão em Pensando")
         },
         end: @escaping (NSObjectProtocol) -> Void = { ProcessInfo.processInfo.endActivity($0) }) {
        self.begin = begin
        self.end = end
    }

    var isHeld: Bool { activity != nil }

    func watch(_ chat: ChatModel) {
        let session = chat.sessionID
        withObservationTracking {
            update(chat.sessionStates, of: session)
        } onChange: { [weak self, weak chat] in
            let (hold, changed) = (self, chat)
            Task { @MainActor in
                guard let changed else { return hold?.update([], of: session) }
                hold?.watch(changed)
            }
        }
    }

    func update(_ states: Set<SessionState>, of session: UUID) {
        if states.contains(.thinking), states.isDisjoint(with: [.awaitingDecision, .outOfTokens]) {
            thinkingSessions.insert(session)
        } else {
            thinkingSessions.remove(session)
        }
        settle()
    }

    func release() {
        thinkingSessions.removeAll()
        settle()
    }

    private func settle() {
        if !thinkingSessions.isEmpty, activity == nil {
            activity = begin()
        } else if thinkingSessions.isEmpty, let activity {
            end(activity)
            self.activity = nil
        }
    }
}
