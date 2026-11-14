import Foundation

@MainActor
final class ReadingSpot {
    private(set) var top: UUID?
    private var left: (session: UUID, message: UUID)?

    func see(_ visible: [UUID], in order: [UUID]) {
        let shown = Set(visible)
        top = order.first { shown.contains($0) }
    }

    func leave(_ session: UUID, atEnd: Bool) {
        left = atEnd ? nil : top.map { (session, $0) }
    }

    func resume(in session: UUID) -> UUID? {
        defer { left = nil }
        return left?.session == session ? left?.message : nil
    }
}
