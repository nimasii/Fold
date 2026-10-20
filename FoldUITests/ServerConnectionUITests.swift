import XCTest

/// Runs only against Tests/Fixtures/connection_server.py, never an owner server.
final class ServerConnectionUITests: XCTestCase {
    @MainActor func testServerOwnedSignInAndLogout() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--connection-fixture"]
        app.launch()
        let server = app.textFields.firstMatch
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        attach(app, "01-connection-setup")
        server.tap()
        server.typeText("http://127.0.0.1:18079")
        if app.buttons["Done"].firstMatch.isHittable { app.buttons["Done"].firstMatch.tap() }
        app.buttons["connection.sign-in"].tap()
        let finish = app.buttons["Finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        let fixtureLogin = app.webViews.links["Sign in to fixture"]
        XCTAssertTrue(fixtureLogin.waitForExistence(timeout: 10))
        attach(app, "02-server-owned-login")
        // An Umbrel gateway cookie alone is insufficient.
        finish.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Sign-in could not be verified")).firstMatch.waitForExistence(timeout: 10))
        fixtureLogin.tap()
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Signed in to the fixture server")).firstMatch.waitForExistence(timeout: 10))
        app.webViews.links["Test blocked external redirect"].tap()
        XCTAssertTrue(app.staticTexts["Sign-in tried to leave this server. Check the server address."].waitForExistence(timeout: 5))
        attach(app, "03-external-redirect-blocked")
        finish.tap()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 10))
        attach(app, "04-connected-fixture")
        app.buttons["More"].tap()
        app.buttons["section.settings"].tap()
        let logout = app.buttons["settings.logout"]
        for _ in 0..<6 where !logout.isHittable { app.swipeUp() }
        logout.tap()
        XCTAssertTrue(app.sheets.buttons["Log Out"].waitForExistence(timeout: 5))
        app.sheets.buttons["Log Out"].tap()
        XCTAssertTrue(app.buttons["connection.sign-in"].waitForExistence(timeout: 10))
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
