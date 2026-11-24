import Testing
import Foundation
@testable import Thalamus

private func temporaryLog() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "diagnostics-\(UUID().uuidString)/diagnostics.log")
}

private func read(_ url: URL) -> String {
    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

@MainActor
private func makeWatch(logTo url: URL) -> SidebarFocusWatch {
    SidebarFocusWatch(log: DiagnosticsLog(url: url), confirmAfter: .milliseconds(10))
}

@MainActor
@Test func movingTheFocusWritesNothing() {
    let url = temporaryLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let watch = makeWatch(logTo: url)
    let alpha = UUID(), beta = UUID()
    watch.update(alpha, row: "branch:/wt/alpha", isFocused: true)
    watch.update(beta, row: "branch:/wt/beta", isFocused: true)
    watch.update(alpha, row: "branch:/wt/alpha", isFocused: false)
    watch.check()
    #expect(read(url).isEmpty)
}

@MainActor
@Test func twoFocusedRowsAreLoggedOnceWithWhatCameBefore() {
    let url = temporaryLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let watch = makeWatch(logTo: url)
    watch.focusMoved(to: .branch("alpha"))
    watch.update(UUID(), row: "branch:/wt/alpha", isFocused: true)
    watch.update(UUID(), row: "branch:/wt/beta", isFocused: true)
    watch.check()
    watch.check()

    let lines = read(url).split(separator: "\n").map(String.init)
    #expect(lines.count == 4)
    #expect(lines[0].contains("sidebar: 2 linhas em foco: branch:/wt/alpha#"))
    #expect(lines[1].hasSuffix("  antes: foco: branch(\"alpha\")"))
    #expect(lines[2].contains("  antes: branch:/wt/alpha#") && lines[2].hasSuffix(" em foco"))
}

@MainActor
@Test func aRowThatLeavesTheListStopsCountingAsFocused() {
    let url = temporaryLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let watch = makeWatch(logTo: url)
    let leaving = UUID()
    watch.update(leaving, row: "branch:/wt/alpha", isFocused: true)
    watch.remove(leaving)
    watch.update(UUID(), row: "favorites:/wt/alpha", isFocused: true)
    watch.check()
    #expect(read(url).isEmpty)
}

@MainActor
@Test func anOverlapIsLoggedOnlyIfItOutlastsTheWait() async throws {
    let url = temporaryLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let watch = makeWatch(logTo: url)
    let fading = UUID()
    watch.update(fading, row: "branch:/wt/alpha", isFocused: true)
    watch.update(UUID(), row: "branch:/wt/beta", isFocused: true)
    watch.remove(fading)
    try await Task.sleep(for: .milliseconds(100))
    #expect(read(url).isEmpty)

    watch.update(UUID(), row: "branch:/wt/gamma", isFocused: true)
    try await Task.sleep(for: .milliseconds(100))
    #expect(read(url).contains("sidebar: 2 linhas em foco"))
}

@Test func theLogStartsOverPastItsLimit() {
    let url = temporaryLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let log = DiagnosticsLog(url: url, limit: 10)
    log.write(["primeira linha longa"])
    log.write(["segunda"])
    #expect(read(url).split(separator: "\n").map { $0.hasSuffix("segunda") } == [true])
}
