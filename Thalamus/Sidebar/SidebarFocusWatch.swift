import Foundation
import Observation

@MainActor
@Observable
final class SidebarFocusWatch {
    @ObservationIgnored private let log: DiagnosticsLog
    @ObservationIgnored private let confirmAfter: Duration
    @ObservationIgnored private var focused: [UUID: String] = [:]
    @ObservationIgnored private var recentEvents: [String] = []
    @ObservationIgnored private var lastReported: [String] = []
    @ObservationIgnored private var isChecking = false

    private static let eventsKept = 30

    init(log: DiagnosticsLog, confirmAfter: Duration = .seconds(1)) {
        self.log = log
        self.confirmAfter = confirmAfter
    }

    func update(_ instance: UUID, row: String, isFocused: Bool) {
        guard (focused[instance] != nil) != isFocused else { return }
        focused[instance] = isFocused ? Self.label(row, instance) : nil
        record("\(Self.label(row, instance)) \(isFocused ? "em foco" : "sem foco")")
        scheduleCheck()
    }

    func remove(_ instance: UUID) {
        guard let label = focused.removeValue(forKey: instance) else { return }
        record("\(label) saiu da lista")
        scheduleCheck()
    }

    func focusMoved(to row: SidebarRow?) {
        record("foco: \(row.map { String(describing: $0) } ?? "nenhum")")
    }

    func rowsShown(_ ids: [String]) {
        record("linhas: \(ids.joined(separator: " "))")
    }

    func statusChanged(_ status: NsStatus?) {
        let branches = status?.branches.map { branch in
            branch.nickname.map { "\(branch.branch) (\($0))" } ?? branch.branch
        }
        record("ns status: \(branches?.joined(separator: ", ") ?? "sem resposta")")
    }

    func layoutChanged(_ layout: SidebarLayout) {
        let favorites = layout.favorites.map { URL(fileURLWithPath: $0.path).lastPathComponent }.sorted()
        let collapsed = layout.collapsed.map(\.rawValue).sorted()
        record("favoritos: \(favorites.joined(separator: ", ")); encolhidos: \(collapsed.joined(separator: ", "))")
    }

    func check() {
        let labels = focused.values.sorted()
        guard labels.count > 1 else {
            lastReported = []
            return
        }
        guard labels != lastReported else { return }
        lastReported = labels
        log.write(["sidebar: \(labels.count) linhas em foco: \(labels.joined(separator: ", "))"]
            + recentEvents.map { "  antes: \($0)" })
    }

    private func record(_ event: String) {
        recentEvents = Array((recentEvents + [event]).suffix(Self.eventsKept))
    }

    private func scheduleCheck() {
        guard !isChecking else { return }
        isChecking = true
        Task { @MainActor in
            try? await Task.sleep(for: confirmAfter)
            isChecking = false
            check()
        }
    }

    private static func label(_ row: String, _ instance: UUID) -> String {
        "\(row)#\(instance.uuidString.prefix(4))"
    }
}
