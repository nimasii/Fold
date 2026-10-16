import XCTest

/// Launches the isolated preview app; it reuses production views with synthetic repositories.
final class ModernInterfaceUITests: XCTestCase {
    @MainActor func testSignInLightAndDark() {
        for dark in [false, true] {
            let app = launch(screen: "login", dark: dark)
            XCTAssertTrue(app.textFields["connection.server"].waitForExistence(timeout: 10))
            let signIn = app.buttons["connection.sign-in"]
            XCTAssertFalse(signIn.isEnabled)
            app.textFields["connection.server"].tap()
            app.textFields["connection.server"].typeText("https://archive.example.com")
            XCTAssertTrue(signIn.isEnabled)
            app.buttons["Done"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            capture(app, "signin-\(dark ? "dark" : "light")")
            app.buttons["Use an existing API token"].tap()
            XCTAssertTrue(app.secureTextFields["API token"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor func testSearchResultsClearAndEmptyStates() {
        for dark in [false, true] {
            let app = launch(screen: "search", dark: dark)
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            capture(app, "search-idle-\(dark ? "dark" : "light")")
            search.tap()
            search.typeText("mountains")
            XCTAssertTrue(app.staticTexts["A Quiet Morning in the Mountains"].waitForExistence(timeout: 5))
            app.keyboards.buttons["Search"].tap()
            app.scrollViews.firstMatch.swipeUp()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            capture(app, "search-results-\(dark ? "dark" : "light")")
            search.tap()
            let clear = search.buttons["Clear text"]
            if clear.exists { clear.tap() }
            else { search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "mountains".count)) }
            search.typeText("no fixture matches this")
            app.keyboards.buttons["Search"].tap()
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No Results")).firstMatch.waitForExistence(timeout: 5))
            capture(app, "search-empty-\(dark ? "dark" : "light")")
            app.terminate()
        }
    }

    @MainActor func testSignInAtAccessibilityTextSize() {
        let app = launch(screen: "login", dark: false, largeText: true)
        XCTAssertTrue(app.textFields["connection.server"].waitForExistence(timeout: 10))
        app.textFields["connection.server"].tap()
        app.textFields["connection.server"].typeText("https://archive.example.com")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.swipeUp()
        for _ in 0..<4 where !app.buttons["connection.sign-in"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["connection.sign-in"].isHittable)
        capture(app, "signin-accessibility-text")
        app.terminate()
    }

    @MainActor private func launch(screen: String, dark: Bool, largeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "ru.mzhukov.TAClient.UIReviewPreview")
        app.launchArguments = ["--review-screen=\(screen)"]
        if dark { app.launchArguments.append("--review-dark") }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
