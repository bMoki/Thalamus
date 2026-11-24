import AppKit
import XCTest

private let bigProject = """
    mkdir -p admin-web/src orders-api/src
    : > orders-api/pom.xml
    i=0
    while [ $i -lt 4100 ]; do
      : > admin-web/src/f$i; : > orders-api/src/f$i
      i=$((i + 1))
    done
    """

private let backendWithWorktree = """
    java=orders-domain/src/main/java/com/example/orders
    for copy in orders-api worktrees/feature-1/orders-api; do
      mkdir -p $copy/$java $copy/src
      : > $copy/$java/OrderRepository.java
    done
    mkdir -p orders-api/.git orders-api/target/classes
    echo "gitdir: $(pwd -P)/orders-api/.git/worktrees/orders-api" > worktrees/feature-1/orders-api/.git
    i=0
    while [ $i -lt 4100 ]; do
      : > orders-api/src/f$i; : > orders-api/target/classes/f$i.class
      : > worktrees/feature-1/orders-api/src/f$i
      i=$((i + 1))
    done
    """

/// Drives the real app through its accessibility tree. Each test gets its own
/// data root and fake CLIs, so no real session, preference or CLI is touched.
///
/// This runner is sandboxed: it can read anywhere but write only inside its
/// container, which the app cannot reach. So the app owns the data root, under
/// /tmp, and the fake CLIs' steps travel in the launch environment.
final class ConversationUITests: XCTestCase {
    private var root: URL!
    private var claude: FakeCLI!
    private var openCode: FakeCLI!

    private let patience: TimeInterval = 15

    override func setUpWithError() throws {
        continueAfterFailure = false
        root = URL(fileURLWithPath: "/private/tmp")
            .appending(path: "ThalamusUITests-" + UUID().uuidString)
        claude = try FakeCLI(appRoot: root, harness: "claude-code")
        openCode = try FakeCLI(appRoot: root, harness: "opencode")
    }

    override func tearDownWithError() throws {
        claude.remove()
        openCode.remove()
    }

    @MainActor
    private func launch(projectSetup: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["THALAMUS_UI_TEST_ROOT"] = root.path
        app.launchEnvironment["THALAMUS_PROJECT_SETUP"] = projectSetup
        for cli in [claude!, openCode!] {
            app.launchEnvironment.merge(cli.launchEnvironment) { $1 }
        }
        app.launchEnvironment["THALAMUS_CLI_claude-code"] = claude.executable
        app.launchEnvironment["THALAMUS_CLI_opencode"] = openCode.executable
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        return app
    }

    /// Fails with the accessibility tree attached, which is what to read when a
    /// query stops matching.
    @MainActor
    private func require(_ element: XCUIElement, in app: XCUIApplication,
                         file: StaticString = #filePath, line: UInt = #line) {
        guard !element.waitForExistence(timeout: patience) else { return }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        XCTFail("never appeared: \(element)", file: file, line: line)
    }

