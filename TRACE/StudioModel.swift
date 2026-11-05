import SwiftUI
import RealityKit
import Observation
import QuartzCore

@MainActor @Observable
final class StudioModel {
    enum Phase: String { case idle, countdown, recording, review }
    enum ConsoleMode { case capture, playback }
    enum Panel { case options, studies, hands, view, loop, insights }
    var panel: Panel?
    var consoleMode: ConsoleMode = .capture
    let tracking = HandTrackingService()
    @ObservationIgnored lazy var renderer = ChamberScene()
    var phase: Phase = .idle
    var immersiveOpen = false
    var opening = false
    var introVisible = true
    var selectedHands: HandSelection = .both
    var takes: [MotionTake] = []
    var savedTakeIDs: Set<UUID> = []
    var selectedTake: MotionTake?
    var isPlaying = false
    var playhead: Double = 0
    var speed: Double = 1
    var loopEnabled = false
    var loopStart: Double = 0
    var loopEnd: Double = 0
    var reversePlayback = false
    var exportRequested = false
    var viewYaw: Double = 0
    var viewPitch: Double = 0
    var viewScale: Double = 1
    var showMotionPaths = false
    private(set) var motionSummaries: [HandMotionSummary] = []
    var countdown = 3
    var recordingElapsed: Double = 0
    var notice = "Your next movement can become a sculpture."
    var saveError: String?
    var trackedHands = 0
    var trackedHandMask = 0
    var practice = false
    var nearTips = 0
    var comparedTips = 0
    var stageMoved = false
    var deleteConfirmation = false
    var compactHelp = false
    var motionReduced = false
    #if targetEnvironment(simulator)
    let isSimulator = true
    var sampleInput = false
    var previewCountdown = false
    #else
    let isSimulator = false
    let sampleInput = false
    #endif
    @ObservationIgnored private let store = TakeStore()
    @ObservationIgnored private var clockRunning = false
    @ObservationIgnored private var capture: CaptureBuffer?
    @ObservationIgnored private var countdownStart = 0.0
    @ObservationIgnored private var recordingStart = 0.0
    @ObservationIgnored private var nextCaptureAt = 0.0
    @ObservationIgnored private var sampleStart = 0.0
    @ObservationIgnored private var lastTick = 0.0
    @ObservationIgnored private var appliedCalibration = false
    @ObservationIgnored private var dragOrigin: SIMD3<Float>?
    @ObservationIgnored private var saveTasks: [Task<Void, Never>] = []
    @ObservationIgnored private(set) var liveHands: [HandPose] = []

    var duration: Double { selectedTake?.duration ?? 0 }
    var playbackRegion: PlaybackRegion {
        .init(start: loopEnabled ? loopStart : 0, end: loopEnabled ? loopEnd : duration, duration: duration)
    }
    var canRecord: Bool { phase != .countdown && phase != .recording && (sampleInput || (tracking.status == .running && selectionTracked)) }
    var sourceLabel: String { sampleInput ? "SAMPLE INPUT · SIMULATOR" : tracking.status.label }
    var selectionTracked: Bool {
        let mask = selectedHands == .both ? 3 : (selectedHands == .left ? 1 : 2)
        return trackedHandMask & mask != 0
    }

