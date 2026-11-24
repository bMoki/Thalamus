import XCTest

final class SidebarFocusUITests: XCTestCase {
    @MainActor
    func testAFocusedRowMovingInAndOutOfFavoritesLeavesOneRowInFocus() throws {
        let root = URL(fileURLWithPath: "/private/tmp").appending(path: "ThalamusUITests-" + UUID().uuidString)
        let worktrees = root.appending(path: "wt").path
        let layout = try JSONSerialization.data(withJSONObject: [
            "favorites": ["alpha"].map { ["kind": "branch", "path": worktrees + "/" + $0] },
            "order": "name", "collapsed": [String](),
        ])
        let app = XCUIApplication()
        app.launchEnvironment["THALAMUS_UI_TEST_ROOT"] = root.path
        app.launchEnvironment["THALAMUS_NS"] = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appending(path: "ns").path)
        app.launchEnvironment["FAKE_NS_STATUS"] = root.appending(path: "status.json").path
        app.launchEnvironment["THALAMUS_PROJECT_SETUP"] = """
            mkdir -p '\(worktrees)/alpha' '\(worktrees)/beta'
            for name in alpha beta; do
              id=$(uuidgen); mkdir -p '\(root.path)'/sessions/$id
              printf '{"id":"%s","title":"S %s","workingDirectory":"file://\(worktrees)/%s/","segments":[]}' \\
                $id $name $name > '\(root.path)'/sessions/$id/session.json
            done
            branch() { printf '{"branch":"%s","path":"\(worktrees)/%s"}' "$1" "$1"; }
            printf '{"worktreesDir":"\(worktrees)","baseRepos":[],"branches":[%s,%s]}' \\
              "$(branch alpha)" "$(branch beta)" > '\(root.path)'/status.json
            """
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-Thalamus.style", "tty",
                                "-Thalamus.sidebarLayout", "<\(layout.map { String(format: "%02x", $0) }.joined())>"]
        app.launch()
        let sidebar = app.descendants(matching: .any).matching(identifier: "Sidebar").firstMatch
        let row = { (name: String) in
            sidebar.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
        }
        for _ in 0..<2 {
            for name in ["alpha", "beta"] {
                XCTAssertTrue(row(name).waitForExistence(timeout: 40))
                row(name).click()
                Thread.sleep(forTimeInterval: 0.5)
                row(name).rightClick()
                let item = app.scrollViews["thalamus-menu"].buttons
                    .matching(NSPredicate(format: "label == 'Favoritar' OR label == 'Remover dos favoritos'")).firstMatch
                XCTAssertTrue(item.waitForExistence(timeout: 5))
                item.click()
                Thread.sleep(forTimeInterval: 1.5)
            }
        }
        let log = root.appending(path: "diagnostics.log")
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path),
                       (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }
}
