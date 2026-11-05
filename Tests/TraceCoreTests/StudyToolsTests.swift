import XCTest
import simd
@testable import TraceCore

final class StudyToolsTests: XCTestCase {
    private func fixture() -> MotionTake {
        let frames = (0...10).map { i in
            let p = JointPose(position: [Float(i) * 0.01, 1, 0])
            return MotionFrame(time: Double(i) / 10, hands: [.init(side: .left, tracked: true, joints: ["wrist": p, "indexFingerTip": p])], trackingState: "fixture")
        }
        return MotionTake(title: "Synthetic test", source: .simulatorSample, selection: .left, frames: frames)
    }
    func testLoopKeepsOvershootInBothDirections() {
        let range = PlaybackRegion(start: 2, end: 4, duration: 6)
        XCTAssertEqual(range.advanced(from: 3.9, by: 0.4, speed: 1, reverse: false, loops: true).time, 2.3, accuracy: 0.00001)
        XCTAssertEqual(range.advanced(from: 2.1, by: 0.4, speed: 1, reverse: true, loops: true).time, 3.7, accuracy: 0.00001)
        XCTAssertEqual(range.advanced(from: 3, by: 10.5, speed: 2, reverse: false, loops: true).time, 2, accuracy: 0.00001)
    }
    func testNonloopStopsAtRegionEdges() {
        let range = PlaybackRegion(start: 2, end: 4, duration: 6)
        let forward = range.advanced(from: 3.9, by: 0.5, speed: 1, reverse: false, loops: false)
        let reverse = range.advanced(from: 2.1, by: 0.5, speed: 1, reverse: true, loops: false)
        XCTAssertEqual(forward.time, 4); XCTAssertTrue(forward.finished)
        XCTAssertEqual(reverse.time, 2); XCTAssertTrue(reverse.finished)
    }
    func testRegionRejectsNonfiniteAndClampsOutOfBounds() {
        XCTAssertEqual(PlaybackRegion(start: -2, end: 20, duration: 6), .init(end: 6, duration: 6))
        let empty = PlaybackRegion(start: 10, end: -1, duration: 6)
        XCTAssertEqual(empty.duration, 0)
        XCTAssertTrue(empty.advanced(from: .nan, by: 1, speed: 1, reverse: false, loops: true).finished)
        XCTAssertEqual(PlaybackRegion(start: .nan, end: .infinity, duration: 6).duration, 6)
    }
    func testTrimCreatesIndependentStudyAndInterpolatesBoundaries() throws {
        let original = fixture()
        let copy = try XCTUnwrap(MotionEditing.trimmed(original, region: .init(start: 0.25, end: 0.75, duration: 1)))
        XCTAssertTrue(copy.isValid); XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.duration, 0.5, accuracy: 0.00001)
        XCTAssertEqual(copy.frames.first!.time, 0)
        XCTAssertEqual(copy.frames.first!.hands[0].joints["wrist"]!.position.x, 0.025, accuracy: 0.00001)
        XCTAssertEqual(copy.frames.last!.hands[0].joints["wrist"]!.position.x, 0.075, accuracy: 0.00001)
        XCTAssertEqual(original.frames.count, 11); XCTAssertEqual(original.duration, 1)
        XCTAssertEqual(copy.source, .simulatorSample); XCTAssertEqual(copy.coordinateSystem, original.coordinateSystem)
    }
    func testTrimPreservesLowConfidence() throws {
        var take = fixture(); take.frames[3].hands[0].joints["wrist"]!.tracked = false
        let copy = try XCTUnwrap(MotionEditing.trimmed(take, region: .init(start: 0.25, end: 0.75, duration: 1)))
        XCTAssertFalse(copy.frames[0].hands[0].joints["wrist"]!.tracked)
        XCTAssertNil(MotionEditing.trimmed(take, region: .init(start: 0.2, end: 0.21, duration: 1)))
    }
    func testDistanceAndPeakSpeedUseOnlyMeasuredContinuousWristFrames() {
        let summary = MotionAnalysis.summary(fixture(), side: .left)
        XCTAssertEqual(summary.distance, 0.1, accuracy: 0.00001)
        XCTAssertEqual(summary.peakSpeed, 0.1, accuracy: 0.00001)
        XCTAssertEqual(summary.coverage, 1)
        var take = fixture(); take.frames[5].hands[0].joints["wrist"]!.tracked = false
        let broken = MotionAnalysis.summary(take, side: .left)
        XCTAssertEqual(broken.distance, 0.08, accuracy: 0.00001)
        XCTAssertEqual(broken.trackedFrames, 10)
        take.frames = [take.frames[0], take.frames[10]]
        XCTAssertEqual(MotionAnalysis.summary(take, side: .left).distance, 0)
    }
    func testPathsNeverBridgeMissingOrInferredJoints() {
        var take = fixture(); take.frames[5].hands[0].joints["indexFingerTip"]!.tracked = false
        let paths = MotionAnalysis.paths(take, side: .left)
        XCTAssertEqual(paths.map(\.count), [5, 5])
        take.frames = [take.frames[0], take.frames[10]]
        XCTAssertTrue(MotionAnalysis.paths(take, side: .left).isEmpty)
    }
    func testRotationKeepsPivotAndCompletesFullTurnWithoutChangingData() {
        let center = SIMD3<Float>(0, 1.4, -0.2), point = center + [0.1, 0, 0]
        XCTAssertLessThan(simd_distance(InspectionTransform.point(point, around: center, yaw: 360, pitch: 0), point), 0.00001)
        XCTAssertLessThan(simd_distance(InspectionTransform.point(center, around: center, yaw: 130, pitch: 75, scale: 2), center), 0.00001)
        let opposite = InspectionTransform.point(point, around: center, yaw: 180, pitch: 0)
        XCTAssertEqual(opposite.x, -0.1, accuracy: 0.00001)
        XCTAssertLessThan(simd_distance(MotionAnalysis.center(fixture()), [0.05, 1, 0]), 0.00001)
    }
    func testJSONRoundTripAndCSVKeepUnitsTimestampsAndConfidence() throws {
        var take = fixture(); take.frames[3].hands[0].joints["wrist"]!.tracked = false
        let decoded = try JSONDecoder().decode(MotionTake.self, from: MotionExport.json(take))
        XCTAssertEqual(decoded.id, take.id); XCTAssertTrue(decoded.isValid)
        XCTAssertFalse(decoded.frames[3].hands[0].joints["wrist"]!.tracked)
        let csv = String(decoding: MotionExport.csv(take), as: UTF8.self)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 23)
        XCTAssertTrue(lines[0].contains("x_m,y_m,z_m,qx,qy,qz,qw"))
        XCTAssertTrue(csv.contains("simulatorSample,stage-relative-meters-y-up-v1,0.300000,left,true,\"wrist\",false"))
    }
    func testCSVRetainsMissingHandsAndNeutralizesSpreadsheetFormulas() {
        var take = fixture(); take.frames[1].hands = [.missing(.left)]
        take.frames[2].hands[0].joints["=formula"] = .init(position: [0,1,0])
        let csv = String(decoding: MotionExport.csv(take), as: UTF8.self)
        XCTAssertTrue(csv.contains("0.100000,left,false,,false,,,,,,,"))
        XCTAssertTrue(csv.contains("\"'=formula\""))
    }
}
