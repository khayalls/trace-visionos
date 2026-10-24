import RealityKit
import UIKit
import Metal
import simd

@MainActor
final class ChamberScene {
    let root = Entity()
    let stage = Entity()
    let playbackRoot = Entity()
    let consoleMount = Entity()
    let introMount = Entity()
    let counterMount = Entity()
    let handle = ModelEntity()
    private let architecture = Entity()
    private let pulseRing: ModelEntity
    private let orbitRing: ModelEntity
    private var liveRigs: [HandSide: HandRig] = [:]
    private var ghostRigs: [HandSide: HandRig] = [:]
    var renderIssue: String? { (Array(liveRigs.values) + Array(ghostRigs.values)).compactMap(\.initializationError).first }
    private var previousRecording = false
    private var previousPlaying = false
    private var lastTrail = 0.0
    private var revealAt = 0.0
    private var ringState = -1
    static let handBlue = UIColor(white: 0.82, alpha: 1)
    static let handPearl = UIColor(white: 0.92, alpha: 1)
    static let graphite = UIColor(red: 0.086, green: 0.09, blue: 0.098, alpha: 1)
    static let chalk = UIColor(red: 0.85, green: 0.839, blue: 0.8, alpha: 1)
    static let coral = UIColor(red: 1, green: 0.467, blue: 0.369, alpha: 1)
    static let blue = UIColor(red: 0.647, green: 0.725, blue: 0.761, alpha: 1)

