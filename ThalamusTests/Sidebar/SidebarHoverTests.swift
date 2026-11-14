import Foundation
import Testing
@testable import Thalamus

@MainActor
@Test func onlyTheLastRowEnteredIsHovered() {
    let hover = SidebarHover()
    let first = UUID()
    let second = UUID()
    hover.enter(first)
    hover.enter(second)
    #expect(hover.row == second)
}

@MainActor
@Test func leavingARowThatIsNoLongerHoveredKeepsTheCurrentOne() {
    let hover = SidebarHover()
    let stale = UUID()
    let current = UUID()
    hover.enter(stale)
    hover.enter(current)
    hover.leave(stale)
    #expect(hover.row == current)
    hover.leave(current)
    #expect(hover.row == nil)
}

@MainActor
@Test func clearingLeavesNoRowHovered() {
    let hover = SidebarHover()
    hover.enter(UUID())
    hover.clear()
    #expect(hover.row == nil)
}
