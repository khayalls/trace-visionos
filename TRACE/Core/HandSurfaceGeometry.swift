import Foundation
import simd

/// Authored human anatomy and skin weights, retargeted to measured hand joints.
/// The asset contains no animation; live and replay poses use the same deformation path.
struct HandSurfaceGeometry {
    struct Vertex: Sendable {
        var position: SIMD3<Float> = .zero
        var normal: SIMD3<Float> = [0, 0, 1]
        var tangent: SIMD3<Float> = [1, 0, 0]
        var bitangent: SIMD3<Float> = [0, 1, 0]
        var uv: SIMD2<Float> = .zero
    }
    struct Section: Sendable {
        let name: String
        let vertexRange: Range<Int>
        let indexRange: Range<Int>
    }
    private struct Asset: Decodable {
        struct Joint: Decodable { let name: String; let position: [Float]; let child: Int?; let parent: Int?; let group: Int }
        let version: Int
        let positions: [[Float]], normals: [[Float]], uvs: [[Float]], weights: [[Float]]
        let jointIndices: [[Int]], indices: [UInt32], joints: [Joint]
    }
    private struct Joint: Sendable {
        let name: String, point: SIMD3<Float>, child: Int?, parent: Int?, group: Int
    }
    private struct Binding: Sendable {
        let vertex: Vertex
        let joints: SIMD4<Int32>, weights: SIMD4<Float>
    }
    private struct Shape: Sendable {
        let sections: [Section], indices: [UInt32], bindings: [Binding], joints: [Joint]
        let points: [String: SIMD3<Float>]
    }
    private static let left = Result { try load(.left) }
    private static let right = Result { try load(.right) }
    private let shape: Shape
    let side: HandSide
    let sections: [Section]
    let indices: [UInt32]
    private(set) var vertices: [Vertex]
    private(set) var visible = Array(repeating: false, count: 7)
    private(set) var origin = SIMD3<Float>.zero

