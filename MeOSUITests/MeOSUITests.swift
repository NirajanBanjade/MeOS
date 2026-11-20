import XCTest

@MainActor
final class MeOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFreshLaunchPresentationPathAndRapidTapSafety() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UI_TEST_FRESH_START"]
        app.launch()

        let start = app.buttons["home.primaryAction"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "First enabled interaction must be reachable within 15 seconds")
        start.doubleTap()
        XCTAssertTrue(app.buttons["game.pause"].waitForExistence(timeout: 3))

        app.buttons["game.server"].tap()
        XCTAssertTrue(app.staticTexts["Server"].waitForExistence(timeout: 2))
        app.buttons["Close"].tap()

        app.buttons["game.pause"].tap()
        app.buttons["pause.glossary"].tap()
        XCTAssertTrue(app.staticTexts["Component Glossary"].waitForExistence(timeout: 2))
        app.buttons["Close"].tap()
    }

    func testSoundCreditsPauseAndResumeAreAccessible() {
        let app = XCUIApplication()
        app.launch()
        let sound = app.buttons["home.soundToggle"]
        XCTAssertTrue(sound.waitForExistence(timeout: 5))
        sound.tap()
        app.buttons["home.credits"].tap()
        XCTAssertTrue(app.staticTexts["Credits"].waitForExistence(timeout: 2))
        app.buttons["Close"].tap()

        app.buttons["home.primaryAction"].tap()
        app.buttons["game.pause"].tap()
        app.buttons["pause.resume"].tap()
        XCTAssertTrue(app.buttons["game.pause"].exists)
    }

    func testContinueAppearsAfterValidCheckpoint() {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TEST_FRESH_START"]
        app.launch()
        app.buttons["home.primaryAction"].tap()
        app.buttons["game.pause"].tap()
        app.buttons["pause.home"].tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 3))
    }

    func testReduceMotionRetainsStateFeedback() {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TEST_REDUCE_MOTION"]
        app.launch()
        app.buttons["home.primaryAction"].tap()
        app.buttons["game.mission"].tap()
        XCTAssertTrue(app.staticTexts["Current objective"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Permitted actions"].exists)
    }

    func testAccessibilityTextSizeKeepsPrimaryPathOperable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UI_TEST_FRESH_START",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()
        let primary = app.buttons["home.primaryAction"]
        XCTAssertTrue(primary.waitForExistence(timeout: 15))
        if !primary.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(primary.isHittable)
        primary.tap()
        XCTAssertTrue(app.buttons["game.pause"].waitForExistence(timeout: 3))
    }

    func testEngineerTeachingCardAndDirectAccessibleInteraction() {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TEST_FRESH_START"]
        app.launch()
        app.buttons["home.primaryAction"].tap()

        XCTAssertTrue(app.staticTexts["System Engineer"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Inspect the Server to learn how requests are processed."].exists)
        app.buttons["engineer.introduction.dismiss"].tap()

        app.buttons["game.accessibleInteractions"].tap()
        XCTAssertTrue(app.staticTexts["Accessible Interactions"].waitForExistence(timeout: 2))
        let server = app.buttons["accessible.server"]
        XCTAssertTrue(server.waitForExistence(timeout: 2))
        server.tap()

        XCTAssertTrue(app.staticTexts["First-discovery teaching card"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["What it is"].exists)
        XCTAssertTrue(app.staticTexts["Why this mission uses it"].exists)
        app.buttons["teaching.continue.server"].tap()
        XCTAssertTrue(app.staticTexts["Component inspection"].waitForExistence(timeout: 2))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["game.pause"].exists)
    }

    func testLockedObjectsExposePurposeAndAvailabilityWithoutActing() {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TEST_FRESH_START"]
        app.launch()
        app.buttons["home.primaryAction"].tap()
        app.buttons["game.accessibleInteractions"].tap()

        let cpuName = app.descendants(matching: .any)["accessible.name.cpuStation"]
        XCTAssertTrue(cpuName.waitForExistence(timeout: 2))
        let cpu = app.descendants(matching: .any)["accessible.cpuStation"]
        XCTAssertTrue(cpu.waitForExistence(timeout: 2))
        XCTAssertEqual(cpu.value as? String, "Unlocks in Mission 2")
        XCTAssertFalse(cpu.isEnabled)
    }
}

