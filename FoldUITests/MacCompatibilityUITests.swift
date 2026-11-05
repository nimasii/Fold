#if targetEnvironment(macCatalyst)
import XCTest

final class MacCompatibilityUITests: XCTestCase {
    @MainActor func testLibraryDownloadsAndQueueNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--streaming-fixture", "--streaming-fixture-dark", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play,")).firstMatch.waitForExistence(timeout: 15))
        capture(app, "mac-library")
        let downloads = app.radioButtons["Downloads"].firstMatch
        XCTAssertTrue(downloads.waitForExistence(timeout: 5)); downloads.tap()
        capture(app, "mac-downloads")
        let queue = app.radioButtons["Queue"].firstMatch
        XCTAssertTrue(queue.waitForExistence(timeout: 5)); queue.tap()
        capture(app, "mac-queue")
        app.terminate()
    }

    @MainActor func testVLCPlaybackSeekingRepeatedFullscreenAndReopening() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--playback-fixture", "--playback-fixture-vlc", "-AppleLanguages", "(en)"]
        for launch in 0..<2 {
            app.launch()
            XCTAssertTrue(app.buttons["Online video"].waitForExistence(timeout: 10)); app.buttons["Online video"].tap()
            XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10)); app.buttons["Play"].tap()
            let elapsed = app.staticTexts["vlc.elapsed"]
            XCTAssertTrue(elapsed.waitForExistence(timeout: 15))
            let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "0:00"), object: elapsed)
            let result = await XCTWaiter.fulfillment(of: [advanced], timeout: 10)
            XCTAssertEqual(result, .completed)
            let playPause = app.buttons["vlc.playpause"]
            if !playPause.isHittable { app.otherElements["video.player.surface"].firstMatch.tap() }
            playPause.tap()
            for cycle in 0..<3 {
                let fullscreen = app.buttons["vlc.fullscreen"]
                XCTAssertTrue(fullscreen.waitForExistence(timeout: 5)); fullscreen.tap()
                capture(app, "mac-vlc-fullscreen-\(launch)-\(cycle)")
                XCTAssertTrue(fullscreen.waitForExistence(timeout: 5)); fullscreen.tap()
                XCTAssertTrue(app.buttons["Pin player"].waitForExistence(timeout: 5))
            }
            app.sliders["vlc.timeline"].adjust(toNormalizedSliderPosition: 0.5)
            capture(app, "mac-vlc-inline-seek-\(launch)")
            app.terminate() // Closing during an active player must drain its outputs.
        }
    }

    @MainActor func testAVKitPlaybackAndFullscreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--playback-fixture", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["Online video"].waitForExistence(timeout: 10)); app.buttons["Online video"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10)); app.buttons["Play"].tap()
        let fullscreen = app.buttons["Fullscreen Button"]
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 15)); fullscreen.tap()
        capture(app, "mac-avkit-fullscreen")
        app.terminate()
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
}
#endif
