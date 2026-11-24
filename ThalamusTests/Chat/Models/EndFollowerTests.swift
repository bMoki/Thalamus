import Testing
import Foundation
@testable import Thalamus

@MainActor
@Test func manyChunksInOneFrameScrollOnce() async {
    let follower = EndFollower(nextFrame: {})
    var scrolls = 0
    let frames = (1...20).map { _ in follower.follow { scrolls += 1 } }
    #expect(scrolls == 0)
    #expect(frames.compactMap(\.self).count == 1)
    await frames.first??.value
    #expect(scrolls == 1)
}

@MainActor
@Test func aChunkAfterTheFrameScrollsAgain() async {
    let follower = EndFollower(nextFrame: {})
    var scrolls = 0
    await follower.follow { scrolls += 1 }?.value
    #expect(scrolls == 1)
    await follower.follow { scrolls += 1 }?.value
    #expect(scrolls == 2)
}
