import SwiftUI
import RealityKit

struct MotionChamberView: View {
    @Bindable var studio: StudioModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var legacyGestures: Bool { if #available(visionOS 26.0, *) { false } else { true } }
    var body: some View {
        RealityView { content, attachments in
            content.add(studio.renderer.root)
            if let console = attachments.entity(for: "console") { studio.renderer.consoleMount.addChild(console) }
            if let intro = attachments.entity(for: "intro") { studio.renderer.introMount.addChild(intro) }
        } update: { _, attachments in
            if let intro = attachments.entity(for: "intro") {
                if intro.parent == nil { studio.renderer.introMount.addChild(intro) }
                intro.isEnabled = studio.introVisible
            }
        } attachments: {
            Attachment(id: "console") {
                ConsoleView(studio: studio, exit: {
                    Task { openWindow(id: "studio"); await dismissImmersiveSpace() }
                }, export: {
                    studio.exportRequested = true
                    Task { openWindow(id: "studio"); await dismissImmersiveSpace() }
                })
            }
            Attachment(id: "intro") {
                if studio.introVisible {
                VStack(spacing: 13) {
                    Eyebrow(text: "WELCOME TO TRACE")
                    Text("Make a motion. Keep a moment.").font(.title2.weight(.medium)).foregroundStyle(TraceStyle.chalk)
                    Text("Look at a control and pinch to select. Record gives you three seconds to prepare.\nMove one or both hands, then replay the movement at your own pace.")
                        .font(.callout).foregroundStyle(TraceStyle.blue).multilineTextAlignment(.center)
                    Button("Got it") { studio.introVisible = false }.buttonStyle(.bordered).foregroundStyle(TraceStyle.chalk).accessibilityIdentifier("dismissIntro")
                }.padding(28).frame(width: 480).background(TraceStyle.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 26)).accessibilityHidden(!studio.introVisible).glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 26))
                }
            }
        }
        .upperLimbVisibility(studio.tracking.status == .running && studio.renderer.renderIssue == nil ? .hidden : .visible)
        .gesture(DragGesture().targetedToEntity(studio.renderer.handle)
            .onChanged { value in
                if #available(visionOS 26.0, *) { return }
                let translation = value.convert(value.translation3D, from: .local, to: studio.renderer.stage)
                studio.dragPlayback(translation, ended: false)
            }
            .onEnded { value in
                if #available(visionOS 26.0, *) { return }
                let translation = value.convert(value.translation3D, from: .local, to: studio.renderer.stage)
                studio.dragPlayback(translation, ended: true)
            }, including: legacyGestures ? .all : .none)
        .task {
            studio.motionReduced = reduceMotion; await studio.enter()
            #if targetEnvironment(simulator)
            if CommandLine.arguments.contains("--preview-chamber") {
                studio.loadSample(); studio.introVisible = false
                if CommandLine.arguments.contains("--preview-capture") { studio.setSampleInput(true); studio.chooseMode(.capture) }
                if CommandLine.arguments.contains("--preview-hand-detail") { studio.renderer.playbackRoot.position = [0, -0.02, 0.30] }
                if CommandLine.arguments.contains("--preview-flexed") { studio.scrub(2.6); studio.renderer.playbackRoot.position.y = 0.10 }
                if CommandLine.arguments.contains("--preview-countdown") {
                    studio.setSampleInput(true); studio.chooseMode(.capture)
                    studio.beginRecording(); studio.previewCountdown = true; studio.countdown = 2
                }
                if CommandLine.arguments.contains("--preview-view") { studio.viewPreset(yaw: 135, pitch: 15); studio.openPanel(.view) }
                if CommandLine.arguments.contains("--preview-paths") { studio.showMotionPaths = true; studio.scrub(3); studio.openPanel(.insights) }
                if CommandLine.arguments.contains("--preview-loop") { studio.loopStart = 1.5; studio.loopEnd = 3.5; studio.loopEnabled = true; studio.scrub(2.5); studio.openPanel(.loop) }
            }
            #endif
        }
        .onChange(of: reduceMotion) { _, value in studio.motionReduced = value }
        .onDisappear { studio.leave() }
    }
}
