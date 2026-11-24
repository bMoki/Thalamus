import SwiftUI
import HarnessCore

struct ChatView: View {
    @Bindable var chat: ChatModel
    @State private var slash = SlashController()
    @State private var mentions = MentionController()
    @State private var expanded: Set<UUID> = []
    @State private var keys = ChatKeyMonitor()

    @State private var zoomed: ZoomedImage?
    @State private var nearBottom = true
    @State private var scrollPosition = ScrollPosition()
    @State private var readingSpot = ReadingSpot()
    @State private var endFollower = EndFollower()
    @State private var blankEnd = BlankEndWatch()
    @State private var tableLock = TableScrollLock()
    @State private var transcriptHeight: CGFloat = .infinity

    @AppStorage(InspectorPane.storageKey) private var pane: InspectorPane = .closed
    let gitChanges: GitChangesModel
    let files: FileTree
    let editors: EditorTabs
    var openPage: (SidebarRow) -> Void
    @Environment(NsWorkspace.self) private var ns

    private struct ScrollEdgeState: Equatable {
        var isNearBottom: Bool
        var distance: CGFloat
        var contentHeight: CGFloat

        static func bucket(_ value: CGFloat) -> CGFloat { (value / 8).rounded() * 8 }
    }

    private enum LiveRow {
        case compacting, streaming, typing
    }

    private static let questionShare: CGFloat = 0.6
    private static let partlyVisible = 0.01
    private static let alwaysDrawn = 30

