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
        XCTAssertTrue(app.staticTexts["Mission 1 · Sequential Server"].waitForExistence(timeout: 2))
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

    func testVisualizationControlsMetricsAndReducedMotionAlternative() {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TEST_FRESH_START", "-UI_TEST_REDUCE_MOTION"]
        app.launch()
        app.buttons["home.primaryAction"].tap()
        app.buttons["game.pause"].tap()
        app.buttons["pause.glossary"].tap()
        app.buttons["glossary.inspect.server"].tap()
        app.buttons["system.primaryAction"].tap()

        let play = app.buttons["visualization.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Reduced Motion: travel is replaced by highlights; event order and outcomes are unchanged."].exists)
        XCTAssertTrue(app.staticTexts["Completed"].exists)

        play.doubleTap()
        XCTAssertTrue(app.buttons["visualization.reset"].waitForExistence(timeout: 2))
        app.buttons["visualization.reset"].tap()
        XCTAssertTrue(play.isEnabled)

        let scroll = app.scrollViews["panel.scroll"]
        let timeline = app.descendants(matching: .any)["Scheduling timeline"]
        for _ in 0..<3 where !timeline.exists { scroll.swipeUp() }
        XCTAssertTrue(timeline.waitForExistence(timeout: 2))
        let architecture = app.descendants(matching: .any)["System architecture"]
        for _ in 0..<3 where !architecture.exists { scroll.swipeUp() }
        XCTAssertTrue(architecture.waitForExistence(timeout: 2))
    }

    func testMission1FromServerToUnderstandingAndMission2Unlock() {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TEST_FRESH_START", "-UI_TEST_REDUCE_MOTION"]
        app.launch()
        app.buttons["home.primaryAction"].tap()

        app.buttons["game.server"].tap()
        if app.buttons["teaching.continue.server"].waitForExistence(timeout: 2) {
            app.buttons["teaching.continue.server"].tap()
        }
        XCTAssertTrue(app.buttons["mission1.receiveCards"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Queue empty"].exists)
        XCTAssertFalse(app.buttons["mission1.startServer"].isEnabled)
        app.buttons["mission1.receiveCards"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mission1.requestIDs"].waitForExistence(timeout: 2))

        let start = app.buttons["mission1.startServer"]
        XCTAssertTrue(start.waitForExistence(timeout: 2))
        start.doubleTap()
        let metrics = app.descendants(matching: .any)["mission1.metrics"]
        XCTAssertTrue(metrics.waitForExistence(timeout: 3))

        let finish = app.buttons["mission1.finishPresentation"]
        let scroll = app.scrollViews["panel.scroll"]
        for _ in 0..<4 where !finish.isHittable { scroll.swipeUp() }
        if finish.waitForExistence(timeout: 2), finish.isEnabled { finish.tap() }
        XCTAssertTrue(app.staticTexts["Why did later requests wait?"].waitForExistence(timeout: 3))
        let wrong = app.buttons["mission1.cause.cpuWasMissing"]
        for _ in 0..<5 where !wrong.isHittable { scroll.swipeUp() }
        wrong.tap()
        XCTAssertEqual(
            app.descendants(matching: .any)["mission1.feedback"].label,
            "Not quite. The event history shows later requests queued while the single worker was occupied."
        )
        let correct = app.buttons["mission1.cause.queueWhileWorkerBusy"]
        for _ in 0..<3 where !correct.isHittable { scroll.swipeUp() }
        correct.tap()

        XCTAssertTrue(app.descendants(matching: .any)["mission1.complete"].waitForExistence(timeout: 3))
        let continueButton = app.buttons["mission1.continue"]
        for _ in 0..<5 where !continueButton.isHittable { scroll.swipeUp() }
        continueButton.tap()
        XCTAssertTrue(app.staticTexts["Mission 2 · Worker Concurrency"].waitForExistence(timeout: 3))
    }

    func testMission2BaselineComparisonRetryVictoryAndMission3Unlock() {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TEST_FRESH_START", "-UI_TEST_REDUCE_MOTION"]
        app.launch()
        app.buttons["home.primaryAction"].tap()

        // Complete Mission 1 through its deterministic reduced-motion path.
        app.buttons["game.server"].tap()
        if app.buttons["teaching.continue.server"].waitForExistence(timeout: 2) { app.buttons["teaching.continue.server"].tap() }
        app.buttons["mission1.receiveCards"].tap()
        app.buttons["mission1.startServer"].tap()
        let mission1Scroll = app.scrollViews["panel.scroll"]
        let mission1Finish = app.buttons["mission1.finishPresentation"]
        for _ in 0..<5 where !mission1Finish.isHittable { mission1Scroll.swipeUp() }
        if mission1Finish.isEnabled { mission1Finish.tap() }
        let correct = app.buttons["mission1.cause.queueWhileWorkerBusy"]
        for _ in 0..<5 where !correct.isHittable { mission1Scroll.swipeUp() }
        correct.tap()
        let continue1 = app.buttons["mission1.continue"]
        for _ in 0..<5 where !continue1.isHittable { mission1Scroll.swipeUp() }
        continue1.tap()

        app.buttons["game.server"].tap()
        XCTAssertTrue(app.buttons["mission2.runBaseline"].waitForExistence(timeout: 3))
        app.buttons["mission2.runBaseline"].tap()
        let scroll = app.scrollViews["panel.scroll"]
        let finish = app.buttons["mission2.finishPresentation"]
        for _ in 0..<6 where !finish.isHittable { scroll.swipeUp() }
        if finish.isEnabled { finish.tap() }

        let retry = app.buttons["mission2.retry"]
        for _ in 0..<8 where !retry.isHittable { scroll.swipeUp() }
        XCTAssertTrue(retry.exists)
        retry.tap()

        let restoredBaseline = app.buttons["mission2.runBaseline"]
        for _ in 0..<5 where !restoredBaseline.isHittable { scroll.swipeDown() }
        XCTAssertTrue(restoredBaseline.waitForExistence(timeout: 3))
        restoredBaseline.tap()
        for _ in 0..<6 where !finish.isHittable { scroll.swipeUp() }
        if finish.isEnabled { finish.tap() }

        let two = app.buttons["mission2.worker.2"]
        for _ in 0..<8 where !two.isHittable { scroll.swipeDown() }
        two.tap()
        app.buttons["mission2.runComparison"].tap()
        for _ in 0..<7 where !finish.isHittable { scroll.swipeUp() }
        if finish.isEnabled { finish.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["mission2.comparisonValues"].waitForExistence(timeout: 3))
        let complete = app.descendants(matching: .any)["mission2.complete"]
        for _ in 0..<7 where !complete.isHittable { scroll.swipeUp() }
        XCTAssertTrue(complete.exists)
        let continue2 = app.buttons["mission2.continue"]
        for _ in 0..<5 where !continue2.isHittable { scroll.swipeUp() }
        continue2.tap()
        XCTAssertTrue(app.staticTexts["Mission 3 · Database Storage"].waitForExistence(timeout: 3))
    }
}
