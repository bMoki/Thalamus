import Testing
import AppKit
import SwiftUI
@testable import Thalamus

private func tip(_ title: String, detail: String? = "Thalamus · Claude Code") -> PaneTip {
    PaneTip(title: title, detail: detail, state: nil, anchor: .zero)
}

@MainActor
@Test func aTitleThatWrapsMakesTheHoverCardTaller() {
    let short = HoverTipPanel.size(of: tip("Curto"))
    let long = HoverTipPanel.size(of: tip("Estilizar todos os dropdowns conforme o projeto"))

    #expect(long.height >= short.height + 12)
    #expect(long.width <= PaneHoverCard.maxWidth + 2 * PaneHoverCard.margin)
}

@MainActor
@Test func aShortHoverCardHugsItsText() {
    let size = HoverTipPanel.size(of: tip("Curto", detail: nil))

    #expect(size.width < PaneHoverCard.maxWidth)
    #expect(size.width >= 120 + 2 * PaneHoverCard.margin)
}

@MainActor
@Test func theHoverCardKeepsTheSizeItWasMeasuredAt() {
    let path = tip("project", detail: "/private/tmp/ThalamusUITests-\(UUID().uuidString)/project")
    let size = HoverTipPanel.size(of: path)
    let host = NSHostingView(rootView: PaneHoverCard(tip: path, width: size.width - 2 * PaneHoverCard.margin))

    #expect(host.fittingSize == size)
}
