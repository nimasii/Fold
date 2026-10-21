import XCTest

/// Production screens with the loopback-only, in-memory fixture repository.
final class ApprovedCinemaUITests: XCTestCase {
    @MainActor func testCollectionsChannelDetailSheetsAndConfirmations() {
        continueAfterFailure = false
        let app = launch()
        app.buttons["library.playlists"].tap()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 5))
        capture(app, "13-collections")
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Above the atmosphere")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Above the atmosphere"].waitForExistence(timeout: 5))
        capture(app, "16-regular-collection")
        app.buttons["Delete Playlist"].tap()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5)); capture(app, "47-playlist-confirmation")
        cancel(app)
        back(app); back(app)
        openVisibleChannel(app, "Orbital Journal")
        XCTAssertTrue(app.navigationBars["Orbital Journal"].waitForExistence(timeout: 5))
        capture(app, "10-channel")
        app.buttons["About this channel"].tap()
        capture(app, "11-channel-about")
        back(app)
        app.buttons["video.card.earthrise"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Now showing"].waitForExistence(timeout: 5))
        capture(app, "18-video-description")
        app.buttons["video.actions"].tap()
        app.buttons["Add to Playlist"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5)); capture(app, "22-add-to-playlist")
        app.buttons["Done"].tap()
        app.buttons["video.actions"].tap(); app.buttons["Delete video"].tap()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5)); capture(app, "44-server-delete-confirmation")
        cancel(app)
        app.swipeUp()
        app.buttons["Comments"].tap(); capture(app, "20-comments")
        app.buttons["Similar"].tap(); capture(app, "21-similar")
        app.buttons["Description"].tap()
        app.buttons["Video details"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "File size:")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "19-expanded-metadata")
        app.terminate()
    }

    @MainActor func testPlaylistCreationAndLocalRemovalConfirmations() {
        continueAfterFailure = false
        let app = launch()
        app.buttons["library.playlists"].tap()
        app.buttons["playlist.create"].tap()
        let name = app.textFields["playlist.create.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["playlist.create.confirm"].isEnabled)
        name.tap(); name.typeText("UI fixture collection")
        capture(app, "15-create-playlist-keyboard")
        app.buttons["playlist.create.confirm"].tap()
        let collection = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "UI fixture collection")).firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 5)); collection.press(forDuration: 1)
        app.buttons["Delete Playlist"].tap()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5)); capture(app, "48-list-delete-cancel")
        cancel(app); back(app)
        app.tabBars.buttons["Downloads"].tap()
        let local = app.buttons.containing(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "video.card.", "On the edge of daylight")).firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 20)); local.press(forDuration: 1)
        app.buttons["Remove Local Copy"].tap()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5)); capture(app, "49-local-remove-cancel")
        cancel(app)
        XCTAssertTrue(local.exists)
        app.terminate()
    }

    @MainActor func testChannelSelectionAndBatchDeleteCancellation() {
        continueAfterFailure = false
        let app = launch()
        openVisibleChannel(app, "Orbital Journal")
        XCTAssertTrue(app.navigationBars["Orbital Journal"].waitForExistence(timeout: 5))
        let card = app.buttons["video.card.earthrise"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        for _ in 0..<3 where !card.isHittable { app.swipeUp() }
        card.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Delete selected"].waitForExistence(timeout: 5))
        capture(app, "12-channel-selection")
        app.buttons["Delete selected"].tap()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        capture(app, "45-batch-delete-cancel")
        cancel(app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(card.exists)
        app.terminate()
    }

    @MainActor func testHeroPlaysAndBackSurvivesRepeatedNavigation() {
        continueAfterFailure = false
        let app = launch()
        for _ in 0..<2 {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Resume, ")).firstMatch.tap()
            XCTAssertTrue(app.buttons["Pin player"].waitForExistence(timeout: 10))
            capture(app, "05-featured-direct-play")
            back(app)
            XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 5))
        }
        app.terminate()
    }

    @MainActor func testAboutLicensesAndSignOutCancel() {
        continueAfterFailure = false
        let app = launch()
        app.buttons["section.menu"].tap(); app.buttons["section.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5)); capture(app, "36-settings")
        let about = app.buttons["About"]
        for _ in 0..<6 where !about.isHittable { app.swipeUp() }
        about.tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5)); capture(app, "38-about")
        app.buttons["MobileVLCKit license"].tap()
        XCTAssertTrue(app.navigationBars["MobileVLCKit"].waitForExistence(timeout: 5)); capture(app, "39-vlc-license")
        app.swipeUp(); back(app)
        app.buttons["Fold license"].tap()
        XCTAssertTrue(app.navigationBars["Fold"].waitForExistence(timeout: 5)); capture(app, "40-fold-license")
        back(app); back(app)
        let logout = app.buttons["settings.logout"]
        for _ in 0..<6 where !logout.isHittable { app.swipeUp() }
        logout.tap(); XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5)); capture(app, "50-signout-cancel")
        cancel(app)
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        app.terminate()
    }

    @MainActor private func launch() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.jacobcampbell.ta-client")
        app.launchArguments = ["--streaming-fixture", "--streaming-fixture-reset", "--streaming-fixture-dark", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func openVisibleChannel(_ app: XCUIApplication, _ name: String) {
        // A label repeats in multiple shelves. XCTest's firstMatch auto-scroll can
        // target an offscreen duplicate after restoring a lazy scroll position.
        for _ in 0..<4 {
            let top = app.navigationBars.firstMatch.frame.maxY
            let bottom = app.tabBars.firstMatch.frame.minY
            if let button = app.buttons.matching(identifier: name).allElementsBoundByIndex.first(where: {
                $0.isHittable && $0.frame.minY >= top && $0.frame.maxY <= bottom
            }) { button.tap(); return }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTFail("No visible channel link: " + name)
    }

    @MainActor private func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor private func cancel(_ app: XCUIApplication) {
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
