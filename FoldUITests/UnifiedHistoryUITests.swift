import XCTest
import UIKit

/// Shipping navigation/repositories/player against a loopback fixture. Only the
/// fixture namespace is reset; the owner's library and credentials are untouched.
final class UnifiedHistoryUITests: XCTestCase {
    @MainActor func testLibraryDeleteConfirmationAndLocalCopyFollowServerOutcome() async throws {
        continueAfterFailure = false
        for serverFails in [true, false] {
            try await mode(offline: false, reset: true, codec: "h264", deleteError: serverFails)
            let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
            app.launchArguments = ["--history-playback-fixture", "--history-fixture-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 12)); app.swipeUp()
            let card = app.buttons["video.card.HISTORY0001"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
            XCTAssertTrue(app.buttons["Download to iPhone"].waitForExistence(timeout: 8)); app.buttons["Download to iPhone"].tap()
            XCTAssertTrue(app.buttons["View Download"].waitForExistence(timeout: 30))
            app.buttons["video.actions"].tap(); app.buttons["Delete video"].tap()
            let disclosure = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Linked downloads on this device")).firstMatch
            XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
            capture("library-delete-disclosure-" + String(serverFails))
            if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
            else {
                // iOS 26's native confirmation popover cancels through its
                // exposed dismiss region rather than rendering a Cancel row.
                let dismiss = app.otherElements["PopoverDismissRegion"]
                XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
                dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.95)).tap()
            }
            XCTAssertTrue(app.buttons["View Download"].exists)
            let canceled = try await counts(); XCTAssertEqual(canceled["videoDeletes"], 0)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(card.waitForExistence(timeout: 8)); card.tap()
            XCTAssertTrue(app.staticTexts["Playing the copy on this device"].waitForExistence(timeout: 8))
            app.buttons["video.play-action"].tap()
            try await pauseNativePlayer(app) // Quiesce AVKit before opening a native glass menu.
            app.buttons["video.actions"].tap(); app.buttons["Delete video"].tap()
            app.buttons["Delete"].firstMatch.tap()
            if serverFails {
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic deletion failed")).firstMatch.waitForExistence(timeout: 12))
                app.navigationBars.buttons.element(boundBy: 0).tap()
            } else {
                XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 12))
                let state = try await counts(); XCTAssertEqual(state["videoDeletes"], 1)
            }
            app.tabBars.buttons["Downloads"].tap()
            let local = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "video.card.")).firstMatch
            if serverFails { XCTAssertTrue(local.waitForExistence(timeout: 8)) }
            else { XCTAssertTrue(app.staticTexts["No Downloads Yet"].waitForExistence(timeout: 8)); XCTAssertFalse(local.exists) }
            capture("library-delete-downloads-" + String(serverFails))
            app.terminate()
            try await mode(offline: true)
            app.launchArguments.removeAll { $0 == "--history-fixture-reset" }
            app.launch()
            XCTAssertTrue(app.tabBars.buttons["Downloads"].waitForExistence(timeout: 12)); app.tabBars.buttons["Downloads"].tap()
            if serverFails { XCTAssertTrue(local.waitForExistence(timeout: 8)) }
            else { XCTAssertTrue(app.staticTexts["No Downloads Yet"].waitForExistence(timeout: 8)); XCTAssertFalse(local.exists) }
            capture("library-delete-offline-relaunch-" + String(serverFails))
            app.terminate()
        }
        try await mode(offline: false)
    }

    @MainActor func testLargeTypeLibraryAndOfflineDownloadHistory() async throws {
        continueAfterFailure = false
        try await mode(offline: false, reset: true, codec: "h264")
        var seed = URLRequest(url: URL(string: "http://127.0.0.1:18086/api/video/HISTORY0001/progress/")!)
        seed.httpMethod = "POST"; seed.setValue("Token HISTORY_FIXTURE_TOKEN", forHTTPHeaderField: "Authorization")
        seed.httpBody = try JSONSerialization.data(withJSONObject: ["position": 18])
        _ = try await URLSession.shared.data(for: seed)
        let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
        app.launchArguments = ["--history-playback-fixture", "--history-fixture-reset", "--history-hide-probes", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 12)); app.swipeUp()
        let card = app.buttons["video.card.HISTORY0001"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        let point = app.staticTexts["video.resume-position"]
        XCTAssertTrue(point.waitForExistence(timeout: 8)); XCTAssertTrue(point.label.hasSuffix("0:18"))
        app.buttons["Download to iPhone"].tap()
        XCTAssertTrue(app.buttons["View Download"].waitForExistence(timeout: 30))
        capture("history-large-type-library")
        try audit(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Downloads"].firstMatch.tap() // iPad's floating tabs have no TabBar ancestor.
        let local = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "video.card.")).firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 8)); local.tap()
        XCTAssertTrue(point.waitForExistence(timeout: 8)); XCTAssertTrue(point.label.hasSuffix("0:18"))
        capture("history-large-type-download")
        app.terminate()
        try await mode(offline: true)
        app.launchArguments.removeAll { $0 == "--history-fixture-reset" }
        app.launch()
        XCTAssertTrue(app.buttons["Downloads"].firstMatch.waitForExistence(timeout: 12)); app.buttons["Downloads"].firstMatch.tap()
        XCTAssertTrue(local.waitForExistence(timeout: 8)); local.tap()
        XCTAssertTrue(point.waitForExistence(timeout: 8)); XCTAssertTrue(point.label.hasSuffix("0:18"))
        capture("history-large-type-offline-relaunch")
        try audit(app)
        app.terminate()
        try await mode(offline: false)
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor func testVLCStreamingRewindTransfersToNativeDownloadedPlayback() async throws {
        continueAfterFailure = false
        try await mode(offline: false, reset: true, codec: "vp9")
        let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
        app.launchArguments = ["--history-playback-fixture", "--history-fixture-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 12)); app.swipeUp()
        let card = app.buttons["video.card.HISTORY0001"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8)); card.tap()
        app.buttons["video.play-action"].tap()
        let timeline = app.sliders["vlc.timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 10))
        let pause = app.buttons["Pause"]
        if !pause.exists {
            app.otherElements["video.player.surface"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        }
        let pauseReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: pause)
        let pauseReadyResult = await XCTWaiter.fulfillment(of: [pauseReady], timeout: 5)
        XCTAssertEqual(pauseReadyResult, .completed)
        pause.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5), "VLC must be paused before seeking")
        timeline.adjust(toNormalizedSliderPosition: 0.5)
        let forwardPoint = try await confirmedVLCPoint(app, minimum: 20, maximum: 65)
        timeline.adjust(toNormalizedSliderPosition: 0.2)
        let backwardPoint = try await confirmedVLCPoint(app, minimum: 0, maximum: forwardPoint - 5)
        XCTAssertLessThan(backwardPoint, forwardPoint - 5)
        let point = app.staticTexts["video.resume-position"]
        let expected = point.label
        capture("history-vlc-paused-rewind")
        app.buttons["Download to iPhone"].tap()
        XCTAssertTrue(app.buttons["View Download"].waitForExistence(timeout: 60))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let baseline = try await counts()["mediaRequests"]
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        XCTAssertTrue(app.staticTexts["Playing the copy on this device"].waitForExistence(timeout: 5))
        XCTAssertEqual(point.label, expected)
        app.buttons["video.play-action"].tap()
        showControls(app)
        XCTAssertTrue(app.sliders["Current position"].waitForExistence(timeout: 8), "Converted local media uses the native player")
        let localRequests = try await counts()["mediaRequests"]
        XCTAssertEqual(localRequests, baseline)
        capture("history-vlc-point-native-local-resume")
        app.terminate()
    }

    @MainActor func testLibraryDownloadSharedResumeOfflineRelaunchAndReconnect() async throws {
        continueAfterFailure = false
        try await mode(offline: false, reset: true, codec: "h264")
        let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
        app.launchArguments = ["--history-playback-fixture", "--history-fixture-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 12))
        app.swipeUp() // Materialize the lazy card below the artwork-led hero.
        let card = app.buttons["video.card.HISTORY0001"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 12)); card.tap()
        let download = app.buttons["Download to iPhone"]
        if !download.waitForExistence(timeout: 3) {
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "history-before-download"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(download.exists); download.tap()
        let completed = app.buttons["View Download"]
        XCTAssertTrue(completed.waitForExistence(timeout: 20))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let baseline = try await counts()["mediaRequests"] ?? -1
        // Opening from Library must now use exactly the same completed local file.
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        XCTAssertTrue(app.staticTexts["Playing the copy on this device"].waitForExistence(timeout: 5))
        app.buttons["video.play-action"].tap()
        showControls(app)
        let elapsed = app.staticTexts["Elapsed Time"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        let advancing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT label BEGINSWITH %@", "0:00"), object: elapsed)
        let advancedResult = await XCTWaiter.fulfillment(of: [advancing], timeout: 6)
        XCTAssertEqual(advancedResult, .completed)
        try await pauseNativePlayer(app)
        app.sliders["Current position"].adjust(toNormalizedSliderPosition: 0.25)
        let point = app.staticTexts["video.resume-position"]
        XCTAssertTrue(point.waitForExistence(timeout: 5))
        let sought = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", ".*0:(1[5-9]|20)"), object: point)
        let seekResult = await XCTWaiter.fulfillment(of: [sought], timeout: 5)
        XCTAssertEqual(seekResult, .completed)
        let savedLabel = point.label
        capture("history-library-local-point")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Downloads"].tap()
        let localCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "video.card.")).firstMatch
        XCTAssertTrue(localCard.waitForExistence(timeout: 8)); localCard.tap()
        XCTAssertTrue(point.waitForExistence(timeout: 5)); XCTAssertEqual(point.label, savedLabel)
        capture("history-downloads-same-point")
        let mediaCountOne = try await counts()["mediaRequests"]
        XCTAssertEqual(mediaCountOne, baseline)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.terminate()
        try await mode(offline: true)
        app.launchArguments.removeAll { $0 == "--history-fixture-reset" }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Downloads"].waitForExistence(timeout: 12)); app.tabBars.buttons["Downloads"].tap()
        XCTAssertTrue(localCard.waitForExistence(timeout: 8)); localCard.tap()
        XCTAssertTrue(point.waitForExistence(timeout: 5)); XCTAssertEqual(point.label, savedLabel)
        app.buttons["video.play-action"].tap()
        showControls(app)
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        capture("history-offline-relaunch-resume")
        try await pauseNativePlayer(app)
        app.sliders["Current position"].adjust(toNormalizedSliderPosition: 0)
        showControls(app)
        // AVKit's accessibility drag can stop short of the endpoint. Its real
        // ten-second-back control guarantees a genuine seek to zero from here.
        app.otherElements["video.player.surface"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.26, dy: 0.50)).tap()
        let rewind = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", ".*0:0[0-3]"), object: point)
        let rewindResult = await XCTWaiter.fulfillment(of: [rewind], timeout: 5)
        XCTAssertEqual(rewindResult, .completed)
        let enginePoint = try XCTUnwrap(Double(app.staticTexts["fixture.player.position"].label))
        let savedPoint = try XCTUnwrap(Double(app.staticTexts["fixture.saved.position"].label))
        XCTAssertLessThanOrEqual(enginePoint, 3)
        XCTAssertEqual(savedPoint, enginePoint, accuracy: 0.05, "Persist the engine's exact backward seek, including zero")
        let rewoundLabel = point.label
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let mediaCountTwo = try await counts()["mediaRequests"]
        XCTAssertEqual(mediaCountTwo, baseline)
        try await mode(offline: false)
        XCUIDevice.shared.press(.home)
        app.activate()
        try await Task.sleep(for: .seconds(2))
        localCard.tap()
        XCTAssertTrue(point.waitForExistence(timeout: 5)); XCTAssertEqual(point.label, rewoundLabel)
        let server = try await counts()
        XCTAssertEqual(server["position"], 0, "The API ignores <=5 sec; reset its stale point but keep the precise local rewind")
        XCTAssertGreaterThan(server["progressDeletes"] ?? 0, 0)
        capture("history-reconnected-rewind-retained")
        app.terminate()
    }

    @MainActor private func audit(_ app: XCUIApplication) throws {
        var issues: [String] = []
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .textClipped, .contrast]) { issue in
            let report = issue.detailedDescription + "\n" + (issue.element?.debugDescription ?? "No element")
            let attachment = XCTAttachment(string: report); attachment.name = "history-accessibility-issue"; attachment.lifetime = .keepAlways; self.add(attachment)
            // iOS 26.5 flags these plain black labels on the light canvas even
            // at 19.6:1. Independently inspect their actual rendered pixels;
            // this is bounded to the two reproduced nodes and fails below if
            // contrast is insufficient or cannot be measured. All other native
            // findings remain failures, including these nodes' other audits.
            let os = ProcessInfo.processInfo.operatingSystemVersion
            if issue.auditType == .contrast, os.majorVersion == 26, os.minorVersion == 5,
               let element = issue.element,
               element.identifier == "video.resume-position" || element.label == "Fixture Studio",
               let contrast = self.renderedTextContrast(element), contrast >= 4.5 {
                let evidence = XCTAttachment(string: "Native contrast false positive; rendered ink/canvas contrast: \(contrast):1. Minimum: 4.5:1.")
                evidence.name = "history-measured-contrast"; evidence.lifetime = .keepAlways; self.add(evidence)
                let pixels = XCTAttachment(screenshot: element.screenshot()); pixels.name = "history-measured-label"; pixels.lifetime = .keepAlways; self.add(pixels)
                return true
            }
            issues.append(report)
            return true // Collect all unexplained issues; fail below.
        }
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n"))
    }

    @MainActor private func renderedTextContrast(_ element: XCUIElement) -> Double? {
        guard let image = element.screenshot().image.cgImage else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard rendered else { return nil }
        var counts: [Int: Int] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let rgb = Int(pixels[i]) << 16 | Int(pixels[i + 1]) << 8 | Int(pixels[i + 2])
            counts[rgb, default: 0] += 1
        }
        func luminance(_ rgb: Int) -> Double {
            let red = (rgb >> 16) & 255
            let green = (rgb >> 8) & 255
            let blue = rgb & 255
            let components: [Double] = [Double(red) / 255, Double(green) / 255, Double(blue) / 255]
            let values = components.map { value -> Double in
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
        }
        guard let canvas = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        let background = luminance(canvas)
        guard let ink = counts.filter({ abs(luminance($0.key) - background) > 0.12 && $0.value >= 50 })
            .max(by: { $0.value < $1.value })?.key else { return nil }
        let foreground = luminance(ink)
        return (max(background, foreground) + 0.05) / (min(background, foreground) + 0.05)
    }

    @MainActor private func confirmedVLCPoint(_ app: XCUIApplication, minimum: Double, maximum: Double) async throws -> Double {
        let requested = try XCTUnwrap(Double(app.staticTexts["fixture.saved.position"].label))
        XCTAssertGreaterThan(requested, minimum)
        XCTAssertLessThan(requested, maximum)
        // This VLCKit version holds its reported clock while paused. Confirm the
        // actual seek as playback resumes, then pause again before reading history.
        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5)); play.tap()
        let deadline = Date().addingTimeInterval(6)
        var confirmedTarget: Double = -1; var confirmedActual: Double = -1
        repeat {
            confirmedTarget = Double(app.staticTexts["fixture.vlc.confirmed-target"].label) ?? -1
            confirmedActual = Double(app.staticTexts["fixture.vlc.confirmed-position"].label) ?? -1
            if abs(confirmedTarget - requested) < 0.05, confirmedActual >= requested - 0.5 { break }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        XCTAssertEqual(confirmedTarget, requested, accuracy: 0.05)
        let confirmedElapsed = try XCTUnwrap(Double(app.staticTexts["fixture.vlc.confirmed-elapsed"].label))
        XCTAssertGreaterThanOrEqual(confirmedActual, requested - 0.5)
        XCTAssertLessThanOrEqual(confirmedActual, requested + confirmedElapsed + 0.5, "A delayed clock must match the seek plus actual playing time; an old pre-seek position cannot confirm it")
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5)); pause.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        let saved = try XCTUnwrap(Double(app.staticTexts["fixture.saved.position"].label))
        let pausedActual = try XCTUnwrap(Double(app.staticTexts["fixture.vlc.position"].label))
        XCTAssertEqual(pausedActual, saved, accuracy: 0.5, "Pause must save the actual latest VLC point")
        return saved
    }

    @MainActor private func pauseNativePlayer(_ app: XCUIApplication) async throws {
        let status = app.staticTexts["fixture.player.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Fixture native status: 2"), object: status)
        let playingResult = await XCTWaiter.fulfillment(of: [playing], timeout: 6)
        XCTAssertEqual(playingResult, .completed, "Pause test must begin with an actually playing AVPlayer")
        showControls(app)
        let button = app.buttons["Play/Pause"]
        XCTAssertTrue(button.isHittable)
        button.tap()
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Fixture native status: 0"), object: status)
        let pausedResult = await XCTWaiter.fulfillment(of: [paused], timeout: 5)
        XCTAssertEqual(pausedResult, .completed)
        XCTAssertEqual(status.label, "Fixture native status: 0", "AVPlayer must actually be paused before seeking")

    }

    @MainActor private func showControls(_ app: XCUIApplication) {
        let surface = app.otherElements["video.player.surface"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 8))
        if !app.buttons["Play/Pause"].isHittable {
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).tap()
        }
        XCTAssertTrue(app.buttons["Play/Pause"].waitForExistence(timeout: 5))
    }
    @MainActor private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func mode(offline: Bool, reset: Bool = false, codec: String? = nil, deleteError: Bool? = nil) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:18086/fixture-mode")!)
        var payload: [String: Any] = ["offline": offline, "reset": reset]
        if let codec { payload["codec"] = codec }
        if let deleteError { payload["deleteError"] = deleteError }
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        _ = try await URLSession.shared.data(for: request)
    }
    private func counts() async throws -> [String: Int] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:18086/fixture-state")!)
        let all = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return all.compactMapValues { ($0 as? NSNumber)?.intValue }
    }
}
