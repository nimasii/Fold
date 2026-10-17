import XCTest

/// Production screens, isolated synthetic account, credited test art, and real local media.
final class StreamingRedesignUITests: XCTestCase {
    override func tearDown() async throws { try await mode(offline: false) }
    @MainActor func testMainScreensAndNativePlayback() async throws {
        continueAfterFailure = false
        try await mode(offline: false)
        let app = launch(dark: true)
        XCTAssertTrue(app.navigationBars["Watch"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["More"].exists)
        capture(app, "01-watch-dark")
        app.buttons["View video, The Earth, from here"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))
        capture(app, "02-video-native-dark")
        app.buttons["Play"].tap()
        XCTAssertTrue(app.otherElements["video.player.surface"].firstMatch.waitForExistence(timeout: 15))
        // Native AVKit controls and actual generated twelve-second media.
        revealPlayer(app)
        XCTAssertTrue(app.buttons["Fullscreen Button"].waitForExistence(timeout: 10))
        let elapsed = app.staticTexts["Elapsed Time"]
        let advancing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", "0:0[1-9].*"), object: elapsed)
        let result = await XCTWaiter.fulfillment(of: [advancing], timeout: 10)
        XCTAssertEqual(result, .completed)
        capture(app, "03-native-controls-dark")
        app.buttons["Play/Pause"].tap()
        app.buttons["Fullscreen Button"].tap()
        XCUIDevice.shared.orientation = .landscapeRight
        try await Task.sleep(for: .seconds(1))
        if !app.buttons["Done"].exists && !app.buttons["Close"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        }
        capture(app, "03b-native-fullscreen-landscape")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "stream-fullscreen-tree"; tree.lifetime = .keepAlways; add(tree)
        let done = app.buttons["Done"].exists ? app.buttons["Done"] : app.buttons["Close"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCUIDevice.shared.orientation = .portrait
        let channel = app.buttons["Orbital Journal"].firstMatch
        for _ in 0..<2 where !channel.isHittable { app.swipeUp() }
        channel.tap()
        XCTAssertTrue(app.navigationBars["Orbital Journal"].waitForExistence(timeout: 10))
        capture(app, "03c-channel-detail-dark")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        capture(app, "04-search-idle-dark")
        search.tap(); search.typeText("Earth")
        XCTAssertTrue(app.buttons["video.card.earthrise"].waitForExistence(timeout: 10))
        if app.keyboards.buttons["Search"].exists { app.keyboards.buttons["Search"].tap() }
        capture(app, "05-search-results-dark")
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 10))
        capture(app, "06-library-dark")
        app.buttons["library.destination.rectangle.stack"].tap()
        XCTAssertTrue(app.staticTexts["Above the atmosphere"].waitForExistence(timeout: 10))
        capture(app, "07-collections-dark")
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Above the atmosphere")).firstMatch.tap()
        XCTAssertTrue(app.buttons["video.card.earthrise"].waitForExistence(timeout: 10))
        capture(app, "08-collection-detail-dark")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let settings = app.buttons["library.destination.slider.horizontal.3"]
        for _ in 0..<3 where !settings.isHittable { app.swipeUp() }
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        capture(app, "09-settings-dark")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let queue = app.buttons["library.destination.server.rack"]
        for _ in 0..<3 where !queue.isHittable { app.swipeUp() }
        queue.tap()
        XCTAssertTrue(app.navigationBars["Server queue"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls.buttons["Pending"].exists)
        XCTAssertTrue(app.staticTexts["The Earth, from here"].waitForExistence(timeout: 10))
        capture(app, "10-server-pending-dark")
        app.segmentedControls.buttons["Ignored"].tap()
        XCTAssertTrue(app.staticTexts["The first Earthrise"].waitForExistence(timeout: 10))
        capture(app, "11-server-ignored-dark")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Downloads"].tap()
        let local = app.buttons.containing(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "video.card.", "On the edge of daylight")).firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 45))
        capture(app, "12-private-downloads-dark")
        try await mode(offline: true)
        let before = try await counts()
        local.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10)); app.buttons["Play"].tap()
        XCTAssertTrue(app.otherElements["video.player.surface"].firstMatch.waitForExistence(timeout: 15))
        revealPlayer(app)
        XCTAssertTrue(app.buttons["Fullscreen Button"].waitForExistence(timeout: 10))
        capture(app, "13-private-native-offline-dark")
        let after = try await counts()
        XCTAssertEqual(before["mediaRequests"], after["mediaRequests"], "Private playback must use its local file")
        try await mode(offline: false)
        app.terminate()
    }

    @MainActor func testLightMainScreensAndLogin() {
        continueAfterFailure = false
        let app = launch(dark: false)
        XCTAssertTrue(app.navigationBars["Watch"].waitForExistence(timeout: 10))
        capture(app, "14-watch-light")
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 10))
        capture(app, "15-library-light")
        app.tabBars.buttons["Downloads"].tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 10))
        capture(app, "16-downloads-light")
        app.tabBars.buttons["Watch"].tap()
        app.buttons["More"].tap(); app.buttons["Log Out"].tap()
        app.buttons["Log Out"].tap()
        XCTAssertTrue(app.buttons["connection.sign-in"].waitForExistence(timeout: 10))
        capture(app, "17-login-light")
        app.buttons["Use an existing API token"].tap()
        XCTAssertTrue(app.secureTextFields["API token"].exists)
        app.terminate()
    }

    @MainActor func testAccessibilityTextAndSelection() {
        continueAfterFailure = false
        let app = launch(dark: true, additional: ["--streaming-fixture-accessibility", "--streaming-fixture-long-list"])
        XCTAssertTrue(app.navigationBars["Watch"].waitForExistence(timeout: 10))
        capture(app, "18-watch-accessibility")
        // All exposes the archive without the discovery shelves.
        app.buttons["All"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watch.featured"].firstMatch.waitForNonExistence(timeout: 5))
        capture(app, "18b-all-filter-accessibility")
        let card = app.otherElements["video.grid"].firstMatch.buttons["video.card.earthrise"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        capture(app, "19-selection-accessibility")
        app.buttons["Cancel"].tap()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 10))
        capture(app, "20-library-accessibility")
        app.tabBars.buttons["Downloads"].tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 10))
        capture(app, "21-downloads-accessibility")
        app.terminate()
    }

    @MainActor func testArchiveScrollAndTabState() async {
        continueAfterFailure = false
        let app = launch(dark: false, additional: ["--streaming-fixture-long-list"])
        XCTAssertTrue(app.buttons["All"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["All"].firstMatch.tap()
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<5 { scroll.swipeUp() }
        capture(app, "22-archive-after-scrolling")
        let visible = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "video.card.")).allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(visible)
        let id = visible!.identifier
        app.tabBars.buttons["Library"].tap()
        app.tabBars.buttons["Watch"].tap()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons[id].firstMatch)
        let restored = await XCTWaiter.fulfillment(of: [ready], timeout: 5)
        capture(app, "23-archive-tab-return")
        let tree = XCTAttachment(string: "Expected visible card: " + id + "\n" + app.debugDescription)
        tree.name = "archive-tab-return-tree"; tree.lifetime = .keepAlways; add(tree)
        XCTAssertEqual(restored, .completed, "Switching tabs must preserve the archive scroll position")
        app.buttons[id].firstMatch.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10), "Normal card activation must still open video details")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons[id].firstMatch.waitForExistence(timeout: 5), "One activation must push one detail route")
        app.terminate()
    }

    @MainActor private func launch(dark: Bool, additional: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
        app.launchArguments = ["--streaming-fixture", "--streaming-fixture-reset", dark ? "--streaming-fixture-dark" : "--streaming-fixture-light", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + additional
        app.launch()
        XCTAssertTrue(app.staticTexts["streaming.fixture-label"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func revealPlayer(_ app: XCUIApplication) {
        if !app.buttons["Fullscreen Button"].isHittable {
            app.otherElements["video.player.surface"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).tap()
        }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func mode(offline: Bool) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:18084/mode")!)
        request.timeoutInterval = 5
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: ["offline": offline])
        _ = try await URLSession.shared.data(for: request)
    }
    private func counts() async throws -> [String: Int] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:18084/counts")!)
        return (try JSONSerialization.jsonObject(with: data) as! [String: Any]).compactMapValues { ($0 as? NSNumber)?.intValue }
    }
}
