import SwiftUI
import RealityKit

struct MotionChamberView: View {
    @Bindable var studio: StudioModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        RealityView { content, attachments in
            content.add(studio.renderer.root)
            if let console = attachments.entity(for: "console") { studio.renderer.consoleMount.addChild(console) }
            if let intro = attachments.entity(for: "intro") { studio.renderer.introMount.addChild(intro) }
            if let counter = attachments.entity(for: "counter") { studio.renderer.counterMount.addChild(counter) }
        } update: { _, attachments in
            if let intro = attachments.entity(for: "intro") {
                if intro.parent == nil { studio.renderer.introMount.addChild(intro) }
                intro.isEnabled = studio.introVisible
            }
            if let counter = attachments.entity(for: "counter") {
                if counter.parent == nil { studio.renderer.counterMount.addChild(counter) }
                counter.isEnabled = studio.phase == .countdown
            }
        } attachments: {
            Attachment(id: "console") {
                ConsoleView(studio: studio) {
                    Task { openWindow(id: "studio"); await dismissImmersiveSpace() }
                }
            }
            Attachment(id: "intro") {
                if studio.introVisible {
                VStack(spacing: 13) {
                    Eyebrow(text: "WELCOME TO TRACE")
                    Text("Make a motion. Keep a moment.").font(.title2.weight(.medium)).foregroundStyle(TraceStyle.chalk)
                    Text("Look at a control and pinch to select. Record gives you three seconds to prepare.\nMove one or both hands, then replay the movement at your own pace.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Got it") { studio.introVisible = false }.buttonStyle(.bordered).accessibilityIdentifier("dismissIntro")
                }.padding(28).frame(width: 480).background(TraceStyle.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 26)).accessibilityHidden(!studio.introVisible).glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 26))
                }
            }
            Attachment(id: "counter") {
                if studio.phase == .countdown {
                VStack(spacing: 8) {
                    Text("GET READY").font(.system(size: 12, weight: .medium, design: .monospaced)).tracking(3)
                    Text("\(studio.countdown)").font(.system(size: 84, weight: .ultraLight, design: .rounded)).monospacedDigit()
                    Text("Keep your hands comfortably in view").font(.caption)
                }.foregroundStyle(TraceStyle.chalk).padding(26).glassBackgroundEffect(in: Circle())
                }
            }
        }
        .upperLimbVisibility(studio.tracking.status == .running && studio.renderer.renderIssue == nil ? .hidden : .visible)
        .gesture(DragGesture().targetedToEntity(studio.renderer.handle)
            .onChanged { value in
                let translation = value.convert(value.translation3D, from: .local, to: studio.renderer.stage)
                studio.dragPlayback(translation, ended: false)
            }
            .onEnded { value in
                let translation = value.convert(value.translation3D, from: .local, to: studio.renderer.stage)
                studio.dragPlayback(translation, ended: true)
            })
        .task {
            studio.motionReduced = reduceMotion; await studio.enter()
            #if targetEnvironment(simulator)
            if CommandLine.arguments.contains("--preview-chamber") {
                studio.loadSample(); studio.introVisible = false
                if CommandLine.arguments.contains("--preview-capture") { studio.setSampleInput(true); studio.chooseMode(.capture) }
                if CommandLine.arguments.contains("--preview-hand-detail") { studio.renderer.playbackRoot.position = [0, -0.02, 0.30] }
                if CommandLine.arguments.contains("--preview-flexed") { studio.scrub(2.6); studio.renderer.playbackRoot.position.y = 0.10 }
            }
            #endif
        }
        .onChange(of: reduceMotion) { _, value in studio.motionReduced = value }
        .onDisappear { studio.leave(); openWindow(id: "studio") }
    }
}