    init() {
        pulseRing = ModelEntity(mesh: .generateBox(size: [0.16, 0.002, 0.002]), materials: [Self.glow(Self.chalk, intensity: 0.35)])
        orbitRing = ModelEntity(mesh: .generateBox(size: [0.002, 0.002, 0.16]), materials: [Self.glow(Self.blue, intensity: 0.3)])
        root.name = "Motion Chamber"; stage.name = "Stable stage reference"; playbackRoot.name = "Recorded sculpture"
        root.addChild(architecture); root.addChild(stage)
        stage.addChild(playbackRoot); stage.addChild(consoleMount); stage.addChild(introMount); stage.addChild(counterMount)
        stage.addChild(pulseRing); pulseRing.position.y = 0.006
        stage.addChild(orbitRing); orbitRing.position.y = 0.006
        buildArchitecture()
        for side in HandSide.allCases {
            let live = HandRig(side: side, color: side == .left ? Self.handBlue : Self.handPearl, ghost: false)
            let ghost = HandRig(side: side, color: side == .left ? Self.handBlue : Self.handPearl, ghost: true)
            liveRigs[side] = live; ghostRigs[side] = ghost
            stage.addChild(live.root); playbackRoot.addChild(ghost.root)
        }
        // A small native gaze/pinch drag target below the sculpture.
        handle.model = ModelComponent(mesh: Self.torus(radius: 0.042, tube: 0.007), materials: [Self.surface(UIColor(white: 0.48, alpha: 1), emission: 0)])
        handle.position = [0, 0.76, 0.06]
        handle.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        handle.components.set(InputTargetComponent())
        handle.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.07)]))
        handle.components.set(HoverEffectComponent())
        handle.name = "Move sculpture"
        playbackRoot.addChild(handle)
        reset()
    }
    func reset() {
        stage.transform = Transform(translation: [0, 0, -0.85])
        architecture.transform = .identity
        positionAttachments(eyeHeight: 1.55)
        resetPlaybackTransform(); clearMotion(); ringState = -1
    }
    func calibrate(worldFromStage: simd_float4x4, eyeHeight: Float) {
        stage.transform = Transform(matrix: worldFromStage)
        architecture.transform = Transform(matrix: worldFromStage)
        positionAttachments(eyeHeight: eyeHeight)
    }
    private func positionAttachments(eyeHeight: Float) {
        consoleMount.position = [0, max(0.55, eyeHeight - 0.38), -0.60]
        introMount.position = [0, eyeHeight + 0.1, -0.75]
        counterMount.position = [0, eyeHeight - 0.03, -0.1]
    }
    func resetPlaybackTransform() { playbackRoot.transform = .identity }
    func clearTrails() { liveRigs.values.forEach { $0.clearTrail() }; ghostRigs.values.forEach { $0.clearTrail() } }
    func clearMotion() {
        liveRigs.values.forEach { $0.hide() }; ghostRigs.values.forEach { $0.hide() }
        handle.isEnabled = false; clearTrails()
    }
    func revealGhosts(reduceMotion: Bool) { revealAt = reduceMotion ? 0 : ProcessInfo.processInfo.systemUptime }
    func update(live: [HandPose], ghost: [HandPose], recording: Bool, countdown: Bool, playing: Bool, practice: Bool, now: Double, reduceMotion: Bool) -> (near: Int, total: Int) {
        let state = recording ? 2 : (countdown ? 1 : 0)
        if state != ringState {
            pulseRing.model?.materials = [Self.surface(state == 2 ? Self.coral : UIColor(white: 0.82, alpha: 1), emission: 0)]
            ringState = state
        }
        if recording != previousRecording || playing != previousPlaying { clearTrails(); previousRecording = recording; previousPlaying = playing }
        let pulse = recording && !reduceMotion ? 1 + Float(sin(now * 2)) * 0.008 : 1
        pulseRing.scale = SIMD3(repeating: pulse)
        var near = 0, total = 0
        let addTrail = now - lastTrail >= 1.0 / 30
        if addTrail { lastTrail = now }
        for side in HandSide.allCases {
            let actual = live.first { $0.side == side } ?? .missing(side)
            let reference = ghost.first { $0.side == side } ?? .missing(side)
            var nearNames = Set<String>()
            if practice && actual.tracked && reference.tracked {
                for name in SkeletonLayout.tips {
                    if let a = actual.joints[name], a.tracked, let b = reference.joints[name], b.tracked {
                        total += 1
                        if simd_distance(a.position, b.position) <= 0.05 { near += 1; nearNames.insert(name) }
                    }
                }
            }
            liveRigs[side]?.update(actual, now: now, trail: addTrail && (recording || ghost.isEmpty) && !reduceMotion, highlights: nearNames)
            ghostRigs[side]?.update(reference, now: now, trail: addTrail && playing && !reduceMotion, highlights: [])
        }
        if revealAt > 0 {
            let t = min(max((now - revealAt) / 0.5, 0), 1)
            playbackRoot.components.set(OpacityComponent(opacity: Float(t)))
            if t >= 1 { revealAt = 0 }
        } else { playbackRoot.components.set(OpacityComponent(opacity: 1)) }
        handle.isEnabled = !ghost.isEmpty && !practice
        return (near, total)
    }
    private func buildArchitecture() {
        architecture.name = "White studio"
        let paper = UIColor.white
        var background = UnlitMaterial(applyPostProcessToneMap: false); background.color = .init(tint: paper); background.faceCulling = .front
        architecture.addChild(ModelEntity(mesh: .generateSphere(radius: 50), materials: [background]))
        var floorMaterial = UnlitMaterial(applyPostProcessToneMap: false); floorMaterial.color = .init(tint: paper)
        let floor = ModelEntity(mesh: .generatePlane(width: 80, depth: 80), materials: [floorMaterial])
        floor.position.y = -0.006; architecture.addChild(floor)
        let key = DirectionalLight()
        key.light.color = .white; key.light.intensity = 850
        key.look(at: [0, 1, -1], from: [-2, 4, 3], relativeTo: nil); architecture.addChild(key)
        let fill = DirectionalLight(); fill.light.color = UIColor(white: 0.97, alpha: 1); fill.light.intensity = 400
        fill.look(at: [0, 1, 0], from: [3, 2, -2], relativeTo: nil); architecture.addChild(fill)
        let front = DirectionalLight(); front.light.color = .white; front.light.intensity = 600
        front.look(at: [0, 1.3, 0], from: [0, 1.8, 4], relativeTo: nil); architecture.addChild(front)
    }
    static func surface(_ color: UIColor, emission: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color); m.roughness = .init(floatLiteral: 0.83)
        m.emissiveColor = .init(color: color); m.emissiveIntensity = emission
        return m
    }
    static func glow(_ color: UIColor, intensity: Float = 1, opacity: Float = 1) -> PhysicallyBasedMaterial {
        var m = surface(color, emission: intensity)
        m.roughness = .init(floatLiteral: 0.45)
        if opacity < 1 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        return m
    }
    static func torus(radius: Float, tube: Float) -> MeshResource {
        var descriptor = MeshDescriptor(name: "Procedural circular detail")
        let major = radius > 2 ? 160 : 96, minor = 6
        var vertices: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        for a in 0...major {
            let u = Float(a) * 2 * .pi / Float(major)
            for b in 0...minor {
                let v = Float(b) * 2 * .pi / Float(minor)
                let n = SIMD3<Float>(cos(u) * cos(v), sin(v), sin(u) * cos(v))
                vertices.append(SIMD3(cos(u) * radius, 0, sin(u) * radius) + n * tube); normals.append(n)
                if a < major && b < minor {
                    let i = UInt32(a * (minor + 1) + b), row = UInt32(minor + 1)
                    indices += [i, i + 1, i + row, i + 1, i + row + 1, i + row]
                }
            }
        }
        descriptor.positions = MeshBuffers.Positions(vertices); descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor])) ?? .generateSphere(radius: tube)
    }
}

