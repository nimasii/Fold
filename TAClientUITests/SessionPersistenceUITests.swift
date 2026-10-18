import XCTest

/// A distinct Simulator-only Keychain service stores synthetic cookies across
/// process termination. No owner Keychain entry is queried or changed.
final class SessionPersistenceUITests: XCTestCase {
    @MainActor func testSessionRelaunch() async throws {
        continueAfterFailure = false
        try await mode("online")
        let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
        app.launchArguments = ["--session-persistence-fixture", "--session-persistence-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let server = app.textFields.firstMatch
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        server.tap(); server.typeText("http://127.0.0.1:18079")
        if app.buttons["Done"].firstMatch.isHittable { app.buttons["Done"].firstMatch.tap() }
        app.buttons["connection.sign-in"].tap()
        let link = app.webViews.links["Sign in to fixture"]
        XCTAssertTrue(link.waitForExistence(timeout: 10)); link.tap()
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Signed in to the fixture server")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["Finish"].tap()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 10))
        capture(app, "01-connected-synthetic-session")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--session-persistence-reset" }
        app.launch()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["connection.sign-in"].exists)
        capture(app, "02-restored-after-process-termination")
        app.terminate()
        try await mode("maintenance")
        app.launch()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["connection.sign-in"].exists)
        app.tabBars.buttons["Downloads"].tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 10))
        capture(app, "03-maintenance-launch-private-downloads-accessible")
        app.terminate()
        try await mode("offline")
        app.launch()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["connection.sign-in"].exists)
        capture(app, "04-network-unavailable-session-retained")
        app.terminate()
        try await mode("online")
        app.launch()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 10))
        capture(app, "05-recovered-without-signing-in")
        app.terminate()
        try await mode("expired")
        app.launch()
        XCTAssertTrue(app.buttons["connection.sign-in"].waitForExistence(timeout: 10))
        capture(app, "06-server-expiry-requires-sign-in")
        app.terminate()
        try await mode("online")
        app.launch()
        XCTAssertTrue(app.buttons["connection.sign-in"].waitForExistence(timeout: 10))
        // Remove only the synthetic service after the proof.
        app.terminate()
        app.launchArguments.append("--session-persistence-reset")
        app.launch(); app.terminate()
    }

    private func mode(_ mode: String) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:18079/fixture-mode")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["mode": mode])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
