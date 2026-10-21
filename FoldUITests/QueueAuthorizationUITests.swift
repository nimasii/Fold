import XCTest

/// Real APIClient/repositories and native navigation against a loopback HTTP server.
/// Existing Simulator-only synthetic Keychain namespace, never owner credentials.
final class QueueAuthorizationUITests: XCTestCase {
    @MainActor func testRepeatedQueuePermissionDenialArtworkAndRelaunchKeepSession() async throws {
        continueAfterFailure = false
        try await mode("forbidden")
        let app = await connect()
        for _ in 0..<3 {
            app.tabBars.buttons["Queue"].tap()
            XCTAssertTrue(permissionMessage(app).waitForExistence(timeout: 10))
            chooseFilter(app, "pending")
            chooseFilter(app, "ignore")
            XCTAssertTrue(permissionMessage(app).waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["connection.sign-in"].exists)
            app.tabBars.buttons["Library"].tap()
            XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 5))
            app.tabBars.buttons["Downloads"].tap()
            XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        }
        capture(app, "queue-403-valid-session-retained")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--session-persistence-reset" }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Queue"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Queue"].tap()
        XCTAssertTrue(permissionMessage(app).waitForExistence(timeout: 10))
        capture(app, "queue-403-session-persisted-after-relaunch")
        let beforeArtwork = try await counter("artwork_denials")
        try await mode("artwork")
        app.buttons["Retry"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Synthetic Queue item")).firstMatch.waitForExistence(timeout: 10))
        let deadline = Date().addingTimeInterval(8)
        var artworkDenials = try await counter("artwork_denials")
        while artworkDenials <= beforeArtwork && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
            artworkDenials = try await counter("artwork_denials")
        }
        XCTAssertGreaterThan(artworkDenials, beforeArtwork)
        XCTAssertFalse(app.buttons["connection.sign-in"].exists)
        capture(app, "queue-artwork-403-keeps-valid-session")
        app.terminate()
    }

    @MainActor func testInterruptedEntryAndMaintenanceKeepSessionButRealExpirySignsOut() async throws {
        continueAfterFailure = false
        try await mode("forbidden")
        let app = await connect()
        try await mode("slow")
        app.tabBars.buttons["Queue"].tap()
        app.tabBars.buttons["Library"].tap()
        app.tabBars.buttons["Downloads"].tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        try await mode("maintenance")
        app.tabBars.buttons["Queue"].tap()
        if app.collectionViews.firstMatch.waitForExistence(timeout: 3) { app.collectionViews.firstMatch.swipeDown() }
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Fixture maintenance")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["connection.sign-in"].exists)
        capture(app, "queue-maintenance-keeps-session")
        try await mode("expired")
        if app.buttons["Retry"].exists { app.buttons["Retry"].tap() }
        else { app.collectionViews.firstMatch.swipeDown() }
        XCTAssertTrue(app.buttons["connection.sign-in"].waitForExistence(timeout: 10))
        capture(app, "queue-confirmed-expiry-requires-sign-in")
        app.terminate()
        try await mode("artwork")
        app.launchArguments.removeAll { $0 == "--session-persistence-reset" }
        app.launch()
        XCTAssertTrue(app.buttons["connection.sign-in"].waitForExistence(timeout: 10))
        app.terminate()
    }

    @MainActor private func connect() async -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
        app.launchArguments = ["--session-persistence-fixture", "--session-persistence-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let server = app.textFields.firstMatch
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        server.tap(); server.typeText("http://127.0.0.1:18085")
        if app.buttons["Done"].firstMatch.isHittable { app.buttons["Done"].firstMatch.tap() }
        app.buttons["connection.sign-in"].tap()
        let login = app.webViews.links["Sign in to Queue fixture"]
        XCTAssertTrue(login.waitForExistence(timeout: 10)); login.tap()
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Signed in to the Queue fixture server")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["Finish"].tap()
        XCTAssertTrue(app.tabBars.buttons["Queue"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func chooseFilter(_ app: XCUIApplication, _ filter: String) {
        app.buttons["section.menu"].tap(); app.buttons["section.filters"].tap()
        app.buttons["queue.filter." + filter].tap()
        XCTAssertTrue(permissionMessage(app).waitForExistence(timeout: 10))
    }
    @MainActor private func permissionMessage(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["This account does not have permission for this server action. Your connection is still saved."]
    }
    private func mode(_ value: String) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:18085/fixture-mode")!)
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: ["mode": value])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
    private func counter(_ key: String) async throws -> Int {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:18085/fixture-state")!)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?[key] as? Int ?? 0
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
