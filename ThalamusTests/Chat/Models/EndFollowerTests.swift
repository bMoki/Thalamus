import Testing
import Foundation
@testable import Thalamus

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: EndFollower.frameInterval)
    }
}

@MainActor
@Test func manyChunksInOneFrameScrollOnce() async throws {
    let follower = EndFollower()
    var scrolls = 0
    for _ in 1...20 { follower.follow { scrolls += 1 } }
    #expect(scrolls == 0)
    try await waitUntil { scrolls > 0 }
    try await Task.sleep(for: EndFollower.frameInterval * 4)
    #expect(scrolls == 1)
}

@MainActor
@Test func aChunkAfterTheFrameScrollsAgain() async throws {
    let follower = EndFollower()
    var scrolls = 0
    follower.follow { scrolls += 1 }
    try await waitUntil { scrolls == 1 }
    follower.follow { scrolls += 1 }
    try await waitUntil { scrolls == 2 }
    #expect(scrolls == 2)
}
