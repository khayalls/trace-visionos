import Foundation
import simd

struct PlaybackRegion: Equatable, Sendable {
    let start: Double
    let end: Double
    var duration: Double { end - start }

    init(start: Double = 0, end: Double, duration: Double) {
        let limit = duration.isFinite ? max(0, duration) : 0
        let a = start.isFinite ? min(max(0, start), limit) : 0
        self.start = a
        self.end = end.isFinite ? min(max(a, end), limit) : limit
    }

    func advanced(from time: Double, by delta: Double, speed: Double, reverse: Bool, loops: Bool) -> (time: Double, finished: Bool) {
        guard duration > 0, delta.isFinite, speed.isFinite else { return (start, true) }
        let current = time.isFinite ? min(max(time, start), end) : start
        let next = current + max(0, delta) * max(0, speed) * (reverse ? -1 : 1)
        if loops {
            let offset = (next - start).truncatingRemainder(dividingBy: duration)
            return (start + (offset < 0 ? offset + duration : offset), false)
        }
        return (min(max(next, start), end), reverse ? next <= start : next >= end)
    }
}

struct HandMotionSummary: Sendable {
    let side: HandSide
    let distance: Float
    let peakSpeed: Float
    let trackedFrames: Int
    let totalFrames: Int
    var coverage: Double { totalFrames == 0 ? 0 : Double(trackedFrames) / Double(totalFrames) }
}

enum MotionAnalysis {
    static let maximumGap = 0.15

    static func measuredPoint(_ hand: HandPose?, joint: String) -> SIMD3<Float>? {
        guard let hand, hand.tracked, let pose = hand.joints[joint], pose.tracked,
              (0..<3).allSatisfy({ pose.position[$0].isFinite }) else { return nil }
        return pose.position
    }

    static func summary(_ take: MotionTake, side: HandSide) -> HandMotionSummary {
        var distance: Float = 0, peak: Float = 0, count = 0
        var previous: (Double, SIMD3<Float>)?
        for frame in take.frames {
            guard let point = measuredPoint(frame.hands.first { $0.side == side }, joint: "wrist") else {
                previous = nil; continue
            }
            count += 1
            if let (time, last) = previous {
                let delta = frame.time - time
                if delta > 0, delta <= maximumGap {
                    let step = simd_distance(point, last)
                    distance += step; peak = max(peak, step / Float(delta))
                }
            }
            previous = (frame.time, point)
        }
        return .init(side: side, distance: distance, peakSpeed: peak, trackedFrames: count, totalFrames: take.frames.count)
    }

    /// Separate segments prevent a line from crossing lost or inferred data.
    static func paths(_ take: MotionTake, side: HandSide, joint: String = "indexFingerTip") -> [[SIMD3<Float>]] {
        var paths: [[SIMD3<Float>]] = [], current: [SIMD3<Float>] = []
        var previousTime: Double?
        func finish() { if current.count > 1 { paths.append(current) }; current = [] }
        for frame in take.frames {
            guard let point = measuredPoint(frame.hands.first { $0.side == side }, joint: joint) else {
                finish(); previousTime = nil; continue
            }
            if let previousTime, frame.time - previousTime > maximumGap { finish() }
            current.append(point); previousTime = frame.time
        }
        finish(); return paths
    }

    static func center(_ take: MotionTake) -> SIMD3<Float> {
        var low = SIMD3<Float>(repeating: .infinity), high = SIMD3<Float>(repeating: -.infinity)
        for frame in take.frames { for hand in frame.hands where hand.tracked {
            for joint in hand.joints.values where (0..<3).allSatisfy({ joint.position[$0].isFinite }) {
                low = simd_min(low, joint.position); high = simd_max(high, joint.position)
            }
        } }
        return low.x.isFinite ? (low + high) / 2 : [0, 1.4, 0]
    }
}

enum MotionEditing {
    /// A new study, leaving the original and its stage coordinate system intact.
    static func trimmed(_ take: MotionTake, region: PlaybackRegion) -> MotionTake? {
        guard region.duration >= 0.1, region.start >= 0, region.end <= take.duration else { return nil }
        var frames = [MotionFrame(time: 0, hands: MotionSampler.hands(in: take, at: region.start), trackingState: "trimmed-boundary")]
        frames += take.frames.filter { $0.time > region.start + 0.000001 && $0.time < region.end - 0.000001 }
            .map { .init(time: $0.time - region.start, hands: $0.hands, trackingState: $0.trackingState) }
        frames.append(.init(time: region.duration, hands: MotionSampler.hands(in: take, at: region.end), trackingState: "trimmed-boundary"))
        let copy = MotionTake(title: "Trimmed study", source: take.source, selection: take.selection, frames: frames)
        return copy.isValid ? copy : nil
    }
}

enum MotionExport {
    static func json(_ take: MotionTake) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(take)
    }

    /// One row per supplied joint. A missing hand gets a row with empty transform fields.
    static func csv(_ take: MotionTake) -> Data {
        var rows = ["source,coordinate_system,time_s,hand,hand_tracked,joint,joint_tracked,x_m,y_m,z_m,qx,qy,qz,qw"]
        func number(_ value: Double) -> String { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value) }
        for frame in take.frames {
            for side in HandSide.allCases where take.selection.includes(side) {
                let hand = frame.hands.first { $0.side == side }
                let prefix = [take.source.rawValue, take.coordinateSystem, number(frame.time), side.rawValue, hand?.tracked == true ? "true" : "false"]
                if let hand, !hand.joints.isEmpty {
                    for name in hand.joints.keys.sorted() {
                        let joint = hand.joints[name]!
                        let values = (0..<3).map { number(Double(joint.position[$0])) } + (0..<4).map { number(Double(joint.orientation[$0])) }
                        rows.append((prefix + [quoted(name), joint.tracked ? "true" : "false"] + values).joined(separator: ","))
                    }
                } else { rows.append((prefix + ["", "false"] + Array(repeating: "", count: 7)).joined(separator: ",")) }
            }
        }
        return Data((rows.joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func quoted(_ value: String) -> String {
        // Prevent spreadsheet formula execution if a joint name ever comes from imported data.
        let safe = ["=", "+", "-", "@", "\t", "\r", "\n"].contains(where: { value.hasPrefix($0) }) ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

enum InspectionTransform {
    static func rotation(yaw: Double, pitch: Double) -> simd_quatf {
        simd_quatf(angle: Float(yaw * .pi / 180), axis: [0, 1, 0]) * simd_quatf(angle: Float(pitch * .pi / 180), axis: [1, 0, 0])
    }
    static func point(_ point: SIMD3<Float>, around center: SIMD3<Float>, yaw: Double, pitch: Double, scale: Float = 1) -> SIMD3<Float> {
        center + rotation(yaw: yaw, pitch: pitch).act((point - center) * scale)
    }
}
