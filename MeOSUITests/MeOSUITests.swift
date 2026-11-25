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

    func testMission3InstallConnectRoundTripWorkloadAndMission4Unlock() {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TEST_FRESH_START", "-UI_TEST_MISSION_3", "-UI_TEST_REDUCE_MOTION"]
        app.launch()
        app.buttons["home.primaryAction"].tap()
        app.buttons["game.mission"].tap()
        app.buttons["mission.primaryAction"].tap()

        XCTAssertTrue(app.buttons["mission3.install"].waitForExistence(timeout: 3))
        app.buttons["mission3.install"].tap()
        XCTAssertTrue(app.buttons["mission3.connect"].waitForExistence(timeout: 3))
        app.buttons["mission3.connect"].tap()

        let scroll = app.scrollViews["panel.scroll"]
        let write = app.buttons["mission3.write"]
        for _ in 0..<5 where !write.isHittable { scroll.swipeUp() }
        XCTAssertTrue(write.isHittable)
        write.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mission3.feedback"].waitForExistence(timeout: 3))

        let read = app.buttons["mission3.read"]
        for _ in 0..<3 where !read.isHittable { scroll.swipeDown() }
        XCTAssertTrue(read.isHittable)
        read.tap()

        let workload = app.buttons["mission3.runWorkload"]
        for _ in 0..<8 where !workload.isHittable { scroll.swipeUp() }
        XCTAssertTrue(workload.waitForExistence(timeout: 3))
        workload.tap()
        let complete = app.descendants(matching: .any)["mission3.complete"]
        for _ in 0..<8 where !complete.isHittable { scroll.swipeUp() }
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["mission3.operationCounts"].exists)

        let continueButton = app.buttons["mission3.continue"]
        for _ in 0..<5 where !continueButton.isHittable { scroll.swipeUp() }
        continueButton.tap()
        XCTAssertTrue(app.staticTexts["Mission 4 · Infrastructure Scaling"].waitForExistence(timeout: 3))
    }

    func testMission4BaselineServerTradeoffResetCacheVictoryAndMission5Unlock() {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TEST_FRESH_START", "-UI_TEST_MISSION_4", "-UI_TEST_REDUCE_MOTION"]
        app.launch()
        app.buttons["home.primaryAction"].tap()
        app.buttons["game.mission"].tap()
        app.buttons["mission.primaryAction"].tap()

        XCTAssertTrue(app.buttons["mission4.runBaseline"].waitForExistence(timeout: 3))
        app.buttons["mission4.runBaseline"].tap()
        let scroll = app.scrollViews["panel.scroll"]
        let server = app.buttons["mission4.upgrade.secondServer"]
        for _ in 0..<6 where !server.isHittable { scroll.swipeUp() }
        server.tap()
        let runUpgrade = app.buttons["mission4.runUpgrade"]
        for _ in 0..<6 where !runUpgrade.isHittable { scroll.swipeUp() }
        runUpgrade.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mission4.feedback"].label.contains("received no traffic"))

        let reset = app.buttons["mission4.reset"]
        for _ in 0..<12 where !reset.isHittable { scroll.swipeUp() }
        reset.tap()
        let baseline = app.buttons["mission4.runBaseline"]
        for _ in 0..<12 where !baseline.isHittable { scroll.swipeDown() }
        baseline.tap()
        let cache = app.buttons["mission4.upgrade.cache"]
        for _ in 0..<6 where !cache.isHittable { scroll.swipeUp() }
        cache.tap()
        for _ in 0..<6 where !runUpgrade.isHittable { scroll.swipeUp() }
        runUpgrade.tap()

        let complete = app.descendants(matching: .any)["mission4.complete"]
        for _ in 0..<12 where !complete.isHittable { scroll.swipeUp() }
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["mission4.metrics"].exists)
        let continueButton = app.buttons["mission4.continue"]
        for _ in 0..<5 where !continueButton.isHittable { scroll.swipeUp() }
        continueButton.tap()
        XCTAssertTrue(app.staticTexts["Mission 5 · System Diagnostics"].waitForExistence(timeout: 3))
    }

    func testMission4ReplicaPathIsAValidMeasuredSolution() {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TEST_FRESH_START", "-UI_TEST_MISSION_4", "-UI_TEST_REDUCE_MOTION"]
        app.launch()
        app.buttons["home.primaryAction"].tap()
        app.buttons["game.mission"].tap()
        app.buttons["mission.primaryAction"].tap()
        app.buttons["mission4.runBaseline"].tap()

        let scroll = app.scrollViews["panel.scroll"]
        let replica = app.buttons["mission4.upgrade.readReplica"]
        for _ in 0..<6 where !replica.isHittable { scroll.swipeUp() }
        replica.tap()
        let run = app.buttons["mission4.runUpgrade"]
        for _ in 0..<6 where !run.isHittable { scroll.swipeUp() }
        run.tap()
        let complete = app.descendants(matching: .any)["mission4.complete"]
        for _ in 0..<12 where !complete.isHittable { scroll.swipeUp() }
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["mission4.feedback"].label.contains("split across two"))
    }

    func testMission5AlertEvidenceWrongRetryRepairTitleAndReplay() {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TEST_FRESH_START", "-UI_TEST_MISSION_5", "-UI_TEST_REDUCE_MOTION"]
        app.launch()
        app.buttons["home.primaryAction"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["mission5.alert"].waitForExistence(timeout: 3))
        app.buttons["mission5.alert.investigate"].tap()
        if app.buttons["teaching.continue.monitoringTerminal"].waitForExistence(timeout: 2) {
            app.buttons["teaching.continue.monitoringTerminal"].tap()
        }

        let scroll = app.scrollViews["panel.scroll"]
        let baseline = app.buttons["mission5.captureBaseline"]
        XCTAssertTrue(baseline.waitForExistence(timeout: 3))
        baseline.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mission5.evidenceGate"].exists)

        let cpu = app.buttons["mission5.evidence.cpu"]
        for _ in 0..<5 where !cpu.isHittable { scroll.swipeUp() }
        cpu.tap()
        XCTAssertFalse(app.buttons["mission5.intervention.increasedWorkers"].exists)

        let database = app.buttons["mission5.evidence.database"]
        for _ in 0..<5 where !database.isHittable { scroll.swipeUp() }
        database.tap()
        let workers = app.buttons["mission5.intervention.increasedWorkers"]
        for _ in 0..<8 where !workers.isHittable { scroll.swipeUp() }
        XCTAssertTrue(workers.waitForExistence(timeout: 3))
        workers.tap()

        let verify = app.buttons["mission5.verify"]
        for _ in 0..<5 where !verify.isHittable { scroll.swipeUp() }
        verify.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mission5.feedback"].label.contains("1650 ms"))

        let retry = app.buttons["mission5.retry"]
        for _ in 0..<10 where !retry.isHittable { scroll.swipeUp() }
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        retry.tap()

        let cache = app.buttons["mission5.intervention.cache"]
        for _ in 0..<10 where !cache.isHittable { scroll.swipeDown() }
        for _ in 0..<10 where !cache.isHittable { scroll.swipeUp() }
        XCTAssertTrue(cache.isHittable)
        cache.tap()
        for _ in 0..<6 where !verify.isHittable { scroll.swipeUp() }
        verify.tap()

        let complete = app.descendants(matching: .any)["mission5.complete"]
        for _ in 0..<10 where !complete.isHittable { scroll.swipeUp() }
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["MeOS System Architect"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["mission5.metrics"].exists)

        app.buttons["Close"].tap()
        app.buttons["game.mission"].tap()
        let replay = app.buttons["mission.replay.5"]
        let briefingScroll = app.scrollViews["panel.scroll"]
        for _ in 0..<12 where !replay.isHittable { briefingScroll.swipeUp() }
        XCTAssertTrue(replay.waitForExistence(timeout: 3))
        replay.tap()
        XCTAssertTrue(app.staticTexts["Mission 5 · System Diagnostics"].waitForExistence(timeout: 3))
        app.buttons["game.mission"].tap()
        app.buttons["mission.primaryAction"].tap()
        XCTAssertTrue(app.buttons["mission5.captureBaseline"].waitForExistence(timeout: 3))
    }

    func testCleanInstallAllMissionsAndThreeMinuteLearningPath() {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TEST_FRESH_START", "-UI_TEST_REDUCE_MOTION"]
        let journeyStart = ProcessInfo.processInfo.systemUptime
        app.launch()

        let start = app.buttons["home.primaryAction"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        app.buttons["game.server"].tap()
        let firstDiscovery = app.buttons["teaching.continue.server"]
        if firstDiscovery.waitForExistence(timeout: 2) { firstDiscovery.tap() }

        app.buttons["mission1.receiveCards"].tap()
        app.buttons["mission1.startServer"].tap()
        let mission1Scroll = app.scrollViews["panel.scroll"]
        let mission1Finish = app.buttons["mission1.finishPresentation"]
        reveal(mission1Finish, in: mission1Scroll, scrollUp: true)
        mission1Finish.tap()
        let queueAnswer = app.buttons["mission1.cause.queueWhileWorkerBusy"]
        reveal(queueAnswer, in: mission1Scroll, scrollUp: true)
        queueAnswer.tap()
        let firstLearningElapsed = ProcessInfo.processInfo.systemUptime - journeyStart
        XCTAssertLessThanOrEqual(firstLearningElapsed, 60, "The first learning outcome should be reachable within one minute.")
        let mission1Continue = app.buttons["mission1.continue"]
        reveal(mission1Continue, in: mission1Scroll, scrollUp: true)
        mission1Continue.tap()

        app.buttons["game.server"].tap()
        app.buttons["mission2.runBaseline"].tap()
        let mission2Scroll = app.scrollViews["panel.scroll"]
        let mission2Finish = app.buttons["mission2.finishPresentation"]
        reveal(mission2Finish, in: mission2Scroll, scrollUp: true)
        mission2Finish.tap()
        let twoWorkers = app.buttons["mission2.worker.2"]
        reveal(twoWorkers, in: mission2Scroll, scrollUp: false)
        twoWorkers.tap()
        let comparison = app.buttons["mission2.runComparison"]
        reveal(comparison, in: mission2Scroll, scrollUp: true)
        comparison.tap()
        reveal(mission2Finish, in: mission2Scroll, scrollUp: true)
        mission2Finish.tap()
        let mission2Continue = app.buttons["mission2.continue"]
        reveal(mission2Continue, in: mission2Scroll, scrollUp: true)
        mission2Continue.tap()

        openCurrentMission(in: app)
        let install = app.buttons["mission3.install"]
        XCTAssertTrue(install.waitForExistence(timeout: 3))
        install.tap()
        app.buttons["mission3.connect"].tap()
        let mission3Scroll = app.scrollViews["panel.scroll"]
        let write = app.buttons["mission3.write"]
        reveal(write, in: mission3Scroll, scrollUp: true)
        write.tap()
        let read = app.buttons["mission3.read"]
        reveal(read, in: mission3Scroll, scrollUp: false)
        read.tap()
        let databaseWorkload = app.buttons["mission3.runWorkload"]
        reveal(databaseWorkload, in: mission3Scroll, scrollUp: true)
        databaseWorkload.tap()
        let mission3Continue = app.buttons["mission3.continue"]
        reveal(mission3Continue, in: mission3Scroll, scrollUp: true)
        mission3Continue.tap()

        openCurrentMission(in: app)
        app.buttons["mission4.runBaseline"].tap()
        let mission4Scroll = app.scrollViews["panel.scroll"]
        let cacheUpgrade = app.buttons["mission4.upgrade.cache"]
        reveal(cacheUpgrade, in: mission4Scroll, scrollUp: true)
        cacheUpgrade.tap()
        let runUpgrade = app.buttons["mission4.runUpgrade"]
        reveal(runUpgrade, in: mission4Scroll, scrollUp: true)
        runUpgrade.tap()
        let mission4Continue = app.buttons["mission4.continue"]
        reveal(mission4Continue, in: mission4Scroll, scrollUp: true)
        mission4Continue.tap()

        let alert = app.descendants(matching: .any)["mission5.alert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        app.buttons["mission5.alert.investigate"].tap()
        let terminalTeaching = app.buttons["teaching.continue.monitoringTerminal"]
        if terminalTeaching.waitForExistence(timeout: 2) { terminalTeaching.tap() }
        app.buttons["mission5.captureBaseline"].tap()
        let mission5Scroll = app.scrollViews["panel.scroll"]
        let cpuEvidence = app.buttons["mission5.evidence.cpu"]
        reveal(cpuEvidence, in: mission5Scroll, scrollUp: true)
        cpuEvidence.tap()
        let databaseEvidence = app.buttons["mission5.evidence.database"]
        reveal(databaseEvidence, in: mission5Scroll, scrollUp: true)
        databaseEvidence.tap()
        let diagnosticCache = app.buttons["mission5.intervention.cache"]
        reveal(diagnosticCache, in: mission5Scroll, scrollUp: true)
        diagnosticCache.tap()
        let verify = app.buttons["mission5.verify"]
        reveal(verify, in: mission5Scroll, scrollUp: true)
        verify.tap()
        XCTAssertTrue(app.staticTexts["MeOS System Architect"].waitForExistence(timeout: 3))

        let totalElapsed = ProcessInfo.processInfo.systemUptime - journeyStart
        XCTAssertLessThanOrEqual(totalElapsed, 180, "The complete primary demonstration should take about three minutes or less.")
    }

    private func openCurrentMission(in app: XCUIApplication) {
        app.buttons["game.mission"].tap()
        app.buttons["mission.primaryAction"].tap()
    }

    private func reveal(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        scrollUp: Bool,
        maxSwipes: Int = 8
    ) {
        for _ in 0..<maxSwipes where !element.isHittable {
            if scrollUp { scrollView.swipeUp() }
            else { scrollView.swipeDown() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        XCTAssertTrue(element.isHittable)
    }
}
