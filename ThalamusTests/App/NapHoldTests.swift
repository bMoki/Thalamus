import Testing
import Foundation
@testable import Thalamus

@MainActor
private final class Activities {
    var begun = 0
    var ended = 0

    var open: Int { begun - ended }

    func hold() -> NapHold {
        NapHold(begin: {
            self.begun += 1
            return NSObject()
        }, end: { _ in self.ended += 1 })
    }
}

private let first = UUID()
private let second = UUID()

@MainActor
@Test func theFirstSessionThinkingOpensTheActivity() {
    let activities = Activities()
    let hold = activities.hold()
    hold.update([.newReply], of: first)
    #expect(activities.begun == 0)
    hold.update([.thinking], of: first)
    #expect(activities.begun == 1)
    #expect(hold.isHeld)
}

@MainActor
@Test func aSecondSessionThinkingKeepsTheSameActivity() {
    let activities = Activities()
    let hold = activities.hold()
    hold.update([.thinking], of: first)
    hold.update([.thinking], of: second)
    hold.update([], of: first)
    #expect(activities.begun == 1)
    #expect(activities.open == 1)
}

@MainActor
@Test func theLastSessionLeavingThinkingClosesTheActivity() {
    let activities = Activities()
    let hold = activities.hold()
    hold.update([.thinking], of: first)
    hold.update([.thinking], of: second)
    hold.update([.thinking, .awaitingDecision], of: first)
    #expect(activities.open == 1)
    hold.update([.thinking, .outOfTokens], of: second)
    #expect(activities.ended == 1)
    #expect(!hold.isHeld)
}

@MainActor
@Test func aNewReplyInTheMiddleOfATurnKeepsTheActivity() {
    let activities = Activities()
    let hold = activities.hold()
    hold.update([.thinking], of: first)
    hold.update([.thinking, .newReply], of: first)
    #expect(activities.open == 1)
    hold.update([.newReply], of: first)
    #expect(activities.open == 0)
}

@MainActor
@Test func quittingClosesTheActivity() {
    let activities = Activities()
    let hold = activities.hold()
    hold.update([.thinking], of: first)
    hold.release()
    #expect(activities.open == 0)
    hold.release()
    #expect(activities.ended == 1)
}
