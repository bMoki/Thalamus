import Testing
import Foundation
@testable import Thalamus

private let messages = (0..<5).map { _ in UUID() }

@MainActor
@Test func theTopIsTheFirstVisibleMessageInTranscriptOrder() {
    let spot = ReadingSpot()
    spot.see([messages[3], messages[1], messages[2]], in: messages)
    #expect(spot.top == messages[1])
}

@MainActor
@Test func nothingVisibleLeavesNoTop() {
    let spot = ReadingSpot()
    spot.see([messages[1]], in: messages)
    spot.see([], in: messages)
    #expect(spot.top == nil)
}

@MainActor
@Test func comingBackToTheSameSessionResumesAtTheTopMessage() {
    let spot = ReadingSpot()
    let session = UUID()
    spot.see([messages[2], messages[3]], in: messages)
    spot.leave(session, atEnd: false)
    #expect(spot.resume(in: session) == messages[2])
}

@MainActor
@Test func leavingAtTheEndResumesAtTheEnd() {
    let spot = ReadingSpot()
    let session = UUID()
    spot.see([messages[2]], in: messages)
    spot.leave(session, atEnd: true)
    #expect(spot.resume(in: session) == nil)
}

@MainActor
@Test func anotherSessionDoesNotResumeTheReadingPoint() {
    let spot = ReadingSpot()
    spot.see([messages[2]], in: messages)
    spot.leave(UUID(), atEnd: false)
    #expect(spot.resume(in: UUID()) == nil)
}

@MainActor
@Test func theReadingPointResumesOnlyOnce() {
    let spot = ReadingSpot()
    let session = UUID()
    spot.see([messages[2]], in: messages)
    spot.leave(session, atEnd: false)
    _ = spot.resume(in: session)
    #expect(spot.resume(in: session) == nil)
}
