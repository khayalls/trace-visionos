import SwiftUI

struct StudyToolsPanel: View {
    @Bindable var studio: StudioModel
    let panel: StudioModel.Panel
    let export: () -> Void

    var body: some View {
        switch panel {
        case .view: viewControls
        case .loop: loopControls
        case .insights: insights
        default: EmptyView()
        }
    }

    private var viewControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pinch the ring beside your recording. Turn your hand, or use both hands to rotate and resize on visionOS 26 and later. These controls work on earlier versions too.")
                .font(.system(size: 14)).foregroundStyle(TraceStyle.blue).fixedSize(horizontal: false, vertical: true)
            HStack {
                preset("Recorded", yaw: 0, id: "viewOriginal")
                preset("Opposite", yaw: 180, id: "viewOpposite")
                preset("Side", yaw: 90, id: "viewSide")
            }
            HStack {
                Button { studio.turnBy(-90) } label: { Label("Turn left", systemImage: "arrow.uturn.backward") }
                    .accessibilityIdentifier("turnLeft")
                Spacer()
                Text("\(Int(studio.viewYaw))°").monospacedDigit().accessibilityIdentifier("viewAngle")
                Spacer()
                Button { studio.turnBy(90) } label: { Label("Turn right", systemImage: "arrow.uturn.forward") }
                    .accessibilityIdentifier("turnRight")
            }.font(.system(size: 14)).buttonStyle(.bordered)
            adjustment("Turn", value: $studio.viewYaw, range: 0...360, suffix: "°", id: "viewYaw")
            adjustment("Tilt", value: $studio.viewPitch, range: -180...180, suffix: "°", id: "viewPitch")
            HStack {
                Text("Size")
                Slider(value: $studio.viewScale, in: 0.5...2, onEditingChanged: { _ in studio.applyInspection() })
                    .onChange(of: studio.viewScale) { _, _ in studio.applyInspection() }.accessibilityIdentifier("viewScale")
                Text("\(studio.viewScale.formatted(.number.precision(.fractionLength(1))))×").monospacedDigit().frame(width: 44)
            }.font(.system(size: 14))
            Toggle("Show fingertip paths", isOn: $studio.showMotionPaths).font(.system(size: 16)).accessibilityIdentifier("motionPaths")
            Button("Reset view") { studio.resetStage() }.buttonStyle(.bordered).accessibilityIdentifier("resetView")
        }
    }
    private func preset(_ title: String, yaw: Double, id: String) -> some View {
        Button(title) { studio.viewPreset(yaw: yaw) }.buttonStyle(.bordered).frame(maxWidth: .infinity).accessibilityIdentifier(id)
    }
    private func adjustment(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String, id: String) -> some View {
        HStack {
            Text(label).frame(width: 35, alignment: .leading)
            Slider(value: value, in: range).onChange(of: value.wrappedValue) { _, _ in studio.applyInspection() }.accessibilityLabel(label).accessibilityIdentifier(id)
            Text("\(Int(value.wrappedValue))\(suffix)").monospacedDigit().frame(width: 44)
        }.font(.system(size: 14))
    }

    private var loopControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(format: "%.1f s", studio.playhead)).font(.title3.monospacedDigit()).accessibilityIdentifier("loopPlayhead")
                Spacer()
                Text(String(format: "Selection %.1f to %.1f s", studio.loopStart, studio.loopEnd)).font(.system(size: 14)).foregroundStyle(TraceStyle.blue).accessibilityIdentifier("loopRange")
            }
            Slider(value: Binding(get: { studio.playhead }, set: { studio.scrub($0) }), in: 0...max(0.01, studio.duration))
                .accessibilityLabel("Choose a moment").accessibilityIdentifier("loopTimeline")
            HStack {
                Button("Back 0.5 s") { studio.scrub(studio.playhead - 0.5) }.accessibilityIdentifier("loopStepBack")
                Button("Ahead 0.5 s") { studio.scrub(studio.playhead + 0.5) }.accessibilityIdentifier("loopStepAhead")
                Spacer()
                Button("Set in") { studio.markLoopStart() }.accessibilityIdentifier("markLoopStart")
                Button("Set out") { studio.markLoopEnd() }.accessibilityIdentifier("markLoopEnd")
            }.font(.system(size: 14)).buttonStyle(.bordered)
            Toggle("Loop selection", isOn: Binding(get: { studio.loopEnabled }, set: { _ in studio.toggleLoop() })).accessibilityIdentifier("loopEnabled")
            Toggle("Play backwards", isOn: $studio.reversePlayback).accessibilityIdentifier("reversePlayback")
            Picker("Speed", selection: $studio.speed) {
                ForEach([0.25, 0.5, 1.0, 2.0], id: \.self) { speed in Text("\(speed.formatted())×").tag(speed) }
            }.pickerStyle(.segmented).accessibilityIdentifier("studySpeed")
            HStack {
                Button("Reset selection") { studio.resetLoop() }.buttonStyle(.bordered).accessibilityIdentifier("resetLoop")
                Spacer()
                Button("Save as new study") { studio.saveTrimmedStudy() }
                    .buttonStyle(.borderedProminent).tint(TraceStyle.graphite).foregroundStyle(.white)
                    .disabled(studio.loopEnd - studio.loopStart < 0.1).accessibilityIdentifier("saveSelection")
            }.font(.system(size: 14))
            Text("Your original stays unchanged. Only the selected time range is copied.")
                .font(.system(size: 13)).foregroundStyle(TraceStyle.blue)
        }.font(.system(size: 16))
    }

    private var insights: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(studio.motionSummaries, id: \.side) { summary in
                VStack(alignment: .leading, spacing: 10) {
                    Text(summary.side == .left ? "Left hand" : "Right hand").font(.system(size: 17, weight: .semibold))
                    HStack {
                        metric("Wrist travel", value: String(format: "%.2f m", summary.distance))
                        Spacer()
                        metric("Peak segment speed", value: String(format: "%.2f m/s", summary.peakSpeed))
                        Spacer()
                        metric("Tracked frames", value: String(format: "%.0f%%", summary.coverage * 100))
                    }
                }.padding(16).background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
            }
            Text("Wrist measurements skip inferred joints and tracking gaps. Peak speed is an estimate between samples, not a calibrated accuracy score.")
                .font(.system(size: 13)).foregroundStyle(TraceStyle.blue).fixedSize(horizontal: false, vertical: true)
            Toggle("Show fingertip paths", isOn: $studio.showMotionPaths).font(.system(size: 16)).accessibilityIdentifier("motionPaths")
            Button(action: export) {
                Label("Export CSV or JSON", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.bordered).accessibilityIdentifier("exportStudy")
        }
    }
    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 22, weight: .medium)).monospacedDigit()
            Text(label).font(.system(size: 11)).foregroundStyle(TraceStyle.blue)
        }
    }
}
