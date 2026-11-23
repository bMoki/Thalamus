import Testing
import Foundation
import HarnessCore
@testable import Thalamus

private let catalog = CommandCatalog(skills: ["review"], supportsCompact: true)
private let review = SlashCommand(id: "review", title: "review", detail: "Skill", kind: .skill)

@Test func matchesRequireALiveSlashPrompt() {
    let controller = SlashController()
    #expect(controller.matches(prompt: "no slash", catalog: catalog).isEmpty)
    #expect(controller.matches(prompt: "/rev", catalog: catalog).map(\.id) == ["review"])
    #expect(controller.matches(prompt: "/", catalog: .empty).isEmpty)

    controller.dismissed = true
    #expect(controller.matches(prompt: "/rev", catalog: catalog).isEmpty)
}

@Test func runEntersAGroupWithoutSending() {
    let chat = inertChat()
    let controller = SlashController()
    controller.selection = 3

    let group = SlashCommand(id: "group:skills", title: "Habilidades", detail: "",
                             kind: .group(.skills, count: 2))
    #expect(controller.run(group, in: chat) == false)
    #expect(controller.group == .skills)
    #expect(controller.selection == 0)
    #expect(chat.prompt == "/")
}

@Test func runSendsARealCommandAndDismisses() {
    let chat = inertChat()
    let controller = SlashController()

    let skill = SlashCommand(id: "review", title: "review", detail: "Skill", kind: .skill)
    #expect(controller.run(skill, in: chat) == true)
    #expect(chat.prompt.isEmpty)
    #expect(controller.dismissed)
}

@Test func runIgnoresServerRows() {
    let chat = inertChat()
    chat.prompt = "/bro"
    let controller = SlashController()

    let server = SlashCommand(id: "mcp:broken", title: "broken", detail: "",
                              kind: .mcpServer(status: .needsAuth))
    #expect(controller.run(server, in: chat) == false)
    #expect(chat.prompt == "/bro")
    #expect(!controller.dismissed)
}

@Test func leaveGroupResetsThePrompt() {
    let chat = inertChat()
    let controller = SlashController()
    controller.group = .skills
    controller.selection = 2

    controller.leaveGroup(in: chat)
    #expect(controller.group == nil)
    #expect(controller.selection == 0)
    #expect(chat.prompt == "/")
}

@Test func completeFillsTheCommandWithoutSending() {
    let chat = inertChat()
    chat.prompt = "/rev"
    let controller = SlashController()

    controller.complete(review, in: chat)
    controller.promptChanged(to: chat.prompt, browsingHistory: false)
    #expect(chat.prompt == "/review ")
    #expect(controller.matches(prompt: chat.prompt, catalog: catalog).isEmpty)

    chat.prompt = "/review src"
    controller.promptChanged(to: chat.prompt, browsingHistory: false)
    #expect(controller.matches(prompt: chat.prompt, catalog: catalog).isEmpty)
}

@Test func completeEntersAGroup() {
    let chat = inertChat()
    let controller = SlashController()

    let group = SlashCommand(id: "group:skills", title: "Habilidades", detail: "",
                             kind: .group(.skills, count: 1))
    controller.complete(group, in: chat)
    #expect(controller.group == .skills)
    #expect(chat.prompt == "/")
    #expect(!controller.dismissed)
}

@Test func theListComesBackOnABareSlashAfterCompleting() {
    let chat = inertChat()
    let controller = SlashController()

    controller.complete(review, in: chat)
    controller.promptChanged(to: "/rev", browsingHistory: false)
    #expect(controller.matches(prompt: "/rev", catalog: catalog).isEmpty)

    controller.promptChanged(to: "/", browsingHistory: false)
    #expect(!controller.matches(prompt: "/", catalog: catalog).isEmpty)
    controller.promptChanged(to: "/rev", browsingHistory: false)
    #expect(controller.matches(prompt: "/rev", catalog: catalog).map(\.id) == ["review"])
}

@Test func theListComesBackAfterSendingACompletedCommand() {
    let chat = inertChat()
    let controller = SlashController()

    controller.complete(review, in: chat)
    controller.promptChanged(to: "/review lib", browsingHistory: false)
    controller.promptChanged(to: "", browsingHistory: false)
    controller.promptChanged(to: "/rev", browsingHistory: false)
    #expect(controller.matches(prompt: "/rev", catalog: catalog).map(\.id) == ["review"])
}
