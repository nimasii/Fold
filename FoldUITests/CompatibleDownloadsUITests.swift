import XCTest

final class CompatibleDownloadsUITests: XCTestCase {
    @MainActor func testPreparationCancelRetryAndNativeOfflinePlayback() async throws {
        continueAfterFailure = false
        try await mode(false)
        let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
        app.launchArguments = ["--playback-fixture", "--playback-fixture-long", "--playback-fixture-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["Prepare local copy"].waitForExistence(timeout: 10))
        app.buttons["Prepare local copy"].tap(); app.buttons["Downloads"].tap()
        XCTAssertTrue(app.staticTexts["Preparing for Apple player"].waitForExistence(timeout: 10))
        capture(app, "01-preparing-apple-compatible-copy")
        app.buttons["Cancel Download"].tap()
        XCTAssertTrue(app.staticTexts["Canceled"].waitForExistence(timeout: 5))
        capture(app, "02-preparation-canceled")
        app.buttons["Retry"].tap()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Production Playback Comparison")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 40))
        capture(app, "03-compatible-copy-ready")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--playback-fixture-reset" }
        try await mode(true)
        app.launch()
        XCTAssertTrue(app.buttons["Downloads"].waitForExistence(timeout: 10)); app.buttons["Downloads"].tap()
        let restoredCard = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Production Playback Comparison")).firstMatch
        XCTAssertTrue(restoredCard.waitForExistence(timeout: 10))
        try await Task.sleep(for: .seconds(1))
        restoredCard.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10)); app.buttons["Play"].tap()
        let pause = app.buttons["Play/Pause"]
        try await Task.sleep(for: .seconds(1))
        let surface = app.otherElements["video.player.surface"].firstMatch
        if !pause.isHittable { surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).tap() }
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        capture(app, "04-converted-copy-native-controls-server-offline")
        XCTAssertTrue(app.buttons["Fullscreen Button"].exists)
        XCTAssertFalse(app.sliders["vlc.timeline"].exists)
        let timeline = app.sliders.matching(NSPredicate(format: "identifier == %@", "Current position")).firstMatch
        let beforeSeek = elapsedSeconds(timeline) ?? 0
        timeline.adjust(toNormalizedSliderPosition: 0.5)
        if !app.staticTexts["Elapsed Time"].exists { surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).tap() }
        let tree = XCTAttachment(string: app.debugDescription); tree.name = "compatible-native-after-seek"; tree.lifetime = .keepAlways; add(tree)
        let sought = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
            guard let element = object as? XCUIElement, let seconds = self.elapsedSeconds(element) else { return false }
            // AVKit's accessibility slider gesture is not a frame-accurate seek.
            // Verify that paused playback moved; unit tests assert exact midpoint seeks.
            return seconds > beforeSeek + 2 && seconds < 29
        }, object: timeline)
        let seekResult = await XCTWaiter.fulfillment(of: [sought], timeout: 5)
        XCTAssertEqual(seekResult, .completed)
        capture(app, "05-native-seek-converted-copy")
        app.terminate()
        try await mode(false)
    }
    private func elapsedSeconds(_ element: XCUIElement) -> Double? {
        guard let value = element.value as? String,
              let token = value.split(whereSeparator: { $0.isWhitespace }).first else { return nil }
        return Double(token)
    }
    private func mode(_ offline: Bool) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:18083/mode")!)
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: ["offline": offline])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
