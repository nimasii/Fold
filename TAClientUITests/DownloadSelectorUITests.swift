import XCTest

/// Uses production Downloads UI and isolated in-memory repositories; never contacts an archive.
final class DownloadSelectorUITests: XCTestCase {
    @MainActor func testPendingIgnoredSelectionInLightAndDark() {
        continueAfterFailure = false
        for dark in [false, true] {
            let app = XCUIApplication(bundleIdentifier: "ru.mzhukov.TAClient.UIReviewPreview")
            app.launchArguments = ["--review-screen=downloads"]
            if dark { app.launchArguments.append("--review-dark") }
            app.launch()
            let picker = app.segmentedControls.firstMatch
            XCTAssertTrue(picker.waitForExistence(timeout: 10))
            let pending = picker.buttons["Pending"]
            let ignored = picker.buttons["Ignored"]
            XCTAssertTrue(app.staticTexts["A Quiet Morning in the Mountains"].waitForExistence(timeout: 5))
            XCTAssertTrue(pending.isSelected)
            capture(app, "downloads-pending-\(dark ? "dark" : "light")")
            ignored.tap()
            XCTAssertTrue(app.staticTexts["Ignored Fixture Video"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["A Quiet Morning in the Mountains"].exists)
            XCTAssertTrue(ignored.isSelected)
            capture(app, "downloads-ignored-\(dark ? "dark" : "light")")
            pending.tap()
            XCTAssertTrue(app.staticTexts["A Quiet Morning in the Mountains"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Ignored Fixture Video"].exists)
            XCTAssertTrue(pending.isSelected)
            app.terminate()
        }
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
