import Foundation
import simd

/// Synthetic anatomical fixture, available only from the simulator interface.
/// The real-device capture path never references this generator.
enum SampleMotion {
    static func hands(at time: TimeInterval) -> [HandPose] {
        HandSide.allCases.map { side in
            let t = Float(time), mirror: Float = side == .left ? -1 : 1
            let wrist = SIMD3<Float>(mirror * (0.20 + 0.09 * sin(t * 1.2)), 1.43 + 0.10 * sin(t * 1.7), -0.10 + 0.12 * cos(t))
            var joints: [String: JointPose] = ["wrist": .init(position: wrist)]
            for (fingerIndex, chain) in SkeletonLayout.fingers.prefix(5).enumerated() {
                let names = Array(chain.dropFirst())
                let offsets: [SIMD3<Float>]
                if fingerIndex == 0 {
                    offsets = [[-0.029, 0.020, 0.003], [-0.049, 0.039, 0.005], [-0.067, 0.057, 0.008], [-0.081, 0.074, 0.010]]
                } else {
                    let x: Float = [-0.028, -0.009, 0.011, 0.029][fingerIndex - 1]
                    let baseY: Float = [0.069, 0.075, 0.071, 0.059][fingerIndex - 1]
                    let length: Float = [0.082, 0.094, 0.087, 0.068][fingerIndex - 1]
                    let spread: Float = [-0.017, -0.004, 0.008, 0.023][fingerIndex - 1]
                    offsets = [[x * 0.6, 0.028, 0], [x, baseY, 0], [x + spread * 0.42, baseY + length * 0.42, 0], [x + spread * 0.76, baseY + length * 0.76, 0], [x + spread, baseY + length, 0]]
                }
                // Articulated simulator fixture: rotate each segment without changing
                // its length, so flexion bends toward the palm instead of stretching tips.
                let cycle = 0.5 - 0.5 * cos(t * 1.1 + Float(fingerIndex) * 0.2)
                var posed = offsets
                var rotations = Array(repeating: simd_quatf(angle: 0, axis: [1,0,0]), count: names.count)
                if fingerIndex > 0 {
                    let bends: [Float] = [0.08 + 0.22 * cycle, 0.20 + 0.70 * cycle, 0.28 + 0.98 * cycle]
                    for j in 2..<names.count {
                        let rotation = simd_quatf(angle: -bends[j-2], axis: [1,0,0])
                        posed[j] = posed[j-1] + rotation.act(offsets[j] - offsets[j-1])
                        rotations[j] = rotation
                    }
                } else {
                    for j in 1..<names.count {
                        let rotation = simd_quatf(angle: -0.15 * cycle * Float(j), axis: [1,0,0])
                        posed[j] = posed[j-1] + rotation.act(offsets[j] - offsets[j-1])
                        rotations[j] = rotation
                    }
                }
                for (jointIndex, name) in names.enumerated() {
                    var offset = posed[jointIndex]; offset.x *= mirror
                    joints[name] = .init(position: wrist + offset, orientation: rotations[jointIndex].vector)
                }
            }
            joints["forearmWrist"] = .init(position: wrist + [0, -0.045, 0.025])
            joints["forearmArm"] = .init(position: wrist + [mirror * 0.015, -0.16, 0.09])
            return .init(side: side, tracked: true, joints: joints)
        }
    }
    static func take() -> MotionTake {
        var capture = CaptureBuffer(source: .simulatorSample, selection: .both)
        for index in 0...360 {
            let t = Double(index) / 60
            capture.append(time: t, hands: hands(at: t), trackingState: "synthetic-simulator-fixture")
        }
        var take = capture.finish()!
        take.title = "Ribbon study · Sample"
        return take
    }
}
