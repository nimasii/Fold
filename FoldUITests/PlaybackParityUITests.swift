import XCTest

/// Runs the shipping target, including MobileVLCKit. No UI_REVIEW_PREVIEW branches.
final class PlaybackParityUITests: XCTestCase {
    @MainActor func testAVKitStreamingAndDownloadedControls() async throws { try await compare(vlc: false) }
    @MainActor func testVP9StreamAndAppleCompatibleDownload() async throws { try await compare(vlc: true) }

    @MainActor private func compare(vlc: Bool) async throws {
        continueAfterFailure = false
        try await mode(offline: false)
        let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
        app.launchArguments = ["--playback-fixture", "--playback-fixture-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + (vlc ? ["--playback-fixture-vlc"] : [])
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["Prepare local copy"].waitForExistence(timeout: 10))
        app.buttons["Prepare local copy"].tap()
        app.buttons["Downloads"].tap()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Production Playback Comparison")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Online video"].tap()
        try await exercise(app, vlc: vlc, name: "online")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--playback-fixture-reset" }
        XCUIDevice.shared.orientation = .portrait
        try await mode(offline: true)
        let before = try await counts()
        app.launch()
        XCTAssertTrue(app.buttons["Downloads"].waitForExistence(timeout: 10)); app.buttons["Downloads"].tap()
        let restoredCard = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Production Playback Comparison")).firstMatch
        XCTAssertTrue(restoredCard.waitForExistence(timeout: 10))
        try await Task.sleep(for: .seconds(1))
        restoredCard.tap()
        try await exercise(app, vlc: false, name: vlc ? "downloaded-converted-vp9" : "downloaded-server-offline")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let after = try await counts()
        XCTAssertEqual(before["mediaRequests"], after["mediaRequests"], "Local playback must make zero media requests")
        XCTAssertEqual(after["unauthorized"], 0)
        app.terminate()
        try await mode(offline: false)
    }

    @MainActor private func exercise(_ app: XCUIApplication, vlc: Bool, name: String) async throws {
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10)); app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pin player"].waitForExistence(timeout: 10))
        if vlc {
            let elapsed = app.staticTexts["vlc.elapsed"]
            XCTAssertTrue(elapsed.waitForExistence(timeout: 10))
            let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "0:00"), object: elapsed)
            let result = await XCTWaiter.fulfillment(of: [advanced], timeout: 10)
            XCTAssertEqual(result, .completed)
            showControls(app, vlc: true)
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3)); app.buttons["Pause"].tap()
            capture(app, "vlc-\(name)-inline")
            app.sliders["vlc.timeline"].adjust(toNormalizedSliderPosition: 0.5)
            let sought = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", "0:0[4-8]"), object: elapsed)
            let seekResult = await XCTWaiter.fulfillment(of: [sought], timeout: 5)
            XCTAssertEqual(seekResult, .completed)
            showControls(app, vlc: true)
            app.buttons["Full Screen"].tap()
            XCUIDevice.shared.orientation = .landscapeRight
            try await Task.sleep(for: .seconds(2)) // UIKit rotation and drawable reparenting.
            if !app.buttons["Full Screen"].isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
            XCTAssertTrue(app.buttons["Full Screen"].waitForExistence(timeout: 5))
            capture(app, "vlc-\(name)-fullscreen")
            app.buttons["Full Screen"].tap()
            XCUIDevice.shared.orientation = .portrait
            try await Task.sleep(for: .seconds(1))
        } else {
            showControls(app, vlc: false)
            let elapsed = app.staticTexts["Elapsed Time"]
            XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
            let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT label BEGINSWITH %@", "0:00"), object: elapsed)
            let result = await XCTWaiter.fulfillment(of: [advanced], timeout: 8)
            XCTAssertEqual(result, .completed)
            showControls(app, vlc: false)
            let pause = app.buttons["Play/Pause"]
            pause.tap()
            capture(app, "avkit-\(name)-inline")
            app.sliders["Current position"].adjust(toNormalizedSliderPosition: 0.5)
            let sought = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", "0:0[4-8].*"), object: elapsed)
            showControls(app, vlc: false)
            let seekTree = XCTAttachment(string: app.debugDescription); seekTree.name = "native-after-seek"; seekTree.lifetime = .keepAlways; add(seekTree)
            let seekResult = await XCTWaiter.fulfillment(of: [sought], timeout: 5)
            XCTAssertEqual(seekResult, .completed)
            app.buttons["Fullscreen Button"].tap()
            XCUIDevice.shared.orientation = .landscapeRight
            try await Task.sleep(for: .seconds(1))
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            let fullscreenTree = XCTAttachment(string: app.debugDescription); fullscreenTree.name = "native-fullscreen-tree"; fullscreenTree.lifetime = .keepAlways; add(fullscreenTree)
            capture(app, "avkit-\(name)-fullscreen")
            let done = app.buttons["Done"].exists ? app.buttons["Done"] : app.buttons["Close"]
            XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
            XCUIDevice.shared.orientation = .portrait
        }
        XCTAssertTrue(app.buttons["Pin player"].waitForExistence(timeout: 5))
        app.buttons["Pin player"].tap()
        app.buttons["Pin player"].tap()
        let tree = XCTAttachment(string: app.debugDescription); tree.name = "\(vlc ? "vlc" : "avkit")-\(name)-controls"; tree.lifetime = .keepAlways; add(tree)
    }
    @MainActor private func showControls(_ app: XCUIApplication, vlc: Bool) {
        let button = app.buttons[vlc ? "Full Screen" : "Fullscreen Button"]
        if !button.isHittable || (!vlc && !app.staticTexts["Elapsed Time"].exists) {
            let surface = app.otherElements["video.player.surface"].firstMatch
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: vlc ? 0.35 : 0.75)).tap()
        }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func mode(offline: Bool) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:18083/mode")!)
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: ["offline": offline])
        _ = try await URLSession.shared.data(for: request)
    }
    private func counts() async throws -> [String: Int] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:18083/counts")!)
        let all = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return all.compactMapValues { ($0 as? NSNumber)?.intValue }
    }
}
