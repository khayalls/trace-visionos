import ARKit
import Observation
import QuartzCore
import simd

@MainActor @Observable
final class HandTrackingService {
    enum Status: Equatable {
        case idle, starting, running, denied, unavailable, interrupted, failed(String)
        var label: String {
            switch self {
            case .idle: "Hands offline"
            case .starting: "Preparing hand tracking…"
            case .running: "Hand tracking ready"
            case .denied: "Hand access is off. Enable TRACE in Settings → Privacy & Security → Hand Tracking."
            case .unavailable: "Hand tracking requires Apple Vision Pro."
            case .interrupted: "Tracking paused. Keep TRACE active, or retry."
            case .failed(let message): "Tracking unavailable: \(message)"
            }
        }
    }
    private(set) var status: Status = .idle
    private(set) var calibrated = false
    private(set) var worldFromStage = matrix_identity_float4x4
    private(set) var eyeHeight: Float = 1.55
    @ObservationIgnored private var session: ARKitSession?
    @ObservationIgnored private var hands: HandTrackingProvider?
    @ObservationIgnored private var stageFromWorld = matrix_identity_float4x4
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var latest: [HandSide: HandPose] = [:]
    @ObservationIgnored private var receivedAt: [HandSide: Double] = [:]
    @ObservationIgnored private var generation = UUID()

    static let jointMap: [(HandSkeleton.JointName, String)] = [
        (.wrist, "wrist"), (.thumbKnuckle, "thumbKnuckle"), (.thumbIntermediateBase, "thumbIntermediateBase"), (.thumbIntermediateTip, "thumbIntermediateTip"), (.thumbTip, "thumbTip"),
        (.indexFingerMetacarpal, "indexFingerMetacarpal"), (.indexFingerKnuckle, "indexFingerKnuckle"), (.indexFingerIntermediateBase, "indexFingerIntermediateBase"), (.indexFingerIntermediateTip, "indexFingerIntermediateTip"), (.indexFingerTip, "indexFingerTip"),
        (.middleFingerMetacarpal, "middleFingerMetacarpal"), (.middleFingerKnuckle, "middleFingerKnuckle"), (.middleFingerIntermediateBase, "middleFingerIntermediateBase"), (.middleFingerIntermediateTip, "middleFingerIntermediateTip"), (.middleFingerTip, "middleFingerTip"),
        (.ringFingerMetacarpal, "ringFingerMetacarpal"), (.ringFingerKnuckle, "ringFingerKnuckle"), (.ringFingerIntermediateBase, "ringFingerIntermediateBase"), (.ringFingerIntermediateTip, "ringFingerIntermediateTip"), (.ringFingerTip, "ringFingerTip"),
        (.littleFingerMetacarpal, "littleFingerMetacarpal"), (.littleFingerKnuckle, "littleFingerKnuckle"), (.littleFingerIntermediateBase, "littleFingerIntermediateBase"), (.littleFingerIntermediateTip, "littleFingerIntermediateTip"), (.littleFingerTip, "littleFingerTip"),
        (.forearmWrist, "forearmWrist"), (.forearmArm, "forearmArm")
    ]

    func start() async {
        stop()
        generation = UUID(); let token = generation
        guard HandTrackingProvider.isSupported, WorldTrackingProvider.isSupported else { status = .unavailable; return }
        status = .starting
        let session = ARKitSession(), hands = HandTrackingProvider(), world = WorldTrackingProvider()
        self.session = session; self.hands = hands
        tasks.append(Task { [weak self] in
            for await event in session.events {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                switch event {
                case .authorizationChanged(let type, let authorization):
                    if type == .handTracking && authorization == .denied { self.status = .denied; self.clearHands() }
                case .dataProviderStateChanged(_, let state, let error):
                    if let error { self.status = .failed(error.localizedDescription); self.clearHands() }
                    else if state == .paused || state == .stopped { self.status = .interrupted; self.clearHands() }
                    else if state == .running && self.calibrated { self.status = .running }
                @unknown default: break
                }
            }
        })
        let authorization = await session.requestAuthorization(for: [.handTracking])
        guard generation == token, !Task.isCancelled else { return }
        guard authorization[.handTracking] == .allowed else { status = .denied; return }
        do { try await session.run([hands, world]) }
        catch { status = .failed(error.localizedDescription); return }
        // Freeze a yaw-only reference once the device pose is known. Never rebase it while recording.
        for _ in 0..<180 {
            guard generation == token, !Task.isCancelled else { return }
            if let anchor = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()), anchor.isTracked {
                worldFromStage = StageCoordinates.initialStage(deviceTransform: anchor.originFromAnchorTransform)
                stageFromWorld = worldFromStage.inverse
                eyeHeight = max(0.9, anchor.originFromAnchorTransform.columns.3.y)
                calibrated = true; status = .running; break
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
        guard calibrated else { status = .failed("The stage could not find a stable reference. Retry while looking forward."); return }
        tasks.append(Task { [weak self] in
            for await update in hands.anchorUpdates {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                let anchor = update.anchor
                let side: HandSide = anchor.chirality == .left ? .left : .right
                self.receivedAt[side] = CACurrentMediaTime()
                guard self.status == .running, update.event != .removed else {
                    self.latest[side] = .missing(side); continue
                }
                self.latest[side] = self.pose(anchor)
            }
        })
    }
    func snapshot(at now: Double) -> [HandPose] {
        HandSide.allCases.map { side in
            guard status == .running, now - (receivedAt[side] ?? 0) < 0.15 else { return .missing(side) }
            return latest[side] ?? .missing(side)
        }
    }
    /// Query near presentation time for display only. Recorded samples continue
    /// to use the unpredicted anchor stream and retain every confidence flag.
    func displaySnapshot(at now: Double) -> [HandPose] {
        guard status == .running, let hands, hands.state == .running else { return HandSide.allCases.map(HandPose.missing) }
        let predicted = hands.handAnchors(at: now + 0.011)
        let fallback = snapshot(at: now)
        return HandSide.allCases.map { side in
            guard now - (receivedAt[side] ?? 0) < 0.15 else { return .missing(side) }
            if let anchor = side == .left ? predicted.leftHand : predicted.rightHand { return pose(anchor) }
            return fallback.first { $0.side == side } ?? .missing(side)
        }
    }
    private func pose(_ anchor: HandAnchor) -> HandPose {
        let side: HandSide = anchor.chirality == .left ? .left : .right
        guard anchor.isTracked, let skeleton = anchor.handSkeleton else { return .missing(side) }
        let stageFromHand = stageFromWorld * anchor.originFromAnchorTransform
        var joints: [String: JointPose] = [:]
        for (name,key) in Self.jointMap {
            let joint = skeleton.joint(name), transform = stageFromHand * joint.anchorFromJointTransform
            joints[key] = .init(position: SIMD3(transform.columns.3.x,transform.columns.3.y,transform.columns.3.z), orientation: simd_quatf(transform).vector, tracked: joint.isTracked)
        }
        return .init(side: side, tracked: true, joints: joints)
    }
    private func clearHands() { latest = [:]; receivedAt = [:] }
    func stop() {
        generation = UUID()
        tasks.forEach { $0.cancel() }; tasks.removeAll()
        session?.stop(); session = nil; hands = nil
        clearHands(); calibrated = false; status = .idle
    }
}
