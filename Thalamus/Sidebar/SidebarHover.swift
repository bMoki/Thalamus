import Foundation
import Observation

@MainActor
@Observable
final class SidebarHover {
    private(set) var row: UUID?

    func enter(_ id: UUID) {
        row = id
    }

    func leave(_ id: UUID) {
        if row == id { row = nil }
    }

    func clear() {
        row = nil
    }
}
