import XCTest

/// Real URLSession transfers against Tests/Fixtures/offline_server.py; no owner media.
final class OfflineDownloadsUITests: XCTestCase {
    @MainActor func testDownloadRestartAndPlaybackWithServerOfflineThenLocalRemoval() async throws {
        continueAfterFailure = false
        try await mode(offline: false)
        let app = launch(["--review-offline-reset", "--review-offline-transfer"])
        app.buttons["Download fixture"].tap()
        XCTAssertTrue(card(app).waitForExistence(timeout: 15))
        capture(app, "offline-downloaded")
        app.terminate()
        try await mode(offline: true)
        let countsBefore = try await counts()
        app.launchArguments = ["--review-screen=offline"] // Signed out; no server auth or seed.
        app.launch()
        XCTAssertTrue(card(app).waitForExistence(timeout: 10))
        card(app).tap()
        XCTAssertTrue(app.otherElements["video.player.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Pin player"].waitForExistence(timeout: 5))
        showNativeControls(app)
        let playPause = app.buttons["Play/Pause"]
        if playPause.label != "Pause" { playPause.tap() }
        let elapsed = app.staticTexts["Elapsed Time"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT label BEGINSWITH %@", "0:00"), object: elapsed)
        let result = await XCTWaiter.fulfillment(of: [advanced], timeout: 5)
        XCTAssertEqual(result, .completed)
        capture(app, "offline-playback-server-unavailable")
        let countsAfter = try await counts()
        XCTAssertEqual(countsBefore["mediaRequests"], countsAfter["mediaRequests"])
        XCTAssertEqual(countsBefore["artworkRequests"], countsAfter["artworkRequests"])
        app.navigationBars.buttons["Downloads"].tap()
        card(app).press(forDuration: 1)
        app.buttons["Remove Local Copy"].tap()
        app.buttons.matching(identifier: "Remove Local Copy").allElementsBoundByIndex.last!.tap()
        XCTAssertTrue(app.staticTexts["No Downloads Yet"].waitForExistence(timeout: 5))
        let removalCounts = try await counts()
        XCTAssertEqual(removalCounts["deleteRequests"], 0)
        app.terminate()
        try await mode(offline: false)
    }

    @MainActor func testPrivateLibraryLightAndDark() {
        continueAfterFailure = false
        for dark in [false, true] {
            let app = launch(["--review-offline-reset", "--review-offline-seed"] + (dark ? ["--review-dark"] : []))
            XCTAssertTrue(card(app).waitForExistence(timeout: 10))
            capture(app, "offline-library-\(dark ? "dark" : "light")")
            card(app).tap()
            XCTAssertTrue(app.otherElements["video.player.surface"].waitForExistence(timeout: 10))
            showNativeControls(app)
            capture(app, "offline-shared-player-\(dark ? "dark" : "light")")
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "shared-player-controls-\(dark)"; tree.lifetime = .keepAlways; add(tree)
            app.terminate()
        }
    }

    @MainActor func testLegacyCopyRefreshesPresentationWithoutRedownloadingMedia() async throws {
        continueAfterFailure = false
        try await mode(offline: false)
        let before = try await counts()
        let app = launch(["--review-offline-reset", "--review-offline-seed", "--review-offline-legacy", "--review-offline-transfer"])
        XCTAssertTrue(card(app).waitForExistence(timeout: 10))
        card(app).press(forDuration: 1)
        app.buttons["Refresh details & artwork"].tap()
        let deadline = Date().addingTimeInterval(10)
        var after = try await counts()
        while (after["artworkRequests"] ?? 0) < (before["artworkRequests"] ?? 0) + 2 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100)); after = try await counts()
        }
        XCTAssertEqual(after["mediaRequests"], before["mediaRequests"])
        XCTAssertGreaterThanOrEqual(after["artworkRequests"] ?? 0, (before["artworkRequests"] ?? 0) + 2)
        XCTAssertTrue(card(app).exists)
        capture(app, "offline-legacy-presentation-refreshed")
        app.terminate()
    }

    @MainActor func testArtworkRedirectCannotLeakAuthenticationOrInvalidateVideo() async throws {
        continueAfterFailure = false
        try await mode(offline: false)
        let before = try await counts()
        let app = launch(["--review-offline-reset", "--review-offline-transfer", "--review-offline-artwork-redirect"])
        app.buttons["Download fixture"].tap()
        XCTAssertTrue(card(app).waitForExistence(timeout: 15))
        let deadline = Date().addingTimeInterval(10)
        var after = try await counts()
        while (after["artworkRequests"] ?? 0) < (before["artworkRequests"] ?? 0) + 2 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100)); after = try await counts()
        }
        XCTAssertEqual(after["leakRequests"], 0)
        XCTAssertGreaterThanOrEqual(after["artworkRequests"] ?? 0, (before["artworkRequests"] ?? 0) + 2)
        card(app).tap()
        XCTAssertTrue(app.otherElements["video.player.surface"].waitForExistence(timeout: 10))
        app.terminate()
    }

    @MainActor func testCancelRetryAndInterruptedRestart() async throws {
        continueAfterFailure = false
        try await mode(offline: false)
        let args = ["--review-offline-transfer", "--review-offline-slow"]
        let app = launch(["--review-offline-reset"] + args)
        app.buttons["Download fixture"].tap()
        XCTAssertTrue(app.buttons["Cancel Download"].waitForExistence(timeout: 5))
        capture(app, "offline-transfer-progress")
        app.buttons["Cancel Download"].tap()
        XCTAssertTrue(app.staticTexts["Canceled"].waitForExistence(timeout: 5))
        app.buttons["Retry"].tap()
        XCTAssertTrue(app.buttons["Cancel Download"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--review-screen=offline"] + args
        app.launch()
        XCTAssertTrue(app.staticTexts["Interrupted · retry from start"].waitForExistence(timeout: 10))
        XCTAssertFalse(card(app).exists)
        capture(app, "offline-transfer-interrupted")
        app.buttons["Retry"].tap()
        XCTAssertTrue(card(app).waitForExistence(timeout: 20))
        app.terminate()
    }

    @MainActor func testAuthFailureAndRedirectNeverCreatePlayableCopyOrLeakCookies() async throws {
        continueAfterFailure = false
        try await mode(offline: false)
        for flag in ["--review-offline-auth-fail", "--review-offline-redirect"] {
            let app = launch(["--review-offline-reset", "--review-offline-transfer", flag])
            app.buttons["Download fixture"].tap()
            XCTAssertTrue(app.staticTexts["Sign in to retry"].waitForExistence(timeout: 10))
            XCTAssertFalse(card(app).exists)
            capture(app, "offline-\(flag.hasSuffix("redirect") ? "redirect-blocked" : "sign-in-required")")
            app.terminate()
        }
        let redirectCounts = try await counts()
        XCTAssertEqual(redirectCounts["leakRequests"], 0)
    }

    @MainActor private func card(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "A Moment Offline,")).firstMatch
    }
    @MainActor private func showNativeControls(_ app: XCUIApplication) {
        if !app.buttons["Play/Pause"].isHittable {
            app.otherElements["video.player.surface"].coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.buttons["Play/Pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Fullscreen Button"].exists)
        XCTAssertTrue(app.sliders["Current position"].exists)
    }
    @MainActor private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "ru.mzhukov.TAClient.UIReviewPreview")
        app.launchArguments = ["--review-screen=offline"] + args
        app.launch()
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    private func mode(offline: Bool) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:18081/mode")!)
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: ["offline": offline])
        _ = try await URLSession.shared.data(for: request)
    }
    private func counts() async throws -> [String: Int] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:18081/counts")!)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return object.compactMapValues { $0 as? Int }
    }
}
