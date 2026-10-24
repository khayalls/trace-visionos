import XCTest
import simd
@testable import TraceCore

final class TraceCoreTests: XCTestCase {
    func fixture(_ frames: [MotionFrame]) -> MotionTake { MotionTake(title: "Test", source: .device, selection: .both, frames: frames) }
    func hand(_ x: Float, tracked: Bool = true, jointTracked: Bool = true) -> HandPose {
        .init(side: .left, tracked: tracked, joints: ["indexFingerTip": .init(position: [x, 1, 0], orientation: simd_quatf(angle: x, axis: [0, 1, 0]).vector, tracked: jointTracked)])
    }
    func testInterpolatesActualJointPositionsAndRotations() {
        let take = fixture([.init(time: 0, hands: [hand(0)], trackingState: "running"), .init(time: 0.1, hands: [hand(1)], trackingState: "running")])
        let pose = MotionSampler.hands(in: take, at: 0.05)[0].joints["indexFingerTip"]!
        XCTAssertEqual(pose.position.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(simd_quatf(vector: pose.orientation).angle, 0.5, accuracy: 0.0001)
    }
    func testClampsToExactEndpoints() {
        let take = fixture([.init(time: 0, hands: [hand(0)], trackingState: "running"), .init(time: 0.1, hands: [hand(1)], trackingState: "running")])
        XCTAssertEqual(MotionSampler.hands(in: take, at: -5)[0].joints["indexFingerTip"]!.position.x, 0)
        XCTAssertEqual(MotionSampler.hands(in: take, at: 50)[0].joints["indexFingerTip"]!.position.x, 1)
    }
    func testLostTrackingDoesNotInventPose() {
        let take = fixture([.init(time: 0, hands: [hand(0)], trackingState: "running"), .init(time: 0.1, hands: [.missing(.left)], trackingState: "running")])
        XCTAssertFalse(MotionSampler.hands(in: take, at: 0.05)[0].tracked)
    }
    func testInferredJointKeepsTransformAndLowConfidenceDuringPlayback() {
        let take = fixture([.init(time: 0, hands: [hand(0)], trackingState: "running"), .init(time: 0.1, hands: [hand(1, jointTracked: false)], trackingState: "running")])
        let joint = MotionSampler.hands(in: take, at: 0.05)[0].joints["indexFingerTip"]!
        XCTAssertFalse(joint.tracked)
        XCTAssertEqual(joint.position.x,0.5,accuracy:0.0001)
    }
    func testLongGapIsHidden() {
        let take = fixture([.init(time: 0, hands: [hand(0)], trackingState: "running"), .init(time: 1, hands: [hand(1)], trackingState: "running")])
        XCTAssertTrue(MotionSampler.hands(in: take, at: 0.5).allSatisfy { !$0.tracked })
    }
    func testCaptureKeepsEstimatedOnlyHandWithoutPromotingConfidence() throws {
        var capture = CaptureBuffer(source: .device,selection: .left)
        for i in 0...2 { capture.append(time: Double(i)/60,hands:[hand(Float(i),jointTracked:false)],trackingState:"running") }
        let take = try XCTUnwrap(capture.finish())
        XCTAssertTrue(take.isValid)
        XCTAssertTrue(take.frames.allSatisfy { $0.hands[0].joints.values.allSatisfy { !$0.tracked } })
        let pose = MotionSampler.hands(in: take,at:0.01)[0]
        XCTAssertTrue(pose.tracked)
        XCTAssertFalse(pose.joints["indexFingerTip"]!.tracked)
    }
    func testCaptureLimitAndHandSelection() {
        var capture = CaptureBuffer(source: .device, selection: .left)
        for i in 0...720 { capture.append(time: Double(i) / 60, hands: SampleMotion.hands(at: Double(i) / 60), trackingState: "running") }
        let take = capture.finish()!
        XCTAssertEqual(take.duration, 10, accuracy: 0.0001)
        XCTAssertEqual(take.frames.count, 601)
        XCTAssertTrue(take.frames.allSatisfy { $0.hands.count == 1 && $0.hands[0].side == .left })
        XCTAssertEqual(take.source, .device)
    }
    func testRejectsEmptyAndNonmonotonicCapture() {
        var capture = CaptureBuffer(source: .device, selection: .both)
        capture.append(time: 0, hands: [], trackingState: "paused")
        capture.append(time: 0, hands: [], trackingState: "paused")
        capture.append(time: -1, hands: [], trackingState: "paused")
        capture.append(time: 0.1, hands: [], trackingState: "paused")
        XCTAssertEqual(capture.frames.count, 2)
        XCTAssertNil(capture.finish())
    }
    func testStableStageIgnoresSubsequentHeadMovement() {
        var device = matrix_identity_float4x4; device.columns.3 = [1, 1.2, 2, 1]
        let stage = StageCoordinates.initialStage(deviceTransform: device)
        var joint = matrix_identity_float4x4; joint.columns.3 = [1.2, 1.1, 1.4, 1]
        let recorded = StageCoordinates.stageFromWorld(stage, worldFromJoint: joint)
        device.columns.3 = [-2, 1.6, 4, 1] // Moving the head does not change the frozen reference.
        let again = StageCoordinates.stageFromWorld(stage, worldFromJoint: joint)
        XCTAssertEqual(recorded.position, again.position)
        let restored = stage * SIMD4(recorded.position, 1)
        XCTAssertEqual(restored.x, joint.columns.3.x, accuracy: 0.0001)
        XCTAssertEqual(restored.z, joint.columns.3.z, accuracy: 0.0001)
    }
    func testYawReferenceWorksWhileLookingSideways() {
        var device = simd_float4x4(simd_quatf(angle: .pi / 2, axis: [0, 1, 0])); device.columns.3 = [0, 1.6, 0, 1]
        let stage = StageCoordinates.initialStage(deviceTransform: device)
        XCTAssertEqual(stage.columns.3.x, -0.85, accuracy: 0.0001)
        XCTAssertEqual(stage.columns.3.y, 0)
        XCTAssertEqual(stage.columns.3.z, 0, accuracy: 0.0001)
    }
    func testSampleIsExplicitlyLabeledAndHasAllJoints() {
        let take = SampleMotion.take()
        XCTAssertTrue(take.isValid); XCTAssertEqual(take.source, .simulatorSample); XCTAssertEqual(take.duration, 6)
        XCTAssertEqual(take.frames[0].hands[0].joints.count, 27)
        XCTAssertEqual(take.frames[0].hands.count, 2)
    }
    func testRejectsUnsupportedSchemaAndMalformedTransform() {
        var take = SampleMotion.take(); take.schemaVersion = 20; XCTAssertFalse(take.isValid)
        take.schemaVersion = 1; take.frames[0].hands[0].joints["wrist"]?.position.x = .infinity
        XCTAssertFalse(take.isValid)
    }
    func testPersistenceRoundTripAndDelete() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TakeStore(directory: directory), take = SampleMotion.take()
        try await store.save(take)
        let loaded = try await store.load()
        XCTAssertEqual(loaded.count, 1); XCTAssertEqual(loaded[0].id, take.id)
        XCTAssertEqual(loaded[0].frames.count, 361); XCTAssertEqual(loaded[0].source, .simulatorSample)
        try await store.delete(take)
        let empty = try await store.load(); XCTAssertTrue(empty.isEmpty)
    }
    func testCorruptLocalFileDoesNotLoseOtherStudies() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TakeStore(directory: directory)
        try await store.save(SampleMotion.take())
        try Data("broken".utf8).write(to: directory.appending(path: "corrupt.json"))
        let loaded = try await store.load(); XCTAssertEqual(loaded.count, 1)
    }
    func testHandSurfaceBuffersAndTopologyStayInBounds() throws {
        let surface = try HandSurfaceGeometry()
        XCTAssertEqual(surface.sections.count, 7)
        XCTAssertEqual(surface.indices.count % 3, 0)
        XCTAssertTrue(surface.indices.allSatisfy { Int($0) < surface.vertices.count })
        XCTAssertEqual(surface.sections.first!.vertexRange.lowerBound, 0)
        XCTAssertEqual(surface.sections.last!.vertexRange.upperBound, surface.vertices.count)
        XCTAssertEqual(surface.sections.last!.indexRange.upperBound, surface.indices.count)
    }
    func testHandSurfaceIsFiniteAndFollowsBothHands() throws {
        for time in [0.0, 1.4, 3.7, 5.9] {
            for hand in SampleMotion.hands(at: time) {
                var surface = try HandSurfaceGeometry(side: hand.side)
                surface.update(hand)
                XCTAssertTrue(surface.visible.allSatisfy { $0 })
                XCTAssertEqual(surface.origin, hand.joints["wrist"]!.position)
                for vertex in surface.vertices {
                    XCTAssertTrue((0..<3).allSatisfy { vertex.position[$0].isFinite && vertex.normal[$0].isFinite })
                    XCTAssertLessThan(simd_length(vertex.position), 0.4)
                    XCTAssertTrue(vertex.uv.x.isFinite && vertex.uv.y.isFinite && (0...1).contains(vertex.uv.y))
                    XCTAssertEqual(simd_length(vertex.normal), 1, accuracy: 0.001)
                }
            }
        }
    }
    func testHandSurfaceDeformsFromCapturedFingerPoints() throws {
        var surface = try HandSurfaceGeometry()
        var hand = SampleMotion.hands(at: 0)[0]
        surface.update(hand)
        let range = surface.sections[2].vertexRange
        let before = Array(surface.vertices[range]).map(\.position)
        hand.joints["indexFingerIntermediateBase"]!.position.z += 0.025
        hand.joints["indexFingerIntermediateTip"]!.position.z += 0.045
        hand.joints["indexFingerTip"]!.position.z += 0.06
        surface.update(hand)
        let after = Array(surface.vertices[range]).map(\.position)
        XCTAssertGreaterThan(zip(before, after).map { simd_distance($0, $1) }.max()!, 0.04)
    }
    func testOccludedFingerUsesARKitInferredTransformWithoutHoles() throws {
        var surface = try HandSurfaceGeometry()
        var hand = SampleMotion.hands(at: 0)[0]
        hand.joints["indexFingerIntermediateBase"]!.tracked = false
        surface.update(hand)
        XCTAssertTrue(surface.visible.allSatisfy { $0 })
        XCTAssertFalse(hand.joints["indexFingerIntermediateBase"]!.tracked)
    }
    func testLostHandClearsEverySurfacePart() throws {
        var surface = try HandSurfaceGeometry()
        surface.update(SampleMotion.hands(at: 0)[0])
        surface.update(.missing(.left))
        XCTAssertTrue(surface.visible.allSatisfy { !$0 })
    }

    func testAuthoredHandBindPoseRoundTripPreservesAnatomy() throws {
        for side in HandSide.allCases {
            var surface = try HandSurfaceGeometry(side: side)
            let rest = surface.vertices.map(\.position)
            surface.update(surface.bindPose)
            XCTAssertTrue(surface.visible.allSatisfy { $0 })
            let error = zip(rest, surface.vertices).map { simd_distance($0, $1.position) }.max()!
            XCTAssertLessThan(error, 0.00001)
            XCTAssertGreaterThan(surface.vertices.map { $0.position.z }.max()! - surface.vertices.map { $0.position.z }.min()!, 0.03)
        }
    }

    func testAnatomicalSkinHasValidUVsAndOrthonormalTangentFrames() throws {
        for side in HandSide.allCases {
            var surface = try HandSurfaceGeometry(side: side)
            surface.update(SampleMotion.hands(at: 2).first { $0.side == side }!)
            XCTAssertGreaterThan(surface.vertices.map { $0.uv.x }.max()! - surface.vertices.map { $0.uv.x }.min()!, 0.5)
            for v in surface.vertices {
                XCTAssertTrue((0...1).contains(v.uv.x) && (0...1).contains(v.uv.y))
                XCTAssertEqual(simd_length(v.tangent), 1, accuracy: 0.001)
                XCTAssertEqual(simd_length(v.bitangent), 1, accuracy: 0.001)
                XCTAssertEqual(simd_dot(v.normal, v.tangent), 0, accuracy: 0.001)
                XCTAssertEqual(simd_dot(v.normal, v.bitangent), 0, accuracy: 0.001)
            }
        }
    }
    func testForearmFollowsArmDirectionWhilePalmStaysWithHand() throws {
        for side in HandSide.allCases {
            var surface = try HandSurfaceGeometry(side: side)
            var hand = surface.bindPose
            surface.update(hand)
            let before = surface.vertices.map(\.position)
            let arm = before.indices.filter { before[$0].y < -0.08 }
            let palm = before.indices.filter { before[$0].y > 0.03 }
            XCTAssertFalse(arm.isEmpty)
            hand.joints["forearmArm"]!.position = [0.10,-0.16,0]
            surface.update(hand)
            XCTAssertGreaterThan(arm.map { simd_distance(before[$0],surface.vertices[$0].position) }.max()!, 0.05)
            XCTAssertLessThan(palm.map { simd_distance(before[$0],surface.vertices[$0].position) }.max()!, 0.00001)
            hand.joints["forearmWrist"]!.tracked = false
            surface.update(hand)
            XCTAssertTrue(surface.visible[6])
        }
    }
    func testOccludedKnucklesDoNotHideAFist() throws {
        for side in HandSide.allCases {
            var surface = try HandSurfaceGeometry(side: side)
            let rest = surface.bindPose
            var hand = rest
            for finger in 1..<5 {
                let chain = Array(SkeletonLayout.fingers[finger].dropFirst(2))
                for i in 1..<chain.count {
                    let bend: Float = [1.3,2.7,3.9][i-1]
                    let segment = rest.joints[chain[i]]!.position-rest.joints[chain[i-1]]!.position
                    hand.joints[chain[i]]!.position = hand.joints[chain[i-1]]!.position + simd_quatf(angle: -bend,axis:[1,0,0]).act(segment)
                }
            }
            for name in Array(hand.joints.keys) { hand.joints[name]!.tracked = false }
            surface.update(hand)
            XCTAssertTrue(surface.visible.allSatisfy { $0 })
            XCTAssertTrue(surface.vertices.allSatisfy { simd_length($0.position) < 0.4 })
        }
    }
    func testMissingTransformAndOutlierRejectWholeSkinWithoutExposedSections() throws {
        var surface = try HandSurfaceGeometry()
        var hand = SampleMotion.hands(at: 0)[0]
        hand.joints.removeValue(forKey: "ringFingerIntermediateBase")
        surface.update(hand)
        XCTAssertTrue(surface.visible.allSatisfy { !$0 })
        hand = SampleMotion.hands(at: 0)[0]
        hand.joints["indexFingerTip"]!.position.x += 0.4
        surface.update(hand)
        XCTAssertTrue(surface.visible.allSatisfy { !$0 })
    }
    func testFingerCurlPassesPalmNormalWithoutFrameFlip() throws {
        var surface = try HandSurfaceGeometry()
        let rest = surface.bindPose
        let chain = Array(SkeletonLayout.fingers[2].dropFirst(2))
        var previous: [SIMD3<Float>]?
        for degrees in 80...100 {
            var hand = rest
            let rotation = simd_quatf(angle: Float(degrees) * .pi/180,axis:[1,0,0])
            let pivot = rest.joints[chain[0]]!.position
            for name in chain.dropFirst() {
                hand.joints[name]!.position = pivot + rotation.act(rest.joints[name]!.position-pivot)
            }
            surface.update(hand)
            XCTAssertTrue(surface.visible.allSatisfy { $0 })
            let points = Array(surface.vertices[surface.sections[3].vertexRange]).map(\.position)
            if let previous { XCTAssertLessThan(zip(previous,points).map { simd_distance($0,$1) }.max()!,0.004) }
            previous = points
        }
    }
}