    @MainActor
    private func text(containing fragment: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@",
                                               fragment, fragment)).firstMatch
    }

    @MainActor
    private func sidebarRow(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "Sidebar").firstMatch
            .descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    @MainActor
    private func pageRow(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "RowPage").firstMatch
            .staticTexts[title]
    }

    @MainActor
    private func openComposer(in app: XCUIApplication) -> XCUIElement {
        require(app.staticTexts["Nenhuma conversa aberta"], in: app)
        app.buttons["Nova conversa"].click()
        let composer = app.textViews["Peça uma alteração…"]
        require(composer, in: app)
        composer.click()
        return composer
    }

    /// Opens a conversation from the empty window and sends its first turn.
    @MainActor
    private func startConversation(_ text: String, in app: XCUIApplication) {
        openComposer(in: app).typeText(text + "\n")
    }

    @MainActor
    private func launchAfterAFirstReply() throws -> XCUIApplication {
        try claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        try claude.answerTitles(with: "Saudação curta")
        let app = launch()
        startConversation("Diga apenas OK e nada mais.", in: app)
        require(app.staticTexts["OK"], in: app)
        return app
    }

    // MARK: - Conversation

    @MainActor
    func testAFirstConversationGetsItsReplyAndATitle() throws {
        let app = try launchAfterAFirstReply()

        require(app.staticTexts["Saudação curta"], in: app)
        require(sidebarRow("project", in: app), in: app)
        XCTAssertEqual(claude.launches.count, 1)
    }

    @MainActor
    func testAllowingFromThePermissionCardFinishesTheTurn() throws {
        let recorded = try RecordedSession.claudePermission()
        try claude.on(FakeCLI.userTurn, reply: recorded.untilAsking)
        try claude.on(FakeCLI.permissionAnswer, reply: recorded.afterAnswer)
        let app = launch()

        startConversation("Crie prova.txt com o texto ok.", in: app)
        let allow = app.buttons["Permitir"]
        require(allow, in: app)
        allow.center.click()

        require(text(containing: "criado com o conte", in: app), in: app)
        XCTAssertFalse(allow.exists)
        XCTAssertEqual(claude.received.last?.contains(#""behavior":"allow""#), true)
    }

    @MainActor
    func testAQuestionGetsASuggestedReplyThatTheRightArrowSends() throws {
        let question = try RecordedSession.claude("hello").map {
            $0.replacingOccurrences(of: #""text":"OK""#, with: #""text":"Quer que eu continue?""#)
        }
        try claude.on(FakeCLI.userTurn, reply: question)
        try claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        try claude.answerSuggestions(with: "Sim, pode continuar.")
        let app = launch()

        startConversation("Faça a primeira parte.", in: app)
        require(app.staticTexts["Quer que eu continue?"], in: app)
        require(app.staticTexts["suggested-reply"], in: app)

        app.typeKey(.rightArrow, modifierFlags: [])

        require(app.staticTexts["OK"], in: app)
        XCTAssertTrue(claude.received.contains { $0.contains("Sim, pode continuar.") })
        XCTAssertFalse(app.staticTexts["suggested-reply"].exists)
    }

    @MainActor
    func testManyAgentQuestionsScrollAndKeepTheAnswerButtonInTheWindow() throws {
        let count = 4
        try claude.on(FakeCLI.userTurn, reply: RecordedSession.claudeQuestions(count))
        let app = launch()

        startConversation("Me pergunte tudo de uma vez.", in: app)
        let answer = app.buttons["Responder"]
        require(answer, in: app)
        require(app.staticTexts["0 de \(count) respondidas"], in: app)

        let window = app.windows.firstMatch.frame
        let questions = app.scrollViews["agent-questions"]
        XCTAssertTrue(window.contains(answer.frame))
        XCTAssertTrue(app.buttons["Dispensar"].frame.maxY <= window.maxY)
        XCTAssertLessThanOrEqual(questions.frame.height, window.height * 0.6)
        XCTAssertGreaterThan(option(1, of: count, in: app).frame.maxY, questions.frame.maxY)

        for number in 1...count {
            let option = option(1, of: number, in: app)
            require(option, in: app)
            while option.frame.maxY > questions.frame.maxY {
                questions.center.scroll(byDeltaX: 0, deltaY: -120)
            }
            option.center.click()
            require(app.staticTexts["\(number) de \(count) respondidas"], in: app)
        }

        XCTAssertTrue(window.contains(answer.frame))
        answer.center.click()
        XCTAssertTrue(answer.waitForNonExistence(timeout: patience))
        XCTAssertEqual(claude.received.last?.contains(RecordedSession.optionLabel(1, of: count)), true)
    }

    @MainActor
    private func option(_ option: Int, of question: Int, in app: XCUIApplication) -> XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@",
                                           RecordedSession.optionLabel(option, of: question))).firstMatch
    }

    @MainActor
    func testAConversationIsStillThereAfterTheAppRelaunches() throws {
        try claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        try claude.answerTitles(with: "Saudação curta")
        var app = launch()
        startConversation("Diga apenas OK e nada mais.", in: app)
        require(app.staticTexts["Saudação curta"], in: app)
        app.terminate()

        app = launch()
        let row = sidebarRow("project", in: app)
        require(row, in: app)
        row.click()

        require(app.staticTexts["OK"], in: app)
    }

    @MainActor
    func testTheSidebarMenuOpensInAppAndDrillsIntoTheHarnesses() {
        let app = launch()

        app.buttons["Nova"].click()
        let menu = app.scrollViews["thalamus-menu"]
        require(menu.buttons["Nova sessão"], in: app)
        XCTAssertTrue(menu.buttons["Abrir pasta…"].exists)

        menu.buttons["Nova sessão com"].click()
        require(app.buttons["Voltar"], in: app)
        XCTAssertFalse(menu.buttons["Abrir pasta…"].exists)
        XCTAssertTrue(menu.buttons["Claude Code"].exists)

        app.buttons["Voltar"].click()
        require(menu.buttons["Abrir pasta…"], in: app)
    }

    @MainActor
    func testTheSidebarMenuAnswersTheKeyboard() {
        let app = launch()

        app.buttons["Nova"].click()
        let menu = app.scrollViews["thalamus-menu"]
        require(menu.buttons["Nova sessão com"], in: app)

        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: [])
        require(app.buttons["Voltar"], in: app)
        XCTAssertTrue(menu.buttons["Claude Code"].exists)

        app.typeKey(.leftArrow, modifierFlags: [])
        require(menu.buttons["Abrir pasta…"], in: app)

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(menu.waitForNonExistence(timeout: 5))
    }

    // MARK: - Mentions

    @MainActor
    func testTabCompletesASkillWithoutSendingIt() throws {
        let app = try launchAfterAFirstReply()

        let composer = app.textViews["Peça uma alteração…"]
        composer.typeText("/veri")
        require(app.staticTexts["verify"], in: app)
        composer.typeText("\t")

        XCTAssertEqual(composer.value as? String, "/verify ")
        XCTAssertFalse(app.staticTexts["verify"].exists)
        composer.typeText("lib")
        XCTAssertEqual(composer.value as? String, "/verify lib")
        XCTAssertEqual(claude.received.filter { $0.contains(FakeCLI.userTurn) }.count, 1)
    }

    @MainActor
    func testMentionsReachEveryFolderOfABigProject() {
        let app = launch(projectSetup: bigProject)
        let composer = openComposer(in: app)

        composer.typeText("@admin-web")
        require(app.staticTexts["admin-web"], in: app)
        composer.typeKey("a", modifierFlags: .command)
        composer.typeText("@orders")
        require(app.staticTexts["orders-api"], in: app)

        composer.typeText("\t")
        XCTAssertEqual(composer.value as? String, "@orders-api/")
    }

    @MainActor
    func testMentionsReachADeepSourceBesideBuildOutputAndAWorktree() {
        let app = launch(projectSetup: backendWithWorktree)
        let composer = openComposer(in: app)

        composer.typeText("@OrderRepo")

        require(text(containing: "orders-api/orders-domain/src/main/java", in: app), in: app)
        XCTAssertFalse(text(containing: "worktrees/feature-1/orders-api", in: app).exists)
    }

    // MARK: - Sidebar

    @MainActor
    private func sessionMenu(in app: XCUIApplication) -> XCUIElement {
        startConversation("Diga apenas OK e nada mais.", in: app)
        require(app.staticTexts["Saudação curta"], in: app)
        sidebarRow("project", in: app).click()
        let row = pageRow("Saudação curta", in: app)
        require(row, in: app)
        row.rightClick()
        let menu = app.scrollViews["thalamus-menu"]
        require(menu, in: app)
        return menu
    }

    @MainActor
    func testRenamingASessionFromItsRowPage() throws {
        try claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        try claude.answerTitles(with: "Saudação curta")
        let app = launch()

        sessionMenu(in: app).buttons["Renomear"].click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Renomeada\n")

        require(pageRow("Renomeada", in: app), in: app)
        XCTAssertFalse(pageRow("Saudação curta", in: app).exists)
    }

    @MainActor
    func testDeletingASessionAsksFirstAndEmptiesTheWindow() throws {
        try claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        try claude.answerTitles(with: "Saudação curta")
        let app = launch()

        sessionMenu(in: app).buttons["Apagar sessão…"].click()
        let confirm = app.sheets.buttons["Apagar"]
        require(confirm, in: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(confirm.exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(confirm.waitForNonExistence(timeout: patience))
        XCTAssertTrue(pageRow("Saudação curta", in: app).exists)

        pageRow("Saudação curta", in: app).rightClick()
        app.scrollViews["thalamus-menu"].buttons["Apagar sessão…"].click()
        require(confirm, in: app)
        confirm.click()

        require(app.staticTexts["Nenhuma conversa aberta"], in: app)
        XCTAssertFalse(sidebarRow("project", in: app).exists)
    }

    @MainActor
    func testFreeTerminalsRunAShellInTheSessionFolder() throws {
        let app = launch()
        _ = openComposer(in: app)

        app.buttons["Mostrar Terminais livres"].click()
        require(app.buttons["Novo Terminal livre"], in: app)
        app.typeText("pwd -P > terminal.txt\r")

        let written = root.appending(path: "project/terminal.txt")
        let deadline = Date().addingTimeInterval(patience)
        while Date() < deadline, (try? String(contentsOf: written, encoding: .utf8))?.isEmpty != false {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        let reported = try String(contentsOf: written, encoding: .utf8)
        XCTAssertEqual(reported.trimmingCharacters(in: .whitespacesAndNewlines), root.path + "/project")

        app.buttons["Novo Terminal livre"].click()
        let tabs = app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Terminal livre ·"))
        XCTAssertEqual(tabs.count, 2)
    }
}

extension ConversationUITests {
    private static let longSession = 80
    private static let firstLongTurn = 40

    @MainActor
    private func startLongSession(pace: Double? = nil) throws -> XCUIApplication {
        try claude.on(FakeCLI.userTurn, reply: RecordedSession.claudeLong(1...Self.firstLongTurn))
        try claude.on(FakeCLI.userTurn, reply: RecordedSession.claudeLong(Self.firstLongTurn + 1...Self.longSession),
                      pace: pace)
        try claude.answerTitles(with: "Conversa longa")
        let app = launch(projectSetup: "echo nota > notas.txt")
        let composer = openComposer(in: app)
        pasteImage(in: app)
        composer.typeText("Escreva bastante.\n")
        require(text(containing: RecordedSession.longMessageTitle(Self.firstLongTurn), in: app), in: app)
        composer.click()
        pasteImage(in: app)
        composer.typeText("Mais texto.\n")
        let images = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "attachments").path)
        XCTAssertEqual(images.filter { $0.hasSuffix(".png") }.count, 2)
        return app
    }

    @MainActor
    private func launchWithLongSession() throws -> XCUIApplication {
        let app = try startLongSession()
        require(text(containing: RecordedSession.longMessageTitle(Self.longSession), in: app), in: app)
        require(app.buttons["Enviar mensagem"], in: app)
        return app
    }

    @MainActor
    private func pasteImage(in app: XCUIApplication) {
        let image = NSImage(size: NSSize(width: 480, height: 320), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        app.typeKey("v", modifierFlags: .command)
    }

    @MainActor
    func testALongAnswerStillShowsMessagesAfterStreaming() throws {
        let app = try launchWithLongSession()

        XCTAssertEqual(messagesInView(in: app).shown.last, Self.longSession)
    }

    @MainActor
    func testTheLastMessageStaysInViewDuringAndAfterALongStreaming() throws {
        let app = try startLongSession(pace: 0.05)
        let streaming = text(containing: RecordedSession.longMessageTitle(Self.firstLongTurn + 2), in: app)
        require(streaming, in: app)

        for moment in 1...3 {
            let shown = messagesInView(in: app).shown
            XCTAssertGreaterThan(shown.max() ?? 0, Self.firstLongTurn, "while streaming, sample \(moment): \(shown)")
        }
        require(text(containing: RecordedSession.longMessageTitle(Self.longSession), in: app), in: app)
        let (shown, highestDrawn) = messagesInView(in: app)
        XCTAssertEqual(highestDrawn, Self.longSession)
        XCTAssertEqual(shown.max(), Self.longSession, "after streaming: \(shown)")
    }

    @MainActor
    func testMessagesMovingToTheLazyPartKeepTheMessageBeingRead() throws {
        let app = try startLongSession(pace: 0.05)
        require(text(containing: RecordedSession.longMessageTitle(Self.firstLongTurn + 2), in: app), in: app)
        let transcript = app.scrollViews["transcript"]
        for _ in 1...4 { transcript.scroll(byDeltaX: 0, deltaY: 600) }
        let reading = try XCTUnwrap(messagesInView(in: app).shown.first, "blank after scrolling up")
        XCTAssertLessThan(reading, Self.firstLongTurn, "not reading the first answer")

        require(text(containing: RecordedSession.longMessageTitle(Self.longSession), in: app), in: app)
        require(app.buttons["Enviar mensagem"], in: app)
        let after = try XCTUnwrap(messagesInView(in: app).shown.first, "blank after the answer arrived")
        XCTAssertTrue((reading - 1...reading).contains(after), "moved to \(after), was reading \(reading)")
    }

    @MainActor
    func testClosingAFileReturnsToTheMessageBeingRead() throws {
        let app = try launchWithLongSession()
        app.typeKey("0", modifierFlags: [.command, .option])
        let file = app.buttons["notas.txt"]
        require(file, in: app)
        let transcript = app.scrollViews["transcript"]
        for _ in 1...6 { transcript.scroll(byDeltaX: 0, deltaY: 600) }
        let reading = try XCTUnwrap(messagesInView(in: app).shown.first, "blank after scrolling up")

        file.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).click()
        let close = app.buttons["Fechar notas.txt"]
        require(close, in: app)
        close.click()

        require(transcript, in: app)
        let back = try XCTUnwrap(messagesInView(in: app).shown.first, "blank back at the reading point")
        XCTAssertTrue((reading - 1...reading).contains(back), "back at \(back), not at \(reading)")
    }

    @MainActor
    func testReopeningALongSessionShowsMessages() throws {
        try launchWithLongSession().terminate()

        let app = launch()
        let row = sidebarRow("project", in: app)
        require(row, in: app)
        row.click()

        require(app.scrollViews["transcript"], in: app)
        XCTAssertFalse(messagesInView(in: app).shown.isEmpty)
    }
}

extension ConversationUITests {
    @MainActor
    private func messagesInView(in app: XCUIApplication) -> (shown: [Int], highestDrawn: Int?) {
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        guard let transcript = try? app.scrollViews["transcript"].snapshot() else { return ([], nil) }
        var numbered: [(number: Int, frame: CGRect)] = []
        var pending = [transcript]
        while let element = pending.popLast() {
            pending += element.children
            let text = (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
            guard let number = Self.messageNumber(in: text) else { continue }
            numbered.append((number, element.frame))
        }
        let shown = numbered.filter { transcript.frame.intersects($0.frame) && $0.frame.height > 0 }
            .sorted { $0.frame.minY < $1.frame.minY }
        return (shown.map(\.number), numbered.map(\.number).max())
    }

    private static func messageNumber(in text: String) -> Int? {
        let prefix = RecordedSession.longMessagePrefix
        guard text.hasPrefix(prefix) else { return nil }
        return Int(text.dropFirst(prefix.count).prefix { $0.isNumber })
    }
}

private extension XCUIElement {
    var center: XCUICoordinate { coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)) }
}