    var body: some View {
        InspectorSplit(isShown: pane != .closed) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    ChatHeader(chat: chat, openPage: openPage)
                    EditorTabStrip(tabs: editors, row: row, files: files, home: .session)
                    if let document = editors.selection(in: row) {
                        EditorView(document: document, folder: ns.rowRoot(of: chat.workingDirectory)) { editors.close(document, in: row) }
                    } else {
                        transcript
                        if let removedBranch {
                            ArchivedSessionBar(branch: removedBranch)
                        } else {
                            ChatComposer(chat: chat, slash: slash, mentions: mentions,
                                         keys: keys) { nearBottom = true }
                        }
                    }
                }
                .area(editors.selection(in: row).map { "editor · \($0.name)" } ?? "sessão", fill: Theme.canvas)
                TerminalPanel(row: row, root: ns.rowRoot(of: chat.workingDirectory))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
        } inspector: {
            inspector
        }
        .navigationTitle(chat.title)
        .focusedSceneValue(\.chat, chat)
        .task(id: chat.sessionID) { await chat.loadBranch() }
        .task(id: chat.workingDirectory) { await mentions.loadIndex(under: chat.workingDirectory) }
        .onChange(of: chat.prompt) {
            mentions.selection = 0
            mentions.dismissed = chat.isBrowsingHistory
            slash.selection = 0
            slash.dismissed = chat.isBrowsingHistory
            if SlashCatalog.query(in: chat.prompt) == nil { slash.group = nil }
        }
        .onChange(of: "\(chat.sessionID)|\(isEditing)", initial: true) {
            if isEditing {
                keys.remove()
            } else {
                keys.install(chat: chat, slash: slash, mentions: mentions,
                             zoomed: $zoomed) { nearBottom = true }
            }
        }
        .onChange(of: chat.isBusy) {
            if !chat.isBusy {
                blankEnd.happened(.turnEnded)
                keys.disarmEsc()
                if shownPane == .changes {
                    let gitChanges = self.gitChanges
                    let directory = chat.workingDirectory
                    Task { await gitChanges.load(directory: directory) }
                }
            }
        }
        .onDisappear { keys.remove() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            let chat = self.chat
            Task { @MainActor in
                if chat.hasUnread { chat.hasUnread = false }
            }
        }
        .overlay { Lightbox(zoomed: $zoomed) }
        .followsPullRequests(of: branch, busy: chat.isBusy)
    }

    private var branch: String? { ns.branchName(of: chat.workingDirectory) }

    private var row: SidebarRow { ns.row(of: chat.workingDirectory) }

    private var isEditing: Bool { editors.selection(in: row) != nil }

    private var removedBranch: String? { ns.removedBranch(of: chat.workingDirectory) }

    private var shownPane: InspectorPane { pane.shown(inBranch: branch != nil) }

    private var inspector: some View {
        InspectorView(pane: $pane, gitChanges: gitChanges, files: files,
                      directory: chat.workingDirectory, branch: branch, removedBranch: removedBranch,
                      open: { editors.open($0, in: row) },
                      mention: { path, isDirectory in mentions.mention(path, isDirectory: isDirectory, in: chat) })
    }

    private func zoom(_ data: Data) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            zoomed = ZoomedImage(data: data)
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        let blocks = chat.blocks
        let starts = Self.turnStarts(in: blocks)
        let tailStartsTurn = blocks.last.map {
            Self.isUserBlock($0) || Self.harness(of: $0) != chat.harness
        } ?? true
        let lastID = blocks.last?.id
        let drawnFrom = max(blocks.count - Self.alwaysDrawn, 0)
        return ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.space(.s20)) {
                    if blocks.isEmpty, !chat.isBusy, chat.streaming.isEmpty {
                        SessionWelcome(chat: chat)
                    }
                    if drawnFrom > 0 {
                        LazyVStack(alignment: .leading, spacing: Theme.space(.s20)) {
                            ForEach(blocks[..<drawnFrom]) { row($0, starts: starts, lastID: lastID) }
                        }
                        .scrollTargetLayout()
                    }
                    VStack(alignment: .leading, spacing: Theme.space(.s20)) {
                        ForEach(blocks[drawnFrom...]) { row($0, starts: starts, lastID: lastID) }
                        tail(startsTurn: tailStartsTurn)
                    }
                    .scrollTargetLayout()
                }
                .padding(.horizontal, Theme.space(.s32))
                .padding(.top, Theme.space(.s28))
                .padding(.bottom, Theme.space(.s30))
                .frame(maxWidth: 784, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityIdentifier("transcript")
            .defaultScrollAnchor(.bottom)
            .scrollPosition($scrollPosition)
            .scrollDisabled(tableLock.isLocked)
            .environment(tableLock)
            .overlay(alignment: .bottom) {
                JumpToEndButton(isVisible: !nearBottom) {
                    withAnimation(.easeOut(duration: 0.2)) { jumpToEnd() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let branch { PullRequestBars(branch: branch) }
                    TransientCards(chat: chat,
                                   maxQuestionHeight: transcriptHeight * Self.questionShare) { nearBottom = true }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                transcriptHeight = $0
            }
            .onScrollGeometryChange(for: ScrollEdgeState.self) { geometry in
                let distance = geometry.contentSize.height
                    - (geometry.contentOffset.y + geometry.containerSize.height
                       - geometry.contentInsets.bottom)
                return ScrollEdgeState(
                    isNearBottom: distance <= 100,
                    distance: ScrollEdgeState.bucket(distance),
                    contentHeight: ScrollEdgeState.bucket(geometry.contentSize.height))
            } action: { old, new in
                let follow: Bool = if new.isNearBottom {
                    true
                } else if old.contentHeight == new.contentHeight,
                          new.distance > old.distance {
                    false
                } else {
                    nearBottom
                }
                if nearBottom != follow { nearBottom = follow }
            }
            .onScrollTargetVisibilityChange(idType: UUID.self, threshold: Self.partlyVisible) { visible in
                readingSpot.see(visible, in: blocks.map(\.id))
                blankEnd.see(rows: visible.count, of: blocks.count, in: chat.sessionID)
            }
            .onScrollTargetVisibilityChange(idType: LiveRow.self, threshold: Self.partlyVisible) { visible in
                blankEnd.see(live: visible.count, in: chat.sessionID)
            }
            .onChange(of: nearBottom, initial: true) {
                blankEnd.see(atEnd: nearBottom, in: chat.sessionID)
            }
            .onAppear {
                let resume = readingSpot.resume(in: chat.sessionID)
                nearBottom = resume == nil
                returnToReading(at: resume, with: reader)
            }
            .onDisappear {
                readingSpot.leave(chat.sessionID, atEnd: nearBottom)
            }
            .onChange(of: chat.lines.count) { scrollToEnd() }
            .onChange(of: chat.streaming) {
                blankEnd.happened(.streamingChunk)
                scrollToEnd()
            }
            .onChange(of: chat.pendingQuestion?.id) { scrollToEnd() }
            .onChange(of: typingVisible) { scrollToEnd() }
            .onChange(of: chat.compactingSince) { scrollToEnd() }
        }
        .id(chat.sessionID)
    }

    @ViewBuilder
    private func row(_ block: ChatBlock, starts: Set<UUID>, lastID: UUID?) -> some View {
        switch block {
        case .line(let line) where line.role == .user || line.role == .compaction:
            TranscriptRow(line: line, expanded: $expanded,
                          onZoom: zoom).id(line.id)
        case .line(let line):
            AssistantTurn(harness: line.harness ?? chat.harness,
                          showsHeader: starts.contains(line.id),
                          moment: line.timestamp) {
                TranscriptRow(line: line, expanded: $expanded, onZoom: zoom)
            }
            .id(line.id)
        case .collapsed(let id, let lines):
            AssistantTurn(harness: Self.harness(of: block) ?? chat.harness,
                          showsHeader: starts.contains(id),
                          moment: lines.first?.timestamp) {
                ToolSteps(id: id, lines: lines, expanded: $expanded,
                          isLive: id == lastID && chat.isBusy
                              && chat.streaming.isEmpty,
                          onZoom: zoom)
            }
            .id(id)
        }
    }

    @ViewBuilder
    private func tail(startsTurn: Bool) -> some View {
        if let since = chat.compactingSince {
            CompactionProgressCard(since: since).id(LiveRow.compacting)
        } else if !chat.streaming.isEmpty {
            AssistantTurn(harness: chat.harness, showsHeader: startsTurn,
                          moment: nil) {
                MessageBubble(text: chat.streaming, moment: nil,
                              style: .assistant, markdown: true)
            }
            .id(LiveRow.streaming)
        } else if chat.isBusy, chat.pending == nil,
                  chat.pendingQuestion == nil {
            AssistantTurn(harness: chat.harness, showsHeader: startsTurn,
                          moment: nil) {
                ThinkingRow(chat: chat)
                    .padding(.vertical, Theme.space(.s4))
            }
            .id(LiveRow.typing)
        }
    }

    private var typingVisible: Bool {
        chat.streaming.isEmpty && chat.isBusy && chat.compactingSince == nil
            && chat.pending == nil && chat.pendingQuestion == nil
    }

    private func returnToReading(at message: UUID?, with reader: ScrollViewProxy) {
        if let message {
            blankEnd.happened(.returnToReading)
            Task { reader.scrollTo(message, anchor: .top) }
        } else {
            jumpToEnd()
        }
    }

    private func jumpToEnd() {
        blankEnd.happened(.jumpToEnd)
        scrollPosition.scrollTo(edge: .bottom)
    }

    private func scrollToEnd() {
        endFollower.follow {
            guard nearBottom else { return }
            blankEnd.happened(.followEnd)
            scrollPosition.scrollTo(edge: .bottom)
        }
    }
}
