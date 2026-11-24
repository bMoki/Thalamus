import Foundation

@MainActor
final class EndFollower {
    private static let frameInterval: Duration = .milliseconds(16)

    private let nextFrame: () async -> Void
    private var pending = false

    init(nextFrame: @escaping () async -> Void = { try? await Task.sleep(for: EndFollower.frameInterval) }) {
        self.nextFrame = nextFrame
    }

    @discardableResult
    func follow(_ scroll: @escaping @MainActor () -> Void) -> Task<Void, Never>? {
        guard !pending else { return nil }
        pending = true
        return Task {
            await nextFrame()
            pending = false
            scroll()
        }
    }
}