    func retryTracking() async {
        guard phase != .recording && phase != .countdown else { return }
        appliedCalibration = false
        await tracking.start()
    }
    func loadLibrary() async {
        do {
            takes = try await store.load()
            savedTakeIDs = Set(takes.map(\.id))
            if selectedTake == nil, let latest = takes.first { select(latest); notice = "Your latest study is ready." }
        } catch { notice = "Could not read local studies: \(error.localizedDescription)" }
    }
    func enter() async {
        appliedCalibration = false; introVisible = true; panel = nil; sampleStart = CACurrentMediaTime()
        renderer.reset()
        if let selectedTake { renderer.configureStudy(selectedTake); applyInspection() }
        guard renderer.renderIssue == nil else { notice = renderer.renderIssue!; return }
        startClock()
        if !isSimulator { await tracking.start() }
        else { notice = "Simulator preview. Load a sample or enable sample input to test recording." }
    }
    func leave() {
        if phase == .recording { finishRecording() }
        if phase == .countdown { phase = selectedTake == nil ? .idle : .review }
        isPlaying = false; practice = false
        clockRunning = false; renderer.root.components.remove(StudioClockComponent.self)
        tracking.stop(); renderer.clearMotion(); immersiveOpen = false
    }
    func suspended() {
        if phase == .recording { finishRecording() }
        if phase == .countdown { cancelCountdown() }
        isPlaying = false
    }
    private func startClock() {
        lastTick = CACurrentMediaTime(); clockRunning = true
        StudioClockSystem.registerSystem()
        renderer.root.components.set(StudioClockComponent(studio: self))
    }
    func openPanel(_ panel: Panel) { self.panel = panel; isPlaying = false }
    func chooseMode(_ mode: ConsoleMode) {
        guard phase != .recording && phase != .countdown else { return }
        guard mode == .capture || selectedTake != nil else { return }
        consoleMode = mode; panel = nil; isPlaying = false; practice = false; renderer.clearTrails()
    }
    func beginRecording() {
        guard canRecord, sampleInput || selectionTracked else { notice = "Bring a selected hand into view before recording."; return }
        introVisible = false; panel = nil; isPlaying = false; practice = false
        countdownStart = CACurrentMediaTime(); countdown = 3; phase = .countdown
        renderer.clearTrails()
        notice = "Get comfortable. Move freely when the stage turns coral."
    }
    func cancelCountdown() { phase = selectedTake == nil ? .idle : .review; notice = "Countdown cancelled." }
    func finishRecording() {
        guard phase == .recording, let buffer = capture else { return }
        capture = nil
        guard let take = buffer.finish() else {
            phase = selectedTake == nil ? .idle : .review
            notice = "No usable hand movement was captured. Bring a hand into view and try again."; return
        }
        phase = .review
        select(take)
        takes.insert(take, at: 0); renderer.clearTrails(); renderer.revealGhosts(reduceMotion: motionReduced)
        notice = "\(take.source == .simulatorSample ? "Sample capture" : "Your movement") is ready. Saving locally…"
        let task = Task { [weak self] in
            guard let self else { return }
            do { try await store.save(take); savedTakeIDs.insert(take.id); if selectedTake?.id == take.id { notice = "Saved on this device. Play your movement."; saveError = nil } }
            catch { saveError = "Save failed: \(error.localizedDescription). The study remains in memory."; notice = saveError! }
        }
        saveTasks.append(task)
    }
    func retrySave() {
        guard let take = selectedTake else { return }
        saveTasks.append(Task {
            do { try await store.save(take); savedTakeIDs.insert(take.id); saveError = nil; notice = "Saved on this device." }
            catch { saveError = "Save failed: \(error.localizedDescription)" }
        })
    }
    func select(_ take: MotionTake) {
        guard phase != .recording, phase != .countdown else { return }
        selectedTake = take; panel = nil; phase = .review; consoleMode = .playback; playhead = 0; isPlaying = false; practice = false; saveError = nil
        loopStart = 0; loopEnd = take.duration; loopEnabled = false; reversePlayback = false
        viewYaw = 0; viewPitch = 0; viewScale = 1; showMotionPaths = false
        motionSummaries = HandSide.allCases.filter(take.selection.includes).map { MotionAnalysis.summary(take, side: $0) }
        renderer.configureStudy(take); resetStage(); renderer.clearTrails()
        if immersiveOpen { renderer.revealGhosts(reduceMotion: motionReduced) }
        notice = take.source == .simulatorSample ? "Synthetic sample · never a real hand recording." : "Recorded \(take.createdAt.formatted(date: .abbreviated, time: .shortened))."
    }
    func togglePlayback() {
        guard selectedTake != nil else { return }
        introVisible = false
        let region = playbackRegion
        if reversePlayback ? playhead <= region.start : playhead >= region.end {
            playhead = reversePlayback ? region.end : region.start; renderer.clearTrails()
        }
        isPlaying.toggle(); notice = isPlaying ? "Following time at \(speed.formatted())×." : "Playback paused. Scrub to explore."
    }
    func restart() { guard selectedTake != nil else { return }; playhead = reversePlayback ? playbackRegion.end : playbackRegion.start; isPlaying = true; renderer.clearTrails() }
    func scrub(_ time: Double) { isPlaying = false; playhead = min(max(0, time), duration); renderer.clearTrails() }
    func resetStage() {
        renderer.resetPlaybackTransform(); viewYaw = 0; viewPitch = 0; viewScale = 1
        stageMoved = false; dragOrigin = nil
    }
    func applyInspection() { renderer.setInspection(yaw: viewYaw, pitch: viewPitch, scale: viewScale); renderer.clearTrails() }
    func turnBy(_ degrees: Double) { viewYaw = (viewYaw + degrees + 360).truncatingRemainder(dividingBy: 360); applyInspection() }
    func viewPreset(yaw: Double, pitch: Double = 0) { viewYaw = yaw; viewPitch = pitch; applyInspection() }
    func markLoopStart() { loopStart = min(playhead, max(0, loopEnd - 0.1)); isPlaying = false }
    func markLoopEnd() { loopEnd = max(playhead, min(duration, loopStart + 0.1)); isPlaying = false }
    func resetLoop() { loopStart = 0; loopEnd = duration; loopEnabled = false }
    func toggleLoop() {
        loopEnabled.toggle()
        if loopEnabled { playhead = min(max(playhead, loopStart), loopEnd) }
    }
    func saveTrimmedStudy() {
        guard let original = selectedTake,
              let copy = MotionEditing.trimmed(original, region: .init(start: loopStart, end: loopEnd, duration: duration)) else {
            notice = "Choose at least a tenth of a second with usable hand data."; return
        }
        takes.insert(copy, at: 0); select(copy)
        saveTasks.append(Task {
            do { try await store.save(copy); savedTakeIDs.insert(copy.id); notice = "Selection saved as a new study." }
            catch { saveError = "Save failed: \(error.localizedDescription)" }
        })
    }
    func dragPlayback(_ delta: SIMD3<Float>, ended: Bool) {
        guard selectedTake != nil, phase == .review, !practice else { return }
        if dragOrigin == nil { dragOrigin = renderer.playbackRoot.position }
        let center = renderer.inspectionCenter
        var offset = (dragOrigin ?? center) + delta - center
        offset.x = min(max(offset.x, -0.65), 0.65); offset.y = min(max(offset.y, -0.25), 0.35); offset.z = min(max(offset.z, -0.5), 0.3)
        renderer.playbackRoot.position = center + offset; stageMoved = simd_length(offset) > 0.001
        renderer.clearTrails()
        if ended { dragOrigin = nil }
    }
    func togglePractice() {
        guard selectedTake != nil else { return }
        practice.toggle(); resetStage(); renderer.clearTrails()
        notice = practice ? "Follow the ghost tips. Coral means within 5 cm. This is distance feedback, not an accuracy score." : "Practice ended."
    }
    func deleteSelected() async {
        guard let take = selectedTake else { return }
        // Serialize deletion after pending saves to avoid recreating a deleted study.
        for task in saveTasks { await task.value }; saveTasks.removeAll()
        do {
            try await store.delete(take)
            savedTakeIDs.remove(take.id)
            takes.removeAll { $0.id == take.id }; selectedTake = nil; consoleMode = .capture; isPlaying = false; practice = false; phase = .idle
            renderer.clearMotion(); notice = "Study deleted from this device."
            if let next = takes.first { select(next) }
        } catch { notice = "Could not delete: \(error.localizedDescription)" }
    }
    #if targetEnvironment(simulator)
    func loadSample() { let take = SampleMotion.take(); select(take); notice = "Synthetic sample · 6 seconds · Simulator only." }
    func setSampleInput(_ enabled: Bool) { sampleInput = enabled; sampleStart = CACurrentMediaTime(); notice = enabled ? "Synthetic sample input enabled. Record tests the same capture pipeline." : "Sample input off." }
    #endif
    fileprivate func tick(now: Double) {
        guard clockRunning else { return }
        let delta = max(0, now - lastTick); lastTick = now
        if tracking.calibrated && !appliedCalibration {
            renderer.calibrate(worldFromStage: tracking.worldFromStage, eyeHeight: tracking.eyeHeight)
            appliedCalibration = true
        }
        liveHands = sampleInput ? SampleMotion.hands(at: now - sampleStart) : tracking.snapshot(at: now)
        let mask = liveHands.filter(\.tracked).reduce(0) { $0 | ($1.side == .left ? 1 : 2) }
        if trackedHandMask != mask { trackedHandMask = mask }
        let count = liveHands.filter(\.tracked).count
        if trackedHands != count { trackedHands = count }
        #if targetEnvironment(simulator)
        let advancesCountdown = !previewCountdown
        #else
        let advancesCountdown = true
        #endif
        if phase == .countdown && advancesCountdown {
            let elapsed = now - countdownStart
            let next = max(1, Int(ceil(3 - elapsed))); if countdown != next { countdown = next }
            if elapsed >= 3 {
                guard sampleInput || (tracking.status == .running && selectionTracked) else { cancelCountdown(); notice = "Tracking was lost. Bring a hand into view, then record again."; return }
                capture = CaptureBuffer(source: sampleInput ? .simulatorSample : .device, selection: selectedHands)
                recordingStart = now; nextCaptureAt = 0; recordingElapsed = 0; phase = .recording
                notice = sampleInput ? "Recording synthetic sample input." : "Recording your movement. Up to 10 seconds."
            }
        }
        if phase == .recording {
            let elapsed = min(now - recordingStart, 10)
            if elapsed-recordingElapsed >= 0.05 || elapsed == 10 { recordingElapsed = elapsed }
            // Rendering follows the display; the persisted capture remains at
            // at most 60 samples/s, including on 90/96/100/120 Hz displays.
            if elapsed >= nextCaptureAt {
                capture?.append(time: elapsed, hands: liveHands, trackingState: sampleInput ? "synthetic-simulator-fixture" : String(describing: tracking.status))
                nextCaptureAt = (floor(elapsed*60)+1)/60
            }
            if elapsed >= 10 || (!sampleInput && tracking.status != .running) { finishRecording() }
        }
        if isPlaying, selectedTake != nil {
            let result = playbackRegion.advanced(from: playhead, by: delta, speed: speed, reverse: reversePlayback, loops: loopEnabled)
            if (reversePlayback && result.time > playhead) || (!reversePlayback && result.time < playhead) { renderer.clearTrails() }
            playhead = result.time
            if result.finished { isPlaying = false; notice = "End of study. Replay or record another movement." }
        }
        renderer.showCountdown(phase == .countdown ? countdown : nil)
        renderer.showPaths(showMotionPaths && phase == .review && consoleMode == .playback && !practice)
        let ghost = selectedTake.map { MotionSampler.hands(in: $0, at: playhead) } ?? []
        let displayHands = sampleInput ? liveHands : tracking.displaySnapshot(at: now)
        let feedback = renderer.update(live: displayHands, ghost: phase == .review && consoleMode == .playback ? ghost : [], recording: phase == .recording, countdown: phase == .countdown, playing: isPlaying, practice: practice, now: now, reduceMotion: motionReduced, allowManipulation: panel == nil || panel == .view, showGhostHands: panel == nil || panel == .view || panel == .loop)
        if nearTips != feedback.near { nearTips = feedback.near }; if comparedTips != feedback.total { comparedTips = feedback.total }
    }
}

private struct StudioClockComponent: Component {
    weak var studio: StudioModel?
}

/// Work belongs to the render update, rather than sleeping for 16 ms after a
/// potentially expensive deformation and adding that work time to every frame.
@MainActor
private final class StudioClockSystem: System {
    private static let query = EntityQuery(where: .has(StudioClockComponent.self))
    required init(scene: RealityKit.Scene) { }
    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            entity.components[StudioClockComponent.self]?.studio?.tick(now: CACurrentMediaTime())
        }
    }
}