@MainActor
private final class HandRig {
    let root = Entity()
    private(set) var initializationError: String?
    private var geometry: HandSurfaceGeometry?
    private var mesh: LowLevelMesh?
    private let skin = ModelEntity()
    private var lastValidPose: HandPose?
    private var lastValidAt = 0.0
    private var displayOpacity: Float = 1

    private var trail: [(ModelEntity, Double)] = []
    private var trailCursor = 0
    private var feedback: [String: ModelEntity] = [:]
    private let isGhost: Bool
    private static var materialCache: [HandSide: (color: TextureResource, opacity: TextureResource)] = [:]
    private static func handGradients(for geometry: HandSurfaceGeometry) throws -> (color: TextureResource, opacity: TextureResource) {
        if let cached = materialCache[geometry.side] { return cached }
        // Bake both gradients into the anatomical UVs, including the extended
        // wrist. A signed rest height keeps the fade below the palm.
        let size = 1024
        var values = [Float](repeating: -.infinity, count: size*size)
        func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x*b.y-a.y*b.x }
        func pixel(_ uv: SIMD2<Float>) -> SIMD2<Float> { [uv.x*Float(size-1), (1-uv.y)*Float(size-1)] }
        for i in stride(from: 0, to: geometry.indices.count, by: 3) {
            let a = geometry.vertices[Int(geometry.indices[i])], b = geometry.vertices[Int(geometry.indices[i+1])], c = geometry.vertices[Int(geometry.indices[i+2])]
            let p = pixel(a.uv), q = pixel(b.uv), r = pixel(c.uv), denominator = cross(q-p,r-p)
            guard abs(denominator) > 0.0001 else { continue }
            let x0 = max(0,Int(floor(min(p.x,min(q.x,r.x))))), x1 = min(size-1,Int(ceil(max(p.x,max(q.x,r.x)))))
            let y0 = max(0,Int(floor(min(p.y,min(q.y,r.y))))), y1 = min(size-1,Int(ceil(max(p.y,max(q.y,r.y)))))
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 { for x in x0...x1 {
                let point = SIMD2<Float>(Float(x)+0.5,Float(y)+0.5)
                let wb = cross(point-p,r-p)/denominator, wc = cross(q-p,point-p)/denominator, wa = 1-wb-wc
                guard min(wa,min(wb,wc)) >= -0.001 else { continue }
                let height = wa*a.position.y+wb*b.position.y+wc*c.position.y
                values[y*size+x] = max(values[y*size+x],height)
            } }
        }
        // Extend island edges into UV padding to keep linear sampling free of halos.
        for _ in 0..<4 {
            var next = values
            for y in 1..<(size-1) { for x in 1..<(size-1) where !values[y*size+x].isFinite {
                let neighbors = [values[(y-1)*size+x],values[(y+1)*size+x],values[y*size+x-1],values[y*size+x+1]].filter { $0.isFinite }
                if !neighbors.isEmpty { next[y*size+x] = neighbors.reduce(0,+)/Float(neighbors.count) }
            } }
            values = next
        }
        func smootherstep(_ value: Float) -> Float {
            let t = min(max(value,0),1)
            return t*t*t*(t*(t*6-15)+10)
        }
        func texture(opacity: Bool) throws -> TextureResource {
            var pixels = [UInt8](repeating: 255, count: size*size*4)
            for i in values.indices {
                let height = values[i].isFinite ? values[i] : -0.2
                // Leave enough diffuse gray over the palm for its anatomy to
                // catch the soft studio light, then ease into black fingers.
                let value: Float = opacity ? smootherstep((height+0.145)/0.17) : 0.56-0.53*smootherstep((height-0.055)/0.115)
                let byte = UInt8(min(max(value,0),1)*255)
                pixels[i*4] = byte; pixels[i*4+1] = byte; pixels[i*4+2] = byte
            }
            guard let provider = CGDataProvider(data: Data(pixels) as CFData), let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size*4, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw CocoaError(.coderInvalidValue) }
            return try TextureResource(image: image, withName: "TRACE.Hand."+(opacity ? "Opacity." : "Charcoal.")+geometry.side.rawValue, options: .init(semantic: opacity ? .raw : .color))
        }
        let result = (color: try texture(opacity: false), opacity: try texture(opacity: true))
        materialCache[geometry.side] = result; return result
    }

    init(side: HandSide, color: UIColor, ghost: Bool) {
        isGhost = ghost
        do {
            let geometry = try HandSurfaceGeometry(side: side)
            self.geometry = geometry
            let descriptor = LowLevelMesh.Descriptor(
                vertexCapacity: geometry.vertices.count,
                vertexAttributes: [
                    .init(semantic: .position, format: .float3, offset: 0),
                    .init(semantic: .normal, format: .float3, offset: MemoryLayout<HandSurfaceGeometry.Vertex>.offset(of: \.normal)!),
                    .init(semantic: .tangent, format: .float3, offset: MemoryLayout<HandSurfaceGeometry.Vertex>.offset(of: \.tangent)!),
                    .init(semantic: .bitangent, format: .float3, offset: MemoryLayout<HandSurfaceGeometry.Vertex>.offset(of: \.bitangent)!),
                    .init(semantic: .uv0, format: .float2, offset: MemoryLayout<HandSurfaceGeometry.Vertex>.offset(of: \.uv)!)
                ],
                vertexLayouts: [.init(bufferIndex: 0, bufferStride: MemoryLayout<HandSurfaceGeometry.Vertex>.stride)],
                indexCapacity: geometry.indices.count, indexType: .uint32)
            let mesh = try LowLevelMesh(descriptor: descriptor)
            geometry.indices.withUnsafeBytes { source in mesh.withUnsafeMutableIndices { $0.copyMemory(from: source) } }
            geometry.vertices.withUnsafeBytes { source in mesh.withUnsafeMutableBytes(bufferIndex: 0) { $0.copyMemory(from: source) } }
            let bounds = BoundingBox(min: [-0.4, -0.4, -0.4], max: [0.4, 0.4, 0.4])
            mesh.parts.replaceAll(geometry.sections.map { .init(indexOffset: $0.indexRange.lowerBound * MemoryLayout<UInt32>.stride, indexCount: 0, topology: .triangle, materialIndex: 0, bounds: bounds) })
            let resource = try MeshResource(from: mesh)
            let gradients = try Self.handGradients(for: geometry)
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .white, texture: .init(gradients.color))
            material.roughness = .init(floatLiteral: 0.94)
            material.specular = .init(floatLiteral: 0.08)
            material.clearcoat = .init(floatLiteral: 0)
            material.blending = .transparent(opacity: .init(texture: .init(gradients.opacity)))
            material.faceCulling = .back
            skin.model = .init(mesh: resource, materials: [material])
            // The gradient supplies transparency; an extra uniform opacity makes
            // overlapping nail geometry appear as dark patches on a gray hand.
            skin.components.set(OpacityComponent(opacity: 1))
            root.addChild(skin); self.mesh = mesh
        } catch { initializationError = "Could not create hand surfaces: \(error.localizedDescription)" }
        let pointMesh = MeshResource.generateSphere(radius: 0.002)
        let trailMaterial = ChamberScene.glow(color, intensity: 1.5, opacity: 0.7)
        for _ in 0..<100 {
            let point = ModelEntity(mesh: pointMesh, materials: [trailMaterial]); point.isEnabled = false
            root.addChild(point); trail.append((point, -100))
        }
        for name in SkeletonLayout.tips {
            let marker = ModelEntity(mesh: .generateSphere(radius: 0.006), materials: [ChamberScene.glow(ChamberScene.coral, intensity: 1.5, opacity: 0.8)])
            marker.isEnabled = false; root.addChild(marker); feedback[name] = marker
        }
        root.isEnabled = false
    }
    func hide() { root.isEnabled = false; lastValidPose = nil; clearTrail() }
    func clearTrail() { for index in trail.indices { trail[index].0.isEnabled = false; trail[index].1 = -100 } }
    func update(_ pose: HandPose, now: Double, trail addTrail: Bool, highlights: Set<String>) {
        guard let mesh, geometry != nil else { hide(); return }
        var opacity: Float = 1
        let changed = pose != lastValidPose || !root.isEnabled
        if changed { geometry!.update(pose) }
        if geometry!.visible.allSatisfy({ $0 }) {
            lastValidPose = pose; lastValidAt = now
        } else if !isGhost, let lastValidPose, now-lastValidAt < 0.15 {
            // Briefly retain the last complete visual pose, then fade the whole
            // hand. This display-only grace never enters a recording.
            geometry!.update(lastValidPose)
            opacity = Float(min(max((0.15-(now-lastValidAt))/0.05,0),1))
        } else { hide(); return }
        guard let geometry else { hide(); return }
        root.isEnabled = true
        if opacity != displayOpacity {
            root.components.set(OpacityComponent(opacity: opacity)); displayOpacity = opacity
        }
        skin.position = geometry.origin
        // Replace the full vertex buffer, rather than editing data that a
        // renderer may still be reading. A paused pose needs no new upload.
        if changed { geometry.vertices.withUnsafeBytes { source in mesh.replaceUnsafeMutableBytes(bufferIndex: 0) { $0.copyMemory(from: source) } } }
        for index in geometry.sections.indices {
            var part = mesh.parts[index]
            let count = geometry.visible[index] ? geometry.sections[index].indexRange.count : 0
            if part.indexCount != count { part.indexCount = count; mesh.parts[index] = part }
        }
        for (name, marker) in feedback {
            marker.isEnabled = highlights.contains(name) && pose.joints[name]?.tracked == true
            if let joint = pose.joints[name] { marker.position = joint.position }
        }
        if addTrail {
            for name in SkeletonLayout.tips {
                guard let joint = pose.joints[name], joint.tracked else { continue }
                trail[trailCursor].0.position = joint.position; trail[trailCursor].0.isEnabled = true
                trail[trailCursor].1 = now; trailCursor = (trailCursor + 1) % trail.count
            }
        }
        for (point, time) in trail {
            let age = now - time
            point.isEnabled = age < 0.65
            if point.isEnabled {
                let alpha = Float(max(0, 1 - age / 0.65))
                point.scale = SIMD3(repeating: max(0.1, alpha))
                point.components.set(OpacityComponent(opacity: alpha * (isGhost ? 0.65 : 0.35)))
            }
        }
    }
}
