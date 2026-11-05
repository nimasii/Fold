import XCTest

/// Production AVKit/VLC controllers with loopback synthetic media. The device
/// stays portrait throughout: only the app's full-screen action requests rotation.
final class FullscreenOrientationUITests: XCTestCase {
    @MainActor func testAVKitRotatesAndRestoresRepeatedly() async throws {
        try await exercise(vlc: false)
    }

    @MainActor func testVLCRotatesAndRestoresRepeatedly() async throws {
        try await exercise(vlc: true)
    }

    @MainActor private func exercise(vlc: Bool) async throws {
        continueAfterFailure = false
        var request = URLRequest(url: URL(string: "http://127.0.0.1:18083/mode")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"offline":false}"#.utf8)
        _ = try await URLSession.shared.data(for: request)
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--playback-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            + (vlc ? ["--playback-fixture-vlc"] : [])
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Online video"].waitForExistence(timeout: 10))
        app.buttons["Online video"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pin player"].waitForExistence(timeout: 15))

        // Pause VLC so its custom controls stay visible throughout the test.
        // AVKit exercises the usual playing path with its native controls.
        if vlc {
            let pause = app.buttons["vlc.playpause"]
            if !pause.exists {
                app.otherElements["video.player.surface"].firstMatch
                    .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
            }
            XCTAssertTrue(pause.waitForExistence(timeout: 5))
            pause.tap()
        }

        for cycle in 1...2 {
            let fullscreen = app.buttons[vlc ? "vlc.fullscreen" : "Fullscreen Button"]
            if !fullscreen.exists {
                app.otherElements["video.player.surface"].firstMatch
                    .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: vlc ? 0.35 : 0.75)).tap()
            }
            XCTAssertTrue(fullscreen.waitForExistence(timeout: 5))
            fullscreen.tap()
            await assertOrientation(app, landscape: true)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "\(vlc ? "vlc" : "avkit")-landscape-\(cycle)"
            shot.lifetime = .keepAlways
            add(shot)

            if vlc {
                if !fullscreen.exists {
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
                }
                fullscreen.tap()
            } else {
                if !app.buttons["Done"].exists && !app.buttons["Close"].exists {
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
                }
                let done = app.buttons["Done"].exists ? app.buttons["Done"] : app.buttons["Close"]
                XCTAssertTrue(done.waitForExistence(timeout: 5))
                done.tap()
            }
            await assertOrientation(app, landscape: false)
            XCTAssertTrue(app.buttons["Pin player"].waitForExistence(timeout: 5))
        }
    }

    @MainActor private func assertOrientation(_ app: XCUIApplication, landscape: Bool) async {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.frame
            return frame.width > 0 && (landscape ? frame.width > frame.height : frame.height > frame.width)
        }, object: app)
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 10)
        XCTAssertEqual(result, .completed, "Expected \(landscape ? "landscape" : "portrait") interface; frame: \(app.frame)")
    }
}
