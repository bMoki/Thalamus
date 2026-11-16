import Foundation

@MainActor
final class EndFollower {
    static let frameInterval: Duration = .milliseconds(16)

    private var pending = false

    func follow(_ scroll: @escaping @MainActor () -> Void) {
        guard !pending else { return }
        pending = true
        Task {
            try? await Task.sleep(for: Self.frameInterval)
            pending = false
            scroll()
        }
    }
}
