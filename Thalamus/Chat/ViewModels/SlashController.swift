import Foundation
import Observation
import HarnessCore

@Observable final class SlashController {
    var selection = 0
    var dismissed = false
    var group: SlashGroup?
    private var completed = false

    func matches(prompt: String, catalog: CommandCatalog) -> [SlashCommand] {
        guard !dismissed, !catalog.isEmpty,
              let query = SlashCatalog.query(in: prompt) else { return [] }
        return SlashCatalog.matches(query, in: catalog, group: group)
    }

    @discardableResult
    func run(_ command: SlashCommand, in chat: ChatModel) -> Bool {
        if let group = command.group {
            self.group = group
            selection = 0
            chat.prompt = "/"
            return false
        }
        guard let text = command.command else { return false }
        chat.prompt = ""
        close()
        Task { await chat.run(command: text) }
        return true
    }

    func complete(_ command: SlashCommand, in chat: ChatModel) {
        guard command.group == nil else {
            run(command, in: chat)
            return
        }
        guard let text = command.command else { return }
        chat.prompt = text + " "
        close()
        completed = true
    }

    func promptChanged(to prompt: String, browsingHistory: Bool) {
        if prompt == "/" || SlashCatalog.query(in: prompt) == nil { completed = false }
        selection = 0
        dismissed = browsingHistory || completed
        if SlashCatalog.query(in: prompt) == nil { group = nil }
    }

    private func close() {
        group = nil
        dismissed = true
    }

    func leaveGroup(in chat: ChatModel) {
        group = nil
        selection = 0
        chat.prompt = "/"
    }
}