    init(side: HandSide = .left) throws {
        let shape = try (side == .left ? Self.left : Self.right).get()
        self.shape = shape; self.side = side
        sections = shape.sections; indices = shape.indices; vertices = shape.bindings.map(\.vertex)
    }
    /// The authored bind pose is useful for inspecting retargeting without a tracking provider.
    var bindPose: HandPose {
        var joints = shape.points.mapValues { JointPose(position: $0) }
        joints["forearmWrist"] = .init(position: [0, -0.04, 0])
        joints["forearmArm"] = .init(position: [0, -0.18, 0])
        return .init(side: side, tracked: true, joints: joints)
    }
    mutating func update(_ hand: HandPose) {
        visible = Array(repeating: false, count: 7)
        guard hand.side == side, hand.tracked, let wrist = point("wrist", hand), let index = point("indexFingerKnuckle", hand),
              let middle = point("middleFingerKnuckle", hand), let little = point("littleFingerKnuckle", hand),
              simd_length(middle - wrist) > 0.015, simd_length(simd_cross(little - index, middle - wrist)) > 0.0001 else { return }
        origin = wrist
        let actual = hand.joints.compactMapValues { joint -> SIMD3<Float>? in
            // ARKit supplies inferred transforms for occluded joints. Confidence
            // is retained in the recording, but does not punch holes in a skin.
            guard (0..<3).allSatisfy({ joint.position[$0].isFinite }) else { return nil }
            return joint.position - wrist
        }
        // A skin needs a complete, plausible skeleton. Reject a corrupt frame
        // as a whole instead of exposing triangle boundaries or stretched spikes.
        for chain in SkeletonLayout.fingers.prefix(5) {
            for (a,b) in zip(chain,chain.dropFirst()) {
                guard let p = actual[a], let q = actual[b], (0.002...0.12).contains(simd_distance(p,q)) else { return }
            }
        }
        guard (0.02...0.16).contains(simd_distance(index,little)),
              (0.025...0.18).contains(simd_distance(middle,wrist)) else { return }
        let restBasis = Self.basis(shape.points), targetBasis = Self.basis(actual)
        let width = simd_distance(index, little) / simd_distance(shape.points["indexFingerKnuckle"]!, shape.points["littleFingerKnuckle"]!)
        let length = simd_length(middle - wrist) / simd_length(shape.points["middleFingerKnuckle"]!)
        let widthScale = min(max(width, 0.55), 1.8), lengthScale = min(max(length, 0.55), 1.8)
        let thicknessScale = sqrt(widthScale * lengthScale)
        let palm = targetBasis * simd_float3x3(diagonal: [widthScale, lengthScale, thicknessScale]) * restBasis.transpose
        // The lower wrist continues into a short forearm. Use the measured arm
        // direction so bending the hand does not swing the forearm with it.
        let forearmDirection: SIMD3<Float>
        if let arm = actual["forearmArm"], let wrist = actual["forearmWrist"], simd_distance(arm, wrist) > 0.02 {
            forearmDirection = wrist - arm
        } else if let wrist = actual["forearmWrist"], simd_length(wrist) > 0.005 {
            forearmDirection = -wrist
        } else { forearmDirection = targetBasis.columns.1 }
        let forearm = Self.frame(forearmDirection, hint: targetBasis.columns.2) * simd_float3x3(diagonal: [widthScale, lengthScale, thicknessScale]) * Self.frame([0,1,0], hint: restBasis.columns.2).transpose
        let forearmNormal = forearm.inverse.transpose
        visible = Array(repeating: true, count: 7)
        var matrices: [simd_float3x3] = [], normalMatrices: [simd_float3x3] = [], translations: [SIMD3<Float>] = []
        for joint in shape.joints {
            guard joint.group > 0, let from = actual[joint.name] else {
                matrices.append(palm); normalMatrices.append(palm.inverse.transpose); translations.append(.zero); continue
            }
            let endIndex = joint.child ?? joint.parent
            guard let endIndex, let end = actual[shape.joints[endIndex].name] else {
                matrices.append(palm); normalMatrices.append(palm.inverse.transpose); translations.append(from - palm * joint.point); continue
            }
            let restDirection = joint.child != nil ? shape.joints[endIndex].point - joint.point : joint.point - shape.joints[endIndex].point
            let direction = joint.child != nil ? end - from : from - end
            guard simd_length(direction) > 0.001, simd_length(restDirection) > 0.001 else {
                matrices.append(palm); normalMatrices.append(palm.inverse.transpose); translations.append(from - palm * joint.point); continue
            }
            let boneLength = min(max(simd_length(direction) / simd_length(restDirection), 0.3), 2.5)
            let restFrame = Self.frame(restDirection, hint: restBasis.columns.2)
            // Preserve the finger's hinge axis while curling through the palm
            // normal. Crossing direction with the palm normal flips at 90°.
            let hinge = targetBasis * restBasis.transpose * restFrame.columns.0
            let frame = Self.bendFrame(direction, hinge: hinge)
            let matrix = frame * simd_float3x3(diagonal: [widthScale, boneLength, thicknessScale]) * restFrame.transpose
            matrices.append(matrix); normalMatrices.append(matrix.inverse.transpose); translations.append(from - matrix * joint.point)
        }
        for (index, binding) in shape.bindings.enumerated() {
            var p = SIMD3<Float>.zero, n = SIMD3<Float>.zero, t = SIMD3<Float>.zero, b = SIMD3<Float>.zero
            for influence in 0..<4 where binding.weights[influence] > 0 {
                let joint = Int(binding.joints[influence]), weight = binding.weights[influence]
                p += (matrices[joint] * binding.vertex.position + translations[joint]) * weight
                n += normalMatrices[joint] * binding.vertex.normal * weight
                t += matrices[joint] * binding.vertex.tangent * weight
                b += matrices[joint] * binding.vertex.bitangent * weight
            }
            let armBlend = Self.smootherstep((0.025-binding.vertex.position.y)/0.05)
            if armBlend > 0 {
                p = simd_mix(p, forearm * binding.vertex.position, SIMD3(repeating: armBlend))
                n = simd_mix(n, forearmNormal * binding.vertex.normal, SIMD3(repeating: armBlend))
                t = simd_mix(t, forearm * binding.vertex.tangent, SIMD3(repeating: armBlend))
                b = simd_mix(b, forearm * binding.vertex.bitangent, SIMD3(repeating: armBlend))
            }
            var vertex = binding.vertex
            vertex.position = p; vertex.normal = Self.unit(n, fallback: binding.vertex.normal)
            vertex.tangent = Self.unit(t - vertex.normal * simd_dot(t, vertex.normal), fallback: binding.vertex.tangent)
            vertex.bitangent = Self.unit(simd_cross(vertex.normal, vertex.tangent), fallback: binding.vertex.bitangent) * (simd_dot(simd_cross(vertex.normal, vertex.tangent), b) < 0 ? -1 : 1)
            vertices[index] = vertex
        }
    }
    private func point(_ name: String, _ hand: HandPose) -> SIMD3<Float>? {
        guard let joint = hand.joints[name], (0..<3).allSatisfy({ joint.position[$0].isFinite }) else { return nil }
        return joint.position
    }
    private static func unit(_ v: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        simd_length_squared(v) > 1e-12 ? simd_normalize(v) : fallback
    }
    private static func smootherstep(_ value: Float) -> Float {
        let t = min(max(value,0),1)
        return t*t*t*(t*(t*6-15)+10)
    }
    private static func basis(_ points: [String: SIMD3<Float>]) -> simd_float3x3 {
        let y = unit(points["middleFingerKnuckle"]! - points["wrist"]!, fallback: [0,1,0])
        let z = unit(simd_cross(points["littleFingerKnuckle"]! - points["indexFingerKnuckle"]!, y), fallback: [0,0,1])
        return .init(columns: (simd_normalize(simd_cross(y,z)), y, z))
    }
    private static func frame(_ direction: SIMD3<Float>, hint: SIMD3<Float>) -> simd_float3x3 {
        let y = simd_normalize(direction)
        let x = unit(simd_cross(y, hint), fallback: unit(simd_cross(y, [0,1,0]), fallback: [1,0,0]))
        return .init(columns: (x,y,simd_normalize(simd_cross(x,y))))
    }
    private static func bendFrame(_ direction: SIMD3<Float>, hinge: SIMD3<Float>) -> simd_float3x3 {
        let y = simd_normalize(direction)
        let x = unit(hinge-y*simd_dot(hinge,y), fallback: frame(direction,hint: [0,0,1]).columns.0)
        return .init(columns: (x,y,simd_normalize(simd_cross(x,y))))
    }
    private static func load(_ side: HandSide) throws -> Shape {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        let name = side == .left ? "LeftHand" : "RightHand"
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "HandAssets") else { throw CocoaError(.fileNoSuchFile) }
        let asset = try JSONDecoder().decode(Asset.self, from: Data(contentsOf: url))
        let count = asset.positions.count
        guard asset.version == 1, count > 1000, asset.normals.count == count, asset.uvs.count == count,
              asset.weights.count == count, asset.jointIndices.count == count, asset.indices.count % 3 == 0,
              asset.indices.allSatisfy({ Int($0) < count }), asset.joints.count == 26 else { throw CocoaError(.coderInvalidValue) }
        let joints: [Joint] = asset.joints.map { .init(name: $0.name, point: SIMD3($0.position), child: $0.child, parent: $0.parent, group: $0.group) }
        var points: [String: SIMD3<Float>] = [:]
        for joint in joints where points[joint.name] == nil { points[joint.name] = joint.point }
        var vertices = (0..<count).map { i in
            var p = SIMD3<Float>(asset.positions[i]), n = SIMD3<Float>(asset.normals[i])
            // Extend only the modeled wrist base. Palm and finger coordinates
            // remain exactly authored; the closed end lies beyond the fade.
            let t = min(max((p.y-0.003)/0.025,0),1)
            let derivative: Float = 1 + 180*t*t*(t-1)*(t-1)
            p.y -= 0.15*(1-smootherstep(t))
            n = unit([n.x,n.y/derivative,n.z], fallback: n)
            return Vertex(position: p, normal: n, uv: SIMD2(asset.uvs[i]))
        }
        var tangents = Array(repeating: SIMD3<Float>.zero, count: count), bitangents = tangents
        var triangles = Array(repeating: [UInt32](), count: 7)
        for i in stride(from: 0, to: asset.indices.count, by: 3) {
            let ids = Array(asset.indices[i..<i+3]).map(Int.init)
            let a = vertices[ids[0]], b = vertices[ids[1]], c = vertices[ids[2]]
            let e1 = b.position-a.position, e2 = c.position-a.position, u1 = b.uv-a.uv, u2 = c.uv-a.uv
            let det = u1.x*u2.y-u1.y*u2.x
            if abs(det) > 1e-10 {
                let t = (e1*u2.y-e2*u1.y)/det, b = (e2*u1.x-e1*u2.x)/det
                for id in ids { tangents[id] += t; bitangents[id] += b }
            }
            var influence = Array(repeating: Float(0), count: 6)
            for id in ids { for j in 0..<4 { influence[joints[asset.jointIndices[id][j]].group] += asset.weights[id][j] } }
            let center = (a.position+b.position+c.position)/3
            var group = influence.indices.max(by: { influence[$0] < influence[$1] })!
            if center.y < 0.016 { group = 6 }
            else if group > 1 {
                let knuckle = points[SkeletonLayout.fingers[group-1][2]]!
                if center.y < knuckle.y*0.90 { group = 0 }
            } else if group == 1 && center.y < 0.025 { group = 0 }
            triangles[group] += ids.map(UInt32.init)
        }
        for i in vertices.indices {
            let n = vertices[i].normal
            let t = unit(tangents[i] - n*simd_dot(n,tangents[i]), fallback: [1,0,0])
            vertices[i].tangent = t
            vertices[i].bitangent = unit(simd_cross(n,t), fallback: [0,1,0]) * (simd_dot(simd_cross(n,t),bitangents[i]) < 0 ? -1 : 1)
        }
        var sections: [Section] = [], bindings: [Binding] = [], indices: [UInt32] = []
        let names = ["palm"] + SkeletonLayout.tips + ["wrist"]
        for group in 0..<7 {
            let startVertex = bindings.count, startIndex = indices.count
            var remap: [UInt32: UInt32] = [:]
            for original in triangles[group] {
                if remap[original] == nil {
                    let i = Int(original), weights = SIMD4<Float>(asset.weights[i]), sum = weights.x+weights.y+weights.z+weights.w
                    guard sum > 0.99, sum < 1.01, asset.jointIndices[i].allSatisfy({ $0 >= 0 && $0 < joints.count }) else { throw CocoaError(.coderInvalidValue) }
                    remap[original] = UInt32(bindings.count)
                    bindings.append(.init(vertex: vertices[i], joints: SIMD4(asset.jointIndices[i].map(Int32.init)), weights: weights/sum))
                }
                indices.append(remap[original]!)
            }
            sections.append(.init(name: names[group], vertexRange: startVertex..<bindings.count, indexRange: startIndex..<indices.count))
        }
        return Shape(sections: sections, indices: indices, bindings: bindings, joints: joints, points: points)
    }
}
