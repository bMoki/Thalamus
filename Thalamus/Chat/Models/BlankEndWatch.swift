import Foundation
import os

@MainActor
final class BlankEndWatch {
    enum Event: String {
        case opened = "abrir a Sessão"
        case streamingChunk = "pedaço de streaming"
        case turnEnded = "fim de turno"
        case returnToReading = "scrollTo do ponto de leitura"
        case jumpToEnd = "scrollTo do fim"
        case followEnd = "scrollTo seguindo o fim"
    }

    nonisolated static let defaultWait: Duration = .milliseconds(500)

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Thalamus",
                                       category: "transcript")

    private let wait: Duration?
    private let report: @MainActor (String) -> Void
    private var lastEvent = Event.opened
    private var rows = 0
    private var messages = 0
    private var live = 0
    private var atEnd = true
    private var suspect: (session: UUID, event: Event)?
    private var reported = false
    private var timer: Task<Void, Never>?

    init(wait: Duration? = BlankEndWatch.defaultWait,
         report: (@MainActor (String) -> Void)? = nil) {
        self.wait = wait
        self.report = report ?? { BlankEndWatch.log($0) }
    }

    private static func log(_ message: String) {
        guard isDebugBuild else { return }
        logger.error("\(message, privacy: .public)")
    }

    func happened(_ event: Event) {
        lastEvent = event
    }

    func see(rows visible: Int, of total: Int, in session: UUID) {
        rows = visible
        messages = total
        evaluate(session)
    }

    func see(live visible: Int, in session: UUID) {
        live = visible
        evaluate(session)
    }

    func see(atEnd: Bool, in session: UUID) {
        self.atEnd = atEnd
        evaluate(session)
    }

    func confirm() {
        guard let suspect, isBlank, !reported else { return }
        reported = true
        report("transcript em branco no fim da Sessão \(suspect.session.uuidString), "
               + "com \(messages) mensagens, depois de: \(suspect.event.rawValue)")
    }

    private var isBlank: Bool {
        atEnd && messages > 0 && rows == 0 && live == 0
    }

    private func evaluate(_ session: UUID) {
        guard isBlank else {
            suspect = nil
            reported = false
            timer?.cancel()
            timer = nil
            return
        }
        guard suspect == nil else { return }
        suspect = (session, lastEvent)
        guard let wait else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.confirm()
        }
    }
}
