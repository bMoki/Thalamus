import Testing
import Foundation
@testable import Thalamus

private let session = UUID()

@MainActor
private final class Reports {
    var lines: [String] = []

    func watch(wait: Duration? = nil) -> BlankEndWatch {
        BlankEndWatch(wait: wait) { self.lines.append($0) }
    }
}

@MainActor
@Test func theEndInViewWithNoRowDrawnIsReportedWithWhatJustHappened() {
    let reports = Reports()
    let watch = reports.watch()
    watch.happened(.streamingChunk)
    watch.see(rows: 0, of: 12, in: session)
    watch.happened(.turnEnded)
    watch.confirm()
    #expect(reports.lines.count == 1)
    #expect(reports.lines.first?.contains(session.uuidString) == true)
    #expect(reports.lines.first?.contains("pedaço de streaming") == true)
}

@MainActor
@Test func aBlankThatPassesBeforeTheWaitIsNotReported() {
    let reports = Reports()
    let watch = reports.watch()
    watch.see(rows: 0, of: 12, in: session)
    watch.see(rows: 3, of: 12, in: session)
    watch.confirm()
    #expect(reports.lines.isEmpty)
}

@MainActor
@Test func theLiveReplyInViewIsNotBlank() {
    let reports = Reports()
    let watch = reports.watch()
    watch.see(live: 1, in: session)
    watch.see(rows: 0, of: 12, in: session)
    watch.confirm()
    #expect(reports.lines.isEmpty)
}

@MainActor
@Test func readingAboveTheEndOrAnEmptySessionIsNotBlank() {
    let reports = Reports()
    let watch = reports.watch()
    watch.see(rows: 0, of: 0, in: session)
    watch.confirm()
    watch.see(atEnd: false, in: session)
    watch.see(rows: 0, of: 12, in: session)
    watch.confirm()
    #expect(reports.lines.isEmpty)
}

@MainActor
@Test func oneBlankIsReportedOnceAndTheNextOneAgain() {
    let reports = Reports()
    let watch = reports.watch()
    watch.see(rows: 0, of: 12, in: session)
    watch.confirm()
    watch.see(rows: 0, of: 13, in: session)
    watch.confirm()
    #expect(reports.lines.count == 1)
    watch.see(rows: 2, of: 13, in: session)
    watch.happened(.turnEnded)
    watch.see(rows: 0, of: 13, in: session)
    watch.confirm()
    #expect(reports.lines.count == 2)
    #expect(reports.lines.last?.contains("fim de turno") == true)
}

@MainActor
@Test func theWaitConfirmsTheBlankOnItsOwn() async throws {
    let reports = Reports()
    let watch = reports.watch(wait: .milliseconds(1))
    watch.see(rows: 0, of: 12, in: session)
    let deadline = ContinuousClock.now + .seconds(30)
    while reports.lines.isEmpty, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(reports.lines.count == 1)
}
