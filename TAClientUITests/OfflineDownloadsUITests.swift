import XCTest

/// Real URLSession transfers against Tests/Fixtures/offline_server.py; no owner media.
final class OfflineDownloadsUITests: XCTestCase {
    @MainActor func testDownloadRestartAndPlaybackWithServerOfflineThenLocalRemoval() async throws {
        continueAfterFailure = false
        try await mode(offline: false)
        let app = launch(["--review-offline-reset", "--review-offline-transfer"])
        app.buttons["Download fixture"].tap()
        XCTAssertTrue(app.buttons["A Moment Offline"].waitForExistence(timeout: 15))
        capture(app, "offline-downloaded")
        app.terminate()
        try await mode(offline: true)
        let countsBefore = try await counts()
        app.launchArguments = ["--review-screen=offline"] // Signed out; no server auth or seed.
        app.launch()
        XCTAssertTrue(app.buttons["A Moment Offline"].waitForExistence(timeout: 10))
        app.buttons["A Moment Offline"].tap()
        let time = app.staticTexts["offline.playback.time"]
        XCTAssertTrue(time.waitForExistence(timeout: 10))
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "0:00"), object: time)
        let playbackResult = await XCTWaiter.fulfillment(of: [advanced], timeout: 10)
        XCTAssertEqual(playbackResult, .completed)
        capture(app, "offline-playback-server-unavailable")
        let countsAfter = try await counts()
        XCTAssertEqual(countsBefore["mediaRequests"], countsAfter["mediaRequests"])
        app.buttons["Done"].tap()
        app.buttons["A Moment Offline"].press(forDuration: 1)
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
            XCTAssertTrue(app.buttons["A Moment Offline"].waitForExistence(timeout: 10))
            capture(app, "offline-library-\(dark ? "dark" : "light")")
            app.terminate()
        }
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
        XCTAssertFalse(app.buttons["A Moment Offline"].exists)
        capture(app, "offline-transfer-interrupted")
        app.buttons["Retry"].tap()
        XCTAssertTrue(app.buttons["A Moment Offline"].waitForExistence(timeout: 20))
        app.terminate()
    }

    @MainActor func testAuthFailureAndRedirectNeverCreatePlayableCopyOrLeakCookies() async throws {
        continueAfterFailure = false
        try await mode(offline: false)
        for flag in ["--review-offline-auth-fail", "--review-offline-redirect"] {
            let app = launch(["--review-offline-reset", "--review-offline-transfer", flag])
            app.buttons["Download fixture"].tap()
            XCTAssertTrue(app.staticTexts["Sign in to retry"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["A Moment Offline"].exists)
            capture(app, "offline-\(flag.hasSuffix("redirect") ? "redirect-blocked" : "sign-in-required")")
            app.terminate()
        }
        let redirectCounts = try await counts()
        XCTAssertEqual(redirectCounts["leakRequests"], 0)
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
