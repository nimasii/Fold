import XCTest

/// Shipping views and services, an isolated account, credited stills and loopback media.
final class StreamingRedesignUITests: XCTestCase {
    override func tearDown() async throws { try await mode(offline: false) }

    @MainActor func testThreeSectionsSearchMenusAndSettings() {
        continueAfterFailure = false
        let app = launch(dark: true)
        XCTAssertTrue(Set(["Library", "Downloads", "Queue"]).isSubset(of: Set(app.tabBars.buttons.allElementsBoundByIndex.map(\.label))))
        XCTAssertEqual(app.tabBars.buttons.count, 4) // Three sections plus native search affordance.
        let field = app.searchFields.firstMatch
        let searchControl = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchControl.waitForExistence(timeout: 10))
        XCTAssertFalse(field.exists)
        XCTAssertLessThan(abs(searchControl.frame.midY - app.tabBars.buttons["Queue"].frame.midY), 16)
        capture(app, "01-library-three-sections-dark")
        for section in ["Library", "Downloads", "Queue"] {
            app.tabBars.buttons[section].tap()
            app.buttons["section.menu"].tap()
            XCTAssertTrue(app.buttons["section.settings"].exists)
            XCTAssertTrue(app.buttons["section.filters"].exists)
            let menuButtons = app.collectionViews.buttons.allElementsBoundByIndex.map(\.label)
            XCTAssertEqual(Set(menuButtons), Set(["Settings", "Filters"]))
            capture(app, "02-menu-" + section.lowercased())
            app.buttons["section.settings"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.searchFields.firstMatch.exists)
            back(app)
        }
        // A global bottom field always routes to the Library, never Queue filtering.
        openSearch(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.typeText("Earth")
        XCTAssertEqual(field.label, "Search Library")
        XCTAssertTrue(app.buttons["video.card.earthrise"].waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "Earth")
        capture(app, "03a-bottom-search-keyboard")
        field.typeText("\n")
        capture(app, "03-bottom-library-search-results")
        app.buttons["video.card.earthrise"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))
        back(app)
        XCTAssertEqual(field.value as? String, "Earth")
        field.buttons["Clear text"].tap()
        XCTAssertTrue(app.staticTexts["Find your next watch."].waitForExistence(timeout: 5))
        field.typeText("no fixture matches this query")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No Results")).firstMatch.waitForExistence(timeout: 10))
        closeSearch(app)
        XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        selectTab(app, "Library")
        XCTAssertTrue(app.descendants(matching: .any)["watch.featured"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        app.terminate()
    }

    @MainActor func testIndependentStacksCollectionsAndLibraryFilters() async {
        continueAfterFailure = false
        let app = launch(dark: false, additional: ["--streaming-fixture-long-list"])
        chooseFilter(app, "library.filter.watch.all")
        XCTAssertTrue(app.descendants(matching: .any)["watch.featured"].firstMatch.waitForNonExistence(timeout: 5))
        app.buttons["library.playlists"].tap()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 5))
        selectTab(app, "Downloads"); openSettings(app)
        selectTab(app, "Queue"); openSettings(app)
        selectTab(app, "Library")
        XCTAssertTrue(app.navigationBars["Playlists"].exists)
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Above the atmosphere")).firstMatch.tap()
        XCTAssertTrue(app.buttons["video.card.earthrise"].waitForExistence(timeout: 5))
        capture(app, "04-collections-with-three-section-navigation")
        selectTab(app, "Downloads"); XCTAssertTrue(app.navigationBars["Settings"].exists)
        back(app); XCTAssertTrue(app.navigationBars["Downloads"].exists)
        selectTab(app, "Queue"); XCTAssertTrue(app.navigationBars["Settings"].exists)
        back(app); XCTAssertTrue(app.navigationBars["Queue"].exists)
        // Search is transient: Cancel restores Queue and the Library collection history.
        openSearch(app)
        app.searchFields.firstMatch.typeText("Lunar")
        XCTAssertTrue(app.buttons["video.card.moon"].waitForExistence(timeout: 10))
        closeSearch(app)
        XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout: 5))
        selectTab(app, "Library")
        XCTAssertTrue(app.buttons["video.card.earthrise"].waitForExistence(timeout: 5))
        back(app); back(app)
        XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 5))
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<4 { scroll.swipeUp() }
        let top = app.navigationBars.firstMatch.frame.maxY + 12
        let bottom = app.tabBars.firstMatch.frame.minY - 12
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "video.card.")).allElementsBoundByIndex.first {
            $0.isHittable && $0.frame.minY > top && $0.frame.maxY < bottom
        }!
        let id = card.identifier
        selectTab(app, "Downloads"); selectTab(app, "Library")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons[id].firstMatch)
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(result, .completed)
        app.buttons[id].firstMatch.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        back(app)
        capture(app, "05-library-scroll-return")
        app.terminate()
    }

    @MainActor func testQueueActionsPrivatePlaybackAndLogout() async throws {
        continueAfterFailure = false
        try await mode(offline: false)
        let app = launch(dark: false)
        selectTab(app, "Queue")
        XCTAssertTrue(app.buttons["queue.start"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["queue.rescan"].exists)
        capture(app, "06-queue-contextual-controls")
        app.buttons["queue.start"].tap(); app.buttons["queue.rescan"].tap()
        app.textFields["queue.add-input"].tap(); app.textFields["queue.add-input"].typeText("TESTVIDEO01")
        app.buttons["queue.add"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let row = app.cells.containing(.staticText, identifier: "The Earth, from here").firstMatch
        revealSwipeAction(app, row: row, action: "Ignore").tap()
        XCTAssertTrue(app.staticTexts["The Earth, from here"].waitForNonExistence(timeout: 5))
        chooseFilter(app, "queue.filter.ignore")
        XCTAssertTrue(app.staticTexts["The Earth, from here"].waitForExistence(timeout: 5))
        capture(app, "07-queue-ignored-filter")
        let ignoredRow = app.cells.containing(.staticText, identifier: "The Earth, from here").firstMatch
        revealSwipeAction(app, row: ignoredRow, action: "Delete").tap()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)).tap() }
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The Earth, from here"].exists)
        selectTab(app, "Downloads")
        let local = app.buttons.containing(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "video.card.", "On the edge of daylight")).firstMatch
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        for _ in 0..<2 where !local.exists { app.swipeUp() }
        XCTAssertTrue(local.waitForExistence(timeout: 20))
        chooseFilter(app, "downloads.filter.transfers")
        XCTAssertTrue(app.staticTexts["No downloads match this filter"].waitForExistence(timeout: 5))
        chooseFilter(app, "downloads.filter.ready")
        XCTAssertTrue(local.waitForExistence(timeout: 5))
        capture(app, "08-private-downloads-filtered")
        app.buttons["downloads.info"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        try await mode(offline: true)
        let before = try await counts()
        local.tap(); XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10)); app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pin player"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        capture(app, "09-native-private-playback-offline")
        let after = try await counts(); XCTAssertEqual(before["mediaRequests"], after["mediaRequests"])
        back(app); try await mode(offline: false)
        openSettings(app)
        let logout = app.buttons["settings.logout"]
        for _ in 0..<6 where !logout.isHittable { app.swipeUp() }
        logout.tap()
        XCTAssertTrue(app.sheets.buttons["Log Out"].waitForExistence(timeout: 5))
        app.sheets.buttons["Log Out"].tap()
        XCTAssertTrue(app.buttons["connection.sign-in"].waitForExistence(timeout: 10))
        app.terminate()
    }

    @MainActor func testAccessibilitySearchAndLegacySafeArea() {
        continueAfterFailure = false
        for (legacy, largeText) in [(false, true), (true, false), (true, true)] {
            let app = launch(dark: true, additional: (legacy ? ["--navigation-legacy-search"] : []) + (largeText ? ["--streaming-fixture-accessibility"] : []))
            let field = app.searchFields.firstMatch
            XCTAssertTrue(searchLauncher(app).waitForExistence(timeout: 10))
            XCTAssertTrue(searchLauncher(app).isHittable)
            capture(app, legacy ? (largeText ? "19-accessibility-inline-fallback" : "11-safe-area-fallback") : "10-accessibility-adaptive-search")
            openSearch(app); XCTAssertTrue(field.waitForExistence(timeout: 5)); field.typeText("Earth")
            XCTAssertTrue(app.buttons["video.card.earthrise"].waitForExistence(timeout: 10))
            XCTAssertTrue(searchClose(app).isHittable)
            closeSearch(app)
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            chooseFilter(app, "library.filter.watch.all")
            let card = app.otherElements["video.grid"].firstMatch.buttons["video.card.earthrise"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5)); card.press(forDuration: 1)
            XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
            app.buttons["Cancel"].tap()
            app.terminate()
        }
    }

    @MainActor private func launch(dark: Bool, additional: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
        app.launchArguments = ["--streaming-fixture", "--streaming-fixture-reset", dark ? "--streaming-fixture-dark" : "--streaming-fixture-light", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + additional
        app.launch()
        XCTAssertTrue(app.staticTexts["streaming.fixture-label"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func searchClose(_ app: XCUIApplication) -> XCUIElement {
        if app.buttons["library.search.cancel"].exists { return app.buttons["library.search.cancel"] }
        return app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Close"])).firstMatch
    }
    @MainActor private func searchLauncher(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["library.search.open"].exists ? app.buttons["library.search.open"] : app.tabBars.buttons["Search"]
    }
    @MainActor private func openSearch(_ app: XCUIApplication) { searchLauncher(app).tap() }
    @MainActor private func closeSearch(_ app: XCUIApplication) {
        // Native toolbar controls can move during the keyboard/tab-bar transition.
        // A synthesized tap may be delivered before their final hit region is ready.
        for _ in 0..<2 {
            let close = searchClose(app)
            guard close.waitForExistence(timeout: 5) else { break }
            close.tap()
            if app.searchFields.firstMatch.waitForNonExistence(timeout: 3) { break }
        }
        XCTAssertFalse(app.searchFields.firstMatch.exists, "Closing search must dismiss its editor")
    }
    @MainActor private func revealSwipeAction(_ app: XCUIApplication, row: XCUIElement, action: String) -> XCUIElement {
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        // Start inside the trailing edge so the gesture has a full horizontal runway.
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        let button = app.buttons[action].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "The row must expose its native swipe action")
        return button
    }
    @MainActor private func selectTab(_ app: XCUIApplication, _ title: String) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        for _ in 0..<2 where !tab.isSelected {
            tab.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: tab)
            if XCTWaiter.wait(for: [selected], timeout: 3) == .completed { break }
        }
        XCTAssertTrue(tab.isSelected, "Native tab selection must complete before querying the destination")
    }
    @MainActor private func chooseFilter(_ app: XCUIApplication, _ id: String) {
        app.buttons["section.menu"].tap(); app.buttons["section.filters"].tap()
        let button = app.buttons[id]
        for _ in 0..<4 where !button.isHittable { app.swipeUp() }
        button.tap()
    }
    @MainActor private func openSettings(_ app: XCUIApplication) {
        app.buttons["section.menu"].tap(); app.buttons["section.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
    @MainActor private func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func mode(offline: Bool) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:18084/mode")!); request.timeoutInterval = 5
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: ["offline": offline])
        _ = try await URLSession.shared.data(for: request)
    }
    private func counts() async throws -> [String: Int] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:18084/counts")!)
        return (try JSONSerialization.jsonObject(with: data) as! [String: Any]).compactMapValues { ($0 as? NSNumber)?.intValue }
    }
}
