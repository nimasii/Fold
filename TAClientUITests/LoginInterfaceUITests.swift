import XCTest

/// Shipping LoginView, isolated Keychain and loopback fixture only.
final class LoginInterfaceUITests: XCTestCase {
    override func tearDown() async throws {
        try await mode("online")
    }

    @MainActor func testEntryKeyboardTokenLoadingErrorAndOfflineAccess() async throws {
        continueAfterFailure = false
        try await mode("online")
        let app = launch()
        let server = app.textFields["connection.server"]
        let signIn = app.buttons["connection.sign-in"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        XCTAssertFalse(signIn.isEnabled)
        capture(app, "01-login-empty")
        server.tap()
        server.typeText("http://127.0.0.1:18079")
        XCTAssertTrue(signIn.isEnabled)
        capture(app, "02-login-keyboard")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        capture(app, "03-login-ready")

        let tokenOption = app.buttons["Use an existing API token"]
        reveal(tokenOption, in: app)
        tokenOption.tap()
        let token = app.secureTextFields["connection.token"]
        let connect = app.buttons["connection.token-connect"]
        reveal(token, in: app)
        XCTAssertTrue(token.exists)
        XCTAssertFalse(connect.isEnabled)
        token.tap(); token.typeText("   ")
        XCTAssertFalse(connect.isEnabled)
        app.buttons["Done"].tap()
        // URL Return chains into the expanded token field instead of opening
        // the browser. The token's Return submits the existing token action.
        reveal(server, in: app, down: true)
        server.tap()
        app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] %@", "Next")).firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        token.typeText("fixture-invalid-token")
        try await mode("slow-reject")
        app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] %@", "Go")).firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertFalse(connect.isEnabled)
        XCTAssertFalse(server.isEnabled)
        XCTAssertFalse(signIn.isEnabled)
        XCTAssertEqual(connect.value as? String, "Connecting…")
        capture(app, "04-login-token-loading")
        let error = app.descendants(matching: .any).matching(identifier: "connection.error").firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(connect.isEnabled)
        reveal(error, in: app, down: true)
        capture(app, "05-login-error")
        try await mode("online")

        reveal(tokenOption, in: app)
        tokenOption.tap()
        XCTAssertTrue(token.waitForNonExistence(timeout: 5))
        // iOS can offer to save SecureField input when it leaves the hierarchy.
        // Never save the synthetic fixture token to the Simulator password store.
        let passwordPrompt = app.sheets["Save Password?"]
        for _ in 0..<3 {
            guard passwordPrompt.waitForExistence(timeout: 1) else { break }
            let notNow = passwordPrompt.buttons["Not Now"]
            XCTAssertGreaterThan(notNow.frame.width, 0)
            notNow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            _ = passwordPrompt.waitForNonExistence(timeout: 2)
        }
        XCTAssertTrue(passwordPrompt.waitForNonExistence(timeout: 5))
        let downloads = app.buttons["connection.downloads"]
        reveal(downloads, in: app)
        downloads.tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        let back = app.navigationBars["Downloads"].buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        reveal(server, in: app, down: true)
        XCTAssertEqual(server.value as? String, "http://127.0.0.1:18079")
        app.terminate()
    }

    @MainActor func testAccessibilityTextCanReachBothSignInOptionsAndDownloads() {
        continueAfterFailure = false
        let app = launch(largeText: true)
        let server = app.textFields["connection.server"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        reveal(server, in: app)
        server.tap(); server.typeText("http://127.0.0.1:18079")
        app.buttons["Done"].tap()
        let signIn = app.buttons["connection.sign-in"]
        reveal(signIn, in: app)
        XCTAssertTrue(signIn.isEnabled)
        capture(app, "06-login-accessibility-primary")
        let option = app.buttons["Use an existing API token"]
        reveal(option, in: app); option.tap()
        let token = app.secureTextFields["connection.token"]
        reveal(token, in: app)
        token.tap(); token.typeText("fixture-invalid-token")
        app.buttons["Done"].tap()
        let connect = app.buttons["connection.token-connect"]
        reveal(connect, in: app)
        XCTAssertTrue(connect.isEnabled)
        capture(app, "07-login-accessibility-token")
        let downloads = app.buttons["connection.downloads"]
        reveal(downloads, in: app)
        XCTAssertTrue(downloads.isHittable)
        capture(app, "08-login-accessibility-downloads")
        app.terminate()
    }

    @MainActor private func launch(largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--connection-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, down: Bool = false) {
        for _ in 0..<8 where !element.isHittable {
            if down { app.scrollViews.firstMatch.swipeDown() } else { app.scrollViews.firstMatch.swipeUp() }
        }
        if !element.isHittable {
            capture(app, "unreachable-control")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Unreachable control hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func mode(_ value: String) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:18079/fixture-mode")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["mode": value])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
}
