import XCTest

final class InlineSearchArtworkUITests: XCTestCase {
    @MainActor func testNativeInlineSearchPrototype() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
        app.launchArguments = ["--streaming-fixture", "--streaming-fixture-reset", "--streaming-fixture-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["streaming.fixture-label"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        capture(app, "01-inline-search-collapsed")
        let search = app.tabBars.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        capture(app, "02-inline-search-expanded")
        field.tap(); field.typeText("Earth")
        XCTAssertTrue(app.buttons["video.card.earthrise"].waitForExistence(timeout: 10))
        capture(app, "03-inline-search-keyboard")
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "native-search-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        field.typeText("\n")
        capture(app, "04-inline-search-submitted")
        app.buttons["video.card.earthrise"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(field.value as? String, "Earth")
        field.buttons["Clear text"].tap()
        XCTAssertTrue(app.staticTexts["Find your next watch."].waitForExistence(timeout: 5))
        capture(app, "05-inline-search-clear")
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Close"])).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watch.featured"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(field.exists)
        app.terminate()
    }
    @MainActor func testLegacyInlineSearchBackAndCancelReturnsQueue() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
        app.launchArguments = ["--streaming-fixture", "--streaming-fixture-reset", "--streaming-fixture-dark", "--navigation-legacy-search", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let queue = app.buttons["section.tab.2"], search = app.buttons["library.search.open"]
        XCTAssertTrue(queue.waitForExistence(timeout: 10)); queue.tap()
        XCTAssertLessThan(abs(queue.frame.midY - search.frame.midY), 12)
        capture(app, "17-legacy-inline-collapsed")
        search.tap(); let field = app.searchFields["library.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.typeText("Earth"); field.typeText("\n")
        XCTAssertTrue(app.buttons["video.card.earthrise"].waitForExistence(timeout: 10))
        app.buttons["video.card.earthrise"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        XCTAssertFalse(field.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(field.value as? String, "Earth")
        XCTAssertTrue(app.buttons["library.search.cancel"].isHittable)
        capture(app, "18-legacy-inline-result-return")
        app.buttons["library.search.cancel"].tap()
        XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout: 5))
        XCTAssertTrue(queue.isHittable && search.isHittable)
        app.terminate()
    }

    override func tearDown() async throws { try await mode(offline: false) }

    @MainActor func testPrivateArtworkSurvivesOfflineRelaunchAndRepairsLegacyCopies() async throws {
        continueAfterFailure = false
        try await mode(offline: false)
        let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
        let normal = ["--streaming-fixture", "--streaming-fixture-dark", "--streaming-fixture-downloads", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchArguments = normal + ["--streaming-fixture-reset"]
        app.launch()
        try await requirePrivateArtwork(app, count: 2)
        let card = app.buttons.containing(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "video.card.", "On the edge of daylight")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        capture(app, "06-private-artwork-saved")
        app.terminate()
        try await mode(offline: true)
        app.launchArguments = normal
        let before = try await counts()
        app.launch(); try await requirePrivateArtwork(app, count: 2)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        capture(app, "07-downloaded-artwork-offline-after-relaunch")
        card.tap(); XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Search"].isHittable)
        capture(app, "08-local-poster-avatar-offline")
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pin player"].waitForExistence(timeout: 5))
        let after = try await counts()
        XCTAssertEqual(before["artRequests"], after["artRequests"])
        XCTAssertEqual(before["mediaRequests"], after["mediaRequests"])
        app.terminate()
        for (index, flag) in ["--streaming-fixture-legacy-artwork", "--streaming-fixture-corrupt-artwork"].enumerated() {
            app.launchArguments = normal + [flag]
            app.launch(); try await requirePrivateArtwork(app, count: 0)
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            capture(app, index == 0 ? "09-older-download-fallback-offline" : "11-corrupt-artwork-fallback-offline")
            app.terminate()
            try await mode(offline: false)
            let mediaBefore = try await counts()["mediaRequests"]
            app.launchArguments = normal
            app.launch(); try await requirePrivateArtwork(app, count: 2)
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            capture(app, index == 0 ? "10-older-download-artwork-repaired" : "12-corrupt-artwork-repaired")
            let mediaAfter = try await counts()["mediaRequests"]
            XCTAssertEqual(mediaBefore, mediaAfter)
            app.terminate(); try await mode(offline: true)
        }
    }

    @MainActor func testCompactQueueControlsAndLoadingStates() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
        app.launchArguments = ["--streaming-fixture", "--streaming-fixture-reset", "--streaming-fixture-dark", "--streaming-fixture-slow-queue", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["Queue"].waitForExistence(timeout: 10)); app.tabBars.buttons["Queue"].tap()
        let start = app.buttons["queue.start"], rescan = app.buttons["queue.rescan"]
        XCTAssertTrue(start.waitForExistence(timeout: 10)); XCTAssertTrue(rescan.exists)
        XCTAssertTrue(start.isHittable && rescan.isHittable)
        XCTAssertLessThan(start.frame.width, app.frame.width * 0.45)
        XCTAssertLessThan(rescan.frame.width, 60)
        capture(app, "13-queue-compact-hierarchy")
        start.tap(); XCTAssertFalse(start.isEnabled)
        capture(app, "14-queue-start-loading")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: start)
        wait(for: [ready], timeout: 10)
        rescan.tap(); XCTAssertFalse(rescan.isEnabled)
        capture(app, "15-queue-rescan-loading")
        let rescanned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: rescan)
        wait(for: [rescanned], timeout: 10)
        app.buttons["section.menu"].tap(); app.buttons["section.filters"].tap(); app.buttons["queue.filter.ignore"].tap()
        XCTAssertFalse(start.isEnabled)
        XCTAssertTrue(app.staticTexts["The first Earthrise"].waitForExistence(timeout: 5))
        capture(app, "16-queue-ignored-compact-controls")
        app.terminate()
    }

    @MainActor private func requirePrivateArtwork(_ app: XCUIApplication, count: Int) async throws {
        let label = app.staticTexts["streaming.fixture-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Private artwork: " + String(count)), object: label)
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 20)
        XCTAssertEqual(result, .completed)
    }
    private func mode(offline: Bool) async throws {
        var r = URLRequest(url: URL(string: "http://127.0.0.1:18084/mode")!); r.timeoutInterval = 5
        r.httpMethod = "POST"; r.httpBody = try JSONSerialization.data(withJSONObject: ["offline": offline])
        _ = try await URLSession.shared.data(for: r)
    }
    private func counts() async throws -> [String: Int] {
        let (d, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:18084/counts")!)
        return (try JSONSerialization.jsonObject(with: d) as! [String: Any]).compactMapValues { ($0 as? NSNumber)?.intValue }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
