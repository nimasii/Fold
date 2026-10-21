import XCTest

/// State and responsive layout coverage uses only the isolated simulator fixtures.
final class CinemaStateUITests: XCTestCase {
    @MainActor func testLoadingAndErrorsAcrossDataScreens() {
        continueAfterFailure = false
        for state in ["loading", "error"] {
            for screen in ["library", "channel", "playlists", "regular", "video", "queue"] {
                let app = launch(screen: screen, state: state)
                let text = state == "loading" ? "Loading your library" : "Fixture connection unavailable"
                XCTAssertTrue(app.staticTexts[text].firstMatch.waitForExistence(timeout: 10), "\(screen): \(state)")
                if state == "error" { XCTAssertTrue(app.buttons["Retry"].firstMatch.exists) }
                capture(app, "state-\(screen)-\(state)")
                app.terminate()
            }
        }
    }

    @MainActor func testEmptyScreensKeepNavigationAndUsefulContext() {
        continueAfterFailure = false
        for screen in ["library", "channel", "playlists", "regular", "custom", "queue", "downloads"] {
            let app = launch(screen: screen, state: "empty")
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["streaming.fixture-label"].exists)
            capture(app, "state-\(screen)-empty")
            if screen == "library" { XCTAssertTrue(app.buttons["library.playlists"].exists) }
            app.terminate()
        }
    }

    @MainActor func testResponsiveAppearancesAndLargeText() {
        continueAfterFailure = false
        for screen in ["library", "downloads", "queue", "playlists", "custom", "video", "settings", "about"] {
            let app = launch(screen: screen)
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
            if app.windows.firstMatch.frame.width > 700 {
                XCUIDevice.shared.orientation = .landscapeLeft
                let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
            }
            capture(app, "responsive-\(screen)-dark")
            app.terminate()
        }
        for screen in ["downloads", "settings", "queue", "video"] {
            let app = launch(screen: screen, light: true)
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
            capture(app, "responsive-\(screen)-light")
            app.terminate()
        }
        for screen in ["library", "settings", "video", "queue"] {
            let app = launch(screen: screen, large: true)
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
            app.swipeUp(); capture(app, "responsive-\(screen)-large")
            app.swipeDown(); app.terminate()
        }
    }

    @MainActor func testIPadLandscapeScreens() {
        continueAfterFailure = false
        for screen in ["library", "downloads", "queue", "playlists", "video", "settings"] {
            let app = launch(screen: screen)
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
            capture(app, "ipad-landscape-" + screen)
            app.terminate()
        }
    }

    @MainActor func testAccessibilityAuditOfPrimaryControls() throws {
        continueAfterFailure = false
        for screen in ["settings", "queue", "video"] {
            let app = launch(screen: screen)
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
            var issues: [String] = []
            try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .textClipped, .contrast]) { issue in
                let report = issue.detailedDescription + "\n" + (issue.element?.debugDescription ?? "No element")
                let attachment = XCTAttachment(string: report); attachment.name = "accessibility-" + screen
                attachment.lifetime = .keepAlways; self.add(attachment)
                issues.append(report)
                return true // Collect every issue, then fail below; none are waived.
            }
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "audit-hierarchy-" + screen
            hierarchy.lifetime = .keepAlways; self.add(hierarchy)
            XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n"))
            app.terminate()
        }
    }

    @MainActor func testContrastIsolationWithoutTabBar() throws {
        let app = launch(screen: "settings", additional: ["--cinema-audit-standalone"])
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: .contrast)
        capture(app, "contrast-settings-without-tabs")
        app.terminate()
    }

    @MainActor private func launch(screen: String, state: String = "ready", light: Bool = false, large: Bool = false, additional: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
        app.launchArguments = ["--streaming-fixture", "--streaming-fixture-reset", light ? "--streaming-fixture-light" : "--streaming-fixture-dark", "--cinema-screen=" + screen, "--cinema-state=" + state, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchArguments += additional
        if large { app.launchArguments.append("--streaming-fixture-accessibility") }
        app.launch()
        XCTAssertTrue(app.staticTexts["streaming.fixture-label"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
