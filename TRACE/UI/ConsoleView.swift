import SwiftUI

struct ConsoleView: View {
    @Bindable var studio: StudioModel
    let exit: () -> Void
    private var busy: Bool { studio.phase == .recording || studio.phase == .countdown }
    private var playbackVisible: Bool { studio.consoleMode == .playback && !busy && studio.selectedTake != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let panel = studio.panel {
                panelHeader(panel)
                switch panel {
                case .options: optionsPanel
                case .studies: studiesPanel
                case .hands: handsPanel
                }
            } else {
                header
                if studio.phase == .countdown { countdown }
                else if studio.phase == .recording { recording }
                else if playbackVisible { playback }
                else { capture }
                if !busy { footer }
                if studio.practice { practiceFeedback }
            }
            if let message = errorMessage {
                Text(message).font(.system(size: 14)).foregroundStyle(TraceStyle.coral)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("studioNotice")
            }
            if studio.saveError != nil { Button("Retry saving") { studio.retrySave() }.buttonStyle(.bordered) }
        }
        .padding(24).frame(width: 560)
        .foregroundStyle(TraceStyle.chalk)
        .background(TraceStyle.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 32))
        .overlay { RoundedRectangle(cornerRadius: 32).strokeBorder(.black.opacity(0.07), lineWidth: 1) }
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 32))
        .shadow(color: .black.opacity(0.07), radius: 20, y: 8)
        .confirmationDialog("Delete this study from this device?", isPresented: $studio.deleteConfirmation, titleVisibility: .visible) {
            Button("Delete study", role: .destructive) { Task { await studio.deleteSelected() } }
        }
        .animation(studio.motionReduced ? nil : .easeInOut(duration: 0.22), value: studio.phase)
        .animation(studio.motionReduced ? nil : .easeInOut(duration: 0.22), value: studio.consoleMode)
    }
    private var header: some View {
        HStack(spacing: 16) {
            Text("TRACE").font(.system(size: 16, weight: .semibold)).tracking(3)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                modeButton("Record", mode: .capture, id: "captureMode")
                modeButton("Playback", mode: .playback, id: "playbackMode")
            }
            .padding(4).background(.black.opacity(0.045), in: Capsule())
            .disabled(busy)
            Spacer(minLength: 4)
            Button(action: exit) { Image(systemName: "xmark").font(.system(size: 16, weight: .medium)).frame(width: 44, height: 44) }
                .buttonStyle(.bordered).buttonBorderShape(.circle)
                .accessibilityLabel("Exit chamber").accessibilityIdentifier("exitChamber")
        }
    }
    private func modeButton(_ title: String, mode: StudioModel.ConsoleMode, id: String) -> some View {
        Button { studio.chooseMode(mode) } label: {
            Text(title).font(.system(size: 14, weight: studio.consoleMode == mode ? .semibold : .medium))
                .frame(width: 96, height: 44)
                .foregroundStyle(studio.consoleMode == mode ? TraceStyle.chalk : TraceStyle.blue)
                .background(studio.consoleMode == mode ? .white : .clear, in: Capsule())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
        .accessibilityAddTraits(studio.consoleMode == mode ? .isSelected : [])
        .disabled(mode == .playback && studio.selectedTake == nil)
    }
    private var capture: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Make a little motion.").font(.system(size: 24, weight: .medium))
                    Text("Three seconds to prepare. Up to ten to move.")
                        .font(.system(size: 14)).foregroundStyle(TraceStyle.blue)
                }
                Spacer()
            }
            Button { studio.beginRecording() } label: {
                HStack(spacing: 10) {
                    Circle().fill(TraceStyle.coral).frame(width: 10, height: 10)
                    Text("Record motion").font(.system(size: 17, weight: .semibold))
                }.frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent).tint(TraceStyle.graphite).foregroundStyle(.white)
            .buttonBorderShape(.capsule).disabled(!studio.canRecord).accessibilityIdentifier("recordMovement")
            HStack(spacing: 7) {
                Circle().fill(studio.canRecord ? Color(red: 0.30, green: 0.49, blue: 0.39) : TraceStyle.blue.opacity(0.45)).frame(width: 5, height: 5)
                Text(readiness).font(.system(size: 13)).foregroundStyle(TraceStyle.blue)
            }
        }
    }
    private var countdown: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Ready in \(studio.countdown)").font(.system(size: 28, weight: .medium)).monospacedDigit()
                Spacer()
                Text("Keep your hands in view").font(.system(size: 14)).foregroundStyle(TraceStyle.blue)
            }
            Button("Cancel") { studio.cancelCountdown() }.buttonStyle(.bordered).frame(maxWidth: .infinity).accessibilityIdentifier("cancelCountdown")
        }
    }
    private var recording: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 8) { Circle().fill(TraceStyle.coral).frame(width: 8, height: 8); Text("Recording").font(.system(size: 24, weight: .medium)) }
                Spacer()
                Text(String(format: "%.1f / 10 s", studio.recordingElapsed)).font(.system(size: 16, design: .monospaced)).monospacedDigit().foregroundStyle(TraceStyle.blue)
            }
            ProgressView(value: studio.recordingElapsed, total: 10).tint(TraceStyle.coral)
            Button { studio.finishRecording() } label: {
                Label("Finish recording", systemImage: "stop.fill").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(TraceStyle.graphite).foregroundStyle(.white).accessibilityIdentifier("stopRecording")
        }
    }
    private var playback: some View {
        VStack(spacing: 14) {
            HStack {
                Text(studio.selectedTake?.source == .simulatorSample ? "Sample motion" : "Your motion").font(.system(size: 24, weight: .medium))
                Spacer()
                Text(String(format: "%.1f / %.1f s", studio.playhead, studio.duration))
                    .font(.system(size: 14, design: .monospaced)).foregroundStyle(TraceStyle.blue).monospacedDigit().accessibilityIdentifier("playbackTime")
            }
            HStack(spacing: 12) {
                Button { studio.scrub(studio.playhead - 1) } label: { Image(systemName: "backward.frame").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Back one second").accessibilityIdentifier("stepBackward")
                Slider(value: Binding(get: { studio.playhead }, set: { studio.scrub($0) }), in: 0...max(0.01, studio.duration))
                    .tint(TraceStyle.graphite).accessibilityLabel("Playback timeline, start to end").accessibilityIdentifier("playbackTimeline")
                Button { studio.scrub(studio.playhead + 1) } label: { Image(systemName: "forward.frame").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Forward one second").accessibilityIdentifier("stepForward")
            }
            HStack(spacing: 16) {
                Button { studio.restart() } label: { Image(systemName: "backward.end").frame(width: 48, height: 48) }
                    .buttonStyle(.bordered).buttonBorderShape(.circle).accessibilityLabel("Replay from beginning").accessibilityIdentifier("restartPlayback")
                Button { studio.togglePlayback() } label: {
                    Label(studio.isPlaying ? "Pause" : "Play", systemImage: studio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(TraceStyle.graphite).foregroundStyle(.white).accessibilityIdentifier("playPause")
                Button { studio.speed = studio.speed == 1 ? 0.5 : 1 } label: {
                    Text(studio.speed == 1 ? "1×" : "0.5×").font(.system(size: 15, weight: .medium)).frame(width: 48, height: 48)
                }
                .buttonStyle(.bordered).buttonBorderShape(.circle).accessibilityLabel("Playback speed")
                .accessibilityValue(studio.speed == 1 ? "1×" : "0.5×").accessibilityIdentifier("playbackSpeed")
                .help("Switch between normal and half speed")

            }
        }
    }
    private var footer: some View {
        HStack(spacing: 16) {
            if !playbackVisible {
                Button { studio.openPanel(.hands) } label: { Label(studio.selectedHands.rawValue, systemImage: "hand.raised") }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).accessibilityLabel("Choose hands to record")
                    .accessibilityValue(studio.selectedHands.rawValue).accessibilityIdentifier("handSelection")
            } else {
                Label(storageLabel, systemImage: studio.selectedTake?.source == .simulatorSample ? "cube.transparent" : "checkmark.circle")
                    .font(.system(size: 13)).foregroundStyle(TraceStyle.blue)
            }
            Spacer(minLength: 0)
            Button { studio.openPanel(.studies) } label: { Image(systemName: "square.stack").frame(width: 44, height: 44) }
                .buttonStyle(.bordered).buttonBorderShape(.circle).accessibilityLabel("Saved studies").accessibilityIdentifier("studyLibrary")
            Button { studio.openPanel(.options) } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .buttonStyle(.bordered).buttonBorderShape(.circle).accessibilityLabel("More options").accessibilityIdentifier("studioMenu")
        }.font(.system(size: 14)).controlSize(.regular)
    }
    private func panelHeader(_ panel: StudioModel.Panel) -> some View {
        HStack(spacing: 16) {
            Button { studio.panel = nil } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .buttonStyle(.bordered).buttonBorderShape(.circle).accessibilityLabel("Back to studio").accessibilityIdentifier("closePanel")
            Text(panel == .options ? "Studio options" : (panel == .studies ? "Saved studies" : "Hands to record")).font(.system(size: 22, weight: .medium))
            Spacer()
            Button(action: exit) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .buttonStyle(.bordered).buttonBorderShape(.circle).accessibilityLabel("Exit chamber").accessibilityIdentifier("exitChamber")
        }
    }
    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if playbackVisible {
                option("Reset sculpture", symbol: "arrow.counterclockwise") { studio.resetStage() }
                option(studio.practice ? "End practice" : "Practice with this study", symbol: "hand.draw") { studio.togglePractice() }
            }
            option("How to use TRACE", symbol: "questionmark.circle") { studio.introVisible = true }
            if !studio.isSimulator { option("Retry hand tracking", symbol: "arrow.clockwise") { Task { await studio.retryTracking() } } }
            #if targetEnvironment(simulator)
            Divider().padding(.vertical, 4)
            Text("Simulator · synthetic data").font(.system(size: 12)).foregroundStyle(TraceStyle.blue)
            option("Load sample", symbol: "cube.transparent", id: "loadSample") { studio.loadSample() }
            option(studio.sampleInput ? "Disable sample input" : "Enable sample input", symbol: "hand.raised", id: "sampleInput") { studio.setSampleInput(!studio.sampleInput) }
            #endif
            if playbackVisible {
                Divider().padding(.vertical, 4)
                option("Delete study…", symbol: "trash", destructive: true) { studio.deleteConfirmation = true }
            }
        }
    }
    private var handsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(HandSelection.allCases, id: \.self) { selection in
                Button { studio.selectedHands = selection; studio.panel = nil } label: {
                    HStack { Text(selection.rawValue); Spacer(); if studio.selectedHands == selection { Image(systemName: "checkmark") } }
                        .font(.system(size: 17)).frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.plain).accessibilityIdentifier("handChoice_\(selection == .both ? "both" : (selection == .left ? "left" : "right"))")
            }
            Text("Only the hands you choose will be recorded.").font(.system(size: 13)).foregroundStyle(TraceStyle.blue)
        }
    }
    private var studiesPanel: some View {
        Group {
            if studio.takes.isEmpty { Text("Your recordings will appear here.").font(.system(size: 16)).foregroundStyle(TraceStyle.blue).frame(maxWidth: .infinity, minHeight: 100) }
            else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(studio.takes) { take in
                            Button { studio.select(take) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(take.source == .simulatorSample ? "Sample capture" : "Motion study").font(.system(size: 17, weight: .medium))
                                        Text(take.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 13)).foregroundStyle(TraceStyle.blue)
                                    }
                                    Spacer()
                                    Text("\(take.duration.formatted(.number.precision(.fractionLength(1)))) s").font(.system(size: 14)).foregroundStyle(TraceStyle.blue)
                                    if take.id == studio.selectedTake?.id { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)) }
                                }.frame(minHeight: 56)
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 280)
            }
        }
    }
    private func option(_ title: String, symbol: String, id: String = "", destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button { studio.panel = nil; action() } label: {
            Label(title, systemImage: symbol).font(.system(size: 17)).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .foregroundStyle(destructive ? TraceStyle.coral : TraceStyle.chalk)
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
    private var practiceFeedback: some View {
        HStack {
            Image(systemName: "hand.draw")
            Text(studio.comparedTips == 0 ? "Bring your fingertips into view" : "\(studio.nearTips) of \(studio.comparedTips) fingertips within 5 cm")
            Spacer()
            Button("End") { studio.togglePractice() }
        }.font(.system(size: 13)).foregroundStyle(TraceStyle.blue)
    }
    private var storageLabel: String {
        guard let take = studio.selectedTake else { return "" }
        if take.source == .simulatorSample { return "Synthetic sample" }
        if studio.savedTakeIDs.contains(take.id) { return "Saved on device" }
        return studio.saveError == nil ? "Saving…" : "Not saved"
    }
    private var readiness: String {
        if studio.sampleInput { return "Synthetic input ready · simulator" }
        if studio.isSimulator { return "Simulator preview · sample available in More" }
        if studio.selectionTracked { return studio.selectedHands == .both ? "\(studio.trackedHands == 1 ? "One hand" : "Both hands") in view" : "\(studio.selectedHands.rawValue) ready" }
        return studio.selectedHands == .both ? "Raise a hand comfortably to begin" : "Bring your \(studio.selectedHands == .left ? "left" : "right") hand into view"
    }
    private var errorMessage: String? {
        if let saveError = studio.saveError { return saveError }
        switch studio.tracking.status {
        case .denied, .failed, .interrupted: return studio.tracking.status.label
        default: break
        }
        if studio.notice.hasPrefix("No usable") || studio.notice.hasPrefix("Tracking was lost") || studio.notice.hasPrefix("Could not") { return studio.notice }
        return nil
    }
}
