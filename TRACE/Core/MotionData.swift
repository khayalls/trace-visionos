import Foundation
import simd

enum HandSide: String, Codable, CaseIterable, Sendable { case left, right }
enum MotionSource: String, Codable, Sendable { case device, simulatorSample }
enum HandSelection: String, CaseIterable, Codable, Sendable {
    case both = "Both hands", left = "Left hand", right = "Right hand"
    func includes(_ side: HandSide) -> Bool { self == .both || (self == .left && side == .left) || (self == .right && side == .right) }
}

struct JointPose: Codable, Sendable, Equatable {
    var position: SIMD3<Float>
    /// Quaternion xyzw in the stable stage coordinate system.
    var orientation: SIMD4<Float>
    var tracked: Bool
    init(position: SIMD3<Float>, orientation: SIMD4<Float> = [0, 0, 0, 1], tracked: Bool = true) {
        self.position = position; self.orientation = orientation; self.tracked = tracked
    }
}
struct HandPose: Codable, Sendable, Equatable {
    var side: HandSide
    var tracked: Bool
    var joints: [String: JointPose]
    static func missing(_ side: HandSide) -> HandPose { .init(side: side, tracked: false, joints: [:]) }
}
struct MotionFrame: Codable, Sendable {
    var time: TimeInterval
    var hands: [HandPose]
    var trackingState: String
}
struct MotionTake: Codable, Identifiable, Sendable {
    var schemaVersion = 1
    var id = UUID()
    var createdAt = Date()
    var title: String
    var source: MotionSource
    var selection: HandSelection
    /// All joint transforms are stage-relative meters, never relative to the moving head.
    var coordinateSystem = "stage-relative-meters-y-up-v1"
    var frames: [MotionFrame]
    var duration: TimeInterval { frames.last?.time ?? 0 }
    // A tracked hand anchor can contain only inferred joints during a fist.
    // Keep those supplied transforms with their original confidence flags.
    var hasTrackedData: Bool { frames.contains { $0.hands.contains { $0.tracked && !$0.joints.isEmpty } } }
    var isValid: Bool {
        schemaVersion == 1 && coordinateSystem == "stage-relative-meters-y-up-v1" && frames.count > 1 && frames.count <= 650 && duration > 0 && duration <= 10.01 && hasTrackedData &&
        zip(frames, frames.dropFirst()).allSatisfy { $0.time < $1.time } &&
        frames.allSatisfy { frame in
            frame.time.isFinite && frame.time >= 0 && Set(frame.hands.map(\.side)).count == frame.hands.count && frame.hands.allSatisfy { hand in
                hand.joints.values.allSatisfy { joint in
                    (0..<3).allSatisfy { joint.position[$0].isFinite && abs(joint.position[$0]) < 100 } &&
                    (0..<4).allSatisfy { joint.orientation[$0].isFinite } && simd_length(joint.orientation) > 0.5 && simd_length(joint.orientation) < 1.5
                }
            }
        }
    }
}

struct CaptureBuffer {
    private(set) var frames: [MotionFrame] = []
    let source: MotionSource
    let selection: HandSelection
    mutating func append(time: TimeInterval, hands: [HandPose], trackingState: String) {
        guard time.isFinite, time >= 0, time <= 10, frames.count < 650,
              frames.last.map({ time > $0.time }) ?? true else { return }
        frames.append(.init(time: time, hands: HandSide.allCases.filter(selection.includes).map { side in
            hands.first(where: { $0.side == side }) ?? .missing(side)
        }, trackingState: trackingState))
    }
    func finish() -> MotionTake? {
        let take = MotionTake(title: source == .device ? "Motion study" : "Sample capture · Simulator", source: source, selection: selection, frames: frames)
        return take.isValid ? take : nil
    }
}

enum MotionSampler {
    static func hands(in take: MotionTake, at requestedTime: TimeInterval) -> [HandPose] {
        guard !take.frames.isEmpty else { return [] }
        let time = min(max(requestedTime, 0), take.duration)
        if time <= take.frames[0].time { return take.frames[0].hands }
        if time >= take.duration { return take.frames.last!.hands }
        var low = 0, high = take.frames.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if take.frames[mid].time <= time { low = mid } else { high = mid }
        }
        let a = take.frames[low], b = take.frames[high]
        if abs(time - a.time) < 0.000001 { return a.hands }
        if abs(time - b.time) < 0.000001 { return b.hands }
        let gap = b.time - a.time
        // Do not invent movement through long data gaps or tracking loss.
        guard gap > 0, gap <= 0.15 else { return HandSide.allCases.filter(take.selection.includes).map(HandPose.missing) }
        let fraction = Float((time - a.time) / gap)
        return a.hands.map { ah in
            guard ah.tracked, let bh = b.hands.first(where: { $0.side == ah.side }), bh.tracked else { return .missing(ah.side) }
            var joints: [String: JointPose] = [:]
            for (name, aj) in ah.joints {
                guard let bj = bh.joints[name] else { continue }
                let q = simd_slerp(simd_quatf(vector: aj.orientation), simd_quatf(vector: bj.orientation), fraction)
                joints[name] = .init(position: simd_mix(aj.position, bj.position, SIMD3(repeating: fraction)), orientation: q.vector, tracked: aj.tracked && bj.tracked)
            }
            return .init(side: ah.side, tracked: true, joints: joints)
        }
    }
}

enum StageCoordinates {
    static func stageFromWorld(_ worldFromStage: simd_float4x4, worldFromJoint: simd_float4x4) -> JointPose {
        let transform = worldFromStage.inverse * worldFromJoint
        return .init(position: SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z), orientation: simd_quatf(transform).vector)
    }
    static func initialStage(deviceTransform: simd_float4x4) -> simd_float4x4 {
        let column = deviceTransform.columns.2
        var forward = SIMD3<Float>(-column.x, 0, -column.z)
        forward = simd_length(forward) > 0.01 ? simd_normalize(forward) : [0, 0, -1]
        let yaw = atan2(-forward.x, -forward.z)
        var stage = simd_float4x4(simd_quatf(angle: yaw, axis: [0, 1, 0]))
        let p = deviceTransform.columns.3
        stage.columns.3 = SIMD4(SIMD3(p.x, 0, p.z) + forward * 0.85, 1)
        return stage
    }
}

enum SkeletonLayout {
    static let fingers = [
        ["wrist", "thumbKnuckle", "thumbIntermediateBase", "thumbIntermediateTip", "thumbTip"],
        ["wrist", "indexFingerMetacarpal", "indexFingerKnuckle", "indexFingerIntermediateBase", "indexFingerIntermediateTip", "indexFingerTip"],
        ["wrist", "middleFingerMetacarpal", "middleFingerKnuckle", "middleFingerIntermediateBase", "middleFingerIntermediateTip", "middleFingerTip"],
        ["wrist", "ringFingerMetacarpal", "ringFingerKnuckle", "ringFingerIntermediateBase", "ringFingerIntermediateTip", "ringFingerTip"],
        ["wrist", "littleFingerMetacarpal", "littleFingerKnuckle", "littleFingerIntermediateBase", "littleFingerIntermediateTip", "littleFingerTip"],
        ["forearmArm", "forearmWrist", "wrist"]
    ]
    static let names = Array(Set(fingers.flatMap { $0 })).sorted()
    static let edges: [(String, String)] = fingers.flatMap { Array(zip($0, $0.dropFirst())) }
    static let tips = ["thumbTip", "indexFingerTip", "middleFingerTip", "ringFingerTip", "littleFingerTip"]
}
