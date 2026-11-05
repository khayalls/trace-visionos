import XCTest

@MainActor
final class TraceUITests: XCTestCase {
    func testChamberRecordingPlaybackAndPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(control("enterChamber", in: app).waitForExistence(timeout: 25))
        control("enterChamber", in: app).tap()
        XCTAssertTrue(control("exitChamber", in: app).waitForExistence(timeout: 30))
        if control("dismissIntro", in: app).exists { control("dismissIntro", in: app).tap() }
        openMore(in: app)
        control("loadSample", in: app).tap()
        XCTAssertTrue(app.sliders["playbackTimeline"].waitForExistence(timeout: 10))
        XCTAssertTrue(control("playbackMode", in: app).isSelected)
        XCTAssertFalse(control("recordMovement", in: app).exists)
        control("playPause", in: app).tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        control("playPause", in: app).tap()
        // Xcode's immersive slider lacks scrubber coordinates; accessible stepping shares its scrub action.
        let beforeStep = app.staticTexts["playbackTime"].label
        control("stepForward", in: app).tap()
        XCTAssertNotEqual(app.staticTexts["playbackTime"].label, beforeStep)
        control("playbackSpeed", in: app).tap()
        XCTAssertEqual(control("playbackSpeed", in: app).value as? String, "0.5×")
        control("restartPlayback", in: app).tap()
        control("playPause", in: app).tap()
        openMore(in: app)
        XCTAssertEqual(control("sampleInput", in: app).label, "Enable sample input")
        control("sampleInput", in: app).tap()
        control("captureMode", in: app).tap()
        XCTAssertTrue(control("captureMode", in: app).isSelected)
        XCTAssertFalse(control("playPause", in: app).exists)
        XCTAssertTrue(control("recordMovement", in: app).isEnabled, app.debugDescription)
        control("handSelection", in: app).tap()
        XCTAssertTrue(control("handChoice_left", in: app).waitForExistence(timeout: 5))
        control("handChoice_left", in: app).tap()
        XCTAssertEqual(control("handSelection", in: app).value as? String, "Left hand")
        control("handSelection", in: app).tap()
        control("handChoice_both", in: app).tap()
        control("recordMovement", in: app).tap()
        XCTAssertTrue(control("cancelCountdown", in: app).waitForExistence(timeout: 3), app.debugDescription)
        control("cancelCountdown", in: app).tap()
        control("recordMovement", in: app).tap()
        XCTAssertTrue(control("stopRecording", in: app).waitForExistence(timeout: 8))
        control("stopRecording", in: app).tap()
        XCTAssertTrue(control("playPause", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(control("playbackMode", in: app).isSelected)
        control("captureMode", in: app).tap()
        control("recordMovement", in: app).tap()
        XCTAssertTrue(control("stopRecording", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(control("playPause", in: app).waitForExistence(timeout: 16))
        XCTAssertTrue(app.staticTexts["playbackTime"].label.contains("10.0 s"))
        control("exitChamber", in: app).tap()
        XCTAssertTrue(control("enterChamber", in: app).waitForExistence(timeout: 15))
        app.terminate(); app.launch()
        XCTAssertTrue(control("enterChamber", in: app).waitForExistence(timeout: 25))
        control("enterChamber", in: app).tap()
        XCTAssertTrue(control("playPause", in: app).waitForExistence(timeout: 30))
        XCTAssertTrue(control("playbackMode", in: app).isSelected)
        control("exitChamber", in: app).tap()
    }
    private func control(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    func testStudyInspectionLoopAndExport() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(control("enterChamber", in: app).waitForExistence(timeout: 25))
        control("enterChamber", in: app).tap()
        XCTAssertTrue(control("exitChamber", in: app).waitForExistence(timeout: 30))
        if control("dismissIntro", in: app).exists { control("dismissIntro", in: app).tap() }
        openMore(in: app); control("loadSample", in: app).tap()
        control("viewTools", in: app).tap()
        control("viewOpposite", in: app).tap()
        XCTAssertEqual(app.staticTexts["viewAngle"].label, "180°")
        control("viewOriginal", in: app).tap()
        for _ in 0..<4 { control("turnRight", in: app).tap() }
        XCTAssertEqual(app.staticTexts["viewAngle"].label, "0°")
        control("viewSide", in: app).tap()
        XCTAssertEqual(app.staticTexts["viewAngle"].label, "90°")
        control("resetView", in: app).tap()
        XCTAssertEqual(app.staticTexts["viewAngle"].label, "0°")
        control("motionPaths", in: app).tap()
        control("closePanel", in: app).tap()
        control("loopTools", in: app).tap()
        control("loopStepAhead", in: app).tap(); control("loopStepAhead", in: app).tap()
        control("markLoopStart", in: app).tap()
        control("loopStepAhead", in: app).tap(); control("loopStepAhead", in: app).tap()
        control("markLoopEnd", in: app).tap()
        XCTAssertTrue(app.staticTexts["loopRange"].label.contains("1.0 to 2.0"))
        control("loopEnabled", in: app).tap(); control("reversePlayback", in: app).tap()
        control("saveSelection", in: app).tap()
        XCTAssertTrue(app.staticTexts["playbackTime"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["playbackTime"].label.contains("1.0 s"))
        control("insightTools", in: app).tap()
        XCTAssertTrue(app.staticTexts["Wrist travel"].firstMatch.exists)
        control("exportStudy", in: app).tap()
        // Xcode 27 can retain the immersive query root after a window handoff.
        // A fresh hierarchy snapshot verifies the actual returned export page.
        let returned = NSPredicate { _, _ in app.debugDescription.contains("identifier: 'exportCSV'") }
        expectation(for: returned, evaluatedWith: nil)
        waitForExpectations(timeout: 20)
        app.terminate()
    }
    func testNativeCSVAndJSONExportPickers() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--preview-export"]; app.launch()
        XCTAssertTrue(control("exportCSV", in: app).waitForExistence(timeout: 25), app.debugDescription)
        control("exportCSV", in: app).tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["Cancel"].firstMatch.tap()
        control("exportJSON", in: app).tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["Cancel"].firstMatch.tap()
        control("closeExport", in: app).tap()
    }
    private func openMore(in app: XCUIApplication) {
        control("studioMenu", in: app).tap()
        XCTAssertTrue(control("loadSample", in: app).waitForExistence(timeout: 5), app.debugDescription)
    }
}
